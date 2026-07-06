# 星诺API 版 Codex++ —— 改造与打包说明

本文件说明本次对 CodexPlusPlus（Codex++ 管理程序）所做的品牌与配置改动，以及如何在 macOS 上生成 `.dmg` 安装包。

---

## 一、已完成的代码改动

全部改动集中在前端（`apps/codex-plus-manager/src`），已通过 `tsc` 类型检查与 Vite 生产构建验证。

### 1. 预览页（概览页）JOJO Code → 星诺API
文件：`apps/codex-plus-manager/src/App.tsx`（概览卡片 `OverviewScreen`）
- 卡片标题 `JOJO Code` → `星诺API`
- 「打开」按钮文案 `打开 JOJO Code` → `打开 星诺API`
- 按钮跳转地址 `https://jojocode.com/` → `https://xingnuoapi.com/`

### 2. 供应商预设
文件：`apps/codex-plus-manager/src/presets.ts`
- 原 `jojocode` 与 `jojocode-max` 两个预设，合并替换为单个 `星诺API` 预设：
  - `id: "xingnuoapi"`，`name: "星诺API"`
  - `websiteUrl` / `apiKeyUrl`：`https://xingnuoapi.com/`
  - `baseUrl`：`https://xingnuoapi.com/v1`

### 3. 供应商配置界面的 Base URL —— 彻底锁死
文件：`apps/codex-plus-manager/src/App.tsx`
- 新增常量 `LOCKED_BASE_URL = "https://xingnuoapi.com/v1"`。
- 供应商配置里的 **Base URL 输入框**改为**只读 + 禁用**，固定显示 `https://xingnuoapi.com/v1`，鼠标悬停提示「已锁定为星诺API，不可修改」。
- 新建供应商的默认 Base URL（`defaultSettings.relayBaseUrl`）改为星诺API 地址。
- `updateDraft` 中对任意改动强制写回 `LOCKED_BASE_URL`，即使通过预设选择等其他途径也无法把 Base URL 改成别的域名。

### 4. 国际化文案
文件：`apps/codex-plus-manager/src/i18n-en.ts`、`tools/i18n-keys.json`
- 翻译键 `打开 JOJO Code` → `打开 星诺API`（英文值 `Open Xingnuo API`）。

> 说明：`crates/codex-plus-core` 里的 Rust 单元测试中仍保留 `jojocode.com` 作为**测试夹具数据**（用于验证 URL 导入解析逻辑，不面向用户、不影响品牌显示），故未改动，以免破坏既有测试断言。

---

## 二、已验证内容（在 Linux 上可做的部分）

- `npm run check`（TypeScript 类型检查）：**通过，无错误**。
- `npm run vite:build`（前端生产构建）：**成功**。
- 检查打包产物：包含「星诺API」「xingnuoapi.com/v1」「已锁定为星诺API」等文本，且**无任何 `jojocode.com` / `JOJO Code` 品牌残留**。

---

## 三、在 macOS 上生成 .dmg

> ⚠️ `.dmg` 是 macOS 专属格式，打包依赖 Apple 工具链（`sips`、`iconutil`、`hdiutil`、`codesign` 等），**必须在 Mac 上执行**，无法在 Linux/Windows 上产出。

### 前置环境（一次性）
1. 安装 Xcode 命令行工具：`xcode-select --install`
2. 安装 Node.js 22：`brew install node@22`（或用 nvm）
3. 安装 Rust：`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

### 一键打包
在项目根目录执行：
```bash
bash build-dmg-mac.sh          # 自动识别当前 Mac 架构（Apple Silicon 或 Intel）
```
可选参数：
```bash
bash build-dmg-mac.sh arm64    # 强制 Apple Silicon
bash build-dmg-mac.sh x64      # 强制 Intel
VERSION=1.2.31 bash build-dmg-mac.sh   # 指定版本号
```
脚本完成后会打印 `.dmg` 路径，默认输出到：
```
dist/macos/CodexPlusPlus-<版本>-macos-<arch>.dmg
```

### 手动分步（等价于脚本内部逻辑）
```bash
# 1. 前端
cd apps/codex-plus-manager
npm install --package-lock=false
npm run vite:build
cd ../..

# 2. Rust 二进制（arm64 示例，Intel 用 x86_64-apple-darwin）
rustup target add aarch64-apple-darwin
cargo build --release --target aarch64-apple-darwin

# 3. 打包 DMG
BINARY_DIR="$PWD/target/aarch64-apple-darwin/release" \
  bash scripts/installer/macos/package-dmg.sh 1.2.31 arm64
