defmodule Demo do
  use Application

  @moduledoc """
  a current demo of the work in progress
  """

  @doc """
  Runs the demo
  """
  def start(_type, _args) do
    IO.puts("starting")
    run()
    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link([], opts)
  end

  defp run() do
    {:ok, target_neuron} = Task.start(Neuron, :run, [{:state, [outgoing: self(), incoming: []]}])
    IO.puts("Started top level: #{inspect(target_neuron)}")
    IO.puts("stopping")
  end
end
