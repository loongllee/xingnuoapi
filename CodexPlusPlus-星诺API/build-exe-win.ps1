# =============================================================================
# 星诺API 版 Codex++ —— Windows 一键打包 .exe 脚本 (PowerShell)
# =============================================================================
# 用法（在项目根目录，PowerShell 中执行）：
#   powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1
#   powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1 -Version 1.2.31
#   powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1 -SkipInstaller  # 只产出裸 exe，不打 NSIS 安装包
#
# 必须在 Windows 上运行。需要：Node.js 22、Rust(MSVC)、（可选）NSIS。
# =============================================================================
param(
  [string]$Version = "",
  [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Error "缺少命令：$cmd。$hint"
    exit 1
  }
}

Write-Host "==> 环境检查"
Need node  "请安装 Node.js 22 (https://nodejs.org)。"
Need npm   "请安装 Node.js（含 npm）。"
Need cargo "请安装 Rust: https://win.rustup.rs 并选择 MSVC 工具链。"

# 版本号：参数优先，否则读 Cargo.toml
if (-not $Version) {
  $line = Select-String -Path "Cargo.toml" -Pattern '^version\s*=' | Select-Object -First 1
  if ($line -and $line.Line -match '"([^"]+)"') { $Version = $Matches[1] } else { $Version = "0.0.0" }
}
Write-Host "==> 版本: $Version"

# ---- 1. 前端 --------------------------------------------------------------
Write-Host "==> [1/5] 安装前端依赖"
Push-Location "apps\codex-plus-manager"
npm install --package-lock=false
Write-Host "==> [2/5] 前端类型检查"
npm run check
Write-Host "==> [3/5] 构建前端产物 (dist/)"
npm run vite:build
Pop-Location

# ---- 2. Rust 发行版二进制 -------------------------------------------------
Write-Host "==> [4/5] 编译 Rust 发行版二进制（首次较慢）"
cargo build --release

$appDir = "dist\windows\app"
New-Item -ItemType Directory -Force $appDir | Out-Null
Copy-Item "target\release\codex-plus-plus.exe"         $appDir -Force
Copy-Item "target\release\codex-plus-plus-manager.exe" $appDir -Force
Write-Host "    裸二进制已生成："
Write-Host "      $Root\target\release\codex-plus-plus.exe"
Write-Host "      $Root\target\release\codex-plus-plus-manager.exe"

# ---- 3. NSIS 安装包 -------------------------------------------------------
if ($SkipInstaller) {
  Write-Host "==> 已跳过 NSIS 安装包（-SkipInstaller）。"
} else {
  $makensis = Join-Path ${env:ProgramFiles(x86)} "NSIS\makensis.exe"
  if (-not (Test-Path $makensis)) {
    if (Get-Command makensis -ErrorAction SilentlyContinue) { $makensis = "makensis" }
    else {
      Write-Warning "未找到 NSIS（makensis）。请先 `choco install nsis -y` 或从 https://nsis.sourceforge.io 安装；"
      Write-Warning "已生成裸 exe，跳过安装包。"
      exit 0
    }
  }
  Write-Host "==> [5/5] 生成 Windows 安装包 (NSIS)"
  Push-Location "scripts\installer\windows"
  & $makensis "/INPUTCHARSET" "UTF8" "/DVERSION=$Version" "CodexPlusPlus.nsi"
  Pop-Location
  Write-Host ""
  Write-Host "✅ 打包完成！安装包路径："
  Write-Host "   $Root\dist\windows\CodexPlusPlus-$Version-windows-x64-setup.exe"
}
