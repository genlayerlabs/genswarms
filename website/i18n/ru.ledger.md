# Concept ledger: GenSwarms landing page, ru

Register: **вы**, using the plural imperative («Развёртывайте…», «Следите…», «Установите…»). This matches the GenLayer Labs homepage and the SubZeroClaw page: plain developer prose with no selling adjectives. The one exception is the copyable prompt, which addresses the agent with **ты** («Прочитай … и настрой рой.»), as Russian users do when writing prompts.

Typography:
- Quotes are « ».
- Every em dash has U+00A0 before it, so a line never starts with «—» (the h2 «Каждый агент — это процесс.» did at 1440px).
- In visible HTML text, one-letter prepositions and conjunctions (в, с, к, и, а, о, у) are followed by U+00A0. The copyable prompt is excluded so the pasted text stays plain.
- Numbers have no grouping space («100»).

Sources read: `README.md`; `docs/architecture.md` (supervision tree); `messaging.md` (invalid_route: the message is "dropped"); `intermediate-representation.md` (seed + overlay, restore, refused); `security.md`; `design/2026-09-25-copy-deck-v2.md`; `scratchpad/i18n/concepts.md`. Approved vocabulary comes from the GenLayer Labs ru ledger and json (`genlayerlabscom-site/i18n/ru.*`) and the SubZeroClaw ru ledger and json (`subzeroclaw site/i18n:i18n/ru.*`).

## Objects

