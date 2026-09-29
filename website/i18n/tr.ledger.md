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

## Redesign pass (2026-09)

The v4 "Zoom" page: one canvas that zooms from the organization to one agent and back, with readouts under it, a legend, a facts row and capitalized spec and list lines. 91 ids translated (new or changed), 50 stale ids deleted. Every existing term decision above still holds; none was changed. Checked in a private temp build at 1440×900, 1024×768 and 390×844 (every zoom keyframe, header, sections, footer); `i18n-audit.cjs` against the served temp build: ok (2 languages × 18 sizes, canvas labels, suggestion bar, no-JS picker, 404).

### Zoom caption (the scale the camera is at)

| Level | EN | TR | Why |
|---|---|---|---|
| organization | organization | organizasyon | Ledger term (never "kuruluş"). |
| team | team | ekip | Ledger term for a swarm with a purpose ("destek ekibi"). |
| agent | agent | ajan | Ledger term; also the label under the agent drawn up close and the legend's circle. |
| counts | {swarms} swarms · {agents} agents | {swarms} sürü · {agents} ajan | Turkish keeps the noun singular after a number ("36 sürü", "2.861 ajan"). |

### Canvas labels

| id | EN | TR | Note |
|---|---|---|---|
| 7242d340 | start · isolate · route · restart | başlat · yalıt · yönlendir · yeniden başlat | The four OS jobs as bare imperatives, the way Turkish service controls are labelled (Başlat / Durdur / Yeniden başlat). 43 chars vs budget 36: "yeniden başlat" has no shorter form that still means restart ("yenile" is refresh). The bar has room at 1024 and 1440; at 390 it is hidden in English too. |
| c2e2d662 | process | süreç | Ledger. |
| 9ed037b8 | sandbox | sandbox | Ledger (as developers say it); listed under `_same_as_english`. |
| 76d1bfb6 | crashed | çöktü | Ledger (çökmek). |
| 545c357f | restarted | yeniden başladı | Intransitive, as in step 4 ("Biri çökerse yeniden başlar"). 15 vs budget 14; "yeniden başlatıldı" would be 18. |
| d493c317 | log of changes | değişiklik kaydı | Ledger (change log). |
| 09d607fd | {n} declared | {n} tanımlı | Ledger (declared → tanımlı); reads "paths 4 tanımlı". |
| 2a4a3109 | never logged | hiç kayda geçmedi | Ledger (logged → kayda geçer). |
| 039b47cb | defines | tanımlar | Same root as "tanımlı": the document defines the swarm. |
| cb79fe53 | restores from its database | veritabanından geri gelir | Ledger ("veritabanından geri gelir", as in step 8). A no-break space in "geri gelir" makes the canvas wrap it "veritabanından / geri gelir" instead of stranding "gelir". |

### Legend and facts row

| EN | TR | Why |
|---|---|---|
| agent / object / supervisor | ajan / nesne / denetleyici | Ledger. |
| message on a declared path | tanımlı yoldaki mesaj | Short, and keeps "tanımlı yol". |
| license / version / runtime | lisans / sürüm / çalışma ortamı | "runtime" is "çalışma ortamı" everywhere (ledger), here over "Elixir / OTP". |
| Open source, MIT | Açık kaynak, MIT | Also on the share card. |

### Readouts

