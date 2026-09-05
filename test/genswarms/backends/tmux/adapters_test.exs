defmodule Genswarms.Backends.Tmux.AdaptersTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.Tmux.Adapters.{Claude, Codex, OpenCode}
  alias Genswarms.Backends.Tmux.AdapterHelpers

  @base %{
    executable: "/bin/sh",
    workspace: "/tmp/tmux adapter workspace",
    swarm_name: "test-swarm",
    agent_name: "worker"
  }

  test "Codex builds argv directly and only enables bypass explicitly" do
    assert {:ok, launch} =
             Codex.launch(
               Map.merge(@base, %{
                 model: "gpt-test",
                 approval_policy: :on_request,
                 sandbox: :workspace_write,
                 args: ["--search"],
                 resume: true
               })
             )

    assert launch.executable == "/bin/sh"
    assert Enum.chunk_every(launch.args, 2, 1, :discard) |> Enum.member?(["-C", @base.workspace])
    assert "--ask-for-approval" in launch.args
    assert "on-request" in launch.args
    assert "--sandbox" in launch.args
    assert "workspace-write" in launch.args
    assert Enum.take(launch.args, -2) == ["resume", "--last"]
    refute "--dangerously-bypass-approvals-and-sandbox" in launch.args

    assert {:ok, dangerous} = Codex.launch(Map.put(@base, :dangerously_bypass, true))
    assert "--dangerously-bypass-approvals-and-sandbox" in dangerous.args
  end

  test "Claude and OpenCode expose their native resume forms" do
    assert {:ok, claude} =
             Claude.launch(
               Map.merge(@base, %{
                 permission_mode: :acceptEdits,
                 effort: :xhigh,
                 resume: "claude-session"
               })
             )

    assert Enum.take(claude.args, -2) == ["--resume", "claude-session"]
    assert "--ax-screen-reader" in claude.args
    refute "--dangerously-skip-permissions" in claude.args

    assert {:ok, opencode} =
             OpenCode.launch(Map.merge(@base, %{resume: true, auto_approve: false}))

    assert Enum.take(opencode.args, -1) == ["--continue"]
    refute "--auto" in opencode.args
  end

  test "invalid permission and argument values fail before tmux starts" do
    assert {:error, {:invalid_approval_policy, "untrusted"}} =
             Codex.launch(Map.put(@base, :approval_policy, :untrusted))

    assert {:error, {:invalid_approval_policy, "sometimes"}} =
             Codex.launch(Map.put(@base, :approval_policy, "sometimes"))

    assert {:error, {:invalid_tmux_args, _}} =
             Claude.launch(Map.put(@base, :args, ["valid", :not_an_argv_string]))

    assert {:error, {:invalid_resume, 42}} = OpenCode.launch(Map.put(@base, :resume, 42))
  end

  test "recognizes prompt glyphs even when a TUI renders footer text below them" do
    assert AdapterHelpers.prompt_visible?("output\n❯ \n  ? for shortcuts")
    assert AdapterHelpers.prompt_visible?("› Ask Codex to review this repo\n  model: gpt-test")
    refute AdapterHelpers.prompt_visible?("still working\nordinary output")
  end

  test "OpenCode recognizes its actual empty input plus mode footer" do
    screen =
      "OpenCode\nAsk anything... \"Fix a TODO in the codebase\"\n BUILD    Fixture · ctrl+p cmd\n"

    assert OpenCode.ready?(screen, %{})
    refute OpenCode.ready?("Ask anything... quoted output without the UI footer", %{})
    refute OpenCode.ready?("OpenCode\n BUILD    Fixture · ctrl+p cmd\n", %{})
    refute OpenCode.ready?("Generating...\n", %{})
  end

  test "Claude recognizes its native screen-reader prompt, not a bare shell" do
    screen = "[Screen Reader Mode: on via flag]\nClaude Code v2.1.260\n real-worker\n$\n\n"
    assert Claude.ready?(screen, %{})
    refute Claude.ready?("shell output\n$\n", %{})

    refute Claude.ready?(
             "[Screen Reader Mode: on via flag]\nClaude Code v2.1.260\nWorking...\n",
             %{}
           )
  end
end
