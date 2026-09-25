# Turkish (tr) concept ledger: GenSwarms landing page

Sources: `README.md`, `docs/architecture.md`, `messaging.md`, `objects.md`, `intermediate-representation.md`, the approved copy deck (`design/2026-09-25-copy-deck-v2.md`), and the translator notes (`concepts.md`). Shared terms follow the GenLayer Labs homepage (`~/dev/genlayerlabscom-site/i18n/tr.ledger.md`) and the SubZeroClaw page (`subzeroclaw site/i18n:i18n/tr.ledger.md`): ajan, yapay zekâ ajanı (first use), sürü, ajan çalışma ortamı → çalışma ortamı, istem, sandbox, framework, konteyner, skill dosyası, Belgeler, Kopyala / Kopyalandı, the suggestion bar strings. One deliberate deviation: supervisor (see below).

Register: formal "siz" imperatives (okuyun, kurun, izleyin), as on both sister pages. UI labels use the bare imperative (Kopyala, Kapat, Karşılaştırma as a noun). Suffixes on names go after the typographic apostrophe ’ (GitHub’da, Telegram’a, AutoGen’den, GenSwarms’ın, sandbox’ında), as on the sister pages.

## Objects

| Concept / object | Source term | Meaning in context | Keep distinct from | TR | Avoid | Source passage |
|---|---|---|---|---|---|---|
| Operating system | operating system | The analogy for the whole product | platform, framework | işletim sistemi | platform | copy deck "Think of it as an operating system" |
| AI workforce | AI workforces | The vision: many agents as an organization's staff | swarm/team; labour-market statistics | yapay zekâ iş gücü (mass noun, singular) | işgücü piyasası sense; "yapay zekâ çalışanları" (reads as the humans working in AI) | copy deck H1 |
| Organization | organization, AI organization | The company whose work the agents do | "kuruluş" (also "founding"), "kurum" | organizasyon; "organizasyonunuz genelinde" | kuruluş ("GenSwarms kuruluşu" parses as "the GenSwarms organization") | hero lede, step 9, fig. 3 |
| Agent | agent | LLM-backed worker, one process each | object, model | yapay zekâ ajanı (first use, title, meta), then ajan | temsilci, aracı | README; GenLayer Labs ledger |
| Object | object | Deterministic Elixir handler on the same graph | agent | nesne | varlık, obje | docs/objects.md |
| Model | model | The LLM an agent calls | agent | model | – | – |
| Prompt | prompt | Part of an agent (fig. 1) | – | istem | prompt (SubZeroClaw ledger) | fig. 1 |
| Process | process | OTP/OS process; each agent is one | business process, "işlem" (transaction) | süreç | işlem, prosedür | architecture.md |
| Sandbox / boundary | sandbox; its boundary | Per-agent isolation (bwrap, Docker, Apple container) | – | sandbox (sandbox’ında); boundary → sınır | korumalı alan (SubZeroClaw ledger) | security.md |
| Supervisor | supervisor | OTP supervisor: software that restarts a crashed process | a human manager | denetleyici; "under its own supervisor" → kendi denetleyicisine bağlı (editor pass); supervised → denetimli | yönetici (GenLayer Labs used it, but it reads as manager/administrator, a person, which concepts.md rules out); denetçi (auditor); süpervizör (call-centre) | architecture.md; en.json "not a person" |
| Crash / restart | crash, restart, fails | Process dies / is started again by its supervisor | general failure | çökmek, çökme; yeniden başlar / yeniden başlatılır / yeniden başlatma | başarısız olmak (calque) | – |
| Declared path | declared paths | The message topology you define up front | workflow, pipeline | tanımlı yol(lar) | beyan edilmiş (legal), bildirilmiş | messaging.md |
| Graph / edge | graph, edges | The declared topology | chart | graf, kenar | grafik (chart), çizge (academic) | – |
| Message | message | What agents send, checked each hop | notification | mesaj; checked → kontrol edilir; each hop → her adımda | denetlenir (would collide with denetleyici) | messaging.md |
| Dropped | dropped (invalid_route) | Off-graph message discarded | lost, deleted | düşürülür / düşürüldü (the networking term for dropped packets) | atıldı ("mesaj atıldı" = "message sent" in everyday Turkish), silindi, kayboldu | messaging.md |
| Swarm | swarm | Running agents + objects + topology | team (plain word) | sürü; never after "bir" alone: "Sürü bir belgedir", "tek bir sürü", "bir GenSwarms sürüsü" | "bir sürü …" (the idiom "a lot of"); küme | GenLayer Labs ledger (both points) |
| Team | team | Plain word for a swarm with a purpose | swarm | ekip (destek ekibi, tek bir ekiple) | takım | copy deck |
| Package | package | Signed, content-addressed unit from swarmidx | app, plugin | paket | eklenti, uygulama | swarmidx |
| Signed / verified | signed, verified, checked | Ed25519 signature, verified locally against a transparency log | certified, approved | imzalı / doğrulanır, doğrulandı; "checked on your machine" → kendi makinenizde kontrol edilir | onaylı, sertifikalı | swarmidx |
| Index | swarmidx index | Package index / notary | store, marketplace | swarmidx dizini (as "Python Paket Dizini") | mağaza, pazar yeri | swarmidx |
| Connector | connectors | Telegram/WhatsApp/email packages | – | bağlayıcı | konnektör | – |
| Gateway | Telegram gateway | Object through which Telegram traffic flows | payment gateway | Telegram geçidi | – | objects.md |
| Scheduler | scheduler (cron) | Deterministic timed messages | calendar | zamanlayıcı | takvim | – |
| Budget | budget for model spend | Object capping LLM spend | company budget | model harcamaları için bir bütçe; spend budgets → harcama bütçeleri | – | – |
| Document | a swarm is a document | Definition is data: seed + log of changes | paper document, file | belge; "Sürü bir belgedir." | dosya | intermediate-representation.md |
| Seed | seed (swarm.state) | The swarm's starting definition | random seed | başlangıç tanımı; in the monospace restore label, short form "tanım" | tohum (opaque to non-specialists) | IR docs |
| Change log | change log, logged | Ordered log of changes (swarm.overlay) | release notes (değişiklik günlüğü/sürüm notları) | değişiklik kaydı; logged → kayda geçer | changelog, sürüm notları | IR docs |
| Refused | refused | Change rejected by the gate before it runs | denied by a person | reddedilir; before it runs → devreye girmeden | – | IR docs |
| Restore from database | comes back from its database | Stopped swarm rebuilt from SQLite | backup by a person | veritabanından geri gelir / geri yükleme | yedekten dönmek | IR docs |
| Control layer | control layer | GenSwarms above models and agents | management layer (human) | kontrol katmanı | yönetim katmanı | – |
| Event stream | live event stream, events | Live feed of messages, crashes, restarts | news feed | canlı olay akışı; olaylar | haber akışı | – |
| Runtime | runtime | What GenSwarms is (comparison table) | framework | çalışma ortamı | çalışma zamanı | GenLayer Labs ledger |
| Backend | backend | Where an agent runs (Local, Docker, SSH…) | – | arka uç | backend | backends.md |
| Illustration | illustration | Caption: simulated events, placeholder data | – | temsilî (as in "görsel temsilîdir") | illüstrasyon (drawing) | en.json note |