| Concept | TR | Why |
|---|---|---|
| K2 rows (model / prompt / tools) | bir sonraki adıma karar verir / işin ne olduğunu söyler / işi yapar | Plain verbs; "iş" twice ties the prompt to the tools. |
| K3 rows | kim kiminle konuşur → her ajanın içine yazılmış; her biri nerede çalışır → nerede başlatıldıysa orada; biri çöktüğünde → onu yeniden başlatan yok | Echo step 2 ("kimin kiminle konuşacağını", "biri çöktüğünde"). |
| K4 rows | başlat / yalıt / yönlendir / yeniden başlat, each with an object in the accusative ("her ajanı ayrı bir süreç olarak", "mesajları yalnızca tanımlı yollardan", "çöken ajanı, denetleyicisi aracılığıyla") | Same verbs as the canvas bar; the row reads as one command. |
| K5 rows | ajan {n} / diğer {n} / çalışıyor / denetleyicisi yeniden başlattı | "diğer 11" is the natural "the other 11"; active voice, the supervisor as the subject. |
| K7 caption | "Model çağrılarını answer ve research, budget üzerinden yapar." | Avoids opening a sentence with a lower-case agent name; "üzerinden" avoids a suffix on the bold name. |
| K9 | geri yükleme → "tanım, sonra değişiklik 1, 2, 3" | Short form "tanım" (ledger) keeps the readout as short as the English: a taller readout made the 1024 stage fall back to the document alone. |
| headings | olaylar / paketler / tek olay akışı + "(temsilî)" | Ledger (illustration → temsilî). |
| alt texts | "Çizim: …" | The canvas's text alternative names what is drawn; "temsilî" stays for the visible caption. |

### Changes to existing strings

| id | before | after | reason |
|---|---|---|---|
| 3b3ae940 | Yapay zekâ iş gücü için işletim&nbsp;sistemi. | Yapay zekâ iş&nbsp;gücü için işletim sistemi. | Geist Mono is wider: at 1440 and 768 the unbreakable "işletim sistemi." no longer fit the column and Chrome broke off the full stop (and at 768 "sistem / i."). Now it breaks between words ("işletim / sistemi.") at those two widths and stays three lines elsewhere. |
| 3c7c53c0 | Bunu bir işletim sistemi gibi düşünün. | Bunu bir işletim&nbsp;sistemi gibi düşünün. | Line break only: at 1024, 768 and 390 the term split as "işletim / sistemi". |
| c39d7104 (was 4713393e) | Tek bir ekiple başlayın. Binlerce ajana büyüyün. | `<span>Tek bir&nbsp;ekiple başlayın.</span> <span>Binlerce ajana büyüyün.</span>` | New two-span markup. The no-break space stops "Tek bir" standing alone on phones (390, 320). |
| 837e43c3 (was 8403b415) | nesneler: aynı graf üzerinde deterministik kod | Nesneler: aynı graftaki deterministik kod. | Capitalized line; "graftaki" as in step 6 after the editor pass. |
| bff34e70 (was 36e77013) | başlangıç tanımı ve değişiklik kaydı; hatalı değişiklikler reddedilir; veritabanından geri yükleme | Başlangıç tanımı ve değişiklik kaydı. Hatalı değişiklikler reddedilir. Veritabanından geri yükleme. | Follows the English's three sentences. |
| 9a976fc2 (was 7b7d0d74) | Seçip kopyalayın | Seçildi | The English changed meaning: the button now reports the state ("Selected"), next to Kopyala / Kopyalandı. |
| 0a4470d6 (was 6ce82780) | Nasıl çalışır bölümüne atla | İçeriğe atla | The link now jumps to the content. |
| e071ace2 (was 3229609e) | Lisans | Lisans (MIT) | As the English. |

The other capitalized spec and list lines (7a956af2, a7b45c42, b02df163, ce5bafa3, 620402be, dfac9de1, c2593f94, 19b6c67d, 1de79ed2, 817dc80f, f294f1c2, bf0dfbad, a1804765, c1071d66, 90361c3e, 2944b590) keep their old translation, capitalized and ending in a full stop. The cold read of the whole page found nothing else to change: the story, spec sheet, comparison and guarantees read as one argument with the new labels.

## Final review (2026-09)

A fresh native-editor read of `/tr/` before launch: cold top to bottom, then string by string against the English, including meta and JSON-LD descriptions, canvas aria-labels (`#zoom-strings`), the 404 page and the suggestion bar. I took screenshots at 1440×900, 1024×768, 390×844, 320×640 and 844×390 (each keyframe after the camera settled, plus the header with the picker open, every section and the footer). The page reads as one argument and every term decision above holds. Four changes, none longer than the line it replaces where layout is tight. The temp build is clean, and `i18n-audit.cjs` (tr × 18 sizes) passes.

