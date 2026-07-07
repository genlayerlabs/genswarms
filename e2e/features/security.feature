Feature: Security & auth — the fail-closed surface
  Every scenario asserts what must NOT happen. Deterministic, no LLM: driven
  against the real REST surface + the auth/loader/endpoint-policy code paths.
  (Digest-mismatch #4.8 and the agent cap need extra fixtures — tracked in
  TEST-PLAN §4, land in a later pass.)

  Scenario: an unauthenticated control-plane request is refused
    When the swarm list is requested with no token
    Then it is rejected 401

  Scenario: the full token is accepted on the control plane
    When the swarm list is requested with the full token
    Then it is accepted 200

  Scenario: a config-scoped token cannot reach the control plane
    When a swarm create is attempted with the config-scoped token
    Then it is rejected 401

  Scenario: a config-scoped token may patch an object config
    Given a running swarm with an echo object
    When its tag is patched with the config-scoped token
    Then it is accepted

  Scenario: patching an immutable key is refused
    Given a running swarm with an echo object
    When an immutable key is patched
    Then it is rejected 422

  Scenario: patching a schemaless object is refused entirely
    Given a running swarm with a schemaless counter object
    When any key is patched
    Then it is rejected 422 no schema

  Scenario: a host-escape key can never be patched
    Given a running swarm with an echo object
    When subzeroclaw_path is patched
    Then it is rejected 422

  Scenario: an oversized patch is refused
    Given a running swarm with an echo object
    When a patch with over 200 keys is applied
    Then it is refused as patch_too_large

  Scenario: secrets are redacted in the snapshot
    Given a running swarm whose agent config holds an api_key
    When the snapshot is rendered
    Then the api_key reads REDACTED and the secret is nowhere in the text

  Scenario: the package loader refuses unsafe entry files
    When a package entry file list contains a traversal path
    Then the loader rejects it as unsafe

  Scenario: the API key is withheld from a non-allowlisted endpoint
    When endpoint policy resolves an untrusted per-agent endpoint
    Then no API key is handed out
