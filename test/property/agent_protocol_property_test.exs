defmodule Genswarms.Property.AgentProtocolPropertyTest do
  @moduledoc """
  Rule: whatever an agent prints, the parser neither crashes nor invents a
  target; a well-formed marker for a known name yields exactly that message.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Long runs (PROPERTY_RUNS) outlast the default 60s per test.
  @moduletag timeout: :infinity

  alias Genswarms.Agents.AgentProtocol

  @targets [:pp_alpha, :pp_beta, :pp_gamma]

  # Random text salted with marker fragments, so near-miss markers show up often.
  defp noisy_output do
    fragment =
      one_of([
        string(:printable, max_length: 20),
        binary(max_length: 8),
        member_of([
          "<<SWARM_MSG:TO=",
          "pp_alpha",
          "no_such_agent_zz9",
          ":START>>\n",
          "<<SWARM_MSG:END>>",
          "<<SWARM_MSG:BROADCAST:START>>\n",
          "../",
          "\n"
        ])
      ])

    map(list_of(fragment, max_length: 12), &Enum.join/1)
  end

  property "parse_output never crashes and only targets existing names" do
    check all(output <- noisy_output()) do
      assert [%{type: :output} | messages] = AgentProtocol.parse_output(output)

      for message <- messages do
        assert message.type in [:send, :broadcast]
        assert is_binary(message.content)
        # The target may be any name the VM already knows (the router then
        # checks for an edge). parse_send/1 uses String.to_existing_atom.
        if message.type == :send, do: assert(is_atom(message.to))
      end
    end
  end

  property "text without markers produces no messages" do
    check all(output <- string(:printable), not String.contains?(output, "<<SWARM_MSG")) do
      assert [%{type: :output}] = AgentProtocol.parse_output(output)
    end
  end

  property "a well-formed marker round-trips" do
    check all(
            target <- member_of(@targets),
            content <- string(:alphanumeric, min_length: 1),
            before <- string(:alphanumeric),
            trailing <- string(:alphanumeric)
          ) do
      output =
        "#{before}<<SWARM_MSG:TO=#{target}:START>>\n#{content}\n<<SWARM_MSG:END>>#{trailing}"

      assert [%{type: :output}, %{type: :send, to: ^target, content: ^content}] =
               AgentProtocol.parse_output(output)
    end
  end

  # Fields may be text or any other JSON type ({"type":"send","to":0} used to raise).
  property "decode never crashes, and rejects any non-text field" do
    check all(
            data <-
              one_of([
                binary(),
                string(:printable),
                json_object(one_of([text(), integer(), boolean(), constant(nil)]))
              ])
          ) do
      case AgentProtocol.decode(data) do
        {:ok, _} -> assert Enum.all?(Map.values(Jason.decode!(data)), &is_binary/1)
        {:error, _} -> :ok
      end
    end
  end

  defp text do
    one_of([
      string(:printable, max_length: 10),
      member_of(~w(output send broadcast status bogus pp_alpha))
    ])
  end

  defp json_object(value) do
    ~w(type to content state from command)
    |> Map.new(&{&1, value})
    |> optional_map()
    |> map(&Jason.encode!/1)
  end
end
