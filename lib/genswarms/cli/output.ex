defmodule Genswarms.CLI.Output do
  @moduledoc """
  Colored output helpers for CLI commands.

  Provides consistent formatting for terminal output including:
  - Colored text (success, error, warning, info)
  - Tables for structured data
  """

  # ANSI color codes
  @reset "\e[0m"
  @bold "\e[1m"
  @dim "\e[2m"
  @red "\e[31m"
  @green "\e[32m"
  @yellow "\e[33m"
  @blue "\e[34m"
  @magenta "\e[35m"
  @cyan "\e[36m"
  @white "\e[37m"

  # Status symbols
  @check "✓"
  @cross "✗"
  @arrow "→"
  @bullet "•"

  @doc """
  Returns whether color output is enabled.
  """
  def colors_enabled? do
    System.get_env("NO_COLOR") == nil and
      System.get_env("TERM") != "dumb" and
      IO.ANSI.enabled?()
  end

  @doc """
  Prints a success message (green with checkmark).
  """
  def success(message) do
    puts(colorize("#{@check} #{message}", :green))
  end

  @doc """
  Prints an error message (red with cross).
  """
  def error(message) do
    puts(colorize("#{@cross} #{message}", :red), :stderr)
  end

  @doc """
  Prints a warning message (yellow).
  """
  def warning(message) do
    puts(colorize("#{@bullet} #{message}", :yellow))
  end

  @doc """
  Prints an info message (cyan).
  """
  def info(message) do
    puts(colorize("#{@arrow} #{message}", :cyan))
  end

  @doc """
  Prints a dim/muted message.
  """
  def dim(message) do
    puts(colorize(message, :dim))
  end

  @doc """
  Prints a header (bold).
  """
  def header(message) do
    puts("")
    puts(colorize(message, :bold))
    puts(colorize(String.duplicate("─", String.length(message)), :dim))
  end

  @doc """
  Prints a newline.
  """
  def newline do
    puts("")
  end

  @doc """
  Prints plain text.
  """
  def puts(message, device \\ :stdio) do
    case device do
      :stderr -> IO.puts(:stderr, message)
      _ -> IO.puts(message)
    end
  end

  @doc """
  Colorizes text with the given color/style.
  """
  def colorize(text, color) when is_atom(color) do
    if colors_enabled?() do
      color_code(color) <> text <> @reset
    else
      text
    end
  end

  @doc """
  Formats a key-value pair for display.
  """
  def kv(key, value) do
    key_str = colorize("#{key}:", :dim)
    "  #{key_str} #{value}"
  end

  @doc """
  Prints a list of items with bullets.
  """
  def list(items) when is_list(items) do
    Enum.each(items, fn item ->
      puts("  #{colorize(@bullet, :dim)} #{item}")
    end)
  end

  @doc """
  Prints a simple table with headers.
  """
  def table(headers, rows, opts \\ []) do
    padding = Keyword.get(opts, :padding, 2)

    # Calculate column widths
    all_rows = [headers | rows]

    widths =
      Enum.reduce(all_rows, %{}, fn row, acc ->
        row
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {cell, idx}, inner_acc ->
          cell_str = to_string(cell)
          current = Map.get(inner_acc, idx, 0)
          Map.put(inner_acc, idx, max(current, String.length(cell_str)))
        end)
      end)

    # Print header
    header_row =
      headers
      |> Enum.with_index()
      |> Enum.map(fn {h, idx} ->
        String.pad_trailing(to_string(h), widths[idx] + padding)
      end)
      |> Enum.join("")

    puts(colorize(header_row, :bold))

    # Print separator
    separator =
      widths
      |> Map.values()
      |> Enum.map(fn w -> String.duplicate("─", w + padding) end)
      |> Enum.join("")

    puts(colorize(separator, :dim))

    # Print rows
    Enum.each(rows, fn row ->
      row_str =
        row
        |> Enum.with_index()
        |> Enum.map(fn {cell, idx} ->
          String.pad_trailing(to_string(cell), widths[idx] + padding)
        end)
        |> Enum.join("")

      puts(row_str)
    end)
  end

  # Private functions

  defp color_code(:reset), do: @reset
  defp color_code(:bold), do: @bold
  defp color_code(:dim), do: @dim
  defp color_code(:red), do: @red
  defp color_code(:green), do: @green
  defp color_code(:yellow), do: @yellow
  defp color_code(:blue), do: @blue
  defp color_code(:magenta), do: @magenta
  defp color_code(:cyan), do: @cyan
  defp color_code(:white), do: @white
  defp color_code(_), do: ""
end
