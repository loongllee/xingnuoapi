#!/usr/bin/env node
/* =============================================================================
 * 星诺API 版 Codex++ —— 幂等改造脚本
 * -----------------------------------------------------------------------------
 * 作用：把上游原版源码，自动改造成「星诺API」版：
 *   1) 品牌 + 跳转 + Base URL 锁定；
 *   2) 自动更新源改指向你自己的仓库（含「关于」页链接）。
 * 特点：可重复运行；已改过则跳过；上游改动锚点会告警而非静默失败。
 *
 * 用法（项目根目录）：node apply-xingnuo.mjs
 * 跟随上游更新：git pull → node apply-xingnuo.mjs → 重新打包
 * ============================================================================= */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

/* ======================= 配置区（按需修改） =========================
 * MY_REPO：你的 GitHub 仓库 owner/repo。保持占位符 "OWNER/REPO" 时，
 *          会【跳过】更新源改造（品牌改造仍会执行）。
 * MY_LATEST_JSON_URL：自建服务器托管 latest.json 时填完整 URL；
 *          留空则用上面的 GitHub 仓库自动推导为 GitHub Release 地址。
 * ================================================================== */
const MY_REPO = "loongllee/xingnuoapi";
const MY_LATEST_JSON_URL = "";
/* ================================================================== */

const ROOT = dirname(fileURLToPath(import.meta.url));
const LOCKED = "https://xingnuoapi.com/v1";
let applied = 0, skipped = 0, warned = 0;

function processFile(relPath, rules) {
  const p = join(ROOT, relPath);
  if (!existsSync(p)) { console.error(`  ✗ 文件不存在: ${relPath}`); warned++; return; }
  let s = readFileSync(p, "utf8");
  const before = s;
  for (const r of rules) {
    if (s.includes(r.done)) { console.log(`  ○ 已应用，跳过：${r.label}`); skipped++; continue; }
    if (r.insertAfter !== undefined) {
      if (!s.includes(r.insertAfter)) { console.warn(`  ! 找不到插入锚点，请手动检查：${r.label}`); warned++; continue; }
      s = s.replace(r.insertAfter, r.insertAfter + r.insert);
    } else {
      if (!s.includes(r.find)) { console.warn(`  ! 找不到原文（上游可能已改动），请手动检查：${r.label}`); warned++; continue; }
      s = s.replace(r.find, r.replace);
    }
    console.log(`  ✓ ${r.label}`); applied++;
  }
  if (s !== before) writeFileSync(p, s);
}

console.log("== 星诺API 改造开始 ==");

/* ---------- 一、品牌 + 跳转 + Base URL 锁定 ---------- */
console.log("[1] apps/codex-plus-manager/src/App.tsx（品牌/锁定）");
processFile("apps/codex-plus-manager/src/App.tsx", [
  { label: "新增 LOCKED_BASE_URL 常量", done: "const LOCKED_BASE_URL =",
    insertAfter: 'const SCRIPT_MARKET_REPOSITORY_URL = "https://github.com/BigPizzaV3/CodexPlusPlusScriptMarket";',
    insert: `\n// 星诺API：供应商配置的 Base URL 已锁定，用户不可修改。\nconst LOCKED_BASE_URL = "${LOCKED}";` },
  { label: "默认 relayBaseUrl 锁定为星诺API", done: "relayBaseUrl: LOCKED_BASE_URL,",
    find: '  relayBaseUrl: "",', replace: "  relayBaseUrl: LOCKED_BASE_URL," },
  { label: "概览页标题 JOJO Code → 星诺API", done: "<h2>星诺API</h2>",
    find: "<h2>JOJO Code</h2>", replace: "<h2>星诺API</h2>" },
  { label: "概览页按钮跳转 → xingnuoapi.com", done: 'openExternalUrl("https://xingnuoapi.com/")',
    find: 'actions.openExternalUrl("https://jojocode.com/")', replace: 'actions.openExternalUrl("https://xingnuoapi.com/")' },
  { label: "概览页按钮文案 → 打开 星诺API", done: '{t("打开 星诺API")}',
    find: '{t("打开 JOJO Code")}', replace: '{t("打开 星诺API")}' },
  { label: "updateDraft 强制锁定 Base URL", done: "const lockedPatch = { ...patch, baseUrl: LOCKED_BASE_URL };",
    find: "  const updateDraft = (patch: Partial<RelayProfile>) => {\n    onProfileChange(applyRelayProfilePatchToFiles(profile, patch, { allowGenerateFiles: isNew }));\n  };",
    replace: "  const updateDraft = (patch: Partial<RelayProfile>) => {\n    // 星诺API：强制锁定 Base URL，任何改动都不会覆盖它。\n    const lockedPatch = { ...patch, baseUrl: LOCKED_BASE_URL };\n    onProfileChange(applyRelayProfilePatchToFiles(profile, lockedPatch, { allowGenerateFiles: isNew }));\n  };" },
  { label: "Base URL 输入框设为只读锁定", done: 'title={t("已锁定为星诺API，不可修改")}',
    find: '            <Field className="relay-field-base-url" label="Base URL">\n              <Input\n                value={profile.baseUrl}\n                onChange={(event) => updateDraft({ baseUrl: event.currentTarget.value })}\n                placeholder={t("填写中转服务 Base URL")}\n              />\n            </Field>',
    replace: '            <Field className="relay-field-base-url" label="Base URL">\n              <Input\n                value={LOCKED_BASE_URL}\n                readOnly\n                disabled\n                title={t("已锁定为星诺API，不可修改")}\n              />\n            </Field>' },
]);

