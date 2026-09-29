# Korean (ko) concept ledger: GenSwarms landing page

**Register.** Korean developer-marketing prose in 합니다체, the same voice as the GenLayer Labs homepage and the SubZeroClaw page (`~/dev/genlayerlabscom-site/i18n/ko.*`, `subzeroclaw site/i18n:i18n/ko.*`). Headlines are short 합니다체 statements ending in a period, or noun phrases where the English is one (h1, "One control layer…"). Calls to action use the polite imperative (~하세요). Spec-sheet rows, table cells and the guarantees lists are noun fragments (…설정, …검증, …가능, …없음), as in the English.

**Authorities.** `README.md` (Features, How it works), `docs/architecture.md` / `objects.md` / `messaging.md` / `intermediate-representation.md` as summarised in the concept notes, `design/2026-09-25-copy-deck-v2.md` (why each v2 sentence exists), the concept notes (`scratchpad/i18n/concepts.md`), and the approved ko vocabulary of the GenLayer Labs homepage (에이전트, 스웜, 조율, 계층, 격리, 모델) and SubZeroClaw (문서, 언어, 복사/복사됨, 샌드박스, 도구, MIT 라이선스, the suggestion-bar wording).

## Objects

| Concept | Source term(s) | Meaning here (source) | Keep distinct from | ko | Avoid | Source |
|---|---|---|---|---|---|---|
| Operating system | operating system | The analogy for the whole product: it runs programs it did not write | platform, framework | 운영체제 | 운영 체제 (spacing), OS 플랫폼, 운영 시스템 | concepts.md "The thesis"; copy deck step 2 |
| AI workforce | AI workforces | Many agents working as an organisation's staff | a single swarm/team; labour-market statistics | AI 에이전트 (h1/title/footer/JSON-LD: "AI 에이전트를 위한 운영체제"; see "Transcreation pass") | AI 인력 (= human AI talent), AI 노동력 (labour statistics), AI 직원 (sounds like individual hires), AI 인재, 디지털 워크포스 (enterprise-sales loanword) | concepts.md; transcreation pass 2026-09-29 |
| Agent | agent | An LLM-backed worker, one OS-style process | object, model | 에이전트 | 에이전트 봇 | genlayerlabs / SubZeroClaw ko |
| Object | object, objects | Deterministic Elixir code on the same message graph ("plain code") | agent; a physical thing | 오브젝트 | 객체 (reads as the generic OOP noun, loses the product term), 사물 | README "Objects"; concepts.md |
| Model | model | The LLM an agent calls | agent | 모델 | 언어모델 in short copy | genlayerlabs ko |
| Process | process | An OTP process; each agent is one | 절차, 업무 프로세스 | 프로세스 | 과정 | README "fault tolerance via OTP supervision" |
| Sandbox / boundary | sandbox; boundary | Per-agent isolation (bwrap, Docker, Apple container); the drawn box around each agent | — | 샌드박스; 경계 | 격리 환경 for "sandbox" (kept for "isolation" = 격리) | SubZeroClaw ko 샌드박스 |
| Isolation / isolated | isolates, isolation, isolated agents | Sandboxing and `network: :isolated` | — | 격리, 격리하다, 격리된 | 분리 | genlayerlabs "격리된 환경" |
| Supervisor | supervisor, supervised | The OTP supervisor that restarts a crashed process. Software, not a boss | a human manager | 슈퍼바이저; "supervised process" = 슈퍼바이저가 관리하는 프로세스 | 감독자, 관리자, 상사 (all read as a person here; see note) | concepts.md "supervisor"; figure note "not a person"; README "OTP supervision trees" |
| Crash / restart | crash, crashed, restart(s) | A process dying and being started again by its supervisor | "failure" in general (실패) | 크래시 (noun; 크래시가 나다), 재시작 / 재시작되다 | 다운 (GL used it for a story agent; here the event names are crash/restart), 충돌 (reads as "collision/conflict") | concepts.md; event stream wording |
| Fail | fail(s) (step 1, step 2) | An agent not doing its job, the general word the English uses before introducing "crash" | crash | 실패하다 | — | copy deck steps 1–2 |
| Declared path | declared paths, declared message paths | The directed message topology you declare; the only way messages move | workflow, pipeline | 선언된 경로, 선언된 메시지 경로 | 정의된 경로, 지정된 경로 (lose "declared") | README "Arbitrary topologies"; messaging.md |
| Graph / topology | the graph; topology (404) | The same topology, drawn | — | 그래프; 토폴로지 | 도표 | copy deck step 4 |
| Message | message | What agents send each other, checked each hop | notification | 메시지 | 알림 | — |
| Dropped | dropped (prose, red SVG label) | A message off the graph is discarded (`invalid_route`) | lost, deleted | 폐기되다 / 폐기됨 | 손실, 삭제, 차단 | concepts.md |
| Checked each hop | checked, checked each hop | The router checks every message against the graph | package verification | 검사 / 검사되다; 홉마다 검사 | 검증 (kept for signatures) | messaging.md |
| Swarm | swarm | A running set of agents + objects + topology | team (plain word) | 스웜 | 군집, 무리 | genlayerlabs ko 스웜; SubZeroClaw 스웜 |
| Team | team, support team | A swarm with a purpose (plain word) | swarm | 팀, 지원팀 | — | copy deck step 4 example |
| Package | package | Signed, content-addressed unit from swarmidx | app, plugin | 패키지 | 플러그인, 앱 | concepts.md |
| Connector | connectors | Telegram/WhatsApp/email packages | — | 커넥터 | 연동 (SubZeroClaw uses 연동 for "integration", a different idea) | — |
| Signed / verified | signed, verified, checked on your machine | Ed25519 signature, verified locally against a transparency log | certified, approved | 서명된, 검증된 / 검증됨 / 검증 | 인증된, 승인된 | swarmidx "a notary… not a blob host" |
| Index | swarmidx index | The package index / notary | store, marketplace | swarmidx 인덱스 | 스토어, 마켓플레이스 | swarmidx.ygr.ai |
| Content-addressed | content-addressed | Identified by the hash of its content | — | 콘텐츠 주소 지정 | 내용 기반 주소 | standard ko CS term (콘텐츠 주소 지정 스토리지) |
| Document | a swarm is a document | The swarm's definition is data: a seed plus a log of changes | paper document, file | 문서 | 서류, 파일 | intermediate-representation.md |
| Seed | seed | `swarm.state`, the starting definition | — | 시드 | 씨앗 (too literary), 초기값 | IR doc |
| Change log | change log, log of changes, logged | `swarm.overlay`, the ordered log of changes | release notes | 변경 로그; 기록되다 | 릴리스 노트, 변경 이력 (reads as history view) | IR doc |
| Refused | refused | A change the validation gate rejects before it runs | denied by a person | 거부 / 거부되다 | 반려 (human approval flow), 금지 | concepts.md |
| Restore | restore, comes back from its database | A stopped swarm rebuilt from SQLite (seed + replayed changes) | backup by a person | 복원 / 복원되다 | 복구 (kept for step 1's general "way back") | README "coordinated through SQLite" |
| Control layer | control layer | GenSwarms as the layer above models and agents | a human management layer | 제어 계층 | 관리 계층, 컨트롤 레이어 | genlayerlabs "조율 계층" pattern (…계층) |
| Coordinate | coordinate | Make agents work together | consensus | 조율하다 | 조정, 협조 | genlayerlabs 조율 |
| Deploy | deploy | Start agents somewhere | — | 배포하다 | 디플로이 | — |
| Event stream | event stream, events | Live feed of every message, crash, restart | news feed | 이벤트 스트림, 이벤트 | 알림 피드 | README "real-time event streaming" |
| Live / as it happens | live | In real time | — | 실시간으로 | 라이브로 | — |
| Budget | budget for model spend, spend budgets | An object that caps LLM spending | a company's financial budget | 모델 비용 예산, 비용 예산 | 재정 예산 | concepts.md; llm-proxy |
| Scheduler | scheduler, cron scheduler | Deterministic timed messages | calendar | 스케줄러, cron 스케줄러 | 일정 관리 | — |
| Gateway | Telegram gateway | The object Telegram messages come in and go out through | payment gateway | Telegram 게이트웨이 | 관문 | — |
| Model calls | model calls | The calls agents make through the budget proxy | — | 모델 호출 | 모델 콜 | SubZeroClaw 호출 |
| Role / backend / where it runs | role, model and backend set separately | Body, model and backend are separate settings | — | 역할, 모델, 백엔드 (spec) / 실행 위치 (prose) | — | README "Per-agent skills", "Pluggable backends" |
| Operator token | operator token | The single bearer token of the API | — | 운영자 토큰 | 관리자 토큰 | README "Bearer-token auth" |
| Delivery semantics | at-least-once / exactly once | Message delivery guarantees | — | 최소 한 번 전달 / 정확히 한 번 | 적어도 한 번 | standard ko distributed-systems terms |
| Live swap | live swap | Replacing a package without restarting its agent | — | 실행 중 교체 | 라이브 스왑, 핫스왑 | — |
| Core | the core | GenSwarms itself, without packages | — | 코어 | 핵심부 | — |
| Illustration | illustration (captions under figures 5–8) | The events and data drawn are simulated | a picture | 예시 | 일러스트 (reads as "drawing") | figure captions |
| Coding agent / skill file | your coding agent; a skill file | Claude Code, Codex etc.; `skill.md` | — | 코딩 에이전트; 스킬 파일 | — | SubZeroClaw 스킬 파일 |

**Supervisor note (deviation from GenLayer Labs).** The GenLayer Labs homepage uses 감독자 for "supervisor", but there it names a manager *agent* in a story (splits work, settles disagreements). On this page the concept notes and the figure note are explicit: the supervisor is the OTP supervisor, software that restarts a crashed process, "not a person". 감독자 reads as a person overseeing others, and the page pairs it with "OTP". Korean Elixir/Erlang material calls it 슈퍼바이저 (슈퍼바이저 트리). So this page uses 슈퍼바이저 throughout. A native reviewer should confirm; if the owner prefers cross-site consistency, 감독자 is a drop-in swap in 10 strings.

## Texture words

| Concept | Occurrences | ko choice | Rationale |
|---|---|---|---|
| operating system | title, h1, step 2 h2 and paragraph, figure 3, footer, JSON-LD | 운영체제 | The standard computer term, so the metaphor lands. It also shares 운영 with the kicker's 운영합니다, which the English gets from "operating"/"runs". |
| workforce | title, h1, footer, JSON-LD | AI 에이전트 (superseded AI 인력 on 2026-09-29) | AI 인력 reads as human AI talent; see "Transcreation pass". |
| runs (the organization) | kicker line 3 | 운영합니다 | Operate/run, not a human boss's 관리합니다. Echoes 운영체제. |
| runs (programs, agents) | step 2, step 3, JSON-LD, spec, comparison | 실행하다 / 실행되다 | The plain technical verb. I did not use the casual 돌리다 of SubZeroClaw because this page talks about processes and backends, where 실행 is the standard term. |
| plain code / the same thing every time | step 5, legend | 일반 코드; 매번 같은 일을 합니다 | Neutral and unglamorous. 순수 코드 would mean "pure code". 평범한 코드 was considered; it can read as mildly dismissive. |
| deterministic | spec "Services" | 결정적 코드 | The standard CS term (결정적 알고리즘). |
| declared | every path mention | 선언된 | "You state it up front, in configuration" = 선언. Kept identical everywhere. |
| drive it | step 8 | 다루다 | "Drive it by API or CLI" = work it through. 제어 is already "control"; 조작 sounds like tampering. |
| hand it to your coding agent | step 8, close label | 코딩 에이전트에게 맡기세요 / 에이전트에게 맡기세요 | 맡기다 is the GenLayer Labs verb for handing work over. |
| the kicker | step 8 triad | 모델은 지능을 제공합니다. / 에이전트는 일을 수행합니다. / GenSwarms는 조직을 운영합니다. | Three parallel "X는 Y를 ~합니다" lines, each ending in a two-syllable Sino-Korean verb + 합니다 (제공/수행/운영). The rhythm holds and the last beat echoes 운영체제. I kept 합니다체 because every headline on the page uses it; the plain 한다체 form saves only one syllable per line. |
| thousands | lede, close | 수천 개 | Counter 개 for agents, as on genlayerlabs ("수천 개씩"). |
| ran off the swarm / wandered off the topology | 404 | 스웜 밖으로 달아났습니다 / 토폴로지 밖으로 길을 잃었나 봅니다 | 달아나다 matches the SubZeroClaw 404; ~나 봅니다 keeps the dry guess. |

## Headlines

1. AI&nbsp;인력을&nbsp;위한 운영체제. (editor pass: second &nbsp; added)
2. 모델과 프롬프트만으로는 부족합니다. (first pass "에이전트에게 필요한 건 모델과 프롬프트만이 아닙니다." set in four lines at 1440 px, one more than the English; the shorter form says the same thing, since the agent is the subject of the whole page.)
3. 운영체제라고 생각해 보세요.
4. 모든 에이전트는 프로세스입니다.
5. 에이전트는 선언된 경로로만 대화합니다.
6. 모든 일에 모델이 필요한 건 아닙니다.
7. 에이전트에게 필요한&nbsp;건 설치하세요. (editor pass)
8. 스웜은 문서입니다.
9. AI 조직을 위한 단일 제어 계층.
10. Close: 한 팀으로 시작하세요. 에이전트&nbsp;수천&nbsp;개로 확장하세요. (the non-breaking spaces stop the desktop break from falling between 에이전트 and 수천.)

## Left in English

GenSwarms, GenLayer Labs, GitHub, OTP, bwrap, Docker, Apple container, SSH, REST, WebSocket, CLI, API, JS, Python, gsp, swarmidx, Telegram, WhatsApp, LangGraph, LangSmith Deployment, CrewAI, AMP, AutoGen, Microsoft Agent Framework, MIT, 0.2.0, the drawn identifiers (telegram, triage, research, answer, cron, budget, browser, swarm.state, swarm.overlay, message_routed, invalid_route). In the figure-6 aria-label, "Telegram" and "cron" name the drawn objects. "(run)" is added after 실행 in two comparison cells because "run" is the term LangGraph and CrewAI docs use.

## Meta description (7b40834f, limit 80)

`GenSwarms: AI 에이전트마다 슈퍼바이저가 관리하는 프로세스, 선언된 메시지 경로, API와 실시간 이벤트 스트림. 오픈소스, MIT.` (79). The full sentence ("GenSwarms는 … 실행합니다.") came to 89–91 characters. The noun-fragment form keeps every fact and the protected names (GenSwarms, MIT), and matches the SubZeroClaw description style approved by the ko editor ("SubZeroClaw: …").

## SVG labels

All within their width hints (Korean counted as two): 슈퍼바이저 10/15, 운영체제 8/17, 제어 계층 9/20, 폐기됨 6/8, 거부: 에이전트 100개 상한 초과 30/33, 복원: 시드 + 변경 2건 21/33, 에이전트마다 자기 경계 안의 프로세스 하나 41/43×3. The layout audit (en + ko, 14 sizes) passed with no overlaps.

## Review

- [x] Every id present, tags/placeholders/protected names kept (build validator).
- [x] Rendered at 1440×900 and 390×844, every story step and the proof sections; `i18n-audit.cjs` ok for en + ko × 14 sizes.
- [x] Cold read without the English; three lines rewritten (lede 수천 개의 → 에이전트 수천 개를; step-3 restart clause; 404 second sentence merged).
- [x] No claim strengthened: no 모든 곳, no 완벽, "그 에이전트가 재시작되고" (not "그 에이전트만"), budgets stay a package.
- [x] Native editor pass (see "Editor pass" below).

## Editor pass

Native editor, second pass (playbook §8.6). I read `/ko/` cold at 1440×900 and 390×844 before comparing with the English, then measured every headline candidate at 1440, 1280, 1024, 768, 390 and 320 px. The build is clean, and nothing was lengthened beyond a character or two in flowing paragraphs. No claim was strengthened.

### Flagship verdicts

| Term | Verdict |
|---|---|
| AI workforce → AI 인력 | **Keep.** 인력 is an organisation's personnel, which is the right sense. The known risk is that "AI 인력" on its own also means human AI specialists (AI 인력 양성). The h1's lede ("AI 에이전트 수천 개를…") and the drawing resolve it at once. The alternatives are all worse on tone: 워크포스 is consultant loanword, 노동력 is labour economics, and 직원 means individual hires. |
| operating system → 운영체제 | **Keep.** It is the standard computer term (one word, no space), so the metaphor lands, and it shares 운영 with the kicker. |
| supervisor → 슈퍼바이저 | **Keep, and confirm the deviation from genlayerlabs.com's 감독자.** Here it is the OTP supervisor. Korean Elixir/Erlang material says 슈퍼바이저 (슈퍼바이저 트리), and 감독자 would read as a person, which the concept notes forbid. |
| runs the organization → 조직을 운영합니다 | **Keep.** 운영 is "operate/run" without the human-boss sense of 관리, and it echoes 운영체제. |
| three-beat kicker | **Keep in 합니다체:** 모델은 지능을 제공합니다. / 에이전트는 일을 수행합니다. / GenSwarms는 조직을 운영합니다. The three lines stay parallel (X는 Y를 [2-syllable Sino-Korean verb]합니다). The third line wraps at every width, but so does the English ("GenSwarms runs the / organization."), and the Korean breaks cleanly at "조직을 | 운영합니다." 한다체 would not stop the wrap and would be the only 한다체 on the page. |
| swarm → 스웜 | **Keep.** It matches genlayerlabs.com and SubZeroClaw. 군집 and 무리 read as biology. |

Translator's other doubts: the **meta description** noun fragment reads fine as a Korean search snippet. A full sentence does not fit in 80, so keep it. **오브젝트** is right as a product term, since 객체 would sound like generic OOP. **크래시**: in prose I use the verb 크래시되다, which is what developers say ("앱이 크래시되면"), and keep the noun forms (크래시가 난, 크래시 후) elsewhere. **예시** is right for the figure captions. **실행(run)** is harmless and helps readers who know the LangGraph/CrewAI docs, so keep it.

### Changes

| id | before | after | reason |
|---|---|---|---|
| 3b3ae940 (h1) | AI&nbsp;인력을 위한 운영체제. | AI&nbsp;인력을&nbsp;위한 운영체제. | The line broke as "AI 인력을 / 위한 운영체제.", which splits the modifier from its phrase. It now sets "AI 인력을 위한 / 운영체제." at every width from 320 to 1440. |
| 84d5e16a (step 2) | 에이전트 하나는 쉽습니다. … 누가 누구와 대화할지 정한 규칙, 하나가 실패했을 때 복구할 방법이 필요합니다. | 에이전트 하나쯤은 쉽습니다. … 누가 누구와 대화할지 정하는 규칙, 하나가 실패하면 복구할 방법이 필요합니다. | "하나는 쉽습니다" read as a literal rendering. 하나쯤은 sets up the "but many…" turn the way a Korean writer would. 정한 (past) became 정하는, because the rules are ongoing. 실패하면 is tighter, so the length stays the same. |
| d5661343 (step 3) | 운영체제는 자기가 만들지 않은 … GenSwarms는 에이전트를 그렇게 다룹니다. | 운영체제는 직접 만들지 않은 … GenSwarms는 에이전트를 그렇게 실행합니다. | 자기가 is awkward with an inanimate subject, and 직접 is natural. 실행합니다 repeats the first sentence's verb, so the analogy (runs programs → runs agents the same way) is explicit and the list that follows reads as "how". |
| 90e66590 (step 4) | … 자기 슈퍼바이저 아래에서 실행됩니다. 하나에 크래시가 나면 그 에이전트가 재시작되고, … 따로따로 정합니다. | … 자기 슈퍼바이저 아래 실행됩니다. 하나가 크래시되면 그 에이전트는 재시작되고, … 따로 정합니다. | "하나에 크래시가 나면" is unidiomatic, and developers say "크래시되면". The contrastive 는…는 (그 에이전트는 / 나머지는) carries "it restarts, the others keep working". The repeated -에서 and the chatty 따로따로 are gone. |
| 2cd90562 (step 5) | … 모든 메시지는 그래프와 대조해 검사되고, 그래프를 벗어난 메시지는 폐기됩니다. | … 모든 메시지는 그래프에 맞는지 검사되고, 벗어난 메시지는 폐기됩니다. | "대조해 검사되고" (a passive with an active adverbial) read as translated. The third 그래프 in two short sentences is dropped. |
| 3407f33c (step 7 h2) | 에이전트에게 필요한 것을 설치하세요. | 에이전트에게 필요한&nbsp;건 설치하세요. | It broke as "필요한 / 것을" at every width, splitting a modifier from its dependent noun. It now sets "에이전트에게 / 필요한 건 설치하세요." 건 matches step 6's "필요한 건 아닙니다" and is one syllable shorter. |
| a895f8a4 (step 8) | 멈춘 스웜은 자기 데이터베이스에서 복원됩니다. | 멈춘 스웜은 자체 데이터베이스에서 복원됩니다. | 자체 is the natural word for "its own" with a system as subject. |
| 3f22753b (spec: Control) | REST, WebSocket, CLI, 그리고 코딩 에이전트용 스킬 파일 | REST, WebSocket, CLI, 코딩 에이전트용 스킬 파일 | "…, 그리고 X" before the last item copies English list syntax. |
| d15f403e (guarantees h2) | 보장하는 것, 아직 보장하지 않는 것. | 보장하는 것, 아직&nbsp;보장하지 않는&nbsp;것. | It broke as "보장하는 것, 아직 / 보장하지 않는 것.", stranding 아직. It now sets "보장하는 것, / 아직 보장하지 않는 것." |
| 32814eeb (guarantee) | 크래시는 스웜 전체가 아니라 에이전트 하나만 재시작 | 크래시가 나면 스웜이 아니라 에이전트 하나만 재시작 | "크래시는 … 재시작" makes the crash the agent of the restart, which is odd in Korean. The claim is unchanged ("one agent, not the swarm"), and the item is one character shorter. |
| 938739e1 (close) | 지금도 채팅 어시스턴트, …, 그리고 다른 스웜을 지켜보는 스웜에 쓰이고 있습니다. | 현재 채팅 어시스턴트, …, 다른 스웜을 지켜보는 스웜에 쓰이고 있습니다. | 지금도 means "still / even now", but "In use today" is neutral, so 현재 fits. The English-style "그리고" before the last item is dropped. |

Checked after the changes: the temp-dir build is clean, and I re-read screenshots of every changed string at 1440×900 and 390×844.

## Redesign pass (2026-09)

The v4 "zoom" design replaces the SVG figures and the story rail with one canvas drawing, a zoom caption, readouts under the drawing, a legend and a hero facts row. 91 ids are new or changed; the 50 stale ids (old figures, their alt texts, the rail, the lowercase spec and list lines) are deleted. All earlier term decisions still hold; none was changed.

### New terms

| Concept | English | ko | Note |
|---|---|---|---|
| Zoom caption: scale | organization / team / agent | 조직 / 팀 / 에이전트 | One word each, as in the English. 조직 matches "AI 조직" (step 9) and "조직을 운영합니다"; 팀 matches 지원팀. |
| Zoom caption: counts | {swarms} swarms · {agents} agents | 스웜 {swarms}개 · 에이전트 {agents}개 | Noun + number + counter, the natural Korean order. Numbers stay placeholders. |
| The four OS jobs (bar + readout rows) | start · isolate · route · restart | 시작 · 격리 · 라우팅 · 재시작 | Same verbs as step 3's paragraph (시작하고, 격리하고, 라우팅하고, 재시작합니다), so bar, readout and prose read as one list. |
| Process-tree callouts | supervisor / process / sandbox | 슈퍼바이저 / 프로세스 / 샌드박스 | Ledger terms. |
| Crash states (canvas + event log) | crashed → restarted | 크래시됨 → 재시작됨 | ~됨 state form, like the existing 폐기됨 and 검증됨. |
| Event-log rows | agent {n} / {n} others / running / restarted by its supervisor | 에이전트 {n} / 나머지 {n}개 / 실행 중 / 슈퍼바이저가 재시작 | 나머지 echoes step 4 ("나머지는 계속 일합니다"); "슈퍼바이저가 재시작" is the comparison cell's wording. |
| Swarm document notes | seed / log of changes / {n} declared / never logged | 시드 / 변경 로그 / {n}개 선언됨 / 기록되지 않음 | Ledger terms (변경 로그, 기록되다, 선언된). |
| Arrow document → swarm | defines | 정의 | A noun on the arrow; it also echoes step 8's "스웜의 정의는 데이터". |
| Database note | restores from its database | 데이터베이스에서 복원 | 복원 per ledger; wraps to two lines on the canvas. |
| Legend | agent / object / supervisor / message on a declared path | 에이전트 / 오브젝트 / 슈퍼바이저 / 선언된 경로 위의 메시지 | |
| Readout row labels (objects) | agents / objects; {names}: use a model / plain code | 에이전트 / 오브젝트; {names}: 모델 사용 / 일반 코드 | Carried over from the old legend strings. |
| Readout: one agent | decides the next step / says what the job is / do the work | 다음 단계를 결정 / 할 일을 지시 / 작업을 수행 | Three parallel noun fragments (결정/지시/수행), as in the spec sheet. |
| Readout: wired by hand | who talks to whom / where each one runs / when one fails | 누가 누구와 대화하나 / 각자 어디서 실행되나 / 하나가 실패하면 | Questions in the plain ~나 form; answers are fragments (에이전트마다 코드에 직접 작성 / 시작된 곳 아무 데서나 / 아무도 재시작하지 않음). |
| Readout headings | packages / (illustration) / one event stream | 패키지 / (예시) / 통합 이벤트 스트림 | "one event stream" = every swarm's events in one stream: 통합 is how Korean says it; "하나의 이벤트 스트림" reads translated. |
| Hero facts | license / version / runtime; Open source, MIT | 라이선스 / 버전 / 런타임; 오픈소스, MIT | |
| Canvas alt texts | Illustration: … | 그림: … | 그림 is the plain alt-text prefix. 예시 stays the visible "illustration" tag (simulated data). |
| Skip link | Skip to content | 본문으로 건너뛰기 | The standard Korean skip-link wording. |
| Copy fallback | Selected | 선택됨 | |

**Spec rows and lists.** The English now sets them as capitalized lines with full stops. Korean has no capitals, so the ko lines keep their noun-fragment (개조식) form and only gain the full stop; where the English splits with a semicolon or a period (State row, live-swap limit), ko splits with a period too.

### Changes to existing strings

The old ids were deleted and re-created under new ids; this table lists every case where the ko text changed beyond adding a full stop.

| id (new, was) | before | after | reason |
|---|---|---|---|
| 7a956af2 (was cf800878) | 모든 에이전트는 슈퍼바이저가 관리하는 OTP 프로세스: 역할, 모델, 백엔드는 따로 설정 | 에이전트마다 슈퍼바이저가 관리하는 OTP 프로세스. 역할, 모델, 백엔드는 따로 설정. | A topic-marked clause (…는) followed by a colon reads unnatural as a spec fragment; 에이전트마다 … 프로세스 is a clean noun phrase. |
| bff34e70 (was 36e77013) | 시드와 변경 로그, 잘못된 변경은 거부, 데이터베이스에서 복원 | 시드와 변경 로그. 잘못된 변경은 거부. 데이터베이스에서 복원. | The English now uses three sentences; commas become periods. |
| 90361c3e (was 7c9e677f) | 패키지를 업데이트하면 에이전트가 재시작됨, 실행 중 교체는 아직 없음 | 패키지를 업데이트하면 에이전트가 재시작됨. 실행 중 교체는 아직 없음. | Same (English semicolon). |
| c39d7104 (was 4713393e) | 한 팀으로 시작하세요. 에이전트&nbsp;수천&nbsp;개로 확장하세요. | `<span>`한 팀으로 시작하세요.`</span>` `<span>`에이전트&nbsp;수천&nbsp;개로 확장하세요.`</span>` | New markup (one line per sentence); the &nbsp; still keeps "에이전트 수천 개로" together on phones. |
| 9a976fc2 (was 7b7d0d74) | 선택해서 복사하세요 | 선택됨 | The English changed from an instruction to a state. |
| 0a4470d6 (was 6ce82780) | 작동 방식으로 건너뛰기 | 본문으로 건너뛰기 | The English target changed ("Skip to content"). |
| e071ace2 (was 3229609e) | 라이선스 | 라이선스 (MIT) | English changed. |
| cad9c020 (was 9967a2e3) | 오픈소스, MIT. 버전 0.2.0. | 오픈소스, MIT | Split into the facts row (라이선스 / 버전 / 런타임 labels). |
| 88127da4, 9a24dc0c (were 4390d133, 411a8f28) | 에이전트, 모델 사용 / 오브젝트, 일반 코드 | {names}: 모델 사용 / {names}: 일반 코드 | Now templates after the names; wording kept. |

Unchanged ids (headlines, step paragraphs, comparison, 404, meta) were re-read cold in the new layout and kept: none sounded translated next to the new labels, and the step 3 paragraph already uses the four job verbs.

### Layout check

Temp-dir build clean. `/ko/` screenshotted at 1440×900, 1024×768 and 390×844: every keyframe (0–10), every step, the sections and the footer. No label collides or clips; the drawing keeps the English framing. The database note is left out at 390 px, as in the English. `i18n-audit.cjs` (ko × 18 sizes, canvas label audit included): ok.

Budgets (Korean counted as two): 크래시됨 8/12, 재시작됨 8/14, 조직 4/14, 팀 2/14, 에이전트 8/14, 스웜 36개 · 에이전트 2,861개 ≈26/30, 시작 · 격리 · 라우팅 · 재시작 29/36, 프로세스 8/15, 샌드박스 8/15, 변경 로그 9/22, 4개 선언됨 10/20, 기록되지 않음 13/22, 정의 4/12, 데이터베이스에서 복원 21/20×2 (wraps to two lines), 오브젝트 8/14, 선언된 경로 위의 메시지 25/30. Over by one: 에이전트 {n} 11/10 and 나머지 {n}개 11/10, both readout rows in the event log, where the column fits them at every size.

## Final review (2026-09)

Fresh pre-launch review by a senior Korean tech editor, not the translator. I read `/ko/` cold at 1440×900, 1024×768, 390×844, 320×640 and 844×390. That covered every step (centred, camera settled), every keyframe 0–10, the header with the language picker open, the four sections, the close, the footer, the 404 (served at `/ko/…`) and the suggestion bar (English and Spanish pages, Korean browser). I then compared every string with the English. I also checked the meta, og and JSON-LD descriptions, the `#zoom-strings` aria-labels and the 404 title. No claim is strengthened or weakened, refusals stay limited to the cap, refused changes are never logged, and live swap is still "not yet". Temp-dir build clean; `i18n-audit.cjs` (ko × 18 sizes) ok.

| id | before | after | reason |
|---|---|---|---|
| 6ca90ca9 (readout, "wherever it was started") | 시작된 곳 아무 데서나 | 시작한 곳 어디서든 | 아무 데서나 reads as "any old place" and sits badly after 시작된 곳. 어디서든 is the natural "wherever", and the active 시작한 matches the plain dev register. |
| 0d6fb0ce (readout, "nothing restarts it") | 아무도 재시작하지 않음 | 재시작되지 않음 | 아무도 is "nobody" (a person), which the English avoids. The passive states the fact the row is about in a clean 개조식 form. |
| 88127da4 (readout) | {names}: 모델 사용 | {names}: 모델(U+00A0)사용 | At 320 and 844 the line broke as "…answer: 모델 / 사용", stranding 사용. A no-break space keeps the two words together (plain-text string, so a literal U+00A0 and not an entity). |
| 9a24dc0c (readout) | {names}: 일반 코드 | {names}: 일반(U+00A0)코드 | Same guard for the objects row. |
| 57b1f883 (step 6) | Telegram 게이트웨이 | Telegram&nbsp;게이트웨이 | At 1440 the paragraph broke between "Telegram" and "게이트웨이", splitting one name. |
| 8ee1cf08 (comparison, CrewAI) | 오류 시 재시도하고 | 오류&nbsp;시 재시도하고 | At 1440 and 320 the line broke as "오류 / 시", separating the particle-like 시 from its noun. |
| 90361c3e (not yet) | 실행 중 교체는 아직 없음. | 실행&nbsp;중&nbsp;교체는 아직 없음. | At 390 it broke as "실행 중 / 교체는", splitting the ledger term 실행 중 교체. |

Tried and dropped: `Apple&nbsp;container` in a7b45c42 (to stop "Apple / container" at 320). The build refuses it because the protected name must appear verbatim. The English wraps the same way.

### Translator doubts (task 5)

- **정의 on the document → swarm arrow:** keep. A bare noun on a diagram arrow is normal Korean diagram style. The arrow carries the direction, and 정의함 would be stiffer for no gain.
- **Readout fragments ("wired by hand", "one agent"):** 할 일을 지시, 에이전트마다 코드에 직접 작성 and 작업을 수행 are fine. 시작된 곳 아무 데서나 and 아무도 재시작하지 않음 are rewritten (see the table above). The loose look of multi-word Korean in the readouts comes from the monospace font's wide space. It is a CSS matter, reported outside this file.
- **Full stops on 개조식 lines:** keep. The English redesign ends every spec and guarantee line with a period, and Korean tech pages that use 개조식 inside prose-like lists commonly do too. The page is consistent, and dropping them would reintroduce commas in the State row and the live-swap limit.
- **통합 이벤트 스트림:** keep. It is the idiomatic "one stream for everything"; 단일 이벤트 스트림 would read as a spec term.
- **선택됨 (copy fallback):** keep. It states what happened (the prompt is selected), which mirrors 복사됨.

## Transcreation pass (2026-09-29)

A senior Korean developer-tools product marketer re-read `/ko/` cold. The question was not whether the page is accurate but whether it reads as written in Korean. No claim was strengthened and nothing was dropped. Tags, placeholders and protected names are kept. 30 strings changed.

### "AI workforce": AI 인력 → AI 에이전트

**Decision:** «AI 에이전트를 위한 운영체제» (back-translation: "the operating system for AI agents"). It is used in the h1 (`3b3ae940`), the title (`836e01a9`), the footer tagline (`37294ee3`) and the JSON-LD (`ffebc746`).

**Evidence**
- **«AI 인력» means people.** In current Korean it is the standard term for human AI talent: "AI 인력 양성" (training AI people), "AI 인력 부족" (shortage of AI engineers), plus hiring coverage in 한국경제, CIO Korea and AI타임스 (September 2026). A Korean reader, or someone searching Naver, takes «AI 인력을 위한 운영체제» to mean "an OS for AI professionals".
- **«AI 에이전트를 위한 운영체제 / OS» is the phrase Korean tech writing already uses for this product category.** Examples: Dale Seo's engineering blog, "Cloudflare OS: AI 에이전트를 위한 운영체제" (daleseo.com/cloudflare-os), and CIO Korea, "AI 에이전트를 위한 OS는 어떤 모습일까?". «AI 에이전트» is also the term Korean developers search for, and it matches the lede and the rest of the page.
- **The alternatives don't fit.**
  - «디지털 워크포스» / «디지털 노동력» are Salesforce Korea's Agentforce terms, used in enterprise-sales and HR framing. To a developer they read as a consultancy loanword.
  - «AI 직원» (AI employees) names individual hires in chatbot and RPA marketing.
  - «AI 에이전트 조직» is not an established phrase.
  - «AI 조직» has the same problem as 인력: it means a company's AI department.
- The collective, organisational sense of "workforce" is still carried by the lede ("AI 에이전트 수천 개를 조직 전체에…"), the zoom caption (조직 · 스웜 36개 · 에이전트 2,861개) and step 9. This is the same move Spanish made ("tus agentes de IA").

**Layout.** The h1 sets as «AI 에이전트를 / 위한 운영체제.» at every width from 320 to 1440, in two balanced lines. A no-break space before 위한 would give «AI 에이전트를 위한 / 운영체제.», but at 1440×900 that phrase is 446.5 px against a 444 px column. Chrome would then break inside 위한 («위 / 한»), so I kept the single `&nbsp;` after AI. «AI 에이전트용 운영체제» would fit on one line at every width, but «~를 위한» is the form Korean titles and searches use most.

**Related.** "One control layer for your AI organization" (`41acb76d`) had the same trap in «AI 조직» (an AI division). It is now «조직의 모든 에이전트를, 하나의 제어 계층에서.» ("Every agent in your organization, from one control layer."), and the keyframe-10 alt text follows it (하나의 제어 계층).

**Share image.** The h1 and the triad are on `og-ko.png`. Run `node website/tools/og.cjs` after these strings land, or `--check` will fail on the stale card. I didn't run it because this task may not write into `website/`.

### Changes

| id | before | after | back-translation of after | why the before read as translated |
|---|---|---|---|---|
| 3b3ae940 | AI&nbsp;인력을&nbsp;위한 운영체제. | AI&nbsp;에이전트를 위한 운영체제. | The operating system for AI agents. | «AI 인력» is the everyday Korean term for human AI talent (AI 인력 양성, AI 인력 부족), so the old headline could read as "the OS for AI professionals". |
| 836e01a9 | GenSwarms: AI 인력을 위한 운영체제 | GenSwarms: AI 에이전트를 위한 운영체제 | GenSwarms: the operating system for AI agents | Same term as the headline; «AI 인력» is what a Korean searches for when hiring AI engineers, not for agent software. |
| 37294ee3 | AI 인력을 위한 운영체제. | AI 에이전트를 위한 운영체제. | The operating system for AI agents. | Footer tagline follows the headline. |
| ffebc746 | AI 인력을 위한 운영체제. AI 에이전트를 슈퍼바이저가 관리하는 개별 프로세스로, 선언된 메시지 경로 위에서 실행합니다. REST + WebSocket API와 실시간 이벤트 스트림을 제공합니다. | AI 에이전트를 위한 운영체제. 에이전트마다 슈퍼바이저가 관리하는 별도 프로세스로 실행하고, 메시지는 선언된 경로로 오갑니다. REST + WebSocket API와 실시간 이벤트 스트림을 제공합니다. | The operating system for AI agents. It runs each agent as a separate process managed by a supervisor, and messages travel along declared paths. It provides a REST + WebSocket API and a real-time event stream. | New headline term; "runs … on declared message paths" (선언된 메시지 경로 위에서 실행) was an English prepositional calque, and "AI 에이전트" appeared twice in a row. |
| d4a74b50 | 문서 읽기 | 문서 보기 | View the docs | «문서 읽기» is a word-for-word "Read the docs"; Korean product pages say «문서 보기». |
| 84d5e16a | 에이전트 하나쯤은 쉽습니다. 여러 에이전트가 함께 일하려면 실행할 곳, 누가 누구와 대화할지 정하는 규칙, 하나가 실패하면 복구할 방법이 필요합니다. | 에이전트 하나라면 간단합니다. 하지만 여러 에이전트가 함께 일하려면 실행할 곳, 누가 누구와 대화할지 정하는 규칙, 하나가 실패했을 때 복구할 방법이 필요합니다. | If it's one agent, it's simple. But for many agents to work together, you need a place to run them, rules deciding who talks to whom, and a way to recover when one fails. | «에이전트 하나쯤은 쉽습니다» ("one agent or so is easy") left unsaid what is easy; the Korean needs a condition and an explicit "but" to set up the turn. |
| d5661343 | 운영체제는 직접 만들지 않은 프로그램을 실행합니다. GenSwarms는 에이전트를 그렇게 실행합니다. 시작하고, 격리하고, 메시지를 라우팅하고, 실패하면 재시작합니다. | 운영체제는 직접 만들지 않은 프로그램을 실행합니다. GenSwarms가 에이전트에게 하는 일이 바로 이것입니다. 에이전트를 시작하고, 격리하고, 메시지를 라우팅하고, 실패하면 재시작합니다. | An operating system runs programs it didn't write itself. That is exactly what GenSwarms does for agents: it starts them, isolates them, routes their messages and restarts them when they fail. | «GenSwarms는 에이전트를 그렇게 실행합니다» ("GenSwarms runs agents like that") is a stiff rendering of "does that for agents". |
| 90e66590 | 각 에이전트는 자기 샌드박스 안에서, 자기 슈퍼바이저 아래 실행됩니다. 하나가 크래시되면 그 에이전트는 재시작되고, 나머지는 계속 일합니다. 역할, 모델, 실행 위치는 따로 정합니다. | 각 에이전트는 전용 샌드박스 안에서, 전용 슈퍼바이저의 관리를 받으며 실행됩니다. 하나가 크래시되면 그 에이전트는 재시작되고, 나머지는 계속 일합니다. 역할, 모델, 실행 위치는 각각 따로 정합니다. | Each agent runs inside its own dedicated sandbox, managed by its own dedicated supervisor. If one crashes, that agent restarts and the rest keep working. Role, model and where it runs are each set separately. | «자기 샌드박스 … 자기 슈퍼바이저 아래» copies the English "its own … under its own"; «전용» (dedicated) and «관리를 받으며» are how Korean says it. |
| 2cd90562 | 그래프는 직접 그립니다. 모든 메시지는 그래프에 맞는지 검사되고, 벗어난 메시지는 폐기됩니다. | 그래프는 직접 그립니다. 모든 메시지는 이 그래프를 기준으로 검사되고, 벗어난 메시지는 폐기됩니다. | You draw the graph yourself. Every message is checked with this graph as the reference, and messages that stray from it are dropped. | «그래프에 맞는지 검사되고» ("is checked whether it fits the graph") is an awkward passive; «~를 기준으로 검사» is the standard way to say "checked against". |
| 169c0a3b | 여기서부터 그림은 스웜 하나를 따라갑니다. Telegram에서 고객에게 답하는 지원팀입니다. | 여기서부터 그림은 스웜 하나를 따라갑니다. Telegram에서 고객 문의에 답하는 지원팀입니다. | From here the drawings follow one swarm: a support team that answers customer inquiries on Telegram. | «고객에게 답하는» ("answers to customers") is a calque; Korean support copy says «고객 문의에 답하는». |
| 57b1f883 | 오브젝트는 같은 그래프 위의 일반 코드입니다. Telegram&nbsp;게이트웨이, 스케줄러, 모델 비용 예산이 여기에 속합니다. 매번 같은 일을 합니다. | 오브젝트는 같은 그래프 위의 일반 코드입니다. Telegram&nbsp;게이트웨이, 스케줄러, 모델 비용 예산이 그 예입니다. 매번 똑같이 동작합니다. | Objects are plain code on the same graph. A Telegram gateway, a scheduler and a model-spend budget are examples. They behave exactly the same way every time. | «…이 여기에 속합니다» ("belong here") read like a taxonomy; «그 예입니다» is natural. «매번 같은 일을 합니다» had no subject and read as a fragment. |
| 3407f33c | 에이전트에게 필요한&nbsp;건 설치하세요. | 에이전트에게 필요한&nbsp;건 설치해서 쓰세요. | What your agents need, install it and use it. | «필요한 건 설치하세요» sounded clipped and oddly contrastive; «설치해서 쓰세요» is how Korean dev copy says "install what you need". |
| 41acb76d | AI 조직을 위한 단일 제어 계층. | 조직의 모든 에이전트를, 하나의 제어 계층에서. | Every agent in your organization, from one control layer. | «AI 조직» in Korean means a company's AI division (AI 조직 개편), the same trap as «AI 인력»; «단일 제어 계층» read like a spec sheet. |
| e28ae737 | 모든 메시지, 크래시, 재시작을 실시간으로 지켜보세요. API나 CLI로 다루거나, 코딩 에이전트에게 맡기세요. | 모든 메시지, 크래시, 재시작을 실시간으로 확인하세요. API나 CLI로 제어하거나, 코딩 에이전트에게 맡기세요. | Check every message, crash and restart in real time. Control it with the API or CLI, or leave it to your coding agent. | «지켜보세요» ("keep watch") is literary; «확인하세요» is the product verb. «다루거나» ("handle") was vague for "drive"; «제어하거나» matches the control-layer headline. |
| a0b063e5 | 모델은 지능을 제공합니다. | 지능은 모델이. | Intelligence: by the models. | The three «X는 Y를 ~합니다» sentences read as a translated list. «지능은 모델이. 일은 에이전트가. 조직 운영은 GenSwarms가.» is the elliptical "X은 Y가" slogan pattern Korean ads use for a division of labour. |
| a34eb019 | 에이전트는 일을 수행합니다. | 일은 에이전트가. | The work: by the agents. | Second beat of the same pattern. |
| 86d0513d | GenSwarms는 조직을 운영합니다. | 조직 운영은 GenSwarms가. | Running the organization: by GenSwarms. | «GenSwarms는 조직을 운영합니다» was the literal "runs the organization"; the elliptical beat lands on GenSwarms, as the English does. |
| fdf7837b | 운영체제의 구성 요소별로 GenSwarms가 채워 넣은 것. | 운영체제의 구성 요소별로, GenSwarms에서는 무엇이 그 역할을 하는지. | For each part of an operating system, what plays that role in GenSwarms. | «구성 요소별로 GenSwarms가 채워 넣은 것» ("the thing GenSwarms stuffed in per component") was a calque of "what GenSwarms puts in each place". |
| f8768e8a | 에이전트가 실행되는 곳 | 실행 위치 | Where it runs | «에이전트가 실행되는 곳» was a long clause for a row label; «실행 위치» is the ledger's prose term and standard label wording. |
| f294f1c2 | 패키지는 서명된 로그와 대조해 검증. | 패키지는 서명된 로그를 기준으로 검증. | Packages verified against a signed log (as the reference). | «로그와 대조해 검증» is a stiff calque of "checked against"; «~를 기준으로 검증» is standard. |
| c39d7104 | &lt;span&gt;한 팀으로 시작하세요.&lt;/span&gt; &lt;span&gt;에이전트&nbsp;수천&nbsp;개로 확장하세요.&lt;/span&gt; | &lt;span&gt;팀 하나로 시작하세요.&lt;/span&gt; &lt;span&gt;에이전트&nbsp;수천&nbsp;개까지 확장하세요.&lt;/span&gt; | Start with one team. Scale up to thousands of agents. | «한 팀으로» also means "as one united team"; «팀 하나로» is unambiguous. «수천 개로 확장» ("expand into thousands") → «수천 개까지 확장» ("scale up to"), the Korean idiom for scaling. |
| 938739e1 | 현재 채팅 어시스턴트, 코딩 에이전트, 트레이딩 시뮬레이션, 다른 스웜을 지켜보는 스웜에 쓰이고 있습니다. | 현재 채팅 어시스턴트, 코딩 에이전트, 트레이딩 시뮬레이션, 다른 스웜을 모니터링하는 스웜에 쓰이고 있습니다. | Currently used for chat assistants, coding agents, trading simulations and swarms that monitor other swarms. | «지켜보는» ("watch over") is literary; developers say «모니터링하는». |
| 3c90a001 | 아니면 에이전트에게 맡기세요: | 또는 에이전트에게 이렇게 요청하세요: | Or ask your agent like this: | «에이전트에게 맡기세요:» ("entrust it to your agent:") before a prompt doesn't tell the reader what to do with the text below; Korean says "ask it like this". |
| 2714bd32 | 각자 자기 샌드박스 안에 | 각자 전용 샌드박스 안에 | Each inside its own dedicated sandbox | Follows step 4 (전용 샌드박스). |
| e08af9a7 | 그림: 스웜 36개, 에이전트 수천 개로 이뤄진 조직. 각 스웜은 에이전트(원)와 오브젝트(사각형)가 선언된 경로로 이어지고 슈퍼바이저 아래 놓인 작은 구조입니다. 메시지가 경로를 따라 흐르고, 이따금 에이전트 하나가 크래시되면 슈퍼바이저가 재시작합니다. | 그림: 스웜 36개, 에이전트 수천 개로 이뤄진 조직. 각 스웜은 에이전트(원)와 오브젝트(사각형)로 된 작은 구조로, 선언된 경로로 이어져 있고 슈퍼바이저의 관리를 받습니다. 메시지가 경로를 따라 흐르고, 이따금 에이전트 하나가 크래시되면 슈퍼바이저가 재시작합니다. | Illustration: an organization of 36 swarms and several thousand agents. Each swarm is a small structure of agents (circles) and objects (squares), linked by declared paths and managed by supervisors. Messages flow along the paths; now and then one agent crashes and its supervisor restarts it. | The second sentence was one long English-shaped clause stack («…이어지고 … 아래 놓인 작은 구조»). |
| c73bd527 | 그림: 카메라가 스웜 하나, 지원팀으로 확대해 들어갑니다. | 그림: 카메라가 스웜 하나(지원팀)를 확대합니다. | Illustration: the camera zooms in on one swarm (a support team). | «확대해 들어갑니다» ("zooms, going in") is a calque of "zooms into". |
| e12cf2d5 | 그림: 각 에이전트가 자기 샌드박스 안에서 자기 슈퍼바이저 아래 실행됩니다. 에이전트 하나가 크래시된 뒤 재시작되는 동안 나머지는 계속 실행됩니다. | 그림: 각 에이전트가 전용 샌드박스 안에서 전용 슈퍼바이저의 관리를 받으며 실행됩니다. 에이전트 하나가 크래시된 뒤 재시작되는 동안 나머지는 계속 실행됩니다. | Illustration: each agent runs inside its own dedicated sandbox, managed by its own dedicated supervisor. While one agent crashes and is restarted, the rest keep running. | Same fix as step 4 (자기 … 자기). |
| 7596f4cc | 그림: 문서로서의 스웜. 시드와 변경 로그로 이뤄집니다. 에이전트 100개 상한을 넘는 변경은 거부되고 기록되지 않습니다. | 그림: 문서로 표현된 스웜. 시드와 변경 로그로 이뤄집니다. 에이전트 100개 상한을 넘는 변경은 거부되고 기록되지 않습니다. | Illustration: the swarm represented as a document. It consists of a seed and a log of changes. A change over the 100-agent cap is refused and not logged. | «문서로서의 스웜» is a textbook calque of "the swarm as a document". |
| 3d579ae6 | 그림: 각 오브젝트는 서명된 패키지에서 오며, 로드되기 전에 검증됩니다. | 그림: 각 오브젝트는 서명된 패키지로 제공되며, 로드되기 전에 검증됩니다. | Illustration: each object is provided as a signed package and is verified before it loads. | «패키지에서 오며» ("comes from a package") is a calque of "comes from". |
| 9ff6bfcc | 그림: 카메라가 뒤로 물러나 조직 전체를 보여 줍니다. 이제 모두 단일 제어 계층 아래 있습니다. | 그림: 카메라가 뒤로 물러나 조직 전체를 보여 줍니다. 이제 모두 하나의 제어 계층 아래 있습니다. | Illustration: the camera pulls back to show the whole organization. Now everything is under one control layer. | «단일 제어 계층» follows the step 9 headline (하나의 제어 계층). |

**Left as they were, on purpose.**
- **Meta description (`7b40834f`):** any full-sentence form comes to 88 to 94 characters, over the 80 limit.
- **The step headlines 2, 3, 4, 5, 6 and 8:** they already read as native Korean.
- **The lede:** «AI 에이전트 수천 개를 조직 전체에 배포하고, 조율하고, 제어하세요.» is natural, and repeating «AI 에이전트» right after the h1 helps search.
- **The spec sheet, comparison cells and "not yet" list:** they are correct 개조식 (bullet-style) fragments.
- **The 404:** it is fine as it is.
- **The prompt «다음 문서를 읽고 스웜을 설정해 주세요: …»:** it is already a natural Korean request.

**Checked.** The temp-dir build is clean. Every changed string was viewed at 1440×900, 1024×768 and 390×844, with 3 s settle before each shot. Headline breaks:
- The triad sets as three short lines.
- The close sets as «팀 하나로 시작하세요. / 에이전트 수천 개까지 확장하세요.» on desktop and adds a third line («확장하세요.») at 390.
- «조직의 모든 에이전트를, / 하나의 제어 계층에서.» breaks at the comma at every width.

`AUDIT_LANGS=ko i18n-audit.cjs`: ok, 1 language × 18 sizes.
