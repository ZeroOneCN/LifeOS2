# 构建 Android release APK，并生成版本清单与静态下载产物。
#
# 为什么要有这个脚本：清单里的 versionCode / versionName / SHA-256 / 体积
# 必须来自实际产物，人工填写迟早和 APK 对不上；对不上的后果是「下载完校验失败」
# 或「系统拒绝安装」。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\build_release_apk.ps1 -BuildNumber 2009 -Notes "修复xxx"
#
# 产物：
#   backend\downloads\LifeOS-<version>-<code>.apk   可供 App 下载的安装包
#   backend\downloads\android.json                  版本清单（原子替换）
#
# 约束：签名沿用 debug 签名（build.gradle.kts 的 signingConfig 不动），
# 包名固定 com.lifeos.mobile；versionCode 必须比设备已装的大。

param(
    # 构建号（versionCode）。必须显式传入且单调递增，脚本不猜。
    [Parameter(Mandatory = $true)][int]$BuildNumber,
    # 语义版本（versionName），三段整数
    [string]$VersionName = "1.0.0",
    # 更新说明（纯文本，最多 500 字）
    [string]$Notes = "常规更新",
    # 清单渠道标识，当前只有 stable
    [string]$Channel = "stable",
    # 复用已构建的 APK（仅用于重跑清单生成；仍会用 aapt 校验版本号）
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile"
$releaseDir = Join-Path $repoRoot "backend\downloads"
$apkSource = Join-Path $mobileDir "build\app\outputs\flutter-apk\app-release.apk"
$flutter = "C:\Env\flutter\bin\flutter.bat"

if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
    throw "VersionName 必须是 major.minor.patch，当前为 $VersionName"
}
if ($Notes.Length -gt 500) {
    throw "Notes 最多 500 字，当前 $($Notes.Length) 字"
}

function Find-BuildTool([string]$name) {
    # 从高版本开始找，避免用到过旧的 aapt / apksigner
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"),
        "C:\Env\Android\SDK\build-tools"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Directory |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object {
                # 新版 build-tools 只带 apksigner.bat，旧版带 .exe，两种都要找
                $candidate = Join-Path $_.FullName "$name.exe"
                if (Test-Path $candidate) { $candidate }
                else { Join-Path $_.FullName "$name.bat" }
            } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    throw "找不到 $name.exe，请确认 Android build-tools 已安装"
}

Write-Host "[1/5] 构建 release APK（build-number=$BuildNumber）..." -ForegroundColor Cyan
# 只出 universal 包：清单只维护一个 versionCode，客户端不需要上报 ABI。
# 注意不要加 --split-per-abi，否则 Flutter 会给 versionCode 加 1000×ABI 偏移。
if ($SkipBuild -and (Test-Path $apkSource)) {
    Write-Host "  复用已有产物：$apkSource" -ForegroundColor Yellow
} else {
    Push-Location $mobileDir
    try {
        & $flutter build apk --release --build-name $VersionName --build-number $BuildNumber
        if ($LASTEXITCODE -ne 0) { throw "flutter build 失败" }
    } finally {
        Pop-Location
    }
}
if (-not (Test-Path $apkSource)) { throw "构建产物不存在：$apkSource" }

Write-Host "[2/5] 读取产物版本号..." -ForegroundColor Cyan
$aapt = Find-BuildTool "aapt"
$badging = & $aapt dump badging $apkSource
$codeLine = ($badging | Select-String "package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'").Matches[0]
$actualPackage = $codeLine.Groups[1].Value
$actualCode = [int]$codeLine.Groups[2].Value
$actualName = $codeLine.Groups[3].Value
if ($actualPackage -ne "com.lifeos.mobile") { throw "包名被改动：$actualPackage" }
if ($actualCode -ne $BuildNumber) {
    # 拆分 ABI 构建会自动加偏移；这里只发 universal 包，出现不一致说明构建方式变了
    throw "产物 versionCode=$actualCode 与请求的 $BuildNumber 不一致（是否改成了 split-per-abi？）"
}
if ($actualName -ne $VersionName) { throw "产物 versionName=$actualName 与请求的 $VersionName 不一致" }

Write-Host "[3/5] 校验签名与计算哈希..." -ForegroundColor Cyan
$apksigner = Find-BuildTool "apksigner"
$certOut = & $apksigner verify --print-certs $apkSource
$certLine = ($certOut | Select-String "certificate SHA-256 digest: ([0-9a-fA-F]+)")
$certSha = if ($certLine) { $certLine.Matches[0].Groups[1].Value.ToLower() } else { "" }
$hash = (Get-FileHash -Algorithm SHA256 -Path $apkSource).Hash.ToLower()
$size = (Get-Item $apkSource).Length

Write-Host "[4/5] 复制 APK 到发布目录..." -ForegroundColor Cyan
if (-not (Test-Path $releaseDir)) { New-Item -ItemType Directory -Path $releaseDir | Out-Null }
$apkName = "LifeOS-$actualName-$actualCode.apk"
Copy-Item -Force $apkSource (Join-Path $releaseDir $apkName)

Write-Host "[5/5] 原子写入版本清单..." -ForegroundColor Cyan
$manifest = [ordered]@{
    manifest_version     = 1
    platform             = "android"
    channel              = $Channel
    version_name         = $actualName
    version_code         = $actualCode
    download_url         = "/api/v1/downloads/$apkName"
    sha256               = $hash
    size                 = $size
    release_notes        = $Notes
    published_at         = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
    min_android_sdk      = 26
    signing_cert_sha256  = $certSha
}
$manifestPath = Join-Path $releaseDir "android.json"
$tmpPath = "$manifestPath.tmp"
# 必须写不带 BOM 的 UTF-8：PowerShell 5 的 -Encoding UTF8 会加 BOM，
# 部分 JSON 解析器（包括服务端）会直接报错
$json = $manifest | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
Move-Item -Force $tmpPath $manifestPath

Write-Host ""
Write-Host "完成" -ForegroundColor Green
Write-Host "  APK      : $(Join-Path $releaseDir $apkName)"
Write-Host "  version  : $actualName ($actualCode)"
Write-Host "  size     : $size"
Write-Host "  sha256   : $hash"
Write-Host "  cert     : $certSha"
Write-Host "  manifest : $manifestPath"
