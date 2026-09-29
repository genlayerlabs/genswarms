# zh-Hans concept ledger: GenSwarms landing page

Sources read: design/2026-09-25-copy-deck-v2.md (approved English and why v2 dropped escalation/human-review claims),
docs/architecture.md (supervision tree, SwarmManager, IR gate), docs/intermediate-representation.md (seed, overlay,
restore), docs/messaging.md (`invalid_route`: message dropped), docs/objects.md (objects = deterministic Elixir
handlers), README; the translator concept notes; the rendered en page.
Approved vocabulary reused (playbook §8.4): GenLayer Labs homepage `zh.ledger.md` / `zh.json` (智能体, 监督者, 集群,
模型, 语言, 文档) and the SubZeroClaw zh page (技能文件, 沙箱, MIT 许可证, 复制/已复制, 关闭, suggestion-bar strings
verbatim).

Register: mainland developer marketing, same voice as the Labs and SubZeroClaw zh pages: plain, short, confident, 你
(not 您). Conventions: a space between CJK and Latin/digits ("AI 智能体", "100 个"); full-width punctuation; 、 between
list items; em dash ——.

## Objects

| Concept | Source term | Meaning (source) | Keep distinct from | zh | Avoid | Source |
|---|---|---|---|---|---|---|
| operating system | operating system | analogy for the whole product (computer OS) | platform, framework | 操作系统 | 平台, 系统平台 | copy deck "OS story"; step 3 |
| AI workforce | AI workforces | the vision: many agents as an organisation's staff | a swarm/team; labour statistics | AI 员工 (title, h1, footer, JSON-LD) | 劳动力 (labour-market/statistics register), 数字劳动力 | concepts.md |
| agent | agent | LLM-backed worker, one process each | object; model | 智能体 | 代理 | Labs zh |
| object | object | deterministic Elixir handler on the same message graph | agent | 对象 (legend "对象，普通代码") | 物体, 实体 | docs/objects.md "plain Elixir module that runs deterministic code" |
| model | model | the LLM an agent uses | agent | 模型 | 大模型 | Labs zh |
| process | process | OTP process; each agent is one | business process, 流程 | 进程 | 流程, 过程 | architecture.md "AgentServer (per agent)" |
| sandbox / boundary | sandbox; "its boundary" (figure 4) | per-agent isolation (bwrap, Docker, Apple container) | — | 沙箱; 边界 | 沙盒 | SubZeroClaw zh 沙箱 |
| supervisor | supervisor | OTP supervisor that restarts a crashed process; software | a human boss | 监督者 ("由自己的监督者看管") | 主管, 管理员, 老板 | architecture.md supervision tree; Labs zh 监督者 |
| crash / restart / fail | crash, restart, fail | process dies / supervisor starts it again; "fails" in step 2–3 is the general case | — | 崩溃 / 重启 / 出故障 | 失败 for crash | architecture.md |
| declared path, the graph | declared paths; graph | directed message topology you declare; only route messages take | workflow, pipeline | 声明的路径 (body, spec, guarantees); 声明路径 (step-5 headline, for the line break); 图 | 工作流, 管道 | messaging.md |
| message / hop | message, hop | what agents send; checked at each hop | notification | 消息; 每一跳 | 通知 | messaging.md |
| dropped | dropped | off-graph message discarded (`invalid_route`) | lost, deleted | 丢弃 / 已丢弃 | 丢失, 删除 | messaging.md "the message is dropped" |
| swarm | swarm | running set of agents + objects + topology | team (plain word, e.g. 客服团队) | 集群 | 蜂群 (SubZeroClaw ledger), 群组 | Labs zh 集群内部的分歧 |
| team | team | a swarm with a purpose, used as a plain word | swarm | 团队 | — | copy deck |
| package | package | signed, content-addressed unit from swarmidx | app, plugin | 软件包 | 插件, 应用 | copy deck |
| signed / verified / checked | signed, verified, checked on your machine | Ed25519 signature; checked locally against a transparency log | certified, approved | 签名 / 验证 (已验证) | 认证, 批准 | swarmidx notes |
| index | swarmidx index | package index / notary | store, marketplace | 索引 ("swarmidx 索引") | 商店, 市场 | swarmidx.ygr.ai |
| document | "a swarm is a document" | definition is data: seed + log of changes | paper document, file | 文档 ("集群就是一份文档") | 文件 | intermediate-representation.md |
| seed | seed (swarm.state) | the starting definition the overlay folds over | — | 初始定义 (figure note, restore line, spec, aria) | 种子 (opaque to a cold reader) | IR doc "fold(seed_state, overlay_events)" |
| change log | change log / log of changes | ordered swarm.overlay | release notes | 变更日志; 变更 | 更新日志 (release-notes sense) | IR doc |
| refused | refused | gate rejects a change before it runs | denied by a person | 拒绝 / 已拒绝 | 驳回 (human register) | architecture.md IR gate |
| restore | restore from its database | stopped swarm rebuilt from SQLite seed + replay | backup by a person | 从数据库恢复 | 备份还原 | IR doc restore_swarm |
| control layer | control layer | GenSwarms as the layer above swarms and models | management layer | 控制层 | 管理层 | copy deck |
| event stream | live event stream | feed of every message, crash, restart | news feed | 实时事件流 | — | observability |
| budget | a budget for model spend; spend budgets | object capping LLM spend per conversation (llm-proxy package) | company budget | 控制模型开销的预算; 开销预算 | 财务预算 | copy deck "Removed from v1" |
| scheduler | scheduler / cron scheduler | deterministic timed messages | calendar | 调度器; cron 调度器 | 日程 | objects.md |
| gateway | Telegram gateway | object through which Telegram traffic flows | payment gateway | Telegram 网关 | — | copy deck |
| connectors | connectors | Telegram/WhatsApp/email packages | — | 连接器 | 插件 | copy deck |
| operator token | one operator token | single API token | per-user roles | 操作员令牌; 按用户划分的角色 | — | security.md |
| delivery | at-least-once, exactly once | messaging semantics | — | 至少一次投递 / 恰好一次 | 精确一次 is also used; kept 恰好 | messaging.md |
| live swap | no live swap yet | package update without restart | — | 热替换 | 实时交换 (calque) | copy deck |
| coding agent | coding agent | Claude Code, Codex etc. | — | 编程智能体 | 编码代理 | — |
| skill file | a skill file | skill.md read by a coding agent | — | 技能文件 | — | SubZeroClaw zh |
| runtime / framework / orchestration (comparison) | runtime, framework, orchestration, checkpoints, workers | sourced cells | — | 运行时, 框架, 编排, 检查点, 工作进程; CrewAI crews/flows as 智能体团队（crew）/ 流程（flow） | — | design/comparison-sources.md |

