defmodule Genswarms.Skills.SkillsManager do
  @moduledoc """
  GenServer for listing repository skills.

  Provides:
  - ETS-based caching of skill files
  - Loading skills from the skills repository (priv/skills)
  - Reloading skills from disk on request
  """

  use GenServer
  require Logger

  @ets_table :subzeroclaw_skills

  defstruct [:skills_dir]

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Lists all available skills in the repository.
  """
  @spec list_skills() :: [String.t()]
  def list_skills do
    GenServer.call(__MODULE__, :list_skills)
  end

  @doc """
  Reloads all skills from disk.
  """
  @spec reload_skills() :: :ok
  def reload_skills do
    GenServer.call(__MODULE__, :reload_skills)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for caching
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    skills_dir =
      Application.get_env(:genswarms, :skills_dir, "priv/skills")
      |> Path.expand()

    state = %__MODULE__{
      skills_dir: skills_dir
    }

    # Load skills on startup
    load_skills(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:list_skills, _from, state) do
    skills =
      :ets.tab2list(@ets_table)
      |> Enum.map(fn {name, _content, _mtime} -> name end)
      |> Enum.sort()

    {:reply, skills, state}
  end

  def handle_call(:reload_skills, _from, state) do
    :ets.delete_all_objects(@ets_table)
    load_skills(state)
    {:reply, :ok, state}
  end

  # Private functions

  defp load_skills(state) do
    skills_dir = state.skills_dir

    if File.exists?(skills_dir) do
      case File.ls(skills_dir) do
        {:ok, files} ->
          skill_files = Enum.filter(files, &String.ends_with?(&1, ".md"))

          Enum.each(skill_files, fn file ->
            load_skill_to_cache(skills_dir, file)
          end)

          Logger.info("Loaded #{length(skill_files)} skills from #{skills_dir}")

        {:error, reason} ->
          Logger.warning("Failed to list skills directory: #{inspect(reason)}")
      end
    else
      Logger.info("Skills directory does not exist: #{skills_dir}")
      File.mkdir_p(skills_dir)
    end
  end

  defp load_skill_to_cache(skills_dir, filename) do
    path = Path.join(skills_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        mtime = File.stat!(path).mtime
        :ets.insert(@ets_table, {filename, content, mtime})

      {:error, reason} ->
        Logger.warning("Failed to load skill #{filename}: #{inspect(reason)}")
    end
  end
end