| Concept / object | Source term | What it is | Must stay distinct from | RU | Short form | Avoid | Source |
|---|---|---|---|---|---|---|---|
| The analogy | operating system | The computer OS, used as a metaphor for the whole product | platform, framework | операционная система | — (the word «ОС» is never used on the page; the full form fits everywhere, see SVG notes) | «платформа», «ОС» in headlines | copy deck v2 "Think of it as an operating system" |
| The vision | AI workforce(s) | Many agents working as an organization's staff | a swarm/team; labour-market «рабочая сила» | ИИ-персонал («для ИИ-персонала») | — | «рабочая сила ИИ» (labour statistics), «ИИ-сотрудники» (tried first: the plural breaks into «ИИ-сотрудни-ков» in the h1) | concepts.md "staff/personnel of an organization" |
| Agent | agent | An LLM-backed worker, run as its own process | object; model | агент; «ИИ-агент» in the meta, the hero lede and the JSON-LD | агент | «бот» | README; Labs «ИИ-агенты» |
| Object | object | Deterministic code (an Elixir handler) on the same message graph | agent | объект; always glossed as «обычный код» / «детерминированный код» | объект | «сервис» as the noun (the spec row *label* "Services" is «Сервисы», with «объекты: …» after it) | docs/objects.md |
| Model | model | The LLM an agent calls | agent | модель | — | «нейросеть» | SZC ledger |
| Prompt | prompt | Instructions for the model | — | промпт | — | «подсказка» | SZC ledger «системный промпт» |
| Process | process | An OS/OTP process; each agent is one | business process | процесс; «OTP-процесс» in the spec | — | «процедура» | architecture.md |
| Sandbox / boundary | sandbox, boundary | Per-agent isolation (bwrap, Docker, Apple container) | — | песочница; the boundary is «границы» (plural: «в своих границах» is the natural Russian form) | — | «граница» (singular sounds like a national border) | security.md |
| Supervisor | supervisor | The OTP supervisor that restarts a crashed process. It is software, not a person | manager, boss | супервизор | — | «начальник», «менеджер», «надзиратель». The Labs ledger already approved «супервизор» | architecture.md "Supervision tree"; Labs ledger |
| Crash / restart | crash, crashed; restart | A process dies and its supervisor starts it again | a generic failure | noun: **сбой**; verb: **падает / упал** (dev idiom: «процесс упал»); restart: **перезапуск / перезапускается / перезапущен** | — | «авария», «крах» | README "Fault tolerance" |
| Declared path / graph | declared paths, the graph | The directed message topology stated up front in config; the only way messages move | workflow, pipeline | **объявленные маршруты**; граф | маршруты | «пути» (reads as file paths), «заданные» (weaker than "declared") | messaging.md |
| Routes (verb) | routes their messages | Delivers along the graph | — | маршрутизирует | — | «перенаправляет» | — |
| Message | message | What agents send each other, checked at each hop | notification | сообщение | — | «уведомление» | messaging.md |
| Dropped | dropped | A message off the graph is discarded (`invalid_route`) | lost, deleted | **отбрасывается / отброшено** (the networking verb: «пакет отброшен») | — | «потеряно», «удалено» | messaging.md "the message is dropped" |
| Swarm | swarm | A running set of agents, objects and topology | team (a plain word for one swarm) | рой (pl. рои, gen. pl. роёв) | — | «стая» | Labs, SZC ledgers «рой» |
| Team | team | Plain word: a swarm with a purpose | swarm | команда; "support team" = **служба поддержки** | — | — | copy deck |
| Package | package | A signed, content-addressed unit from swarmidx | app, plugin | пакет | — | «плагин», «приложение» | swarmidx |
| Index (swarmidx) | index / notary | The package index that notarizes packages | store, marketplace | **реестр swarmidx** | реестр | «магазин», «маркетплейс», «индекс» (in Russian that means a postcode or a search index, not a package source) | swarmidx.ygr.ai "A notary … not a blob host" |
| Signed / verified | signed, verified | Ed25519 signature; checked on your machine against a transparency log | certified, approved | подписанный; **проверен / проверяются** | — | «сертифицирован», «одобрен» | concepts.md |
| Signed log | signed log | The transparency log | — | подписанный журнал | — | — | — |
| Content-addressed | content-addressed | Identified by its hash | — | адресуются по содержимому | — | — | — |
| Document | a swarm is a document | The definition is data: a seed plus a log of changes | paper document, file | документ | — | «файл» | intermediate-representation.md |
| Seed | seed | The starting `swarm.state` | snapshot, backup | **исходное состояние**; «исходное» in the monospace restore line | — | «затравка», «семя» (literal) | IR doc "fold(seed_state, overlay_events)" |
| Change log | change log / log of changes | `swarm.overlay`, the ordered log of changes | release notes | журнал изменений; «попадает в журнал» for "is logged" | журнал | «лог», «список изменений» (release-notes sense) | IR doc |
| Refused | refused | The gate rejects a change before it runs | "denied" by a person | **отклоняется / отклонено** | — | «запрещено», «отказано» (human decision) | IR doc "are refused" |
| Bad (change/config) | bad change | Invalid: fails validation, e.g. over the cap | — | **недопустимое / недопустимые** | — | «плохое» (colloquial), «ошибочное» (implies a mistake rather than a rule) | security.md "bounded by the cap" |
| Restore | restore from its database | A stopped swarm is rebuilt from SQLite (seed + replayed changes) | a human-run backup/restore | восстанавливается из своей базы данных; «восстановление» | — | «бэкап» | IR doc `restore_swarm` |
| Control layer | control layer | GenSwarms as the layer above models and agents | a human management layer | **слой управления** | — | «уровень менеджмента». «Слой» follows the Labs page («слой маршрутизации», «слой координации») | Labs ledger |
| Event stream | event stream | A live feed of every message, crash and restart | news feed | поток событий; «живой поток событий» (meta) / «в реальном времени» (prose) | — | «лента» | observability.md |
| Budget | budget for model spend | An object that caps LLM spending | a company budget | бюджет расходов на модели; «бюджеты расходов» | бюджет | «смета» | concepts.md |
| Scheduler | scheduler (cron) | Deterministic timed messages | calendar | планировщик | — | «календарь» | — |
| Gateway | Telegram gateway | The object that Telegram messages come in and replies go out through | payment gateway | шлюз Telegram | — | — | — |
| Connector | connector | A package linking a channel (Telegram, WhatsApp, email) | — | коннектор | — | — | — |
| Runtime | runtime | What GenSwarms/LangGraph are in the table | — | среда выполнения | — | «рантайм» (Labs rejected it) | Labs, SZC ledgers |
| Framework | framework | — | — | фреймворк | — | «каркас» | SZC ledger |
| Coding agent | coding agent | Claude Code, Codex etc. | — | **кодинг-агент** | — | «агент для программирования» (clunky, and «для … для» in the Control row) | — |
| Skill file | skill file | `skill.md` | — | файл навыка | — | «скилл» | SZC ledger «навык» |
| Delivery semantics | at-least-once / exactly-once | Message delivery guarantees | — | доставка «как минимум один раз» / «ровно один раз» | — | — | messaging.md |
| Live swap | live swap | Replacing a package without a restart | — | горячая замена | — | — | — |
| Endpoint | model endpoint | The model API address | — | эндпоинт | — | «конечная точка» (rare in dev speech) | — |
| Backend / drivers | backend, drivers | Local, Tmux, Docker… | — | бэкенд; the row label is «Драйверы» | — | — | backends.md |