## Texture words

| Word | Decision | Why |
|---|---|---|
| "operating system" | işletim sistemi, everywhere | The standard computer term; the analogy works only if it is the same word. |
| "workforce" | iş gücü | "Dijital iş gücü" is the established Turkish marketing term for software workers; it reads as an organization's staff. "Kadro" (staff roster) was the runner-up, flagged for review. |
| "runs" (the organization) | işletir | "İşletmek" is the verb inside "işletim sistemi", so the kicker ends on the OS idea. "Yönetir" would suggest a human manager. Programs/agents "run" → çalıştırır. |
| "plain code" / "the same thing every time" | sade kod / her seferinde aynı şeyi yapar | Unglamorous and reliable, no selling. |
| "declared" | tanımlı | What you define in configuration, up front. |
| kicker | "Zekâyı modeller sağlar. İşi ajanlar yapar. Organizasyonu GenSwarms işletir." | Object–subject–verb in all three beats puts each subject in the focus slot, which is the Turkish way to say "models do X, agents do Y, GenSwarms does Z". It also avoids "GenSwarms organizasyonu", which would parse as "the GenSwarms organization". Three short, parallel lines. |
| Headlines | short statements ending in "." | genlayerlabs.com voice, no selling adjectives. |
| "Drive it" | yönetin | Plain "operate it". "Yönlendirin" is kept for message routing. |
| 404 "ran off the swarm" | Bu sayfa sürüden koptu. | "Sürüden kopmak" (to stray from the herd) is an idiom, so the joke survives; "topolojinin dışına sapmış" keeps "wandered off", with the evidential -mış. |

