defmodule Genswarms.IR.FromConfig do
  @moduledoc """
  Translates a current GenSwarms swarm config (the `.exs`/`.json`/`.yaml` DSL)
  into a `swarm.state` IR document (phase `desired`).

  The DSL describes *local, inline* things; the IR is built for content-addressed
  *packages*. Local things become
  non-package `<other>` refs (§2.1) and the agent persona becomes an *inline*
  body — when a config is later published with `gsp`, those `inline:`/`local:`/…
  refs become real `swarmidx:`/`oci:` packages with digests.

  Mapping:

      agent.skills/presets   -> body  {ref: "inline:<name>", kind: data}
                                       + overrides {skills, presets}
      agent.model "x/y"      -> model {ref: "openrouter:x/y", attested: true}
      backend :bwrap/:local/:mock -> {ref: "bwrap"|"local"|"mock"}
      backend {:docker, n}   -> {ref: "oci:<n>", kind: data}
      backend :apple_container / {:apple_container, image}
                           -> {ref: "apple_container", image?: image}
      backend {:tmux, client} -> {ref: "tmux", client: client}
      backend {:ssh, "u@h"}  -> {ref: "ssh", host: "u@h"}
      object.handler Mod     -> handler {ref: "module:<Mod>", kind: code}

  Returns a validated `IR.State` (`{:ok, state}`) so any mapping that violates
  the §6 invariants is caught immediately.
  """

  alias Genswarms.IR

  @doc "Translates a swarm config map into a validated `swarm.state` (IR1)."
  @spec from_config(map()) :: {:ok, IR.State.t()} | {:error, term()}
  def from_config(config) when is_map(config) do
    with {:ok, agents} <- map_each(Map.get(config, :agents, []), &agent/1),
         {:ok, objects} <- map_each(Map.get(config, :objects, []), &object/1) do
      IR.state(%{
        "v" => 1,
        "kind" => "swarm.state",
        "name" => to_string(Map.get(config, :name, "swarm")),
        "phase" => "desired",
        "agents" => agents,
        "objects" => objects,
        "topology" => topology(Map.get(config, :topology, [])),
        "options" => stringify_keys(Map.get(config, :options, %{}))
      })
    end
  end

  def from_config(_), do: {:error, :config_not_a_map}

  # ── agents ──────────────────────────────────────────────────────────────────

  defp agent(%{} = a) do
    name = to_string(Map.get(a, :name))
    slots = Map.get(a, :ir_slots, %{})

    with {:ok, backend} <- backend_ref(Map.get(a, :backend, :bwrap)) do
      {:ok,
       %{
         "name" => name,
         "body" => Map.get(slots, "body", %{"ref" => "inline:" <> name, "kind" => "data"}),
         "model" => Map.get(slots, "model", model_slot(Map.get(a, :model))),
         "backend" => backend,
         "overrides" => Map.get(slots, "overrides", overrides(a)),
         "config" => stringify_keys(Map.get(a, :config, %{}))
       }}
    end
  end

  defp agent(_), do: {:error, :invalid_agent_config}

  # The persona becomes an inline body; skills/presets ride in overrides.
  defp overrides(a) do
    %{
      "skills" => Map.get(a, :skills, []),
      "presets" => a |> Map.get(:presets, []) |> Enum.map(&to_string/1)
    }
    |> Map.merge(
      Map.new(
        for key <- [:endpoint, :request_extra, :compact_extra],
            value = Map.get(a, key),
            not is_nil(value),
            do: {Atom.to_string(key), value}
      )
    )
  end

  # A model string ("provider/model", OpenRouter format) -> a service ref.
  defp model_slot(model) do
    %{"ref" => "openrouter:" <> to_string(model || "default"), "attested" => true}
  end

  defp backend_ref(:local), do: {:ok, %{"ref" => "local"}}
  defp backend_ref(:bwrap), do: {:ok, %{"ref" => "bwrap"}}
  defp backend_ref(:mock), do: {:ok, %{"ref" => "mock"}}

  defp backend_ref({kind, opts}) when kind in [:local, :bwrap, :mock],
    do: {:ok, %{"ref" => Atom.to_string(kind), "opts" => stringify_keys(opts)}}

  defp backend_ref(:apple_container), do: {:ok, %{"ref" => "apple_container"}}
  defp backend_ref({:apple_container, image}), do: {:ok, apple_container(image)}

  defp backend_ref({:apple_container, image, opts}),
    do: {:ok, Map.put(apple_container(image), "opts", stringify_keys(opts))}

  defp backend_ref({:docker, name}), do: {:ok, oci(name)}

  defp backend_ref({:docker, name, opts}),
    do: {:ok, Map.put(oci(name), "opts", stringify_keys(opts))}

  defp backend_ref({:ssh, host}), do: {:ok, %{"ref" => "ssh", "host" => to_string(host)}}

  defp backend_ref({:ssh, host, opts}),
    do: {:ok, %{"ref" => "ssh", "host" => to_string(host), "opts" => stringify_keys(opts)}}

  defp backend_ref({:tmux, client}), do: {:ok, tmux(client)}

  defp backend_ref({:tmux, client, opts}),
    do: {:ok, Map.put(tmux(client), "opts", stringify_keys(opts))}

  defp backend_ref(other), do: {:error, {:unsupported_backend, other}}

  defp oci(name), do: %{"ref" => "oci:" <> to_string(name), "kind" => "data"}

  defp apple_container(image),
    do: %{"ref" => "apple_container", "image" => to_string(image)}

  defp tmux(client), do: %{"ref" => "tmux", "client" => to_string(client)}

  # ── objects ─────────────────────────────────────────────────────────────────

  defp object(%{handler: handler} = o) when is_map(handler) do
    # Loader options are execution metadata, not a module-name string. Keep
    # the package identity/digest intact across JSON and runtime translation.
    get = fn key -> Map.get(handler, key, Map.get(handler, Atom.to_string(key))) end
    mode = get.(:mode) || :verify

    if mode in [:require, :verify, "require", "verify"] do
      {:ok,
       %{
         "name" => to_string(Map.get(o, :name)),
         "handler" => %{
           "ref" => get.(:ref),
           "digest" => get.(:digest),
           "kind" => "code",
           "opts" => %{"path" => get.(:path), "mode" => to_string(mode)}
         },
         "config" => stringify_keys(Map.get(o, :config, %{}))
       }}
    else
      {:error, :invalid_handler_load_mode}
    end
  end

  defp object(%{handler: handler} = o) when is_atom(handler) and not is_nil(handler) do
    {:ok,
     %{
       "name" => to_string(Map.get(o, :name)),
       "handler" => %{"ref" => "module:" <> inspect(handler), "kind" => "code"},
       "config" => stringify_keys(Map.get(o, :config, %{}))
     }}
  end

  # IR objects are handler (code) nodes; a backend-only object has no IR §3.4
  # equivalent yet.
  defp object(%{}), do: {:error, :object_without_handler}
  defp object(_), do: {:error, :invalid_object_config}

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp topology(edges) do
    Enum.map(edges, fn {from, to} -> [to_string(from), to_string(to)] end)
  end

  defp map_each(list, fun) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, mapped} -> {:cont, {:ok, acc ++ [mapped]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp map_each(_, _), do: {:error, :not_a_list}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = to_string(k)

      value =
        if key in ["extra_ro_binds", "extra_rw_binds"] and is_list(v) do
          Enum.map(v, fn
            {source, target} when is_binary(source) and is_binary(target) -> [source, target]
            item -> item
          end)
        else
          v
        end

      {key, value}
    end)
  end

  defp stringify_keys(other), do: other
end
