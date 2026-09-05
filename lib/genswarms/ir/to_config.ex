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
      backend {ref: "tmux", client: c, opts?: o}              -> {:tmux, c, opts?}
      backend {ref: "ssh", host: h}                           -> {:ssh, h}
      handler {ref: "module:<Mod>"}                           -> the module atom
  """

  alias Genswarms.Config.SwarmConfig
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
      config: a.config |> SwarmConfig.atomize_known_backend_opts() |> normalize_option_values()
    }
  end

  @doc "IR object -> runtime object spec map."
  @spec object_spec(Object.t()) :: map()
  def object_spec(%Object{} = o) do
    %{name: o.name, handler: handler_module(o.handler), config: o.config}
  end

  # ── backend ──────────────────────────────────────────────────────────────────

  defp backend(%{scheme: "bwrap", opts: opts}), do: with_opts(:bwrap, opts)
  defp backend(%{scheme: "local", opts: opts}), do: with_opts(:local, opts)
  defp backend(%{scheme: "mock", opts: opts}), do: with_opts(:mock, opts)

  defp backend(%{scheme: "oci", ref: ref, opts: opts}),
    do: with_opts({:docker, String.replace_prefix(ref, "oci:", "")}, opts)

  defp backend(%{scheme: "apple_container", image: nil, opts: opts})
       when opts == %{} or is_nil(opts),
       do: :apple_container

  defp backend(%{scheme: "apple_container", image: nil}),
    do: raise(ArgumentError, "Apple container IR options require an explicit image")

  defp backend(%{scheme: "apple_container", image: image, opts: opts}),
    do: with_opts({:apple_container, image}, opts)

  defp backend(%{scheme: "tmux", client: client, opts: opts}),
    do: with_opts({:tmux, client}, opts)

  defp backend(%{scheme: "ssh", host: host, opts: opts}), do: with_opts({:ssh, host}, opts)

  defp with_opts(base, opts) when opts == %{} or is_nil(opts), do: base

  defp with_opts(base, opts) do
    opts = opts |> SwarmConfig.atomize_known_backend_opts() |> normalize_option_values()
    if is_tuple(base), do: Tuple.insert_at(base, tuple_size(base), opts), else: {base, opts}
  end

  # These backend selectors are atoms at execution time, strings in JSON.
  # Never create arbitrary atoms from IR values (Docker network names, etc.).
  defp normalize_option_values(opts) do
    Map.new(opts, fn
      {:network, "isolated"} -> {:network, :isolated}
      {:privilege_mode, "rootless"} -> {:privilege_mode, :rootless}
      {:privilege_mode, "cgroup"} -> {:privilege_mode, :cgroup}
      {:proc_mount, "new"} -> {:proc_mount, :new}
      {:proc_mount, "bind"} -> {:proc_mount, :bind}
      entry -> entry
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
