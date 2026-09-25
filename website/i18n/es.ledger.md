# Concept ledger: GenSwarms landing page, Spanish (es)

Register: neutral international Spanish, tú for direct address, infinitive for buttons and links. This matches the GenLayer Labs homepage (`~/dev/genlayerlabscom-site/i18n/es.ledger.md`) and the SubZeroClaw page (`subzeroclaw` branch `site/i18n`, `i18n/es.ledger.md`). Everyday developer vocabulary, no selling adjectives, no calques.
Authorities: `README.md`, `docs/architecture.md`, `intermediate-representation.md`, `messaging.md`, `objects.md`, `security.md`, the approved copy deck `design/2026-09-25-copy-deck-v2.md`, and the translator concept notes. For vocabulary shared with them, the two sibling Spanish pages decide (enjambre, supervisor, entorno aislado, se cae, entorno de ejecución, skill, prompt, Docs, the suggestion bar strings).

## Objects

| Concept | Source term | What it is (source) | Must stay distinct from | Spanish | Avoid | Source passage |
|---|---|---|---|---|---|---|
| Operating system (analogy) | operating system | The computer-OS metaphor for the whole product | platform, framework | sistema operativo | "plataforma", "SO" | copy deck, story step 2 |
| AI workforce | AI workforces | The vision: many agents working as an organization's staff | a swarm, a team | la fuerza laboral de IA (singular, with the article) | "plantilla" (means *template* in LatAm and in tech), "personal de IA" (reads as *personal AI*), "equipos" (that is what a swarm is) | concept notes "AI workforce" |
| AI organization | your AI organization | The org whose staff are agents | | tu organización de IA | | step 9 headline |
| Agent | agent | LLM-backed worker, one process each | object, model | agente | | README |
| Object | object | Deterministic Elixir handler on the same graph | agent | objeto | "componente" | objects.md; architecture.md "execute deterministic Elixir instead of LLM calls" |
| Plain code | plain code | Code with no model, same result every time | | código convencional | "código simple" (reads as *easy code*), "código plano" | step 6 |
| Model | model | The LLM an agent uses | agent | modelo | | |
| Process | process | OTP process, one per agent | business process | proceso | "procedimiento" | architecture.md "Supervision tree" |
| Sandbox | sandbox | Per-agent isolation (bwrap, Docker, Apple container) | | entorno aislado (prose and the comparison cell); spec row label "Aislamiento" | "sandbox" in prose (the GenLayer Labs homepage already says "cada uno en su propio entorno aislado" about GenSwarms) | security.md; genlayerlabs es.json ddb88e97 |
| Boundary (figure 4) | its boundary | The sandbox edge drawn around each agent | limit, quota | su perímetro | "límite" (reads as a quota or cap, which collides with the 100-agent cap) | figure 4 |
| Supervisor | supervisor | OTP software that restarts a crashed process, not a person | a manager | supervisor | "jefe", "gestor" | architecture.md; GenLayer Labs ledger |
| Crash / crashed | crash, crashes | A process dying | failure in general | caída (noun), se cae (verb), caído (figure status) | "colapso", "falla" for the crash itself | GenLayer Labs es.json 82366a65 "cuando uno se cae" |
| Fail | when they fail / when one fails | General failure that leads to restart | crash | fallar | | step 2, step 3 |
| Restart | restart | The supervisor starting it again | | reiniciar / reinicio | "relanzar" | |
| Declared path | declared paths | Directed edges declared in the swarm topology; the only way messages move | workflow, pipeline | rutas declaradas | "caminos", "flujos" | messaging.md "How topology gates routing" |
| The graph | the graph | The declared topology as drawn | chart | el grafo | "el gráfico" (= chart) | step 5 |
| Checked | checked against it / checked each hop | Router validates each hop against the adjacency map | verified (packages) | se contrasta con él; comprobados en cada salto | "verificar" (reserved for packages) | messaging.md "validates every hop" |
| Dropped | dropped | Off-graph message discarded (`invalid_route`) | lost, deleted | se descarta / descartado | "perdido", "borrado", "eliminado" | messaging.md "the message is dropped" |
| Message | message | What agents send each other | notification | mensaje | | |
| Swarm | swarm | Running set of agents, objects and topology | team (plain word) | enjambre | | GenLayer Labs and SubZeroClaw ledgers |
| Team (plain) | a support team, one team | A swarm with a purpose, in everyday words | | equipo | | step 5 example, close |
| Package | package | Signed, content-addressed unit from swarmidx | app, plugin | paquete | "plugin", "extensión" | swarmidx "a notary for GenSwarms packages" |
| Signed | signed | Ed25519 signature | certified | firmado | "certificado" | |
| Verified | verified | Checked on your machine against the transparency log | approved | verificado; "se verifican contra un registro firmado" | "aprobado", "validado" | |
| Index | swarmidx index | Package index / notary | store, marketplace | el índice swarmidx | "tienda", "marketplace" | |
| Content-addressed | content-addressed | Identified by digest | | direccionados por contenido | | IR doc "content-addressable" |
| Connector | connectors | Telegram, WhatsApp, email objects | | conectores | | step 7 |
| Gateway | a Telegram gateway | The object messages come in through and replies go out | payment gateway | pasarela de Telegram | "puerta de enlace" (network router sense, and long) | step 6 |
| Scheduler | scheduler (cron) | Deterministic timed messages | calendar | planificador | "programador" (= programmer) | objects.md |
| Budget | a budget for model spend | Object that caps LLM spending | company budget | un presupuesto para el gasto en modelos; "presupuestos de gasto" | | step 6, Not yet |
| A swarm is a document | a document | The definition is data: seed plus change log | paper document, file | Un enjambre es un documento. | "archivo" | intermediate-representation.md |
| Seed | seed | The starting `swarm.state` | | semilla (also in the figure and the restore line) | "estado inicial" (loses the identity with the IR term) | IR "folding overlays onto a seed state" |
| Change log | change log, log of changes | `swarm.overlay`, ordered mutation events | release notes | registro de cambios; "queda registrado" | "historial de versiones" | IR "an ordered log of mutation events" |
| Bad change / refused | a bad change is refused | Gate rejects an invalid change before it runs | denied by a person | cambio no válido; se rechaza / rechazado | "denegado" (sounds like a permission decision by someone), "cambio malo" | IR, security.md "invalid config is refused at start" |
| Restore | comes back from its database; restore | `restore_swarm` rebuilds seed + replayed changes from SQLite | backup by a person | se restaura desde su base de datos; restauración; "restaurar:" in the figure | "copia de seguridad" | IR "restores that seed and replays" |
| Control layer | control layer | GenSwarms as the layer above swarms and models | management layer | capa de control | "capa de gestión" | step 9 |
| Event stream / live | live event stream, live | Feed of every message, crash, restart | news feed | flujo de eventos en tiempo real; "en tiempo real" | | README |
| Runtime | a runtime | Program that runs agents | "at runtime" | entorno de ejecución | "runtime", "tiempo de ejecución" | SubZeroClaw ledger |
| Coding agent | your coding agent | Claude Code, Codex, etc. | | tu agente de programación | "agente de código" | |
| Hand it to | hand it to your (coding) agent | Delegate setup/driving to an agent | | encárgaselo a tu agente (de programación) | "pásaselo" | step 9, close |
| Skill file | a skill file | `skill.md` | ability | un archivo de skill | "habilidad" | SubZeroClaw ledger |
| Drivers | Drivers | Backend drivers (Local, Tmux, Docker…) | Control row | Drivers (kept) | "Controladores" (collides with the "Control" row right below it) | spec sheet |
| Endpoint | model endpoint | The model API address | | endpoint de su modelo | "punto final" | |