## Texture words (step 2b)

| Word | Decision | Rationale |
|---|---|---|
| operating system (flagship) | 操作系统, everywhere, never 平台 | The page argues by the computer-OS analogy (step 3 "操作系统运行的程序，并不是它自己写的"); 操作系统 is unambiguous. |
| workforce | AI 员工 | Reads as an organisation's staff. 劳动力 reads like labour statistics or "manpower supply"; 员工团队 is longer and doubles 团队, which the page uses for a single swarm. "AI 员工的操作系统" is a crisp noun-phrase headline (h1, title, footer). |
| runs (GenSwarms runs …) | body: 运行 ("把每个 AI 智能体作为…进程运行"); kicker: 组织交给 GenSwarms。 | 运行 is the OS verb (runs programs). For the kicker see below; no 管理/运营 (managerial/business-ops register). |
| kicker | 模型提供智能。/ 智能体执行工作。/ 组织交给 GenSwarms。 | Three short beats, each one line. Lines 1–2 keep the parallel subject–verb–object shape. Line 3 turns to put the brand last, which is where a Chinese slogan lands it, and it fits one line at desktop and 390px. The direct forms (GenSwarms 让组织运转。/ GenSwarms 运转组织。) broke inside 运转 or 组织 at 1440, 1024 or 360px. 组织 also reads as "organising", which fits the product. Doesn't claim more than "runs". |
| plain code / the same thing every time | 普通代码; 每次都做同样的事; spec row: 确定性代码 | 普通 = unglamorous, ordinary. 纯代码 could read as "pure (functional) code". The spec row uses the source's own "deterministic". |
| declared | 声明的 (you state it up front) | Standard config sense (声明式配置). Not 规定的 (imposed by someone else). |
| supervisor (not a person) | 监督者; "看管" as the verb | OTP 监督树 register; 看管 = looks after, not "manages people". |
| control / drive | 控制层; 掌控 (h2); 操控 (drive by API/CLI) | 掌控 keeps "control" without the managerial 管理. |
| thousands | 数千 | Literal "thousands". 成千上万 (thousands upon thousands) inflates the vision claim. Used in the hero lede and the close. |
| refused vs dropped | 拒绝 (a change, by the gate) vs 丢弃 (a message, off the graph) | Two different mechanisms. Keep them apart. |
| verified vs checked | 验证 for both package senses; 检查 for per-hop message checks | Packages: one idea (signature checked locally). Messages: a routing check, not cryptographic. |
| illustration | caption 示意图; log header 事件（示意） | Says the drawing is illustrative, not a live capture. |
| 404 pun "ran off the swarm" | 这个页面跑出了集群。/ …也可能是它溜出了拓扑。 | Keeps the playful running/wandering pun with 跑/溜 (SubZeroClaw zh used 跑 the same way). |

