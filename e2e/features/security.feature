@todo
Feature: Security & auth — the fail-closed surface
  Every scenario asserts what must NOT happen: a regression here is a breach,
  not a bug. API auth, config gating, package integrity, secret handling.
  Steps UNIMPLEMENTED — the written contract. See e2e/TEST-PLAN.md §4.

  Scenario: with no token the API is loopback-only
    Given an engine started without an API token
    When a remote caller hits a control-plane route
    Then it is refused (loopback is the only gate)

  Scenario: control-plane routes require the full token
    Given an engine with a full API token
    When a request carries a wrong or absent token
    Then it is rejected with 401 (constant-time compared)

  Scenario: a config-scoped token cannot touch the control plane
    Given a config-scoped token
    Then it may patch an object config but NOT create or delete a swarm

  Scenario: config patch accepts only x-mutable keys
    When an immutable key is patched
    Then it is rejected 422 immutable_keys

  Scenario: config patch on a schemaless object is refused entirely
    Given an object with no config_schema
    When any key is patched
    Then it is rejected 422 no_config_schema

  Scenario: host-escape keys can never be patched
    When subzeroclaw_path or an extra_* key is patched
    Then it is rejected 422 forbidden_keys, even if the schema listed it

  Scenario: an oversized patch is refused (atom-table backstop)
    When a patch carries more than 200 nested keys
    Then it is rejected 422 patch_too_large

  Scenario: the package loader refuses a digest mismatch
    Given a vendored handler whose bytes do not match the pinned digest
    Then the swarm fails to start and the handler is never bound

  Scenario: the package loader refuses unsafe entry files
    Given a swarm-object.json whose files list contains a traversal path
    Then it is rejected as unsafe_entry_files

  Scenario: secrets are redacted in the snapshot
    Given a running swarm with an api_key in an agent config
    When the snapshot is rendered
    Then the key reads [REDACTED] and appears nowhere in cleartext

  Scenario: the API key is withheld from an untrusted endpoint
    Given an agent pointed at a non-allowlisted endpoint
    Then it receives a nil api_key (SSRF / exfiltration guard)

  Scenario: cron and object allowlists are fail-closed
    Given a cron with empty trusted_sources and allowed_targets
    Then nobody can create jobs and nothing is deliverable

  Scenario: the agent cap rejects the over-limit add
    Given a swarm at its max agent count
    When one more agent is added
    Then it is rejected agent_cap_exceeded before any overlay write