```

### 安装与首次打开
- 打开 `.dmg`，将 `Codex++.app` 与 `Codex++ 管理工具.app` 拖入 `Applications`。
- 安装包未签名/未公证，若被 Gatekeeper 拦截提示「已损坏」，执行：
  ```bash
  sudo xattr -rd com.apple.quarantine "/Applications/Codex++ 管理工具.app"
  sudo xattr -rd com.apple.quarantine "/Applications/Codex++.app"
  ```
  或在「系统设置 → 隐私与安全性」中点『仍要打开』。

---

## 四、文件清单
- `build-dmg-mac.sh` —— 新增，macOS 一键打包脚本。
- `apps/codex-plus-manager/src/App.tsx` —— 预览页品牌/跳转、Base URL 锁定。
- `apps/codex-plus-manager/src/presets.ts` —— 星诺API 预设。
- `apps/codex-plus-manager/src/i18n-en.ts`、`tools/i18n-keys.json` —— 文案。
- `星诺API-改动.patch` —— 相对原仓库的完整改动 diff。

---

## 五、在 Windows 上生成 .exe

> ⚠️ Windows `.exe` 需要在 Windows 上用 MSVC + WebView2 工具链编译（项目 CI 也是在 Windows runner 上打包），**无法在 Linux/macOS 上可靠产出**。品牌与 Base URL 锁定改动是共用同一套前端，Windows 版**自动生效，无需另改**。

### 前置环境（一次性）
1. 安装 Node.js 22：https://nodejs.org
2. 安装 Rust（MSVC 工具链）：https://win.rustup.rs
3. 安装 Visual Studio Build Tools（含「使用 C++ 的桌面开发」工作负载）
4. （打安装包才需要）安装 NSIS：`choco install nsis -y` 或 https://nsis.sourceforge.io

### 一键打包
在项目根目录、PowerShell 中执行：
```powershell
powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1
```
可选参数：
```powershell
# 指定版本号
powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1 -Version 1.2.31
# 只产出裸 exe，不打 NSIS 安装包
powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1 -SkipInstaller
```

产物：
- 裸可执行文件：`target\release\codex-plus-plus.exe`、`target\release\codex-plus-plus-manager.exe`
- NSIS 安装包：`dist\windows\CodexPlusPlus-<版本>-windows-x64-setup.exe`

### 手动分步（等价于脚本内部逻辑）
```powershell
# 1. 前端
cd apps\codex-plus-manager
npm install --package-lock=false
npm run vite:build
cd ..\..

# 2. Rust 二进制
cargo build --release

# 3. 打安装包（可选）
New-Item -ItemType Directory -Force dist\windows\app | Out-Null
Copy-Item target\release\codex-plus-plus.exe         dist\windows\app\
Copy-Item target\release\codex-plus-plus-manager.exe dist\windows\app\
cd scripts\installer\windows
& "${env:ProgramFiles(x86)}\NSIS\makensis.exe" /INPUTCHARSET UTF8 /DVERSION=1.2.31 CodexPlusPlus.nsi
```

新增文件：`build-exe-win.ps1` —— Windows 一键打包脚本。

---

## 六、如何跟随上游更新，并保留改造效果

项目会不定期更新。推荐用下面的**幂等改造脚本**方式，保持上游源码原样，每次更新后一键重新打上改造。

### 方式 A（推荐）：幂等改造脚本 `apply-xingnuo.mjs`
改造只集中在少数几行，脚本会自动重新应用「星诺API 品牌 + 跳转 + Base URL 锁定」，且：
- 可重复运行：已改过的会跳过（幂等）。
- 会自检：若上游改动了被改的那几行，脚本会**警告**并提示手动确认，而不是静默出错。

更新流程（三步）：
```bash
git pull                 # 或重新下载/克隆上游新版本
node apply-xingnuo.mjs   # 重新打上星诺API改造（node 是打包必备，已具备）
# 然后按第三/五节重新打包：
bash build-dmg-mac.sh          # macOS
# 或 Windows：
# powershell -ExecutionPolicy Bypass -File .\build-exe-win.ps1
```
> 说明：把 `apply-xingnuo.mjs`、`build-dmg-mac.sh`、`build-exe-win.ps1` 三个文件保存在项目根目录即可，它们不属于上游文件，`git pull` 不会覆盖它们。

### 方式 B：Git fork + 合并上游
适合熟悉 git 的用户，改动作为真实提交保留：
```bash
# 一次性设置：在 GitHub fork 后
git clone <你的fork地址>
git remote add upstream https://github.com/BigPizzaV3/CodexPlusPlus.git
# 把改造提交到自己的分支（可直接用方式A脚本改完后提交）
node apply-xingnuo.mjs && git add -A && git commit -m "星诺API 改造"