## Left in English

GenSwarms, GenLayer Labs, GitHub, OTP, bwrap, Docker, Apple container, SSH, REST, WebSocket, CLI, API, gsp, swarmidx, Telegram, WhatsApp, LangGraph, LangSmith Deployment, CrewAI, AMP, AutoGen, Microsoft Agent Framework, MIT, 0.2.0, skill.md, the URL, and the identifiers drawn in the figures (triage, research, answer, cron…). "sandbox", "framework", "token" and "skill dosyası" stay as developers say them (SubZeroClaw ledger).

## Layout decisions (checked at 1440×900 and 390×844, i18n audit: 14 sizes, no overlaps)

| id | Decision | Why |
|---|---|---|
| 3d04f665 | `reddedildi: {cap} ajanı aşıyor` (28 chars rendered) | `…{cap} ajan sınırı aşıldı` (34) wrapped on phones, where the English fits one line. "Exceeds 100 agents" keeps the meaning; the alt text still names the cap (100 ajan sınırı). |
| 97dfad27 | `geri yükle: tanım + {n} değişiklik` (32) | `geri yükleme:` wrapped on phones. "tanım" is the short form of "başlangıç tanımı" (the seed note right above it). |
| 41acb76d | `Yapay zekâ organizasyonunuza tek kontrol katmanı.` | The "… için tek bir …" version took four display lines on desktop; the headline-style dative keeps it to three, as in English. |
| 37df3170 | `https://genswarms.com/skill.md dosyasını oku ve sürü kur.` | Informal imperative, as prompts to an agent are written. "bir sürü kur" would read as "set up a lot"; bare "sürü kur" avoids the idiom and is short. |
| ad3f9aa5 | `düşürüldü` (9 vs hint 8) | One word, cannot wrap; sits clear of the arrow at all 14 sizes. The only alternative under 8 that means "dropped" is "atıldı", which reads as "sent". |
| 1d06a0d7 | `model` = English (listed under `_same_as_english`) | Turkish uses the same word. |

## Editor pass

Native editor read of `/tr/` at 1440×900 and 390×844, cold first, then against the English for meaning. Every change is the same length or shorter. Temp build is clean and `i18n-audit.cjs` passes (2 languages × 14 sizes, suggestion bar, no-JS picker, 404).

### Flagship verdicts

| Term | Verdict |
|---|---|
| AI workforce | Keep **yapay zekâ iş gücü**. With "yapay zekâ" in front it reads as an organization's staff, not labour statistics; "kadro" sounds like a payroll roster and does not work in the H1. |
| operating system | Keep **işletim sistemi**. It is the standard term, and the analogy only works if it is the same word everywhere. |
| supervisor | Keep **denetleyici / denetimli**. It reads as a component, as in "disk denetleyicisi", not as a boss; "denetimli süreç" doesn't bring "denetimli serbestlik" to mind. Changed "denetleyicisinin gözetiminde" to "denetleyicisine bağlı", which said supervision twice. |
| runs the organization | Keep **işletir**. It is natural with "organizasyon" and echoes "işletim sistemi"; "yönetir" would sound like a human manager. |
| three-beat kicker | Keep **"Zekâyı modeller sağlar. İşi ajanlar yapar. Organizasyonu GenSwarms işletir."** The OSV order is the Turkish way to put the stress on the actor in each line, so it reads crisp rather than awkward. Added only an `&nbsp;` so the third line breaks as "Organizasyonu / GenSwarms işletir." rather than leaving "işletir." alone on the last line. |
| swarm | Keep **sürü**, with the translator's guard against "bir sürü" ("a lot of"). |