## Texture words

| Word | Spanish | Rationale |
|---|---|---|
| operating system | sistema operativo | The computer term. Every reader hears the OS, so the metaphor works with no gloss. |
| workforce | fuerza laboral | The phrase Spanish AI marketing already uses for agents as staff ("fuerza laboral digital"). It has a slight labour-statistics echo, but "plantilla" means *template* to half the readers and in tech. See doubts. |
| runs (the organization) | hace funcionar | Operating, not managing. "dirige" and "gestiona" sound like a human manager, which the notes rule out. "opera" would echo "operativo" but can read as surgery. |
| runs (agents, programs) | ejecuta / se ejecuta | Standard for software. "corre" is a calque (Fundéu). |
| provide intelligence / perform work | aportan la inteligencia / hacen el trabajo | Three beats, each subject + verb + article + noun: *Los modelos aportan la inteligencia. Los agentes hacen el trabajo. GenSwarms hace funcionar la organización.* Measured: none of the natural versions fit one line at the triad size; each takes two lines, like the English third line, and the block ends above the rail at 1440×900. |
| plain code / the same thing every time | código convencional / Siempre hacen lo mismo. | Deterministic and unglamorous. |
| declared | declaradas | You state them up front in config. |
| talk (agents talk) | hablan | Keeps the plain English verb; "se comunican" is flatter. |
| Think of it as | Piénsalo como | Natural and short. |
| One control layer | Una sola capa de control | "Una capa" alone reads as the indefinite article; "sola" keeps *one*. |
| In use today | Ya se usa en | "Ya" carries *today, already*, without claiming more. |
| no live swap | aún no hay sustitución en caliente | "en caliente" is the standard Spanish term for hot swap. |

