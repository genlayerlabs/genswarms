---------------------------- MODULE SwarmDaemon ----------------------------
(***************************************************************************)
(* The daemon / SQLite registry / task queue protocol for ONE swarm name.  *)
(*                                                                         *)
(* Fixed = FALSE models the code as it is today:                           *)
(*   - `start` never reads the registry; the daemon registers itself with  *)
(*     INSERT OR REPLACE once it has booted (lib/mix/tasks/genswarms.ex).  *)
(*   - the poller delivers a pending task, then marks it processed, with   *)
(*     no claim step (process_pending_tasks/1).                            *)
(*   - a task for an agent that does not exist is dropped with an error    *)
(*     event (it used to exit the daemon).                                 *)
(*   - status writes match the row by name only (mark_stopped/1,           *)
(*     mark_crashed/1 in lib/genswarms/cli/swarm_registry.ex).             *)
(*                                                                         *)
(* Fixed = TRUE models a proposed design:                                  *)
(*   - a per-swarm lock held for the life of the process (e.g. flock), so  *)
(*     a second start is refused while any earlier daemon is still alive.  *)
(*   - a task is claimed (pending -> claimed) in the same statement that   *)
(*     selects it, then delivered, then marked processed.                  *)
(*   - a task that cannot be delivered is marked failed.                   *)
(*   - on start, tasks left claimed by a dead daemon are marked failed     *)
(*     (at-most-once: reported, never silently redelivered).               *)
(*   - a dying daemon only writes status to a row that carries its own pid.*)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS Daemons,   \* OS processes that may ever run this swarm
          Tasks,     \* task ids
          BadTasks,  \* tasks addressed to an agent that does not exist
          Fixed,     \* FALSE = current code, TRUE = proposed design
          MaxFaults, \* how many crashes + stops the environment may inject
          None

ASSUME BadTasks \subseteq Tasks /\ Fixed \in BOOLEAN /\ MaxFaults \in Nat

VARIABLES proc,      \* OS state of each daemon
          phase,     \* where each daemon's poller is: idle / claimed / sent
          hold,      \* the task that poller is working on
          row,       \* the swarm's row in the registry
          task,      \* state of each task row
          delivered, \* how many times each task reached an agent (capped at 2)
          faults     \* crashes + stops injected so far

vars == <<proc, phase, hold, row, task, delivered, faults>>

Live(d) == proc[d] \in {"booting", "running", "stopping"}

TypeOK ==
  /\ proc \in [Daemons -> {"none", "booting", "running", "stopping", "dead"}]
  /\ phase \in [Daemons -> {"idle", "claimed", "sent"}]
  /\ hold \in [Daemons -> Tasks \cup {None}]
  /\ row \in [status : {"absent", "running", "stopped", "crashed"},
              pid : Daemons \cup {None}]
  /\ task \in [Tasks -> {"unqueued", "pending", "claimed", "processed", "failed", "deleted"}]
  /\ delivered \in [Tasks -> 0..2]
  /\ faults \in 0..MaxFaults

Init ==
  /\ proc = [d \in Daemons |-> "none"]
  /\ phase = [d \in Daemons |-> "idle"]
  /\ hold = [d \in Daemons |-> None]
  /\ row = [status |-> "absent", pid |-> None]
  /\ task = [t \in Tasks |-> "unqueued"]
  /\ delivered = [t \in Tasks |-> 0]
  /\ faults = 0

Reset(d) ==
  /\ phase' = [phase EXCEPT ![d] = "idle"]
  /\ hold' = [hold EXCEPT ![d] = None]

(* `genswarms start`. *)
Start(d) ==
  /\ proc[d] \in {"none", "dead"}
  /\ IF Fixed
       THEN /\ \A e \in Daemons : ~Live(e)
            /\ row' = [status |-> "running", pid |-> d]
            /\ task' = [t \in Tasks |-> IF task[t] = "claimed" THEN "failed" ELSE task[t]]
       ELSE UNCHANGED <<row, task>>
  /\ proc' = [proc EXCEPT ![d] = "booting"]
  /\ Reset(d)
  /\ UNCHANGED <<delivered, faults>>

(* The swarm has booted; today this is when the row is written. *)
Register(d) ==
  /\ proc[d] = "booting"
  /\ proc' = [proc EXCEPT ![d] = "running"]
  /\ row' = IF Fixed THEN row ELSE [status |-> "running", pid |-> d]
  /\ UNCHANGED <<phase, hold, task, delivered, faults>>

(* API or CLI queues a task. *)
Queue(t) ==
  /\ task[t] = "unqueued"
  /\ task' = [task EXCEPT ![t] = "pending"]
  /\ UNCHANGED <<proc, phase, hold, row, delivered, faults>>

Bump(t) == [delivered EXCEPT ![t] = IF @ < 2 THEN @ + 1 ELSE @]

(* Today: read pending, deliver. A task for an undeclared agent is marked  *)
(* processed with an error event and the daemon keeps polling (modelled as *)
(* "failed"). Before that fix it exited the daemon on every restart.       *)
Deliver(d, t) ==
  /\ ~Fixed
  /\ proc[d] = "running" /\ phase[d] = "idle" /\ task[t] = "pending"
  /\ IF t \in BadTasks
       THEN /\ task' = [task EXCEPT ![t] = "failed"]
            /\ UNCHANGED <<phase, hold, delivered>>
       ELSE /\ delivered' = Bump(t)
            /\ phase' = [phase EXCEPT ![d] = "sent"]
            /\ hold' = [hold EXCEPT ![d] = t]
            /\ UNCHANGED task
  /\ UNCHANGED <<proc, row, faults>>

