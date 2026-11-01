defmodule NodeMemory do
  @moduledoc """
  Resident memory of the operating-system process that runs this BEAM node.

  `:erlang.memory/1` only counts what the BEAM's own allocators handed out. Memory
  held by NIFs or by an embedded interpreter such as CPython never appears there,
  so a number that has to include a Pythonx interpreter has to come from the OS.
  """

  @doc """
  Resident memory of this node's OS process in MiB.
  """
  @spec rss_mb() :: non_neg_integer()
  def rss_mb, do: div(rss_kb(), 1024)

  @doc """
  Resident memory of this node's OS process in KiB.
  """
  @spec rss_kb() :: non_neg_integer()
  def rss_kb do
    :os.getpid()
    |> List.to_string()
    |> rss_kb_of_os_process()
  end

  defp rss_kb_of_os_process(os_pid) do
    case System.cmd("ps", ["-o", "rss=", "-p", os_pid]) do
      {output, 0} ->
        output |> String.trim() |> String.to_integer()

      {output, status} ->
        raise "cannot read RSS of OS process #{os_pid} (ps exited #{status}): #{output}"
    end
  end
end