## Headline line breaks (layout is part of the translation)

The h2s use `text-wrap: balance`, which splits CJK anywhere. I measured each candidate's line breaks in the built page
at 1440, 1280, 1024, 768, 390 and 360px and picked wording whose break falls at a comma or a word boundary at every
width:
- 智能体要的不止 / 模型和提示词。 (not 你的智能体，需要的不只是模 / 型…)
- 每一个智能体， / 都是一个进程。 (not 每个智能体都 / 是一个进程。)
- 智能体通信时， / 只走声明路径。 (not 智能体只沿声 / 明的路径通信。)
- 智能体缺什么， / 就装什么。 (not 智能体需要什 / 么，…)
- 一个控制层， / 掌控 AI 组织。 (not …掌 / 控…)
- 哪些已能保证， / 哪些还不能。 (not 它能保证什么，还 / 不能保证什么。)
- 从一个团队开始。 / 扩至数千智能体。 (扩展到 broke at 768 and 360px)

## Suggestion bar (strings shown to zh-Hans browsers on other versions)

Reused verbatim from the SubZeroClaw zh page, which went through a second pass: 本页也有简体中文版。 / 阅读简体中文版 / 关闭.

## Left in English

GenSwarms, GenLayer Labs, GitHub, MIT, OTP, bwrap, Docker, Apple container, SSH, REST, WebSocket, CLI, API, JS, Python,
gsp, swarmidx, Telegram, WhatsApp, LangGraph, LangSmith Deployment, CrewAI, AMP, AutoGen, Microsoft Agent Framework,
skill.md and the URL, cron (in "cron 调度器", since the drawing labels the object `cron`), the figure identifiers
(telegram, triage, research, answer, budget, browser, message_routed, invalid_route, swarm.state, swarm.overlay, op
names), "crew"/"flow" in parentheses as CrewAI's own product nouns. `_same_as_english`: none.

## For native review

- Kicker line 3: 组织交给 GenSwarms。 (brand last, one line) vs a direct "GenSwarms 让组织运转。" (breaks badly on most widths).
- AI 员工 for "AI workforce" vs AI 劳动力 / AI 员工团队.
- 集群 for swarm (inherited from the Labs page). It can read as "server cluster" to infrastructure readers.

## Audit

- [x] Accuracy: no escalation, human-review, per-user-role or memory meanings added. Crash cell says "the agent that
  crashed", with no added "only". Not-yet list kept as limits. 100-agent cap and "(configurable)" exact. "数千" not
  inflated.