| id | before | after | reason |
|---|---|---|---|
| 64e0fbb4 | her biri nerede çalışır | nerede çalışır | This K3 row label set the width of the label column, so all three answers wrapped on phones (twice at 320) where the English fits on one line. "Each one" is already in the caption above ("On iki ajan, her biri…"), and the answer "nerede başlatıldıysa orada" is singular. At 390 the rows now fit on one line, as in English. |
| 6f4e39ae | … Model çağrılarını answer ve research, <b>budget</b> üzerinden yapar. | … Answer ve research, model çağrılarını <b>budget</b> üzerinden yapar. | Resolves translator doubt 3. The object-first order with a comma between the subject and the adverbial read as translated. The English itself capitalizes "Answer" at the start of the sentence, so plain subject–object–verb order is natural and follows the source. Same length. |
| 0487a062 | … önce tanım, sonra değişiklikler, sırayla. | … önce tanım, sonra kayıttakiler, sırayla. | The English says "then the *logged* changes". That is the point of the caption: only logged changes are replayed, never refused ones. "Kayıttakiler" (the ones in the log) restores this and is one character shorter. "kayıtlı değişiklikler" and "değişiklik kaydı" both made the 1024 readout three lines, and the stage fell back to showing only the document. |
| 8de95fd5 | Henüz yok | Henüz değil | "Henüz yok" reads as "there are none yet", which contradicts a list of five existing limits. "Henüz değil" is the plain "not yet". |

### Translator doubts (redesign pass)

| Doubt | Verdict |
|---|---|
| 1. H1 on four lines at 1440 and 768 | Keep the headline. On the current build it is three lines at 1440, 1024, 390 and 320. It breaks as "işletim / sistemi." only in the narrow 844×390 landscape column, between words and not as a stranded full stop. Any Turkish wording must end on "işletim sistemi". A smaller Turkish H1 there would be a CSS matter outside these files, and it isn't needed for launch. |
| 2. Imperatives (başlat · yalıt · yönlendir · yeniden başlat) | Keep. The English labels are bare verbs, and Turkish service controls use exactly these imperatives. Verbal nouns would be about 50 characters on a bar budgeted at 36. The K4 rows ("başlat — her ajanı ayrı bir süreç olarak") read as one command, as the English does. |
| 3. K7 caption word order | Changed (see 6f4e39ae): subject first, capitalized "Answer", as the English does. |
| Minor: K4 values wrap on phones | Keep. English wraps these rows at 844×390 and 320 too. The only shorter wording would drop "mesajları" or "aracılığıyla", and it would still wrap because the label "yeniden başlat" is wide. |

## Transcreation pass (2026-09-29)

Brief: find every place that reads as translated from English and rewrite it the way a senior Turkish product marketer at a developer-tools company would. Meaning unchanged, no stronger claims. This pass **supersedes** the "AI workforce" rows above (Objects table, texture words, editor-pass flagship verdict) and the "runs → işletir" texture word.

### "AI workforce" decision: **yapay zekâ ajanları** ("AI agents")

Headline, footer tagline, page title and JSON-LD now read **"Yapay zekâ ajanları için işletim sistemi."** ("The operating system for AI agents.")

- **Why not "yapay zekâ iş gücü" (the old choice).** In Turkish, the phrase belongs to labour-market coverage: PwC Türkiye ("Yapay Zekânın İş Alanlarına Etkisi"), kariyer.net's HR blog and CNBC-e use it for how AI affects the *human* workforce (jobs lost, reskilling). "Yapay zekâ iş gücü için işletim sistemi" can therefore read as "the OS for the AI-era labour force". This is the same trap as Korean «AI 인력» and the Spanish "fuerza laboral". Nobody searching for this product would type it.
- **Why not "dijital iş gücü".** Salesforce's Turkish partners (CMS Wise, Kofana) use it to describe Agentforce, but only in body copy and as a business-outcome word. It drops "AI", it is RPA/CRM register, and it is not what developers search for.
- **Why "yapay zekâ ajanları".** It is the term the Turkish tech press uses for this exact category. Webrazzi's headline on /dev/agents reads "Yapay zeka agent'ları için işletim sistemi geliştiren girişim", which is this headline almost word for word, and "AI ajanları / yapay zeka ajanları" is the working term in Salesforce-partner and press copy. It is already this page's term for "agent" (ledger), so the title, H1 and body now use one word. We chose the generic plural rather than Spanish's "your agents" ("ajanlarınız"), because the English is a generic category statement ("for AI workforces"), and the generic form is the one people search for. The scale that "workforce" carried stays in the lead ("Organizasyonunuz genelinde binlerce yapay zekâ ajanını…").
- H1 markup: `Yapay&nbsp;zekâ ajanları için işletim sistemi.`. It breaks as "Yapay zekâ / ajanları için / işletim sistemi." at 1440, 1024 and 390.
- Share image: the headline is on `og-tr.png`, so `tools/og.cjs` must re-render it before `--check` passes.