## Texture words (step 2b)

| Concept | Choice | Why |
|---|---|---|
| "operating system" (flagship) | **операционная система**, always in full | This is the computer term, and the metaphor needs it. «ОС» would be shorter, but in a headline it reads as jargon. The h1 hyphenates as «Операцион-ная» at 1440px; that is correct Russian hyphenation. |
| "workforce" | **ИИ-персонал** | «Персонал» is literally the staff of an organization, a collective noun just like "workforce". «Рабочая сила» is labour-market statistics. «ИИ-сотрудники» is warmer, but the plural genitive «ИИ-сотрудников» is too long for the h1 column and broke into five lines with «сотрудни-ков». |
| "runs" (GenSwarms runs the organization / runs agents) | kicker **управляет**; product sentences **запускает / выполняет** | In Russian OS vocabulary «ОС управляет процессами» is the standard technical verb, so it doesn't turn GenSwarms into a human manager. «Запускает организацию» is wrong ("launches"). «Ведёт» / «держит» are vague or colloquial. For programs and agents the verb is «запускает» (meta) and «выполняет» ("An OS runs programs…" becomes «выполняет чужие программы»). |
| "control" (lede, control layer, Control row) | lede **контролируйте**; layer / row **управление** | "Deploy, coordinate and control" is three imperatives sharing one accusative object, and «контролировать» keeps the English beat. "Control layer" and the Control row are about driving the system, which is «управление». |
| "plain code", "the same thing every time" | **обычный код**; **каждый раз делают одно и то же** | Unglamorous and deterministic, with no extra technical jargon. «Детерминированный код» appears only in the spec sheet, where the English also says "deterministic". |
| "declared" | **объявленные** | This is the programming verb for stating something up front («объявить переменную»). «Заданные» is weaker, and «разрешённые» suggests a permission system. |
| "crash" | noun **сбой**, verb **падает / упал** | Russian developers say «процесс упал» but name the event «сбой». The Labs page uses «сбой» too. |
| "dropped" | **отбрасывается / отброшено** | This is the networking register (packets are «отброшены»). The message is not «потеряно». |
| "refused" | **отклоняется / отклонено** | A neutral, mechanical rejection by the validator. There is no human "отказ". |
| Kicker "Models provide intelligence. Agents perform work. GenSwarms runs the organization." | **Модели дают интеллект. Агенты делают работу. GenSwarms управляет организацией.** | Three sentences of three words each: subject, verb, object, all present tense. «Делают работу» replaced «выполняют работу» because the longer line wrapped on desktop and pushed the third beat into the progress rail at 1440×900. It is also blunter, which suits the beat. |
| "Think of it as an operating system." | **Это как операционная система.** | Short and plain. «Считайте, что это…» and «Думайте о нём как…» are calques. |
| "Start with one team. Scale to thousands of agents." | **Начните с одной команды. Дорастите до тысяч агентов.** | «Дорасти до» is the native "grow to". «Масштабируйтесь до» is a calque. |
| "This page ran off the swarm." (404) | **Эта страница отбилась от роя.** | This echoes the idiom «отбиться от стаи» and keeps the joke. |

