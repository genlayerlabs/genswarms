Feature: Routing economics — policies and metering over a real agent
  Agents route through the unhardcoded router by Σ_pol, never a named model.
  A real free-first agent takes a turn; we assert from subzeroclaw's local
  USAGE meter that a model was chosen and priced as expected.

  Scenario: a free-first policy routes to a zero-cost provider and completes
    Given a free-first economist agent
    When it takes a turn
    Then a model was chosen and the turn was metered at zero cost
