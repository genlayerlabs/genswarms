# Comparison sources (accessed 2026-09-25)

Sources for the "A runtime, not a library" table on genswarms.com (`website/src/content.mjs`, `CMP`).
Every competitor cell was checked against that project's official docs or repository on 2026-09-25. The cells
stay neutral. Where a project has a hosted or deployment product, the cell names it. Where a project has some form of
retry, persistence or recovery, the cell names that too.

| Project | Row | Cell text | Source |
|---|---|---|---|
| LangGraph | What it is | Orchestration framework and runtime for stateful agents; LangSmith Deployment hosts them | https://docs.langchain.com/oss/python/langgraph/overview ("a low-level orchestration framework and runtime for building, managing, and deploying long-running, stateful agents"); https://docs.langchain.com/langsmith/deployment |
| LangGraph | Where agents run | In your Python or JS process, or on LangSmith Deployment servers | https://docs.langchain.com/oss/python/langgraph/graph-api (graphs are compiled and run with `invoke()` / `stream()` from your code); https://docs.langchain.com/langsmith/deployment (Cloud, hybrid, self-hosted Kubernetes and standalone Agent Servers) |
| LangGraph | What a crash affects | The run; checkpoints let it resume, and nodes can retry | https://docs.langchain.com/oss/python/langgraph/checkpointers ("if one or more nodes fail at a given superstep, you can restart your graph from the last successful step"); https://docs.langchain.com/oss/python/langgraph/fault-tolerance (`RetryPolicy`, resume with the same `thread_id`); https://docs.langchain.com/langsmith/scalability-and-resilience (on a server crash, a sweeper re-queues in-progress runs) |
| LangGraph | Control surface | Python/JS API; Agent Server REST API and streaming when deployed | https://docs.langchain.com/oss/python/langgraph/graph-api; https://docs.langchain.com/langsmith/agent-server (assistants, threads, runs, cron jobs; `/stream`) |
| CrewAI | What it is | Open-source framework for agent crews and flows; AMP deploys them | https://docs.crewai.com/en/introduction ("the leading open-source framework for orchestrating autonomous AI agents"; Crews and Flows); https://docs-platform.crewai.com/platform/en/introduction (CrewAI AMP: "Deploy, monitor, and scale your AI agent workflows") |
| CrewAI | Where agents run | In your Python process, or on CrewAI AMP managed infrastructure | https://docs.crewai.com/en/concepts/flows (`kickoff()` / `kickoff_async()` from Python); https://docs-platform.crewai.com/platform/en/introduction ("Deploy your crews to a managed infrastructure") |
| CrewAI | What a crash affects | The run; agents retry errors, and flows can persist and resume | https://docs.crewai.com/en/concepts/agents (`max_retry_limit`: "Maximum number of retries when an error occurs. Default is 2."); https://docs.crewai.com/en/concepts/flows (`@persist` "across restarts"; resume with `kickoff(inputs={"id": ...})`) |
| CrewAI | Control surface | Python API; AMP adds a REST API, traces and logs | https://docs.crewai.com/en/api-reference/introduction (`/inputs`, `/kickoff`, `/status/{kickoff_id}`); https://docs-platform.crewai.com/platform/en/introduction ("detailed execution traces and logs"; "Access your deployed crews via REST API") |
| AutoGen | What it is | Multi-agent framework, now in maintenance mode; Microsoft Agent Framework succeeds it | https://github.com/microsoft/autogen/blob/main/README.md ("AutoGen is now in maintenance mode… New users should start with Microsoft Agent Framework."); https://microsoft.github.io/autogen/stable/ |
| AutoGen | Where agents run | In your process, or across workers via its experimental distributed runtime | https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/framework/agent-and-agent-runtime.html (`SingleThreadedAgentRuntime`); https://microsoft.github.io/autogen/stable/user-guide/core-user-guide/framework/distributed-agent-runtime.html (host service + gRPC worker runtimes; "an experimental feature") |
| AutoGen | What a crash affects | Your code handles it; team state can be saved and reloaded | https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/state.html (`save_state()` / `load_state()` for agents and teams, persisted to a file or database); the runtime docs above document no automatic restart of a failed agent |
| AutoGen | Control surface | Python and .NET APIs; AutoGen Studio GUI for prototyping | https://github.com/microsoft/autogen/blob/main/README.md (Python and .NET; AutoGen Studio is a "no-code GUI" that "is not meant to be a production-ready app") |

## GenSwarms column

These cells restate spec §4.2 and §4.3 (`design/2026-09-25-landing-page-design.md`) and add nothing new:

| Row | Cell text | Spec basis |
|---|---|---|
| What it is | A runtime that runs each agent as a supervised process | §4.2 Processes |
| Where agents run | Each in its own supervised process: local, sandbox, container or SSH | §4.2 Processes, Isolation, Drivers |
| What a crash affects | The agent that crashed. Its supervisor restarts it | §4.2 Recovery; §4.3 first guarantee |
| Control surface | REST API, WebSocket event stream, CLI | §4.2 Control, Observability |

## Notes

- No row needed the neutral fallback ("Depends on how you deploy it"): every row could be stated briefly and fairly
  for all three projects.
- LangGraph describes itself as "framework and runtime", and LangSmith Deployment re-queues runs after a server crash.
  The cell says so, even though it softens the section heading "A runtime, not a library". The difference that remains
  is scope: those runtimes recover a run (a graph execution). GenSwarms supervises each agent as its own process.
- AutoGen's maintenance-mode status comes from its own README. It is stated as fact, without judgement. If the page
  later compares against Microsoft Agent Framework instead, that column needs its own sources.
- Re-check every cell before each major site update. All four projects change quickly.