## Conventions

- Tú and imperatives in the body copy (Despliega, Instala, Observa, Empieza). Infinitives for buttons and links (Leer la documentación, Ver en GitHub, Copiar, Volver al inicio, Leer).
- Headlines end in a full stop wherever the English does. The spec sheet and the guarantee lists stay lowercase fragments, as in English.
- The hero keeps the `&nbsp;` before the last word: "de&nbsp;IA", so "IA." is never left alone on a line.
- Identifiers stay English inside the Spanish sentences (telegram, triage, research, answer, cron, budget, browser, swarm.state…). The aria-label for figure 5 says "los agentes triage, research y answer", which treats them as names.
- CrewAI's own product nouns, "crews" and "flows", stay in lowercase English. Their docs use them as names, and the sourced cells must keep the facts exact.
- Meta description: 149/150. "a live event stream" became "eventos en vivo" there only (because of the limit). The rest of the page says "en tiempo real".

## Strings identical to English (`_same_as_english`)

| id | text | why |
|---|---|---|
| 0f4d09e4 | supervisor | The Spanish word is the same, and both sibling pages use it. |
| 9c7e05e5 | prompt | Spanish developer usage, as on the SubZeroClaw and GenLayer Labs pages. |
| 68a41942 | Docs | Nav slot on phones. Same decision as the SubZeroClaw page. |
| a40ad45b | Drivers | "Controladores" would sit right next to the "Control" row. "drivers" is common in Spanish. |
| ea1d3df2 | Control | The same word in Spanish. |
| 157fc042 | Error 404 | The same in Spanish. |

## SVG labels against their width hints

Every label renders inside its space at 1440×900 and 390×844. `i18n-audit.cjs` (es × 14 sizes) passes.
- ad3f9aa5 "descartado" is 10 characters against a hint of 8. It is one word and can't wrap. It sits cleanly between the edge and the ✕ on desktop and above the ✕ on phones. The fallback, if it ever collides, is "se descarta", which wraps to two lines of at most 8.
- 712fd4b9 "cada agente se ejecuta como un proceso" takes 3 lines, the maximum (English takes 2). 526fff18 and 5fc8b818 take 2 lines each, within budget.
- 2caa6242 "sistema operativo" is exactly 17/17 and fits the dark band.

## Doubts for a native reviewer

1. "fuerza laboral de IA" for *AI workforces* (title, h1, footer, JSON-LD). Alternatives: "trabajadores de IA" (plainer, loses the collective sense) and "plantilla" (Spain only, and *template* elsewhere).
2. The kicker verb "hace funcionar la organización" (vs "opera", "dirige"), and the echo of "hacen" in the line above.
3. "código convencional" for *plain code*, and "pasarela de Telegram" for *gateway* (Spain leans on "pasarela"; LatAm readers may prefer "puerta de enlace").
4. "semilla" for *seed*. It is correct for the IR, but a cold reader may need the figure to get it.

## Editor pass

Native editor, second pass (playbook §8.6). Read cold at 1440×900 and 390×844 before comparing with the English. Private temp build is clean ("en, es: built"), and `AUDIT_LANGS=es i18n-audit.cjs` passes (1 language × 14 sizes). No string got longer on screen: the triad changes only add `&nbsp;`, and every other change is the same length or shorter. Where this section differs from the tables above, this section wins.

### Flagship verdicts

