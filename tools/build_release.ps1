# 一条命令出 release APK：pub get → analyze → test → build → 报路径与体积。
#
# 用法（仓库根目录）：
#   pwsh -File tools/build_release.ps1            # 完整校验 + 出包
#   pwsh -File tools/build_release.ps1 -SkipTests # 跳过测试（只出包）
#
# 签名：脚本不碰密钥。有 android/key.properties 时 Gradle 用它签名，
# 没有时 Flutter 会用 debug 签名并在输出里提示——发布前记得配好。

param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name 失败（exit $LASTEXITCODE）"
    }
}

Invoke-Step '拉取依赖' { flutter pub get }
Invoke-Step '静态分析' { flutter analyze }

if (-not $SkipTests) {
    Invoke-Step '测试' { flutter test }
}

Invoke-Step '构建 release APK' { flutter build apk --release }

$apk = Join-Path $root 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $apk)) {
    throw "没找到产物：$apk"
}

$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.Substring(0, 16)

Write-Host ''
Write-Host '产物：' -NoNewline
Write-Host $apk -ForegroundColor Green
Write-Host "体积：$sizeMb MB"
Write-Host "SHA256 前 16 位：$sha"
if (-not (Test-Path (Join-Path $root 'android/key.properties'))) {
    Write-Host '注意：没有 android/key.properties，这次用的是 debug 签名（不能上架）。' -ForegroundColor Yellow
}
