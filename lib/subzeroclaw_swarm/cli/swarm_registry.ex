defmodule SubzeroclawSwarm.CLI.SwarmRegistry do
  @moduledoc """
  SQLite-backed registry for tracking running swarms.

  Stores swarm state independently of any running process, allowing the CLI
  to query and manage swarms without requiring the dashboard.

  ## Database Schema

      swarms:
        - name (primary key)
        - status: running | stopped | crashed
        - pid: OS process ID
        - config_path: path to config file
        - log_path: path to event log file
        - started_at: timestamp
        - stopped_at: timestamp (nullable)
  """

  @db_path ".swarm/swarms.db"
  @events_dir ".swarm/events"

  # Open database with busy timeout for concurrency
  defp open_db do
    {:ok, db} = Exqlite.Sqlite3.open(db_path())
    # Set busy timeout to wait up to 5 seconds if database is locked
    Exqlite.Sqlite3.execute(db, "PRAGMA busy_timeout=5000")
    {:ok, db}
  end

  @doc """
  Ensures the database and tables exist.
  """
  def init do
    ensure_dir()
    {:ok, db} = open_db()

    # Enable WAL mode for better concurrency (allows concurrent reads while writing)
    Exqlite.Sqlite3.execute(db, "PRAGMA journal_mode=WAL")
    Exqlite.Sqlite3.execute(db, "PRAGMA busy_timeout=5000")

    Exqlite.Sqlite3.execute(db, """
      CREATE TABLE IF NOT EXISTS swarms (
        name TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'stopped',
        pid INTEGER,
        config_path TEXT,
        log_path TEXT,
        started_at TEXT,
        stopped_at TEXT
      )
    """)

    Exqlite.Sqlite3.execute(db, """
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        swarm TEXT,
        agent TEXT,
        event_type TEXT NOT NULL,
        message TEXT NOT NULL,
        metadata TEXT
      )
    """)

    Exqlite.Sqlite3.execute(db, """
      CREATE INDEX IF NOT EXISTS idx_events_swarm ON events(swarm)
    """)

    Exqlite.Sqlite3.execute(db, """
      CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp)
    """)

    # Tasks table for cross-process task delivery
    Exqlite.Sqlite3.execute(db, """
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        swarm TEXT NOT NULL,
        agent TEXT NOT NULL,
        task TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        processed_at TEXT
      )
    """)

    Exqlite.Sqlite3.execute(db, """
      CREATE INDEX IF NOT EXISTS idx_tasks_pending ON tasks(swarm, status) WHERE status = 'pending'
    """)

    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Queues a task for an agent in a daemon swarm.
  """
  def queue_task(swarm_name, agent_name, task) do
    ensure_db_exists()
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        INSERT INTO tasks (swarm, agent, task, status, created_at)
        VALUES (?, ?, ?, 'pending', datetime('now', 'subsec'))
      """)

    Exqlite.Sqlite3.bind(stmt, [swarm_name, to_string(agent_name), task])
    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Gets pending tasks for a swarm.
  """
  def get_pending_tasks(swarm_name) do
    ensure_db_exists()
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        SELECT id, agent, task FROM tasks
        WHERE swarm = ? AND status = 'pending'
        ORDER BY created_at ASC
      """)

    Exqlite.Sqlite3.bind(stmt, [swarm_name])
    tasks = collect_task_rows(db, stmt, [])

    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    tasks
  end

  @doc """
  Marks a task as processed.
  """
  def mark_task_processed(task_id) do
    ensure_db_exists()
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        UPDATE tasks SET status = 'processed', processed_at = datetime('now', 'subsec')
        WHERE id = ?
      """)

    Exqlite.Sqlite3.bind(stmt, [task_id])
    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    :ok
  end

  defp collect_task_rows(db, stmt, acc) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, [id, agent, task]} ->
        row = %{id: id, agent: String.to_atom(agent), task: task}
        collect_task_rows(db, stmt, [row | acc])

      :done ->
        Enum.reverse(acc)
    end
  end

  @doc """
  Registers a swarm as starting.
  """
  def register_swarm(name, pid, config_path) do
    ensure_dir()
    log_path = Path.join(events_dir(), "#{name}.log")
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        INSERT OR REPLACE INTO swarms (name, status, pid, config_path, log_path, started_at, stopped_at)
        VALUES (?, 'running', ?, ?, ?, datetime('now'), NULL)
      """)

    Exqlite.Sqlite3.bind(stmt, [name, pid, config_path, log_path])
    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    {:ok, log_path}
  end

  @doc """
  Marks a swarm as stopped.
  """
  def mark_stopped(name) do
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        UPDATE swarms SET status = 'stopped', stopped_at = datetime('now'), pid = NULL
        WHERE name = ?
      """)

    Exqlite.Sqlite3.bind(stmt, [name])
    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Deletes a swarm and all its data from the registry.
  This removes the swarm entry, all events, and all pending tasks.
  """
  def delete_swarm(name) do
    ensure_db_exists()
    {:ok, db} = open_db()

    # Delete from swarms table
    {:ok, stmt1} = Exqlite.Sqlite3.prepare(db, "DELETE FROM swarms WHERE name = ?")
    Exqlite.Sqlite3.bind(stmt1, [name])
    Exqlite.Sqlite3.step(db, stmt1)
    Exqlite.Sqlite3.release(db, stmt1)

    # Delete events for this swarm
    {:ok, stmt2} = Exqlite.Sqlite3.prepare(db, "DELETE FROM events WHERE swarm = ?")
    Exqlite.Sqlite3.bind(stmt2, [name])
    Exqlite.Sqlite3.step(db, stmt2)
    Exqlite.Sqlite3.release(db, stmt2)

    # Delete pending tasks for this swarm
    {:ok, stmt3} = Exqlite.Sqlite3.prepare(db, "DELETE FROM tasks WHERE swarm = ?")
    Exqlite.Sqlite3.bind(stmt3, [name])
    Exqlite.Sqlite3.step(db, stmt3)
    Exqlite.Sqlite3.release(db, stmt3)

    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Deletes all files associated with a swarm.
  This includes log files and swarm data directories.
  """
  def delete_swarm_files(name) do
    # Delete .swarm/logs/<name>.log
    log_file = Path.join([File.cwd!(), ".swarm", "logs", "#{name}.log"])
    if File.exists?(log_file), do: File.rm(log_file)

    # Delete ~/.subzeroclaw/swarms/<name>/
    swarm_dir = Path.join([System.user_home!(), ".subzeroclaw", "swarms", name])
    if File.exists?(swarm_dir), do: File.rm_rf(swarm_dir)

    :ok
  end

  @doc """
  Clears all events from the database.
  """
  def clear_all_events do
    ensure_db_exists()
    {:ok, db} = open_db()

    Exqlite.Sqlite3.execute(db, "DELETE FROM events")
    Exqlite.Sqlite3.execute(db, "DELETE FROM tasks")

    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Marks a swarm as crashed.
  """
  def mark_crashed(name) do
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        UPDATE swarms SET status = 'crashed', stopped_at = datetime('now')
        WHERE name = ?
      """)

    Exqlite.Sqlite3.bind(stmt, [name])
    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Gets info about a swarm.
  """
  def get_swarm(name) do
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        SELECT name, status, pid, config_path, log_path, started_at, stopped_at
        FROM swarms WHERE name = ?
      """)

    Exqlite.Sqlite3.bind(stmt, [name])

    result =
      case Exqlite.Sqlite3.step(db, stmt) do
        {:row, row} ->
          [name, status, pid, config_path, log_path, started_at, stopped_at] = row

          {:ok,
           %{
             name: name,
             status: String.to_atom(status),
             pid: pid,
             config_path: config_path,
             log_path: log_path,
             started_at: started_at,
             stopped_at: stopped_at
           }}

        :done ->
          {:error, :not_found}
      end

    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    result
  end

  @doc """
  Lists all swarms.
  """
  def list_swarms do
    ensure_db_exists()
    {:ok, db} = open_db()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        SELECT name, status, pid, config_path, log_path, started_at, stopped_at
        FROM swarms ORDER BY started_at DESC
      """)

    swarms = collect_rows(db, stmt, [])

    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    swarms
  end

  @doc """
  Lists running swarms (verifies PIDs are alive).
  """
  def list_running do
    list_swarms()
    |> Enum.filter(fn s -> s.status == :running and process_alive?(s.pid) end)
  end

  @doc """
  Logs an event to SQLite.
  """
  def log_event(level, category, event_type, message, opts \\ []) do
    ensure_db_exists()
    {:ok, db} = open_db()

    swarm = Keyword.get(opts, :swarm)
    agent = Keyword.get(opts, :agent)
    metadata = Keyword.get(opts, :metadata, %{})

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        INSERT INTO events (timestamp, level, category, swarm, agent, event_type, message, metadata)
        VALUES (datetime('now', 'subsec'), ?, ?, ?, ?, ?, ?, ?)
      """)

    Exqlite.Sqlite3.bind(stmt, [
      to_string(level),
      to_string(category),
      swarm,
      if(agent, do: to_string(agent), else: nil),
      to_string(event_type),
      message,
      Jason.encode!(metadata)
    ])

    Exqlite.Sqlite3.step(db, stmt)
    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    :ok
  end

  @doc """
  Queries events from SQLite.
  """
  def query_events(opts \\ []) do
    ensure_db_exists()
    {:ok, db} = open_db()

    {where_clauses, params} = build_where_clauses(opts)
    limit = Keyword.get(opts, :limit, 50)

    where_sql =
      if where_clauses == [], do: "", else: "WHERE " <> Enum.join(where_clauses, " AND ")

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
        SELECT id, timestamp, level, category, swarm, agent, event_type, message, metadata
        FROM events #{where_sql}
        ORDER BY timestamp DESC
        LIMIT #{limit}
      """)

    Exqlite.Sqlite3.bind(stmt, params)
    events = collect_event_rows(db, stmt, [])

    Exqlite.Sqlite3.release(db, stmt)
    Exqlite.Sqlite3.close(db)
    events
  end

  @doc """
  Checks if a process is alive by PID.
  """
  def process_alive?(nil), do: false

  def process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Cleans up stale entries (marks crashed if PID is dead).
  """
  def cleanup_stale do
    list_swarms()
    |> Enum.filter(fn s -> s.status == :running and not process_alive?(s.pid) end)
    |> Enum.each(fn s -> mark_crashed(s.name) end)
  end

  # Private

  defp db_path do
    case Application.get_env(:subzeroclaw_swarm, :db_path) do
      nil -> Path.join(File.cwd!(), @db_path)
      path -> Path.expand(path)
    end
  end

  defp events_dir do
    case Application.get_env(:subzeroclaw_swarm, :events_dir) do
      nil -> Path.join(File.cwd!(), @events_dir)
      path -> Path.expand(path)
    end
  end

  defp ensure_dir do
    File.mkdir_p!(Path.dirname(db_path()))
    File.mkdir_p!(events_dir())
  end

  defp ensure_db_exists do
    unless File.exists?(db_path()) do
      init()
    end
  end

  defp collect_rows(db, stmt, acc) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, [name, status, pid, config_path, log_path, started_at, stopped_at]} ->
        row = %{
          name: name,
          status: String.to_atom(status),
          pid: pid,
          config_path: config_path,
          log_path: log_path,
          started_at: started_at,
          stopped_at: stopped_at
        }

        collect_rows(db, stmt, [row | acc])

      :done ->
        Enum.reverse(acc)
    end
  end

  defp collect_event_rows(db, stmt, acc) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, [id, timestamp, level, category, swarm, agent, event_type, message, metadata]} ->
        row = %{
          id: id,
          timestamp: timestamp,
          level: String.to_atom(level),
          category: String.to_atom(category),
          swarm: swarm,
          agent: if(agent, do: String.to_atom(agent), else: nil),
          event_type: String.to_atom(event_type),
          message: message,
          metadata: Jason.decode!(metadata || "{}")
        }

        collect_event_rows(db, stmt, [row | acc])

      :done ->
        Enum.reverse(acc)
    end
  end

  defp build_where_clauses(opts) do
    clauses = []
    params = []

    {clauses, params} =
      if opts[:swarm] do
        {clauses ++ ["swarm = ?"], params ++ [opts[:swarm]]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if opts[:agent] do
        {clauses ++ ["agent = ?"], params ++ [to_string(opts[:agent])]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if opts[:category] do
        {clauses ++ ["category = ?"], params ++ [to_string(opts[:category])]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if opts[:level] do
        {clauses ++ ["level = ?"], params ++ [to_string(opts[:level])]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if opts[:event_type] do
        {clauses ++ ["event_type = ?"], params ++ [to_string(opts[:event_type])]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if opts[:minutes] do
        {clauses ++ ["timestamp >= datetime('now', ?)"], params ++ ["-#{opts[:minutes]} minutes"]}
      else
        {clauses, params}
      end

    {clauses, params}
  end
end