| Term | Verdict |
|---|---|
| operating system | **sistema operativo**, kept. The computer term, so the metaphor lands without a gloss. |
| AI workforce | **la fuerza laboral de IA**, kept. It is the established collective noun in Spanish AI copy ("fuerza laboral digital"). The statistical echo is weak next to "sistema operativo". "Plantilla" means *template* in LatAm and in tech, and "trabajadores de IA" loses the collective sense. |
| supervisor | **supervisor**, kept. Same word on both sibling pages. The OTP software is clear from the figure and from "Si uno se cae, se reinicia". |
| runs the organization | **hace funcionar la organización**, kept. "Hacer funcionar" is what you say about a machine, so it fits the OS image. "Dirige" and "gestiona" sound like a human manager. "Opera" can read as surgery. |
| three-beat kicker | Words kept. Every line now breaks at the same point on desktop (`verbo / la inteligencia.`, `hacen / el trabajo.`, `funcionar / la organización.`), so the three beats read as parallel and no article hangs at a line end. The "hacen / hace" echo reads as deliberate parallelism. |
| swarm | **enjambre**, kept. Matches the product name and both sibling pages. |

Other doubts from the translator: **código convencional** is kept, since "software convencional" is the standard Spanish contrast with AI. **pasarela de Telegram** is kept, the same usage as "pasarela de pago" on both sides of the Atlantic. **semilla** is kept: it is the IR term, and the figure labels it right next to `swarm.state`.

### Changes

| id | before | after | reason |
|---|---|---|---|
| 84d5e16a | Un solo agente es fácil. … una forma de recuperarse cuando uno falla. | Con un solo agente es fácil. … una forma de recuperarse si uno falla. | "Un solo agente es fácil" is a calque. "Si" pays back the four added characters. |
| 2cd90562 | Cada mensaje se contrasta con él, y todo lo que queda fuera del grafo se descarta. | Cada mensaje se comprueba contra él y lo que se salga del grafo se descarta. | "Contrastar" is academic register. "Comprobar" matches the spec row ("comprobados en cada salto"). The subjunctive "se salga" carries the English "anything". Shorter. |
| a0b063e5 | Los modelos aportan la inteligencia. | Los modelos aportan la&nbsp;inteligencia. | Parallel line break for the triad. The dangling "la" is gone. |
| a34eb019 | Los agentes hacen el trabajo. | Los agentes hacen el&nbsp;trabajo. | Same break as the other two lines. It still fits on one line on phones. |
| 86d0513d | GenSwarms hace funcionar la organización. | GenSwarms hace funcionar la&nbsp;organización. | Keeps the article with its noun if the width changes. |
| a895f8a4 | …se rechaza antes de ejecutarse… | …se rechaza antes de aplicarse… | In Spanish a change *se aplica*; it isn't *ejecutado*. Same meaning ("before it takes effect"). Shorter. |
| b1ae0f2b | …se rechazan antes de ejecutarse | …se rechazan antes de aplicarse | Same term as step 8. It also fits configurations, which aren't executed either. |
| 179a3c0f | Al agente que se cayó. Su supervisor lo reinicia | Al agente caído. Su supervisor lo reinicia | Uses the ledger term "caído" (as in figure 4). Drops the preterite. Shorter in a narrow column. |
| a0b3f246 | Se encarga tu código; el estado del equipo puede guardarse y volver a cargarse | Lo gestiona tu código; el estado del equipo puede guardarse y recargarse | "Se encarga tu código" lacks its complement ("de ello"). "Recargarse" is shorter. |
| fa899489 | …y comprobados en tu máquina | …y verificados en tu máquina | This is the package check, so it gets the reserved term "verificado" (step 7, figure 7, guarantees). |
| 163d4e0f | los presupuestos de gasto llegan como paquete, no en el núcleo | los presupuestos de gasto vienen como paquete, no en el núcleo | Under "Todavía no", "llegan" reads as a promise that they will arrive. "Vienen" states how they ship today. |
| 57573a62 | …o se extravió fuera de la topología. | …o se salió de la topología. | "Extraviarse fuera" is redundant. Shorter and more playful. |

Checked and left as they are: the h1 and its break ("fuerza / laboral de IA."), "Instala lo que necesitan tus agentes." (3 lines on desktop with "tus agentes" together, 2 on phones; "lo que tus agentes necesitan" is less natural), "Contrólalo por API o CLI" (the neuter *lo* covers "all of this"), "Leer" in the suggestion bar (the SubZeroClaw precedent), "descartado" (10/8, renders cleanly).
