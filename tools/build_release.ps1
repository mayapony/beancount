# 一条命令出 release APK：pub get → analyze → test → build → 报路径与体积。
#
# 用法（仓库根目录）：
#   pwsh -File tools/build_release.ps1            # 完整校验 + 出包
#   pwsh -File tools/build_release.ps1 -SkipTests # 跳过测试（只出包）
#
# 签名：脚本不碰密钥。有 android/key.properties 时 Gradle 用它签名（与 CI 发布同一把），
# 没有时回退 debug 签名并在输出里提示——那种包只能自己装，别分发。
#
# 版本号：默认取最近的 git tag（v1.2.3 → 1.2.3）与提交数；也可显式传 -BuildName/-BuildNumber。
# versionCode 与 .github/workflows/release.yml 一致，都取 git rev-list --count HEAD。
# 真正的发布不走这个脚本，而是打 tag 让 .github/workflows/release.yml 跑（见 RELEASING.md）。

param(
    [switch]$SkipTests,
    [string]$BuildName,
    [string]$BuildNumber
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

if (-not $BuildName) {
    $tag = git describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -eq 0 -and $tag) { $BuildName = $tag.Trim().TrimStart('v') }
}
if (-not $BuildNumber) {
    $count = git rev-list --count HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $count) { $BuildNumber = $count.Trim() }
}

Invoke-Step '拉取依赖' { flutter pub get }
Invoke-Step '静态分析' { flutter analyze }

if (-not $SkipTests) {
    Invoke-Step '测试' { flutter test }
}

$buildArgs = @(
    'build', 'apk', '--release',
    '--target-platform=android-arm64',
    '--android-project-arg=beanOnlyAbi=arm64-v8a',
    '--android-project-arg=beanCompressLibs=true'
)
if ($BuildName) { $buildArgs += "--build-name=$BuildName" }
if ($BuildNumber) { $buildArgs += "--build-number=$BuildNumber" }
Invoke-Step "构建 release APK（$($BuildName ?? 'pubspec')+$($BuildNumber ?? 'pubspec')，arm64 / 压缩原生库）" { flutter @buildArgs }

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
if (Test-Path (Join-Path $root 'android/key.properties')) {
    Write-Host '签名：发布签名（android/key.properties 生效，可直接覆盖安装）。' -ForegroundColor Green
} else {
    Write-Host '签名：debug 签名 —— 只能自己装，不要分发。发布请打 tag 走 CI（见 RELEASING.md）。' -ForegroundColor Yellow
}