- [x] Tags, placeholders ({n}, {cap}, {title}) and protected names kept (build validator clean).
- [x] Same terms in visible copy, aria-labels, SVG labels and metadata (初始定义, 变更日志, 监督者, 声明的路径, 集群).
- [x] Meta description 70/80 chars; og:description 26/80.
- [x] SVG labels all within their width hints (CJK counted as 2).
- [x] Rendered at 1440×900 and 390×844: no overflow, labels clear.

## Editor pass

A native zh-Hans editor read /zh/ cold at 1440×900 and 390×844, then checked each change against the English for
meaning. Headline breaks were measured in the built page at 1440, 1366, 1280, 1024, 900, 768, 600, 414, 390, 360 and
320px (the translator measured 6 widths, and two breaks inside words slipped through: 一/份 at 1440/1024 and 一/个 at
1280/360). Where this section disagrees with the tables above, this section wins: 看管 → 监控, and the step 3, 5, 7, 8
and 9 headline wordings listed under "Headline line breaks" are replaced. Build guard: clean before and after.

| id | before | after | reason |
|---|---|---|---|
| 84d5e16a | 单个智能体不难。多个智能体协作，就需要一个运行的地方，一套谁能和谁通信的规则，还要在某个智能体出故障时有办法恢复。 | 一个智能体好办。多个智能体协同工作，就需要运行的地方、谁和谁通信的规则，以及其中一个出故障时的恢复办法。 | The three needs were three differently built clauses (一个…，一套…，还要…有办法…) and read translated. Now one 、-list of three noun phrases, shorter. 好办 is how a developer says "is easy". |
| 3c7c53c0 | 把它看作一个操作系统。 | 把它想象成操作系统。 | Broke inside 一个 (看作一 / 个操作系统) at 1280 and 360px. 想象成 is the natural "think of it as", and the dropped 一个 was translationese. Clean break at every width. |
| d5661343 | …GenSwarms 为智能体做同样的事：启动、隔离、路由它们的消息，并在出故障时重启。 | …GenSwarms 为智能体做的，正是这件事：启动、隔离、路由消息，出故障时重启。 | "它们的" and "并在" were English scaffolding. 正是这件事 ties the colon list back to "runs programs it didn't write", which is the analogy the whole page rests on. Shorter. |
| 90e66590 | …由自己的监督者看管。…它的角色、模型和运行位置，你可以分别设置。 | …由自己的监督者监控。…角色、模型和运行位置，都可以分别设置。 | 看管 is guarding or babysitting; 监控 is what Chinese OTP/Erlang docs say a supervisor does to its child processes. "它的" right after 其余的 had an unclear referent. |
| 05158e16 | …归 GenSwarms 的监督者管理；… | …由 GenSwarms 的监督者监控；… | Same term as the step 4 body; 管理 is the managerial verb the ledger bans for the supervisor. |
| 51c5fd0f | 智能体通信时，只走声明路径。 | 智能体相互通信，只走声明的路径。 | 声明路径 without 的 parses as verb–object ("declare paths"). The 8/8 comma split breaks cleanly at all 11 widths, so the 的 can come back. |
| 2cd90562 | 图由你来画。每条消息都要对照它检查，不在图上的一律丢弃。 | 图由你来画。每条消息都按图检查，不在图上的一律丢弃。 | 对照它检查 was a calque of "checked against it". 按图检查 is shorter and repeats 图, which keeps the drawing/graph wordplay. |
| 169c0a3b | 接下来的图都围绕同一个集群：一个在 Telegram 上回答客户问题的客服团队。 | 接下来的示意图围绕同一个智能体集群：在 Telegram 上答复客户的客服团队。 | 图 had just meant "the graph" one sentence earlier; the drawings are 示意图 (matches the caption). This is the first time a reader meets 集群, so 智能体集群 makes clear it isn't a server cluster. Same length. |
| 57b1f883 | …Telegram 网关、调度器、控制模型开销的预算。… | …Telegram 网关、调度器、模型开销预算。… | The fused clause broke the rhythm of a list of three nouns. Now matches 开销预算 in the limits list. |
| 3407f33c | 智能体缺什么，就装什么。 | 智能体缺什么，就给它装什么。 | Broke inside 什么 (缺什 / 么) at 600 and 414px. The 7/7 split is clean at every width, and 给它 reads more natural. Still far shorter than the English. |
| 2141c796 | 集群就是一份文档。 | 集群即文档。 | Broke inside 一份 at 1440 and 1024px. 集群即文档 follows the familiar "X 即代码" pattern (基础设施即代码), which is exactly the idea: the swarm's definition is data. One line at every width, and matches the figure 8 alt text. |
| 41acb76d | 一个控制层，掌控 AI 组织。 | 整个 AI 组织，一个控制层。 | 控制层…掌控 repeated 控 and read as a slogan about domination. The noun–noun form carries "one layer for the whole organization" without a verb stronger than the English. Clean at every width. |
| c6918e94 | 它与 LangGraph、CrewAI 或 AutoGen 有何不同？ | 它和 LangGraph、CrewAI、AutoGen 有什么不同？ | Broke 有 / 何 at 1024–1440px. 、 is the normal way to list the three names; 有什么不同 is the plain spoken question. Lines now end at a name or before 有什么不同 at every width. |
| 1f16f72f | 软件包对照签名日志进行验证 | 软件包对照签名日志验证 | 进行 + verb is filler (translationese). |
| 100aa1fb | 在你的进程中，或借助实验性的分布式运行时分布到多个工作进程 | 在你的进程中，或经由实验性的分布式运行时分散到多个工作进程 | 分布式…分布到 repeated 分布. Same sourced fact. |