### Changes

| id | before | after | back-translation of after | why the before read as translated |
|---|---|---|---|---|
| 3b3ae940 | Yapay zekâ iş&nbsp;gücü için işletim sistemi. | Yapay&nbsp;zekâ ajanları için işletim sistemi. | The operating system for AI agents. | "Yapay zekâ iş gücü" is labour-market vocabulary (the human workforce affected by AI); a calque of *AI workforce*. |
| 37294ee3 | Yapay zekâ iş gücü için işletim sistemi. | Yapay zekâ ajanları için işletim sistemi. | The operating system for AI agents. | Same term (footer tagline). |
| 836e01a9 | GenSwarms: yapay zekâ iş gücü için işletim sistemi | GenSwarms: yapay zekâ ajanları için işletim sistemi | GenSwarms: the operating system for AI agents | Same term (page title, search result title). |
| ffebc746 | Yapay zekâ iş gücü için işletim sistemi: yapay zekâ ajanlarını tanımlı mesaj yollarında ayrı, denetimli süreçler olarak çalıştırır; … | Yapay zekâ ajanları için işletim sistemi: her ajanı tanımlı mesaj yollarında ayrı, denetimli bir süreç olarak çalıştırır; REST + WebSocket API ve canlı olay akışı sunar. | The operating system for AI agents: runs each agent as a separate, supervised process on declared message paths; offers a REST + WebSocket API and a live event stream. | Same term; "her ajanı" avoids repeating "yapay zekâ ajanları" twice in one sentence. |
| 96a75294 | Organizasyonunuz genelinde binlerce yapay zekâ ajanını devreye alın, koordine edin ve kontrol edin. | Organizasyonunuz genelinde binlerce yapay zekâ ajanını devreye alın, koordine edin ve kontrol altında tutun. | Across your organization, deploy thousands of AI agents, coordinate them and keep them under control. | "Kontrol edin" most often means "check / inspect" in Turkish; "kontrol altında tutun" is how Turkish says *control*. |
| be8ebc37 | … devreye alın, koordine edin ve kontrol edin. | Yapay zekâ ajanlarını ayrı, denetimli süreçler olarak devreye alın, koordine edin ve kontrol altında tutun. | Deploy AI agents as separate, supervised processes, coordinate them and keep them under control. | Same as the lead (share text). |
| 41acb76d | Yapay zekâ organizasyonunuza tek kontrol katmanı. | Tüm ajanlarınız için tek kontrol katmanı. | One control layer for all your agents. | "Yapay zekâ organizasyonu" is a calque of *AI organization*; no Turkish page says it. The organization of agents is "all your agents". |
| 86d0513d | Organizasyonu GenSwarms&nbsp;işletir. | Organizasyonu GenSwarms&nbsp;yönetir. | GenSwarms runs [manages] the organization. | "İşletmek" collocates with businesses and facilities (otel, fabrika, hat işletmek), not with an organization; it was chosen to echo "işletim sistemi", and it read as a word game. "Yönetir" is the verb Turkish uses with "organizasyon", and it matches "yönetin" in step 9. |
| c39d7104 | … <span>Binlerce ajana büyüyün.</span> | <span>Tek bir&nbsp;ekiple başlayın.</span> <span>Binlerce ajana ulaşın.</span> | Start with one team. Reach thousands of agents. | "Ajana büyümek" (grow into agents) is odd: the reader doesn't become agents. "X ile başlayın, Y’ye ulaşın" is the natural Turkish pair. It is not a stronger claim. |
| 3c90a001 | Ya da ajanınıza bırakın: | Ya da kurulumu ajanınıza bırakın: | Or leave the setup to your agent: | "Bırakın" with no object is a calque of *hand it to*; Turkish needs to say what is left to the agent. |
| e28ae737 | … API veya CLI ile yönetin ya da kodlama ajanınıza bırakın. | Her mesajı, çökmeyi ve yeniden başlatmayı anında izleyin. Sürüyü API ya da CLI ile yönetin veya bu işi kodlama ajanınıza bırakın. | Watch every message, crash and restart as it happens. Manage the swarm by API or CLI, or leave the job to your coding agent. | Two verbs with no object (English's "drive it … hand it"); Turkish reads it as incomplete. |
| 84d5e16a | Tek bir ajan kolaydır. … | Tek bir ajanı yönetmek kolaydır. Birlikte çalışan çok sayıda ajana ise … | Managing a single agent is easy. Many agents working together, however, need … | "Tek bir ajan kolaydır" (*one agent is easy*) is English ellipsis; Turkish names the activity. |
| d5661343 | … GenSwarms da ajanlar için bunu yapar: … | … GenSwarms aynısını ajanlar için yapar: onları başlatır, … | … GenSwarms does the same for agents: it starts them, … | "Bunu yapar" is a calque of *does that*; "aynısını yapar" is the Turkish idiom. |
| 2cd90562 | Grafı siz tanımlarsınız. Her mesaj grafa göre kontrol edilir; grafın dışında kalan her şey düşürülür. | Grafı siz tanımlarsınız. Her mesajın bu grafa uyup uymadığı kontrol edilir; uymayan her şey düşürülür. | You define the graph. Every message is checked for whether it fits this graph; anything that doesn't is dropped. | "Grafa göre kontrol edilir" is a calque of *checked against*. |
| 169c0a3b | Artık çizimler hep aynı sürüyü gösteriyor: … | Bundan sonraki çizimler hep aynı sürüyü gösteriyor: müşterilere Telegram’da yanıt veren bir destek ekibi. | The drawings from here on all show the same swarm: a support team that answers customers on Telegram. | "Artık" also means "anymore", so the line could read as "the drawings now/no longer…". "Bundan sonraki" says *from here on*. |
| f294f1c2 | Paketler imzalı bir kayda göre doğrulanır. | Paketler imzalı bir kayıt üzerinden doğrulanır. | Packages are verified through a signed log. | "Kayda göre doğrulanır" is a calque of *verified against*. |
| c2593f94 | Her mesaj, çökme ve yeniden başlatma, canlı. | Her mesaj, çökme ve yeniden başlatma canlı olarak akar. | Every message, crash and restart streams live. | An English-style nominal chain with a trailing adjective; the verb "akar" ties it to "olay akışı". |

Checked and kept: the step headlines ("Her ajan bir süreçtir.", "Sürü bir belgedir.", "Her şey model gerektirmez.", "Ajanlarınıza gerekeni kurun.", "Bunu bir işletim sistemi gibi düşünün." ("bunu bir … gibi düşünün" is ordinary explanatory Turkish), the first two triad lines (OSV focus order), the nav and buttons ("Belgeleri okuyun", "GitHub’da inceleyin"), "organizasyon" (standard in Turkish B2B; switching to Microsoft's "kuruluş" would touch the canvas and six other strings for no gain), "geri gelir" (the canvas and 1024 readout budgets rule out "geri yüklenir"), the comparison cells (sourced), and the guarantees and limits.

Validation: private temp build clean; H1, story steps 2/3/5/9, close, guarantees, spec sheet and footer looked at 1440×900, 1024×768 and 390×844 after the drawing settled; no horizontal scroll; `AUDIT_LANGS=tr i18n-audit.cjs`: ok (tr × 18 sizes).
