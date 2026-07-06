@todo
Feature: Routing economics — policies, cache, metering
  Agents route through the unhardcoded router by Σ_pol, never a named model.
  engine_core proves cache hits; these prove the policy/metering surface the
  swarms depend on. Steps UNIMPLEMENTED — the written contract.

  Scenario: a free-first policy routes an agent to a $0 provider
    Given an agent with a cheapest-with-tools policy
    When it takes a turn
    Then its USAGE line shows a $0 model was chosen

  Scenario: a policy that names no model still selects and runs
    Given an agent whose request_extra carries only a policy_ir
    When it takes a turn
    Then a provider is chosen and the turn completes

  Scenario: per-session metering accumulates across an agent's turns
    Given an agent taking two turns in one session
    When both complete
    Then /v1/session shows the summed tokens and cost for that sid

  Scenario: a bare /v1 endpoint is rejected before it silently drops turns
    # the szc gotcha we hit repeatedly
    Given an agent endpoint of just the /v1 base
    Then the swarm config is refused (or the turn error is surfaced, never a silent empty)
