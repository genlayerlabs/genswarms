defmodule Genswarms.IR.ToConfig do
  @moduledoc """
  The reverse of `IR.FromConfig`: turns an IR `Agent`/`Object` back into the
  runtime's config-format spec (the map `SwarmManager.add_agent/add_object`
  expect). Lets the IR executor drive the existing orchestrator.

      body {ref: "inline:<name>"} + overrides{skills,presets} -> skills/presets
      model {ref: "openrouter:x/y"}                           -> model: "x/y"
      backend {ref: "bwrap"|"local"|"mock"}                  -> :bwrap/:local/:mock
      backend {ref: "oci:n"}                                  -> {:docker, "n"}
      backend {ref: "apple_container", image?: i, opts?: o}   -> :apple_container / tuple
      backend {ref: "ssh", host: h}                           -> {:ssh, h}
      handler {ref: "module:<Mod>"}                           -> the module atom
  """

  alias Genswarms.IR.State.{Agent, Object}

  @doc "IR agent -> runtime agent spec map."
  @spec agent_spec(Agent.t()) :: map()
  def agent_spec(%Agent{} = a) do
    %{
      name: a.name,
      backend: backend(a.backend),
      model: model(a.model),
      skills: Map.get(a.overrides, "skills", []),
      presets: a.overrides |> Map.get("presets", []) |> Enum.map(&String.to_atom/1),
      config: a.config
    }
  end

  @doc "IR object -> runtime object spec map."
  @spec object_spec(Object.t()) :: map()
  def object_spec(%Object{} = o) do
    %{name: o.name, handler: handler_module(o.handler), config: o.config}
  end

  # ── backend ──────────────────────────────────────────────────────────────────

  defp backend(%{scheme: "bwrap"}), do: :bwrap
  defp backend(%{scheme: "local"}), do: :local
  defp backend(%{scheme: "mock"}), do: :mock
  defp backend(%{scheme: "oci", ref: ref}), do: {:docker, String.replace_prefix(ref, "oci:", "")}
  defp backend(%{scheme: "apple_container", image: nil}), do: :apple_container

  defp backend(%{scheme: "apple_container", image: image, opts: opts})
       when opts == %{} or is_nil(opts),
       do: {:apple_container, image}

  defp backend(%{scheme: "apple_container", image: image, opts: opts}),
    do: {:apple_container, image, atomize_known_backend_opts(opts)}

  defp backend(%{scheme: "ssh", host: host}), do: {:ssh, host}

  @backend_opt_keys ~w(container_name workspace env volumes cmd memory_limit cpu_limit
                       memory_swap pids_limit max_turns network subzeroclaw_src
                       request_extra compact_extra endpoint)a

  defp atomize_known_backend_opts(opts) do
    key_map = Map.new(@backend_opt_keys, fn atom -> {Atom.to_string(atom), atom} end)

    Map.new(opts, fn
      {key, value} when is_binary(key) -> {Map.get(key_map, key, key), value}
      other -> other
    end)
  end

  # ── model ────────────────────────────────────────────────────────────────────

  # The translated default (`openrouter:default`) means "no explicit model".
  defp model({:service, %{ref: "openrouter:default"}}), do: nil
  defp model({:service, %{ref: ref}}), do: String.replace_prefix(ref, "openrouter:", "")
  # A policy slot has no config-format model-string equivalent yet.
  defp model({:policy, _ref}), do: nil

  # ── handler ──────────────────────────────────────────────────────────────────

  # `module:<Mod>` -> the existing module atom (safe_concat never mints — #22).
  defp handler_module(%{ref: ref}) do
    ref |> String.replace_prefix("module:", "") |> String.split(".") |> Module.safe_concat()
  end
end
