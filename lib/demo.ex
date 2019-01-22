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
    {:ok, target_neuron} = new_neuron_connected_to(self())
    IO.puts("Started top level: #{inspect(target_neuron)}")

    n = 1000
    1..n
    |> Enum.map(fn _ ->
      {:ok, neuron} = new_neuron_connected_to(target_neuron)
      target_neuron |> Neuron.connect_input_from(neuron)
    end)

    target_neuron |> Neuron.please_predict()

    # just once for the demo
    wait_for_reply()

    IO.puts("stopping")
  end

  defp wait_for_reply() do
    receive do
      x -> IO.puts("received: #{inspect(x)}")
    after
      # just exit
      5_000 -> false
    end
  end

  defp new_neuron_connected_to(pid) do
    Task.start(Neuron, :start, [pid])
  end
end
