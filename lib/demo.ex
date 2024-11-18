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
    {:ok, target_neuron, _} = new_neuron_connected_to(self())
    IO.puts("Started top level: #{inspect(target_neuron)}")

    n = Application.fetch_env!(:elixir_ne, :number_of_neurons)

    IO.puts("Number of neurons: #{n}")

    1..n
    |> Enum.map(fn _ ->
      {:ok, neuron, selected_node} = new_neuron_connected_to(target_neuron, Node.list())
      target_neuron |> Neuron.connect_input_from(neuron)
      # count the neurons started on which node
      selected_node
    end)
    |> Enum.frequencies_by(&(&1))
    |> IO.inspect(label: "Neurons started on nodes")

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

  defp new_neuron_connected_to(pid, []) do
    {:ok, pid} = Task.start(Neuron, :start, [pid])
    {:ok, pid, Node.self()}
  end

  defp new_neuron_connected_to(pid, node_list) do
    [selected_node | _] = Enum.take_random(node_list ++ [Node.self()], 1)

    # {:ok, Node.spawn(selected_node, fun -> Neuron, :start, [pid])}
    {:ok, Node.spawn(selected_node, fn -> Neuron.start(pid) end), selected_node}
  end

  defp new_neuron_connected_to(pid) do
    {:ok, pid} = Task.start(Neuron, :start, [pid])
    {:ok, pid, Node.self()}
  end
end
