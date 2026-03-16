defmodule Demo do
  use Application

  @moduledoc """
  a current demo of the work in progress
  """

  @config_keys [
    :number_of_neurons,
    :neuron_simulate_computation_ms,
    :prediction_deadline_ms,
    :prediction_quiescence_deadline_ms,
    :demo_reply_timeout_ms
  ]

  @type neuron_counts :: %{required(node()) => non_neg_integer()}
  @type startup_report :: %{
          required(:node) => node(),
          required(:neurons) => [pid()],
          required(:started_count) => non_neg_integer(),
          required(:started_at_ms) => integer(),
          required(:duration_ms) => non_neg_integer()
        }
  @type demo_options :: [
          number_of_neurons: non_neg_integer(),
          neuron_simulate_computation_ms: non_neg_integer(),
      prediction_deadline_ms: non_neg_integer(),
      prediction_quiescence_deadline_ms: non_neg_integer(),
      demo_reply_timeout_ms: non_neg_integer()
        ]

  @doc """
  Runs the demo using application config and env-derived defaults.
  """
  def start do
    start([])
  end

  @doc """
  Runs the demo with optional per-run overrides.

  Supported options:
  - `:number_of_neurons`
  - `:neuron_simulate_computation_ms`
  - `:prediction_deadline_ms`
  - `:prediction_quiescence_deadline_ms`
  - `:demo_reply_timeout_ms`
  """
  def start(overrides) when is_list(overrides) or is_map(overrides) do
    IO.puts("starting")

    available_nodes = [Node.self() | Node.list()]
    runtime_config = resolve_runtime_config(overrides)
    previous_config = apply_runtime_config(available_nodes, runtime_config)

    try do
      run(runtime_config, available_nodes)
    after
      restore_runtime_config(available_nodes, previous_config)
    end
  end

  @doc """
  Runs the demo
  """
  def start(_type, _args) do
    if not iex_started?() do
      start([])
    end

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link([], opts)
  end

  defp run(runtime_config, available_nodes) do
    {:ok, target_neuron, _} = new_neuron_connected_to(self())
    IO.puts("Started top level: #{inspect(target_neuron)}")

    n = runtime_config.number_of_neurons

    IO.puts("Number of neurons: #{n}")

    started_neurons =
      n
      |> allocate_neurons(available_nodes)
      |> start_neurons(target_neuron)

    startup_summary = startup_summary(started_neurons)
    IO.inspect(startup_summary, label: "Neuron startup per node")

    startup_barrier = startup_barrier_report(started_neurons)
    IO.inspect(
      %{
        nodes_reported: startup_barrier.nodes_reported,
        startup_complete: startup_barrier.startup_complete
      },
      label: "Experiment startup barrier"
    )

    connect_neurons(started_neurons, target_neuron)

    prediction_triggered_at_ms = System.system_time(:millisecond)

    IO.inspect(
      %{
        starts_after_all_neurons_started:
          prediction_triggered_at_ms >= startup_barrier.all_neurons_started_by_ms
      },
      label: "Experiment trigger"
    )

    target_neuron |> Neuron.please_predict()

    # just once for the demo
    wait_for_reply(runtime_config)

    IO.puts("stopping")
  end

  defp wait_for_reply(runtime_config) do
    receive do
      {:prediction,
       %{delay: delay, input_count: input_count, prediction: prediction}} ->
        prediction_summary =
          %{
            value: Keyword.get(prediction, :value),
            reason: Keyword.get(prediction, :reason),
            inputs_used: Keyword.get(prediction, :inputs_used)
          }
          |> maybe_put_deadline_remaining(prediction)
          |> maybe_put_prediction_deadline(prediction)
          |> maybe_put_prediction_quiescence_deadline(prediction)

        IO.inspect(%{delay: delay, input_count: input_count, prediction: prediction_summary},
          label: "received prediction"
        )

      _unknown ->
        IO.puts("received an unexpected reply")
    after
      runtime_config.demo_reply_timeout_ms ->
        IO.inspect(
          %{
            reply_received: false,
            timed_out_after_ms: runtime_config.demo_reply_timeout_ms,
            increase: :demo_reply_timeout_ms,
            current_prediction_deadline_ms: runtime_config.prediction_deadline_ms
          },
          label: "Demo reply timeout"
        )

        false
    end
  end

  @doc false
  def allocate_neurons(total_neurons, nodes) when total_neurons >= 0 and nodes != [] do
    nodes
    |> Enum.uniq()
    |> Map.new(&{&1, 0})
    |> do_allocate_neurons(total_neurons)
  end

  @doc false
  def spawn_neurons_for_demo(0, _outgoing_pid), do: []

  @doc false
  def spawn_neurons_for_demo(count, outgoing_pid) when count >= 0 do
    1..count
    |> Enum.map(fn _ ->
      {:ok, pid} = Task.start(Neuron, :start, [outgoing_pid])
      pid
    end)
  end

  @doc false
  def spawn_neurons_with_metrics_for_demo(count, outgoing_pid) when count >= 0 do
    started_at_ms = System.system_time(:millisecond)
    started_at_mono = System.monotonic_time(:millisecond)
    neurons = spawn_neurons_for_demo(count, outgoing_pid)

    %{
      node: Node.self(),
      neurons: neurons,
      started_count: count,
      started_at_ms: started_at_ms,
      duration_ms: System.monotonic_time(:millisecond) - started_at_mono
    }
  end

  defp new_neuron_connected_to(pid) do
    {:ok, pid} = Task.start(Neuron, :start, [pid])
    {:ok, pid, Node.self()}
  end

  defp do_allocate_neurons(node_counts, 0), do: node_counts

  defp do_allocate_neurons(node_counts, remaining) do
    selected_node =
      node_counts
      |> Map.keys()
      |> Enum.take_random(1)
      |> hd()

    node_counts
    |> Map.update!(selected_node, &(&1 + 1))
    |> do_allocate_neurons(remaining - 1)
  end

  defp start_neurons(node_counts, target_neuron) do
    node_counts
    |> Task.async_stream(
      fn {node_name, count} ->
        ensure_remote_modules_loaded(node_name, [__MODULE__, Neuron])

        {node_name, spawn_neurons_on_node(node_name, count, target_neuron)}
      end,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, {node_name, startup_report}} -> {node_name, startup_report}
      {:exit, reason} -> raise "failed to start neurons: #{inspect(reason)}"
    end)
    |> Map.new()
  end

  defp spawn_neurons_on_node(_node_name, 0, target_neuron),
    do: spawn_neurons_with_metrics_for_demo(0, target_neuron)

  defp spawn_neurons_on_node(node_name, count, target_neuron) do
    if node_name == Node.self() do
      spawn_neurons_with_metrics_for_demo(count, target_neuron)
    else
      case :rpc.call(
             node_name,
             __MODULE__,
             :spawn_neurons_with_metrics_for_demo,
             [count, target_neuron],
             :infinity
           ) do
        {:badrpc, reason} -> raise "failed to start neurons on #{inspect(node_name)}: #{inspect(reason)}"
        startup_report -> startup_report
      end
    end
  end

  defp ensure_remote_modules_loaded(node_name, modules) do
    if node_name == Node.self() do
      :ok
    else
      Enum.each(modules, fn module ->
        case :code.get_object_code(module) do
          {^module, binary, beam_path} ->
            case :rpc.call(node_name, :code, :load_binary, [module, beam_path, binary], :infinity) do
              {:module, ^module} -> :ok
              {:error, reason} -> raise "failed to load #{inspect(module)} on #{inspect(node_name)}: #{inspect(reason)}"
              {:badrpc, reason} -> raise "failed to reach #{inspect(node_name)} while loading #{inspect(module)}: #{inspect(reason)}"
            end

          :error ->
            raise "unable to read beam code for #{inspect(module)}"
        end
      end)
    end
  end

  defp connect_neurons(started_neurons, target_neuron) do
    started_neurons
    |> Map.values()
    |> Enum.flat_map(& &1.neurons)
    |> Enum.each(&Neuron.connect_input_from(target_neuron, &1))
  end

  defp startup_summary(started_neurons) do
    started_neurons
    |> Enum.sort_by(fn {node_name, _report} -> Atom.to_string(node_name) end)
    |> Enum.map(fn {node_name, report} ->
      {node_name, %{started: report.started_count, duration_ms: report.duration_ms}}
    end)
    |> Map.new()
  end

  defp startup_barrier_report(started_neurons) do
    all_neurons_started_by_ms =
      started_neurons
      |> Map.values()
      |> Enum.map(&(&1.started_at_ms + &1.duration_ms))
      |> Enum.max(fn -> System.system_time(:millisecond) end)

    %{
      all_neurons_started_by_ms: all_neurons_started_by_ms,
      barrier_observed_at_ms: System.system_time(:millisecond),
      nodes_reported: map_size(started_neurons),
      startup_complete: true
    }
  end

  defp resolve_runtime_config(overrides) do
    overrides =
      overrides
      |> Enum.into([])
      |> Keyword.validate!(@config_keys)

    Map.new(@config_keys, fn key ->
      {key, Keyword.get(overrides, key, Application.fetch_env!(:elixir_ne, key))}
    end)
  end

  defp apply_runtime_config(nodes, runtime_config) do
    Enum.map(nodes, fn node_name ->
      previous_values = Enum.map(@config_keys, &{&1, fetch_config_from_node(node_name, &1)})

      Enum.each(runtime_config, fn {key, value} ->
        put_config_on_node(node_name, key, value)
      end)

      {node_name, previous_values}
    end)
    |> Map.new()
  end

  defp restore_runtime_config(nodes, previous_config) do
    Enum.each(nodes, fn node_name ->
      previous_config
      |> Map.fetch!(node_name)
      |> Enum.each(fn {key, value} -> put_config_on_node(node_name, key, value) end)
    end)
  end

  defp fetch_config_from_node(node_name, key) do
    if node_name == Node.self() do
      Application.fetch_env!(:elixir_ne, key)
    else
      case :rpc.call(node_name, Application, :fetch_env!, [:elixir_ne, key], :infinity) do
        {:badrpc, reason} -> raise "failed to fetch config #{inspect(key)} from #{inspect(node_name)}: #{inspect(reason)}"
        value -> value
      end
    end
  end

  defp put_config_on_node(node_name, key, value) do
    if node_name == Node.self() do
      Application.put_env(:elixir_ne, key, value)
    else
      case :rpc.call(node_name, Application, :put_env, [:elixir_ne, key, value], :infinity) do
        {:badrpc, reason} -> raise "failed to set config #{inspect(key)} on #{inspect(node_name)}: #{inspect(reason)}"
        _result -> :ok
      end
    end
  end

  defp iex_started? do
    Code.ensure_loaded?(IEx) and function_exported?(IEx, :started?, 0) and IEx.started?()
  end

  defp maybe_put_deadline_remaining(summary, prediction) do
    case Keyword.get(prediction, :deadline_remaining_ms) do
      nil -> summary
      remaining -> Map.put(summary, :deadline_remaining_ms, remaining)
    end
  end

  defp maybe_put_prediction_deadline(summary, prediction) do
    case Keyword.get(prediction, :prediction_deadline_ms) do
      nil -> summary
      deadline -> Map.put(summary, :prediction_deadline_ms, deadline)
    end
  end

  defp maybe_put_prediction_quiescence_deadline(summary, prediction) do
    case Keyword.get(prediction, :prediction_quiescence_deadline_ms) do
      nil -> summary
      quiescence -> Map.put(summary, :prediction_quiescence_deadline_ms, quiescence)
    end
  end
end