## Strings kept identical to English

None. Every catalogue string has a Russian form; `_same_as_english` is not used. Protected names stay in Latin inside the Russian text: GenSwarms, OTP («OTP-процесс»), bwrap, Docker, Apple container, SSH, REST, WebSocket, CLI, gsp, swarmidx, Telegram, WhatsApp, MIT, 0.2.0, LangGraph, CrewAI, AutoGen, LangSmith (Deployment), AMP, Microsoft Agent Framework, GitHub, skill.md. CrewAI's own terms "crews" and "flows" are kept in brackets and Latin, because they are product feature names and the facts must stay exact. The figure identifiers (triage, research, answer, cron, budget, browser, telegram) also stay Latin in the aria-labels, because they are the names drawn in the figures.

## SVG labels vs width hints

| id | label | chars / max | rendered |
|---|---|---|---|
| 2caa6242 | операционная система | 20 / 17 | Over the hint. It fits inside the dark band with room to spare at 1440 and 390 (checked). «ОС» would be the fallback, but the flagship term is worth the 3 characters. |
| ad3f9aa5 | отброшено | 9 / 8 | Over by 1. It fits to the left of the ✕ at 1440 and above it at 390, with no collision. «Сброшено» (8) exists but reads as "reset/shed". |
| 97dfad27 | восстановление: исходное + {n} изм. | 33 (with n=2) / 33 | At the limit. «изм.» avoids number agreement (2 изменения / 5 изменений) and fits the column. |
| 5fc8b818 | каждый агент — это процесс в своих границах | 43 / 43 | At the limit, one line at 390. |
| all others | — | within the hint | checked in screenshots |

## Audit notes