(* Proposed: claim first; a bad task is marked failed. *)
Claim(d, t) ==
  /\ Fixed
  /\ proc[d] = "running" /\ phase[d] = "idle" /\ task[t] = "pending"
  /\ IF t \in BadTasks
       THEN /\ task' = [task EXCEPT ![t] = "failed"]
            /\ UNCHANGED <<phase, hold>>
       ELSE /\ task' = [task EXCEPT ![t] = "claimed"]
            /\ phase' = [phase EXCEPT ![d] = "claimed"]
            /\ hold' = [hold EXCEPT ![d] = t]
  /\ UNCHANGED <<proc, row, delivered, faults>>

Send(d) ==
  /\ Fixed
  /\ proc[d] = "running" /\ phase[d] = "claimed"
  /\ delivered' = Bump(hold[d])
  /\ phase' = [phase EXCEPT ![d] = "sent"]
  /\ UNCHANGED <<proc, hold, row, task, faults>>

Mark(d) ==
  /\ proc[d] = "running" /\ phase[d] = "sent"
  /\ task' = [task EXCEPT ![hold[d]] = IF @ = "deleted" THEN @ ELSE "processed"]
  /\ Reset(d)
  /\ UNCHANGED <<proc, row, delivered, faults>>

(* kill -9, OOM, power loss: no cleanup runs. *)
Crash(d) ==
  /\ faults < MaxFaults
  /\ proc[d] \in {"booting", "running"}
  /\ proc' = [proc EXCEPT ![d] = "dead"]
  /\ Reset(d)
  /\ faults' = faults + 1
  /\ UNCHANGED <<row, task, delivered>>

(* `genswarms stop`: TERM the recorded pid, wait a bounded time, mark stopped. *)
StopCLI ==
  /\ faults < MaxFaults
  /\ row.status = "running" /\ row.pid # None
  /\ proc' = [proc EXCEPT ![row.pid] =
                IF @ \in {"booting", "running"} THEN "stopping" ELSE @]
  /\ row' = [status |-> "stopped", pid |-> None]
  /\ faults' = faults + 1
  /\ UNCHANGED <<phase, hold, task, delivered>>

(* A daemon that got TERM finally exits. *)
Exit(d) ==
  /\ proc[d] = "stopping"
  /\ proc' = [proc EXCEPT ![d] = "dead"]
  /\ Reset(d)
  /\ UNCHANGED <<row, task, delivered, faults>>

(* Today a shutting-down daemon may still run mark_crashed(name), which   *)
(* matches by name only. ASSUMPTION: read from the code, not observed.    *)
(* The proposed design guards the write by pid, which makes it a no-op.   *)
LateCrashWrite(d) ==
  /\ ~Fixed
  /\ proc[d] = "stopping" /\ row.status # "absent"
  /\ row' = [row EXCEPT !.status = "crashed"]
  /\ UNCHANGED <<proc, phase, hold, task, delivered, faults>>

(* cleanup_stale/0: a running row whose pid is gone becomes crashed. *)
CleanupStale ==
  /\ row.status = "running" /\ row.pid # None /\ ~Live(row.pid)
  /\ row' = [row EXCEPT !.status = "crashed"]
  /\ UNCHANGED <<proc, phase, hold, task, delivered, faults>>

(* `clean`: delete a stopped/crashed row together with its queued tasks. *)
Clean ==
  /\ row.status \in {"stopped", "crashed"}
  /\ row' = [status |-> "absent", pid |-> None]
  /\ task' = [t \in Tasks |-> IF task[t] \in {"pending", "claimed"} THEN "deleted" ELSE task[t]]
  /\ UNCHANGED <<proc, phase, hold, delivered, faults>>

DaemonStep ==
  \E d \in Daemons :
    \/ Register(d) \/ Send(d) \/ Mark(d) \/ Exit(d)
    \/ \E t \in Tasks : Deliver(d, t) \/ Claim(d, t)

Next ==
  \/ DaemonStep
  \/ \E d \in Daemons : Start(d) \/ Crash(d) \/ LateCrashWrite(d)
  \/ \E t \in Tasks : Queue(t)
  \/ StopCLI \/ CleanupStale \/ Clean

(* Liveness assumes someone keeps restarting the swarm, a running daemon  *)
(* keeps polling, and the environment injects at most MaxFaults crashes   *)
(* and stops (otherwise it could kill every daemon before it boots).      *)
Fairness ==
  /\ SF_vars(\E d \in Daemons : Start(d))
  /\ \A d \in Daemons :
       /\ WF_vars(Register(d)) /\ WF_vars(Exit(d))
       /\ SF_vars(Send(d)) /\ SF_vars(Mark(d))
  /\ \A t \in Tasks :
       SF_vars(\E d \in Daemons : Deliver(d, t) \/ Claim(d, t))

Spec == Init /\ [][Next]_vars /\ Fairness

----------------------------------------------------------------------------
(* What the engine should guarantee. *)

OneLiveDaemon == Cardinality({d \in Daemons : proc[d] = "running"}) <= 1

AtMostOnce == \A t \in Tasks : delivered[t] <= 1

(* A running daemon is the one the registry points at, so stop can find   *)
(* it and clean can never delete a live swarm's row.                      *)
RowTracksDaemon ==
  \A d \in Daemons :
    proc[d] = "running" => (row.status = "running" /\ row.pid = d)

Resolved(t) == task[t] \in {"processed", "failed", "deleted"}

(* Every queued task ends up delivered, reported as failed, or cleaned.   *)
EveryTaskResolved == \A t \in Tasks : (task[t] = "pending") ~> Resolved(t)
=============================================================================
