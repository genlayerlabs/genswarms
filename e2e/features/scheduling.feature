@todo
Feature: Scheduling — cron seed jobs and timers
  The Genswarms.Cron object drives time-based delivery. None of this is
  covered by a real e2e today. Steps are UNIMPLEMENTED — this file is the
  written contract of what a scheduling e2e must prove.

  Scenario: a seed job fires on boot and delivers to its allowlisted target
    Given a swarm with a cron object carrying a seed job every minute to an object
    When the swarm has run for just over one minute
    Then the target object has received exactly one scheduled message
    And the cron job_run event is recorded

  Scenario: cron refuses a target that is not allowlisted (fail-closed)
    Given a cron object whose allowed_targets does NOT include "victim"
    When a create_job for "victim" is attempted
    Then the job is rejected and nothing is delivered to "victim"

  Scenario: a due job that crashes is retried up to max_attempts then fails
    Given a cron job whose delivery raises
    When it becomes due
    Then it is retried with backoff and finally marked failed, never silently dropped

  Scenario: overlapping ticks never double-launch the same job
    Given a job already running
    When a second tick fires before it finishes
    Then the job is not launched twice