- Accuracy (step 6): no claims are strengthened. "The agent that crashed" stays «Упавшего агента» with no «только». "In use today" is «Уже применяется», with no "widely". "under its own supervisor" is kept as the English says, even though architecture.md shows one shared DynamicSupervisor; the copy deck approved this wording. "Весь запуск" renders "The run" (the whole run is affected, as opposed to one agent), which is the English proposition. Nothing adds human escalation, approval or memory.
- Naturalness (step 7): a cold read led to these rewrites: «Каждый работает в своей песочнице, под своим супервизором» → «У каждого своя песочница и свой супервизор» (it repeated the h2's «Каждый»); «поставляются пакетом, а не в ядре» → «— в отдельном пакете, а не в ядре».
- Layout: 1440×900 and 390×844 checked for the hero, all 9 steps and the spec, compare, guarantees and close sections; mobile has no sideways scroll. The comparison table hyphenates heavily at desktop width (narrow columns, hyphens:auto), as the English table does too.

## Editor pass

I read `/ru/` cold at 1440×900 and 390×844 first, then compared it with the English. The build was already clean under the stricter guard, so nothing had to be fixed for it. Most of the page already reads like Russian written by a developer, so I made only three changes. All three are shorter than before, and none of them strengthens a claim.

| id | before | after | reason |
|---|---|---|---|
| 84d5e16a | С одним агентом всё просто. Когда вместе работает много агентов, им нужны место для запуска, правила, кто с кем общается, и способ вернуться в строй, если один из них упадёт. | С одним агентом всё просто. Когда агентов много, им нужно место для запуска, правила общения и способ вернуться в строй, если один упадёт. | «правила, кто с кем общается» is spoken Russian and ungrammatical in writing. «им нужны место…» has a clumsy agreement: a plural verb ahead of a singular first subject, where editors use «нужно». «Когда вместе работает много агентов» was wordy. Now the sentence is 138 characters instead of 174. |
| 90e66590 | …Если один падает, он перезапускается, а остальные продолжают работать… | …Упавший агент перезапускается, а остальные продолжают работать… | «Если один падает, он перезапускается» is a calque of "If one crashes, it restarts". «Упавший агент» is the native construction, and it matches «Упавшего агента» in the comparison table. |
| 4713393e | Начните с одной команды. Дорастите до тысяч агентов. | Начните с одной команды. Дальше — тысячи агентов. | The imperative «Дорастите» sounds odd ("grow up to"), because «дорасти» is completive and people don't say it as an instruction. «Масштабируйтесь» is a calque. «Дальше — тысячи агентов» is how a Russian headline says it, and it is no stronger than "Scale to". Bonus: at 390 the old line broke «ко-манды». The new one breaks only at words. |

### Flagship verdicts

- **AI workforce → ИИ-персонал: keep.** «Персонал» is the staff of an organization, a collective noun like "workforce". «ИИ-сотрудники» doesn't fit the h1, and «рабочая сила» is labour statistics. It is not a set phrase yet, but it is immediately clear.
- **operating system → операционная система: keep, always in full.** It is hyphenated in the h1 at 1440 («Операцион-ная») and in the step 3 h2 at both widths («операци-онная»). The column is narrower than the word at display size and the headline is a hyphens:auto title, so text alone can't avoid it. The breaks are correct Russian hyphenation. «ОС» would read as jargon.
- **supervisor → супервизор: keep.** This is the established term in Russian Erlang/Elixir writing, it was already approved in the Labs ledger, and it never reads as a human boss.
- **runs the organization → управляет организацией: keep.** «Управляет организацией» can mean what a director does. The English "runs the organization" has the same double reading on purpose (an OS runs programs, a CEO runs a company), and the concrete sentences around it use «запускает / выполняет». No verb is closer.
- **Three-beat kicker → «Модели дают интеллект. Агенты делают работу. GenSwarms управляет организацией.»: keep.** Each beat is subject + verb + object. «Дают интеллект» is plain rather than elegant, but «Модели думают» would anthropomorphize and change the claim.
- **swarm → рой: keep.** This is the Labs and SubZeroClaw term, it declines cleanly («роёв», «рои»), and the 404 joke («отбилась от роя») depends on it.

### Translator's other doubts

- **кодинг-агент: keep.** It is current usage on Habr and in Russian dev chat. «Агент для программирования» is clunky, especially in «файл навыка для вашего кодинг-агента».
- **реестр swarmidx: keep.** «Реестр» is how Russian devs say registry (npm-реестр). «Индекс» would suggest a search index or a postcode.
- **«восстановление: исходное + 2 изм.»: keep.** It is a terse monospace log line, so the abbreviation reads as terminal output, and it avoids number agreement.
- **объявленные маршруты: keep.** It is slightly formal, but it is precise ("declared" as in «объявить переменную») and consistent in 6 places. «Заданные» would clash with «Граф задаёте вы» right under the h2.

### Accepted line breaks (not fixable by wording without lengthening)

- h1 at 1440 and 390: «для ИИ-/персонала». The break falls at the word's own hyphen, which Russian typography allows (the hyphen stays at the line end).
- Step 5 h2 at 390: «объявлен-/ным». Step 9 h2: «ИИ-/организацией» at 1440 and «управле-/ния» at 390.
- Close h2: «Дальше —» ends a line at both widths. A dash may end a line, and the NBSP keeps it from starting one.

## Layout pass (controller)

| id | before | after | reason |
|---|---|---|---|
| 2caa6242 | операционная система | ОС | Figure 3's band label must fit beside the "GenSwarms" wordmark in the phone drawing; the long form rendered at 9.7–11.6px at 320–375px (audit floor 11/12px). «ОС» is the standard abbreviation, and the step headline next to the drawing spells out «операционная система». |