### Translator's other doubts

| Doubt | Verdict |
|---|---|
| "düşürülür / düşürüldü" for dropped | Keep. This is the networking term (paket düşürme), and the figure shows it happening; "atıldı" would read as "sent". |
| "reddedildi: 100 ajanı aşıyor" without "sınır" | Keep. It is a log line, the meaning is intact, and the alt text names the cap. |
| "worker" in the AutoGen cell | Keep. It is AutoGen's own term, and Turkish developers say "worker"; "çalışan" would read as "employee". |
| "Binlerce ajana ölçeklenin" | Changed to "büyüyün" (see the table below). |

### Changes

| id | before | after | reason |
|---|---|---|---|
| 90e66590 | Her biri kendi sandbox’ında, kendi denetleyicisinin gözetiminde çalışır. … | Her biri kendi sandbox’ında, kendi denetleyicisine bağlı çalışır. … | "denetleyici … gözetiminde" said supervision twice. "Bağlı" is how people describe a process under a supervisor, and it is shorter. |
| 05158e16 | … bir GenSwarms denetleyicisinin gözetiminde; … | … bir GenSwarms denetleyicisine bağlı; … | Uses the same phrase as the paragraph above (alt text). |
| 2cd90562 | Grafı siz çizersiniz. Her mesaj bu grafa göre kontrol edilir; … | Grafı siz tanımlarsınız. Her mesaj grafa göre kontrol edilir; … | "Çizmek" reads as literally drawing, and it collides with the "çizimler" (the figures) in the next line. "Tanımlarsınız" picks up "tanımlı yollar" from the headline, so step 5 reads as one argument. Dropping "bu" keeps the length the same. |
| 169c0a3b | Buradan sonra çizimler tek bir sürüyü izliyor: … | Artık çizimler hep aynı sürüyü gösteriyor: … | "Çizimler … izliyor" is a calque of "follow", and it can read as "the drawings watch a swarm". The new line is more natural and shorter. |
| 57b1f883 | Nesneler, aynı graf üzerindeki sade kodlardır: … | Nesneler, aynı graftaki sade koddur: … | "Kod" here is a mass noun, and the plural "kodlardır" sounds translated. Shorter. |
| 86d0513d | Organizasyonu GenSwarms işletir. | Organizasyonu GenSwarms&nbsp;işletir. | Line break only. At 1440 and 390 the verb was left alone on the last line. |
| 8ee1cf08 | Çalıştırmayı; ajanlar hatalarda yeniden dener, akışlar durumunu saklayıp kaldığı yerden sürebilir | Çalıştırmayı; ajanlar hatada yeniden dener, akışlar durumu saklayıp kaldıkları yerden sürebilir | "Kaldığı" didn't agree with the plural "akışlar", and the sentence scans better this way. The facts are unchanged (this cell is sourced), and it is 2 characters shorter. |
| 4713393e | Tek bir ekiple başlayın. Binlerce ajana ölçeklenin. | Tek bir ekiple başlayın. Binlerce ajana büyüyün. | "Ölçeklenin" is a SaaS calque. "X ile başlayın, Y’ye büyüyün" is the natural Turkish pair (as in "şirket 500 çalışana büyüdü"), and it is not a stronger claim. Shorter. |

## Final review (controller)

| id | before | after | reason |
|---|---|---|---|
| 97dfad27 | geri yükle: tanım + {n} değişiklik | geri yükleme: tanım + {n} değişiklik | Final review: the English label is a noun; the spec row already says «geri yükleme». |