### Flagship verdicts

| Term | Verdict |
|---|---|
| AI workforce → AI 员工 | Keep. It reads as an organization's staff; AI 劳动力 is labour-market register and AI 员工团队 collides with 团队 (one swarm). |
| operating system → 操作系统 | Keep, everywhere. The step 3 headline is now 把它想象成操作系统。 |
| supervisor → 监督者 | Keep the noun (OTP 监督者, as on the Labs page); change the verb 看管 → 监控, the standard Chinese Erlang/OTP verb. |
| runs the organization / kicker line 3 → 组织交给 GenSwarms。 | Keep. "X 交给 Y" is an idiomatic Chinese slogan ending, and the third beat pivots to land on the brand. The S-V-O options were tested: GenSwarms 运行组织。 breaks inside 组织 at 1024 and 360px, 运行组织 is an odd collocation, and GenSwarms 让组织运转。 breaks inside 运转 at every width. It claims no more than "runs". |
| three-beat kicker | Keep 模型提供智能。/ 智能体执行工作。/ 组织交给 GenSwarms。 Each is one line at 390–1440 except 1024, 360 and 320px, where line 3 wraps at the space before GenSwarms (a word boundary). |
| swarm → 集群 | Keep for consistency with the Labs page and the figure labels, but spell out 智能体集群 at its first appearance (step 5 example line) so infrastructure readers don't take it for a server cluster. 蜂群 would be the literal alternative and reads as a biology metaphor. |

### Known layout limit

At 320px the closing headline 从一个团队开始。扩至数千智能体。 wraps to three lines with breaks inside words. Every
wording that says the same thing does this at 320px. It is clean from 360px up. Left as is.

## Redesign pass (2026-09)

The v4 "zoom" design: one canvas drawing that zooms from the whole organization into one agent and back, with a zoom
caption, readouts under the drawing, a legend and a facts row. 91 ids new or changed, 50 stale ids deleted. Checked in
a private build at 1440×900, 1024×768 and 390×844 (every keyframe, every section), and with
`tests/browser/i18n-audit.cjs` (en + zh-Hans, 18 sizes, canvas labels at every keyframe): ok. The terms in the tables
above still hold; nothing in the new design made one wrong.

### New terms

