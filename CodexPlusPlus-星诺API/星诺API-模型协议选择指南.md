# 星诺API × Codex++ 模型协议选择指南（Responses / Chat Completions）

在「供应商配置」页里，Base URL 已锁定为 `https://xingnuoapi.com/v1`，你只需要填 **API Key**、选 **模型**、选 **上游协议**。本指南说明主流模型该选哪种协议。

> 星诺API 基于 New API 网关，同时支持 OpenAI 的 `/v1/responses` 与 `/v1/chat/completions` 两种端点，并能把 Claude、Gemini 等转成 OpenAI 兼容格式。所以协议由**模型**决定。

---

## 一句话规则

- **Responses API** → 选给 **OpenAI 自家模型**（GPT 系列、o 系列、以及所有 `*-codex` 模型）。
- **Chat Completions** → 选给 **其它所有厂商模型**（Claude、DeepSeek、GLM、通义千问、Kimi、MiniMax、Gemini、Llama 等）。

记忆口诀：**「OpenAI 系走 Responses，非 OpenAI 走 Chat」**。

---

## 速查表

| 模型 / 系列 | 上游协议 | 备注 |
|---|---|---|
| GPT-5.x（gpt-5.5 / gpt-5.4 …） | **Responses** | OpenAI 旗舰，Codex 原生协议 |
| GPT-5-Codex / 任何 `*-codex` | **Responses** | Codex 专用，**必须** Responses |
| GPT-4.1 / GPT-4o | **Responses** | OpenAI 系 |
| o 系列（o3 / o4-mini 等推理模型） | **Responses** | OpenAI 推理模型 |
| Claude（Opus / Sonnet 4.x） | **Chat Completions** | 经兼容层转换 |
| DeepSeek（V3 / R 系列） | **Chat Completions** | |
| 智谱 GLM（glm-5.x） | **Chat Completions** | |
| 通义千问 Qwen（qwen3-coder / max） | **Chat Completions** | |
| Kimi（Moonshot k 系列） | **Chat Completions** | |
| MiniMax（M 系列） | **Chat Completions** | |
| Gemini（2.x / Flash / Pro） | **Chat Completions** | 兼容模式 |
| Llama / Mistral / Grok / 其它开源 | **Chat Completions** | |

> 拿不准某个模型时，先按上表；若报错，切换到另一种协议再试（见下方排查）。

---

## 为什么这样分

Codex 本体是围绕 OpenAI 的 **Responses API**（`/v1/responses`）设计的——它是 OpenAI 专有协议，支持推理、工具调用、状态化对话等完整能力，所以 OpenAI 自家模型（尤其 `*-codex`）走 Responses 体验最完整。

而 Claude、DeepSeek、GLM、Qwen 等**并不提供** OpenAI 的 Responses 端点。星诺API（New API）会把它们统一暴露成 OpenAI 的 **Chat Completions**（`/v1/chat/completions`）格式，所以这些模型选 Chat Completions 才能连通。

---

## 在 App 里怎么配置

1. 打开「供应商配置」页，点「+ 新建供应商」（或选预设「星诺API」一键填充）。
2. **Base URL**：已锁定为 `https://xingnuoapi.com/v1`，无需也无法修改。
3. **Key**：填你在星诺API 后台创建的 API Key。
4. **上游协议**：按上表选 `Responses API` 或 `Chat Completions`。
5. **模型**：填星诺API 支持的模型名（以你后台/文档里的名称为准）。
6. 保存并「测试」，通过即可切换启用。

> 小技巧：一个模型建一个供应商配置。用 GPT 时切到 Responses 那条，用 Claude 时切到 Chat Completions 那条，互不影响。

---

## 常见报错与排查

- **报错 404 / `responses` not found / `unknown endpoint`**：该模型在上游只支持 Chat Completions。→ 把协议改成 **Chat Completions**。
- **用 Claude/DeepSeek 等却选了 Responses，连不上或返回异常**：→ 改 **Chat Completions**。
- **用 GPT-Codex 选了 Chat Completions，工具调用/推理能力缺失或行为异常**：→ 改回 **Responses**。
- **仍失败**：确认模型名与星诺API 后台一致、API Key 有效、账户额度充足；再用「测试」按钮观察返回。

---

## 附：项目内置预设的协议对照（供参考）

以下取自 App 预设，可佐证上面的规则：

- 选 **Responses** 的：OpenAI Official、Azure OpenAI，以及走 OpenAI 直通的聚合站（星诺API、RunAPI、AiHubMix、APIKEY.FUN、PatewayAI、CCSub）——默认模型均为 GPT 系。
- 选 **Chat Completions** 的：DeepSeek、智谱 GLM、Kimi、通义千问、StepFun、MiniMax、火山 Ark、百度千帆、小米 MiMo、ModelScope、Longcat，以及 SiliconFlow、OpenRouter、Novita、TheRouter、胜算云等聚合站的非 OpenAI 路由。

> 注意：**同一模型在不同供应商可能协议不同**（如 gpt-5.5 在 OpenAI 官方是 Responses，在 OpenRouter/胜算云是 Chat Completions）。你已锁定星诺API，所以以星诺API 的支持为准：GPT/Codex 系走 Responses，其余走 Chat Completions。
