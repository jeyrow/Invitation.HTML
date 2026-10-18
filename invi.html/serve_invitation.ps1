$root = (Resolve-Path $PSScriptRoot).Path
$rootPath = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 8080)

try {
    $listener.Start()
    Write-Host "Serving invitation files from $root"
    Write-Host "This PC: http://localhost:8080/"

    $addresses = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up } |
        ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
        Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address -ne [System.Net.IPAddress]::Loopback
        } |
        ForEach-Object { $_.Address.IPAddressToString } |
        Sort-Object -Unique

    foreach ($address in $addresses) {
        Write-Host "Same-network devices: http://${address}:8080/"
    }
    Write-Host "Keep this window open while guests view the invitation."

    while ($listener.Server.IsBound) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            while (($headerLine = $reader.ReadLine()) -and $headerLine.Length -gt 0) { }

            $parts = @($requestLine -split ' ')
            $method = if ($parts.Count -gt 0) { $parts[0] } else { '' }
            $requestPath = if ($parts.Count -gt 1) { ($parts[1] -split '\?')[0] } else { '/' }
            $requestPath = [Uri]::UnescapeDataString($requestPath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($requestPath)) {
                $requestPath = 'index.html'
            }

            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $requestPath))
            $status = '200 OK'
            $contentType = 'application/octet-stream'
            $bytes = [byte[]]@()

            if (($method -ne 'GET' -and $method -ne 'HEAD') -or
                -not $fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                $status = '404 Not Found'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
                $contentType = 'text/plain; charset=utf-8'
            } else {
                $contentType = switch ([System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()) {
                    '.html' { 'text/html; charset=utf-8' }
                    '.css' { 'text/css; charset=utf-8' }
                    '.js' { 'text/javascript; charset=utf-8' }
                    '.jpg' { 'image/jpeg' }
                    '.jpeg' { 'image/jpeg' }
                    '.png' { 'image/png' }
                    '.svg' { 'image/svg+xml' }
                    default { 'application/octet-stream' }
                }
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            }

            $headers = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            if ($method -ne 'HEAD' -and $bytes.Length -gt 0) {
                $stream.Write($bytes, 0, $bytes.Length)
            }
            $stream.Flush()
            $reader.Dispose()
        } catch {
            Write-Warning "Request failed: $_"
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}