# 星诺API 改造工作记录（Notion 粘贴版）

以下为逐条记录，方便手动填入 Notion 数据库。每条对应一行。

---

## 1. 品牌替换：JOJO Code → 星诺API
- **状态**：已完成
- **分类**：品牌改造
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：App.tsx (OverviewScreen ~L2296-2325), i18n-en.ts, i18n-keys.json
- **说明**：预览/概览页的标题、按钮文字、跳转链接全部从 JOJO Code / jojocode.com 替换为 星诺API / xingnuoapi.com

## 2. 供应商预设替换
- **状态**：已完成
- **分类**：品牌改造
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：presets.ts
- **说明**：删除 jojocode + jojocode-max 两个预设，替换为单个 xingnuoapi 预设（name: 星诺API, baseUrl: https://xingnuoapi.com/v1, protocol: responses, model: gpt-5.5）

## 3. Base URL 锁死为星诺API
- **状态**：已完成
- **分类**：核心功能
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：App.tsx (RelayProfileEditor ~L4000, ~L4155)
- **说明**：供应商配置界面 Base URL 彻底锁死为 https://xingnuoapi.com/v1。三重保障：输入框 readOnly+disabled、updateDraft 强制回写 LOCKED_BASE_URL、新建配置默认值也锁定。选择其它预设也会被强制锁回。

## 4. 自动更新源指向用户仓库
- **状态**：已完成
- **分类**：更新机制
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：crates/codex-plus-core/src/update.rs (L6-8)
- **说明**：DEFAULT_REPOSITORY → loongllee/xingnuoapi，DEFAULT_LATEST_JSON_URL → 用户仓库的 releases/latest/download/latest.json

## 5. 关于页链接改为用户仓库
- **状态**：已完成
- **分类**：品牌改造
- **优先级**：中
- **完成日期**：2026-07-05
- **涉及文件**：App.tsx (~L3342-3349)
- **说明**：项目主页、仓库按钮、Issues 按钮三处链接从 BigPizzaV3/CodexPlusPlus 改为 loongllee/xingnuoapi

## 6. 编写幂等 codemod 脚本
- **状态**：已完成
- **分类**：工具脚本
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：apply-xingnuo.mjs (156行)
- **说明**：15 条变换规则覆盖 6 个区域，每条规则有 done 标记（幂等检测）+ find/replace。MY_REPO 写死为 loongllee/xingnuoapi。已在 v1.2.31 和 v1.2.32 两版测试通过。用法：git pull 上游 → node apply-xingnuo.mjs → 重新打包

## 7. 编写 macOS 打包脚本
- **状态**：已完成
- **分类**：构建部署
- **优先级**：中
- **完成日期**：2026-07-05
- **涉及文件**：build-dmg-mac.sh (75行)
- **说明**：自动检测架构（arm64/x64），依次执行 npm install → tsc check → vite build → cargo build → package-dmg.sh。仅能在 macOS 上运行。

## 8. 编写 Windows 打包脚本
- **状态**：已完成
- **分类**：构建部署
- **优先级**：中
- **完成日期**：2026-07-05
- **涉及文件**：build-exe-win.ps1 (81行)
- **说明**：PowerShell 脚本，依次执行 npm install → tsc check → vite build → cargo build → NSIS makensis。仅能在 Windows 上运行。

## 9. 编写改造与打包说明文档
- **状态**：已完成
- **分类**：文档
- **优先级**：中
- **完成日期**：2026-07-05
- **涉及文件**：星诺API-改造与打包说明.md (253行)
- **说明**：完整文档覆盖所有改动清单、Mac/Win 构建步骤、上游同步工作流、更新源配置、latest.json 格式说明

## 10. 编写模型协议选择指南
- **状态**：已完成
- **分类**：文档
- **优先级**：中
- **完成日期**：2026-07-05
- **涉及文件**：星诺API-模型协议选择指南.md (76行)
- **说明**：核心规则——OpenAI 系模型（GPT/o系列/*-codex）→ Responses API；非 OpenAI 模型（Claude/DeepSeek/GLM/Qwen/Kimi 等）→ Chat Completions。含速查表、配置步骤、常见报错排查。

## 11. 验证：脚本市场仓库不受影响
- **状态**：已完成
- **分类**：质量保证
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：apply-xingnuo.mjs
- **说明**：确认所有替换使用精确字符串匹配，BigPizzaV3/CodexPlusPlusScriptMarket（脚本市场，独立仓库）完全不受影响

## 12. 验证：TypeScript 编译通过
- **状态**：已完成
- **分类**：质量保证
- **优先级**：高
- **完成日期**：2026-07-05
- **涉及文件**：全部 .ts/.tsx 文件
- **说明**：改造后 tsc 编译 EXIT=0，无类型错误

---

**项目概要**
- **项目**：CodexPlusPlus 星诺API 品牌改造
- **上游仓库**：BigPizzaV3/CodexPlusPlus
- **用户 Fork**：loongllee/xingnuoapi
- **基线版本**：v1.2.32
- **技术栈**：Tauri (Rust 后端 + React/TypeScript 前端)
- **核心约束**：Base URL 锁死 https://xingnuoapi.com/v1 | 更新源指向用户仓库 | 脚本市场仓库不得修改