# 之后每次更新：
git fetch upstream
git rebase upstream/main      # 或 git merge upstream/main
# 若我改过的那几行上游也动了，会提示冲突，手动解决后：
git rebase --continue
```

### 两种方式对比
- 方式 A：最省心、最抗更新，不需要懂 git 冲突；只有当上游恰好改了被替换的那几行时才需手动看一眼（脚本会警告）。
- 方式 B：保留完整 git 历史，适合长期维护；冲突需自己解决。

> 实测：本脚本在上游 1.2.31 与随后发布的 1.2.32 上均一次性干净应用，类型检查与前端构建均通过。

---

## 七、把「自动更新」指向你自己的仓库

App 内置自更新逻辑在 `crates/codex-plus-core/src/update.rs`：启动/检查时会下载一个 `latest.json`（含最新版本号与安装包下载地址），比对版本后从该地址下载 `.dmg/.exe` 安装。原版指向作者仓库 `BigPizzaV3/CodexPlusPlus`——**若不改，你的用户一"更新"就会被拉回原版 JOJO Code**。

### 需要改什么（脚本已自动处理）
`apply-xingnuo.mjs` 顶部把 `MY_REPO` 改成你的 `owner/repo` 后重跑，即会自动改：
- `update.rs` 的 `DEFAULT_REPOSITORY` 与 `DEFAULT_LATEST_JSON_URL` → 指向你的仓库；
- 「关于」页的项目地址、打开仓库、issues 三个链接 → 指向你的仓库。
- （精确匹配，不会误伤脚本市场仓库 `...CodexPlusPlusScriptMarket`。）

```js
// apply-xingnuo.mjs 顶部
const MY_REPO = "yourname/CodexPlusPlus";   // ← 改成你的 GitHub owner/repo
const MY_LATEST_JSON_URL = "";               // 自建服务器托管 latest.json 时填完整 URL，否则留空
```
自建服务器：把 `MY_LATEST_JSON_URL` 填成你托管的 `latest.json` 完整地址即可（格式见下）。

### 发布侧：你的仓库怎么产出更新（关键）
好消息：发布用的 GitHub Actions（`.github/workflows/release-assets.yml`）里的 `latest.json` 是用 `${{ github.repository }}` **动态生成**的——在**你自己的仓库**发 Release 时，它会自动生成指向你仓库下载地址的 `latest.json`，**这个 workflow 不用改**。

步骤：
1. 在 GitHub **Fork** 本项目到你的账号（得到 `yourname/CodexPlusPlus`）。
2. 在 fork 仓库 **Settings → Actions** 里启用 Actions。
3. 本地：设置 `MY_REPO` 并跑 `node apply-xingnuo.mjs`，提交推送到你的 fork。
4. **提升版本号**：把根 `Cargo.toml` 的 `version` 改大（更新检测是"新版本号 > 当前版本"才触发）。
5. 在你的仓库 **Releases → Draft a new release**，打一个 tag（如 `v1.3.0`）并 **Publish**。
6. `release-assets.yml` 会自动：构建 Windows/macOS 安装包 → 生成 `latest.json` → 全部作为 Release 资产上传。
7. 之后你分发的 App 检查更新时，就会从 `https://github.com/yourname/CodexPlusPlus/releases/latest/download/latest.json` 读到你的新版本并下载你的安装包。

### latest.json 格式（自建服务器时参考）
```json
{
  "version": "v1.3.0",
  "url": "https://github.com/yourname/CodexPlusPlus/releases/tag/v1.3.0",
  "body": "更新说明……",
  "assets": [
    { "name": "CodexPlusPlus-1.3.0-macos-arm64.dmg", "url": "https://.../CodexPlusPlus-1.3.0-macos-arm64.dmg" },
    { "name": "CodexPlusPlus-1.3.0-windows-x64-setup.exe", "url": "https://.../...setup.exe" }
  ]
}
```

### 小结：你的完整发版流程
```bash
git pull                       # 同步上游最新代码
# 编辑 apply-xingnuo.mjs 顶部 MY_REPO（首次）
node apply-xingnuo.mjs         # 打上星诺API改造 + 更新源指向你的仓库
# 提升 Cargo.toml version
git add -A && git commit -m "星诺API vX.Y.Z" && git push   # 推到你的 fork
# 在 GitHub 发 Release → Actions 自动构建并上传安装包 + latest.json
```
