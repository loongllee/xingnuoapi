#!/usr/bin/env bash
# =============================================================================
# 星诺API 版 Codex++ —— macOS 一键打包 .dmg 脚本
# =============================================================================
# 用法（在项目根目录执行）：
#   bash build-dmg-mac.sh              # 自动识别当前 Mac 架构
#   bash build-dmg-mac.sh arm64        # 强制 Apple Silicon
#   bash build-dmg-mac.sh x64          # 强制 Intel
#   VERSION=1.2.31 bash build-dmg-mac.sh   # 指定版本号
#
# 必须在 macOS 上运行（依赖 Xcode 命令行工具、sips、iconutil、hdiutil、codesign）。
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---- 0. 环境检查 ----------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ 该脚本只能在 macOS 上运行（生成 .dmg 需要 Apple 专属工具链）。" >&2
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ 缺少命令：$1，请先安装。" >&2; exit 1; }; }
need node; need npm; need cargo; need rustup
need hdiutil; need sips; need iconutil; need codesign

# ---- 1. 架构与目标 --------------------------------------------------------
ARCH="${1:-}"
if [[ -z "$ARCH" ]]; then
  case "$(uname -m)" in
    arm64) ARCH="arm64" ;;
    x86_64) ARCH="x64" ;;
    *) echo "❌ 未知架构：$(uname -m)" >&2; exit 1 ;;
  esac
fi
case "$ARCH" in
  arm64) TARGET="aarch64-apple-darwin" ;;
  x64)   TARGET="x86_64-apple-darwin" ;;
  *) echo "❌ 架构参数只能是 arm64 或 x64，收到：$ARCH" >&2; exit 1 ;;
esac

VERSION="${VERSION:-$(grep -m1 '^version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')}"
VERSION="${VERSION:-0.0.0}"

echo "==> 架构: $ARCH  |  Rust target: $TARGET  |  版本: $VERSION"

# ---- 2. 安装 Rust 目标 ----------------------------------------------------
echo "==> 确认 Rust target 已安装"
rustup target add "$TARGET" >/dev/null 2>&1 || true

# ---- 3. 构建前端（Vite） --------------------------------------------------
echo "==> [1/4] 安装前端依赖"
( cd apps/codex-plus-manager && npm install --package-lock=false )
echo "==> [2/4] 前端类型检查"
( cd apps/codex-plus-manager && npm run check )
echo "==> [3/4] 构建前端产物 (dist/)"
( cd apps/codex-plus-manager && npm run vite:build )

# ---- 4. 构建 Rust 发行版二进制 --------------------------------------------
echo "==> [4/4] 编译 Rust 发行版二进制（首次较慢）"
cargo build --release --target "$TARGET"

# ---- 5. 打包 DMG ----------------------------------------------------------
echo "==> 生成 .dmg"
DMG_PATH="$(BINARY_DIR="$PWD/target/$TARGET/release" \
  bash scripts/installer/macos/package-dmg.sh "$VERSION" "$ARCH")"

echo ""
echo "✅ 打包完成！"
echo "   DMG 路径: $DMG_PATH"
echo ""
echo "提示：安装包未签名/未公证，首次打开若被 Gatekeeper 拦截，"
echo "     可在「系统设置 → 隐私与安全性」中点『仍要打开』，"
echo "     或执行：sudo xattr -rd com.apple.quarantine \"/Applications/Codex++ 管理工具.app\""
