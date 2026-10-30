# 将本地开发自签名证书导入 Windows「受信任的根证书颁发机构」。
#
# 目的：让 Chrome / Edge 完全信任 https://localhost:9015 与 https://<局域网IP>:9015，
#      访问时不再出现「您的连接不是私密连接」警告。
#
# 需以管理员身份运行：
#   powershell -ExecutionPolicy Bypass -File scripts/trust-dev-cert.ps1

$ErrorCRM = "SilentlyContinue"
$ErrorActionPreference = $ErrorCRM

$certPath = Join-Path $PSScriptRoot "..\certs\dev-cert.pem"

if (-not (Test-Path $certPath)) {
    Write-Host "未找到证书文件：$certPath" -ForegroundColor Red
    Write-Host "请先运行 npm run dev 生成证书，再执行本脚本。" -ForegroundColor Yellow
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "需要管理员权限：请以管理员身份打开 PowerShell 后重新执行。" -ForegroundColor Red
    exit 1
}

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2((Resolve-Path $certPath).Path)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$store.Open("ReadWrite")

# 避免重复导入
$existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
if ($existing) {
    Write-Host "证书已在受信任根中，无需重复导入。" -ForegroundColor Green
} else {
    $store.Add($cert)
    Write-Host "证书已导入「受信任的根证书颁发机构」：" -ForegroundColor Green
    Write-Host ("  主题：{0}" -f $cert.Subject)
    Write-Host ("  指纹：{0}" -f $cert.Thumbprint)
    Write-Host "请完全退出并重启浏览器后生效。" -ForegroundColor Yellow
}

$store.Close()
