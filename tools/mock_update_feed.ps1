# 本地 mock GitHub Release feed，用于真机联调应用内更新。
#
# 用法（仓库根目录）：
#   pwsh -File tools/mock_update_feed.ps1 -ApkPath build/app/outputs/flutter-apk/app-release.apk
#   # 另一个终端：
#   flutter run --dart-define=UPDATE_API_BASE=http://127.0.0.1:8787
#
# 只监听 127.0.0.1，不对外暴露；APK 需要是同一签名构建的测试包。
param(
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [int]$Port = 8787,
    [string]$Version = '1.0.3',
    [string]$PublicBase = '',
    [string]$Notes = "## 变更`n`n- feat(update): 本地 mock 更新源`n- fix(android): 验证下载与安装`n"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ApkPath)) { throw "找不到 APK：$ApkPath" }
$apk = (Resolve-Path $ApkPath).Path
$apkBytes = [IO.File]::ReadAllBytes($apk)
$size = $apkBytes.Length
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$prefix = "http://127.0.0.1:$Port"
if ([string]::IsNullOrWhiteSpace($PublicBase)) { $PublicBase = $prefix }
$tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$versionName = $tag.TrimStart('v')

$latest = @{
    tag_name     = $tag
    name         = "金豆 $versionName（mock）"
    body         = $Notes
    published_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    assets       = @(
        @{
            name                 = 'app-release.apk'
            size                 = $size
            digest               = "sha256:$sha"
            browser_download_url = "$PublicBase/app-release.apk"
        },
        @{
            name                 = 'SHA256SUMS.txt'
            size                 = 0
            browser_download_url = "$PublicBase/SHA256SUMS.txt"
        }
    )
} | ConvertTo-Json -Depth 6 -Compress
$latestBytes = [Text.Encoding]::UTF8.GetBytes($latest)
$sumsBytes = [Text.Encoding]::UTF8.GetBytes("$sha  app-release.apk`n")

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    $Port
)
$listener.Start()
Write-Host "Mock feed 已启动：$prefix" -ForegroundColor Green
Write-Host "  公网/模拟器下载地址：$PublicBase" -ForegroundColor Green
Write-Host "  GET $prefix/repos/mayapony/beancount/releases/latest"
Write-Host "  GET $prefix/app-release.apk（$([math]::Round($size / 1MB, 1)) MB）"
Write-Host "App 侧：flutter run --dart-define=UPDATE_API_BASE=$prefix"
Write-Host '按 Ctrl+C 停止。'

function Write-Response {
    param(
        [IO.Stream]$Stream,
        [int]$Status,
        [string]$ContentType,
        [byte[]]$Body
    )
    $reason = if ($Status -eq 200) { 'OK' } elseif ($Status -eq 404) { 'Not Found' } else { 'Error' }
    $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($Body, 0, $Body.Length)
    $Stream.Flush()
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.NoDelay = $true
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new(
                $stream,
                [Text.Encoding]::ASCII,
                $false,
                1024,
                $true
            )
            $requestLine = $reader.ReadLine()
            while ($null -ne ($line = $reader.ReadLine()) -and $line -ne '') {
                # 读完请求头即可；mock 不处理 body。
            }
            if ($null -eq $requestLine) { continue }

            $path = ($requestLine -split ' ')[1].Split('?')[0]
            switch ($path) {
                '/repos/mayapony/beancount/releases/latest' {
                    Write-Response $stream 200 'application/json' $latestBytes
                }
                '/app-release.apk' {
                    Write-Response $stream 200 'application/vnd.android.package-archive' $apkBytes
                }
                '/SHA256SUMS.txt' {
                    Write-Response $stream 200 'text/plain; charset=utf-8' $sumsBytes
                }
                default {
                    Write-Response $stream 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('not found'))
                }
            }
        } catch {
            Write-Host "请求处理失败：$($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            if ($null -ne $client) { $client.Close() }
        }
    }
} finally {
    $listener.Stop()
    Write-Host 'Mock feed 已停止。'
}