| Concept | English | zh | Note |
|---|---|---|---|
| zoom caption, scale | organization / team / agent | 组织 / 团队 / 智能体 | One word each, as the English. 组织 is the organization (as in 整个 AI 组织); 团队 is one swarm used as a plain word (ledger: team); 智能体 is also the legend's circle and the label under the agent up close. |
| zoom caption, count | {swarms} swarms · {agents} agents | {swarms} 个集群 · {agents} 个智能体 | Numbers stay figures (2,861); 个 keeps it natural Chinese. 26 of 30. |
| the four jobs | start · isolate · route · restart | 启动 · 隔离 · 路由 · 重启 | Same verbs as the step 3 body and the readout rows. |
| callouts | process / sandbox / supervisor | 进程 / 沙箱 / 监督者 | Ledger terms. |
| crash, restart | crashed → restarted | 崩溃 → 已重启 | 崩溃 is the event (orange); 已重启 the state after. The readout rows: 崩溃 / 已由其监督者重启 / 运行中. |
| swarm document notes | log of changes; {n} declared; never logged; defines | 变更日志; 已声明 {n} 条; 不记入日志; 定义 | 变更日志 = ledger "change log". 已声明 4 条 sits after the `paths` key (量词 条 for paths). 不记入日志 under 已拒绝：… keeps refused ≠ dropped. 定义 on the arrow reads as the verb (the document defines the swarm). |
| database note | restores from its database | 从数据库恢复 | Ledger term, one line (12 of 20). |
| legend | agent / object / supervisor / message on a declared path | 智能体 / 对象 / 监督者 / 已声明路径上的消息 | 已声明路径 instead of 声明的路径上的 to avoid a double 的; 已声明 is the same word as the `paths` row. |
| readout labels | model / prompt / tools; agents / objects; restore | 模型 / 提示词 / 工具; 智能体 / 对象; 恢复 | Same words as the canvas. |
| readout headings | events (illustration); packages · swarmidx (illustration); one event stream (illustration) | 事件 (示意); 软件包 · swarmidx (示意); 统一事件流 (示意) | The page puts a space before the suffix, so a full-width （示意） left a 1.5-character gap; half-width parentheses in these mono labels, same in all three. 统一事件流 = every swarm's events in one stream. |
| facts row | license / version / runtime; Open source, MIT | 许可证 / 版本 / 运行时; 开源，MIT | 运行时 as in the comparison table. |
| alt text prefix | Illustration: | 示意图： | Same word as the corner caption 示意图. |
| wired by hand | each wired to the others by hand; written into each agent | 彼此之间靠手工连线; 写死在每个智能体里 | 写死 is the developer word for hard-coded, which is what "written into each agent" means here. |
| copy fallback, skip link, footer | Selected; Skip to content; License (MIT) | 已选中; 跳至主要内容; MIT 许可证 | 许可证（MIT） left a full-width gap before the next footer link. |

Spec rows and guarantee lines: the English only gained a capital and a full stop, so each keeps its earlier translation
with 。 added (cf800878 → 7a956af2, and so on). Closing headline: the same two sentences, one per `<span>`.

### Changes to existing strings

| id | before | after | reason |
|---|---|---|---|
| bc81483a | 事件（示意） | 事件 (示意) | Same form as the two new readout headings, whose suffix follows a space (see above). |
| 84d5e16a | …以及其中一个出故障时的恢复办法。 | …以及某个出故障时的恢复办法。 | At 1440px the last line was a stranded 办法。; 某个 is shorter and is the same wording as the readout row 某个出故障时. |

### Editor pass (whole page, cold)

Read /zh/ top to bottom without the English. The steps now read as one argument with the readouts: the agent (模型 /
提示词 / 工具), the wiring problem (谁和谁通信 / 各自在哪运行 / 某个出故障时), the OS answer (启动 / 隔离 / 路由 /
重启, repeated in the layer bar), then the team. Within the new strings, reworded before settling: the restart row
(出故障的智能体，由其监督者负责 → 出故障的智能体，交给它的监督者: the row label already says 重启, and 负责 left the
sentence hanging), the comparison sub-line (独立的、受监督的 → 独立、受监督的, as in the meta description), the
guarantees sub-line (…以及我们已知的限制 → 0.2.0 版现在提供什么，还有哪些已知限制。: mirrors the headline's 哪些…哪些
and no longer strands 限制。 at 390px). Headlines unchanged: their breaks (tables above) hold in the new type at
1440, 1024 and 390px.