console.log("[2] apps/codex-plus-manager/src/presets.ts");
processFile("apps/codex-plus-manager/src/presets.ts", [
  { label: "jojocode 预设 → 星诺API 预设", done: 'id: "xingnuoapi"',
    find:
`  {
    id: "jojocode",
    name: "JOJO Code",
    websiteUrl: "https://jojocode.com/",
    apiKeyUrl: "https://jojocode.com/",
    category: "aggregator",
    baseUrl: "https://jojocode.com/v1",
    protocol: "responses",
    model: "gpt-5.5",
  },
  {
    id: "jojocode-max",
    name: "JOJO Code 包月",
    websiteUrl: "https://max.jojocode.com/",
    apiKeyUrl: "https://max.jojocode.com/",
    category: "aggregator",
    baseUrl: "https://max.jojocode.com/v1",
    protocol: "responses",
    model: "gpt-5.5",
  },`,
    replace:
`  {
    id: "xingnuoapi",
    name: "星诺API",
    websiteUrl: "https://xingnuoapi.com/",
    apiKeyUrl: "https://xingnuoapi.com/",
    category: "aggregator",
    baseUrl: "https://xingnuoapi.com/v1",
    protocol: "responses",
    model: "gpt-5.5",
  },` },
]);

console.log("[3] apps/codex-plus-manager/src/i18n-en.ts");
processFile("apps/codex-plus-manager/src/i18n-en.ts", [
  { label: "英文文案键 打开 星诺API", done: '"打开 星诺API":',
    find: '  "打开 JOJO Code": "Open JOJO Code",', replace: '  "打开 星诺API": "Open Xingnuo API",' },
]);

console.log("[4] tools/i18n-keys.json");
processFile("tools/i18n-keys.json", [
  { label: "i18n key 列表 打开 星诺API", done: '"打开 星诺API",',
    find: '    "打开 JOJO Code",', replace: '    "打开 星诺API",' },
]);

/* ---------- 二、自动更新源改指向你的仓库 ---------- */
const configured = MY_REPO !== "OWNER/REPO" && MY_REPO.includes("/");
const latestJson = MY_LATEST_JSON_URL || `https://github.com/${MY_REPO}/releases/latest/download/latest.json`;

if (!configured) {
  console.log("[5] 更新源：未设置 MY_REPO（仍为 OWNER/REPO 占位符），已跳过更新源改造。");
  console.log("     → 打开本脚本顶部把 MY_REPO 改成你的 owner/repo，再重跑即可。");
} else {
  console.log(`[5] crates/codex-plus-core/src/update.rs（更新源 → ${MY_REPO}）`);
  processFile("crates/codex-plus-core/src/update.rs", [
    { label: "DEFAULT_REPOSITORY → 你的仓库", done: `DEFAULT_REPOSITORY: &str = "${MY_REPO}"`,
      find: 'pub const DEFAULT_REPOSITORY: &str = "BigPizzaV3/CodexPlusPlus";',
      replace: `pub const DEFAULT_REPOSITORY: &str = "${MY_REPO}";` },
    { label: "DEFAULT_LATEST_JSON_URL → 你的 latest.json", done: `"${latestJson}"`,
      find: '"https://github.com/BigPizzaV3/CodexPlusPlus/releases/latest/download/latest.json"',
      replace: `"${latestJson}"` },
  ]);

  console.log("[6] apps/codex-plus-manager/src/App.tsx（关于页链接 → 你的仓库）");
  processFile("apps/codex-plus-manager/src/App.tsx", [
    { label: "关于页 项目地址文本", done: `value="github.com/${MY_REPO}"`,
      find: 'value="github.com/BigPizzaV3/CodexPlusPlus"', replace: `value="github.com/${MY_REPO}"` },
    { label: "关于页 打开仓库按钮", done: `openExternalUrl("https://github.com/${MY_REPO}")`,
      find: 'actions.openExternalUrl("https://github.com/BigPizzaV3/CodexPlusPlus")',
      replace: `actions.openExternalUrl("https://github.com/${MY_REPO}")` },
    { label: "关于页 issues 按钮", done: `openExternalUrl("https://github.com/${MY_REPO}/issues")`,
      find: 'actions.openExternalUrl("https://github.com/BigPizzaV3/CodexPlusPlus/issues")',
      replace: `actions.openExternalUrl("https://github.com/${MY_REPO}/issues")` },
  ]);
}

console.log("== 完成 ==");
console.log(`应用 ${applied} 处，跳过（已存在）${skipped} 处，警告 ${warned} 处。`);
if (warned > 0) { console.log("⚠ 有警告：通常说明上游改动了对应代码，请手动确认。"); process.exit(2); }
