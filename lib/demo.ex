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
    :demo_reply_timeout_ms,
    :use_pythonx
  ]

  @type neuron_counts :: %{required(node()) => non_neg_integer()}
  @type startup_report :: %{
          required(:node) => node(),
          required(:neurons) => [pid()],
          required(:started_count) => non_neg_integer(),
          required(:started_at_ms) => integer(),
          required(:duration_ms) => non_neg_integer(),
          required(:node_rss_mb) => non_neg_integer(),
          optional(:pythonx_batch_voters) => pos_integer()
        }
  @type demo_options :: [
          number_of_neurons: non_neg_integer(),
          neuron_simulate_computation_ms: non_neg_integer(),
          prediction_deadline_ms: non_neg_integer(),
          prediction_quiescence_deadline_ms: non_neg_integer(),
          demo_reply_timeout_ms: non_neg_integer(),
          use_pythonx: boolean()
        ]

  @doc """
  Runs the demo using application config and env-derived defaults.
  """
  def start do
    start([])
  end

  @doc """
  Measures how much resident memory a run of `:number_of_neurons` neurons adds on
  this node, and extrapolates how many neurons fit into a gigabyte of that growth.

  It reports growth, not the absolute footprint, because a node's baseline is large
  and, with Pythonx, the interpreter is paid for once when it initializes — so the
  interpreter is warmed up before the baseline is taken.

  Options: `:number_of_neurons` (default `10_000`), `:use_pythonx` (default `true`).
  """
  def benchmark_ram(opts \\ []) do
    n = Keyword.get(opts, :number_of_neurons, 10_000)
    use_pythonx = Keyword.get(opts, :use_pythonx, true)
    nodes = [Node.self() | Node.list()]
    previous_config = apply_runtime_config(nodes, %{use_pythonx: use_pythonx})

    try do
      if use_pythonx, do: BatchVoter.votes_now(1)

      baseline_mb = NodeMemory.rss_mb()
      spawn_and_connect(n, nodes)
      growth_mb = NodeMemory.rss_mb() - baseline_mb
      kb_per_neuron = if n > 0, do: div(growth_mb * 1024, n), else: 0

      IO.inspect(
        %{
          neurons: n,
          use_pythonx: use_pythonx,
          growth_mb: growth_mb,
          kb_per_neuron: kb_per_neuron,
          neurons_per_gb_of_growth: neurons_per_gb_of_growth(kb_per_neuron)
        },
        label: "RAM benchmark"
      )
    after
      restore_runtime_config(nodes, previous_config)
    end
  end

  @doc """
  Reports what having a CPython interpreter in this node costs in memory.

  Pythonx embeds one interpreter per BEAM node, so this is a per-node number: ten
  interpreters mean ten nodes.
  """
  def measure_pythonx_ram do
    baseline_mb = NodeMemory.rss_mb()
    votes = BatchVoter.votes_now(1)
    interpreter_mb = NodeMemory.rss_mb() - baseline_mb

    IO.inspect(
      %{
        votes: votes,
        baseline_rss_mb: baseline_mb,
        interpreter_mb: interpreter_mb,
        note: "one interpreter per node; the first eval pays for it, later batches do not"
      },
      label: "Pythonx RAM on this node"
    )
  end

  @doc """
  Runs the demo with optional per-run overrides.

  Supported options:
  - `:number_of_neurons`
  - `:neuron_simulate_computation_ms`
  - `:prediction_deadline_ms`
  - `:prediction_quiescence_deadline_ms`
  - `:demo_reply_timeout_ms`
  - `:use_pythonx` – false = Neuron processes, Elixir votes (default); true = 1 BatchVoter per node, Python votes
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
    if not iex_started?() and not skip_auto_start?() do
      start([])
    end

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link([], opts)
  end

  defp skip_auto_start?, do: System.get_env("DEMO_SKIP_AUTO_START") == "1"

  defp run(runtime_config, available_nodes) do
    {started_neurons, target_neuron} =
      spawn_and_connect(runtime_config.number_of_neurons, available_nodes)

    IO.puts("Number of neurons: #{runtime_config.number_of_neurons}")
    IO.puts("Started top level: #{inspect(target_neuron)}")

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

    prediction_triggered_at_ms = System.system_time(:millisecond)

    IO.inspect(
      %{
        starts_after_all_neurons_started:
          prediction_triggered_at_ms >= startup_barrier.all_neurons_started_by_ms
      },
      label: "Experiment trigger"
    )

    Neuron.please_predict(target_neuron)

    wait_for_reply(runtime_config, python_interpreter_count(started_neurons))

    pythonx_run_summary(started_neurons)

    IO.puts("stopping")
  end

  defp spawn_and_connect(n, nodes) do
    {:ok, target_neuron, _} = new_neuron_connected_to(self())
    started_neurons = n |> allocate_neurons(nodes) |> start_neurons(target_neuron)
    connect_neurons(started_neurons, target_neuron)

    {started_neurons, target_neuron}
  end

  defp python_interpreter_count(started_neurons) do
    started_neurons
    |> Map.values()
    |> Enum.count(&Map.has_key?(&1, :pythonx_batch_voters))
  end

  defp wait_for_reply(runtime_config, python_interpreters) do
    receive do
      {:prediction, %{delay: delay, input_count: input_count, prediction: prediction}} ->
        prediction_summary =
          %{
            value: Keyword.get(prediction, :value),
            reason: Keyword.get(prediction, :reason),
            inputs_used: Keyword.get(prediction, :inputs_used)
          }
          |> maybe_put_deadline_remaining(prediction)
          |> maybe_put_prediction_deadline(prediction)
          |> maybe_put_prediction_quiescence_deadline(prediction)

        prediction_output = %{
          delay: delay,
          input_count: input_count,
          prediction: prediction_summary
        }

        prediction_output =
          if python_interpreters > 0 do
            Map.put(prediction_output, :python_interpreters, python_interpreters)
          else
            prediction_output
          end

        IO.inspect(prediction_output, label: "received prediction")

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
      duration_ms: System.monotonic_time(:millisecond) - started_at_mono,
      node_rss_mb: NodeMemory.rss_mb()
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
    if fetch_config_from_node(node_name, :use_pythonx) do
      do_spawn_batch_voters_on_node(node_name, count, target_neuron)
    else
      do_spawn_neurons_on_node(node_name, count, target_neuron)
    end
  end

  defp do_spawn_neurons_on_node(node_name, count, target_neuron) do
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
        {:badrpc, reason} ->
          raise "failed to start neurons on #{inspect(node_name)}: #{inspect(reason)}"

        startup_report ->
          startup_report
      end
    end
  end

  @doc false
  def spawn_batch_voters_with_metrics_for_demo(neuron_count, outgoing_pid)
      when neuron_count > 0 do
    started_at_ms = System.system_time(:millisecond)
    started_at_mono = System.monotonic_time(:millisecond)
    # 1 BatchVoter per node (Pythonx = 1 interpreter per node)
    {:ok, pid} = BatchVoter.start_link(outgoing_pid: outgoing_pid, batch_size: neuron_count)

    %{
      node: Node.self(),
      neurons: [pid],
      started_count: neuron_count,
      started_at_ms: started_at_ms,
      duration_ms: System.monotonic_time(:millisecond) - started_at_mono,
      pythonx_batch_voters: 1,
      node_rss_mb: NodeMemory.rss_mb()
    }
  end

  defp do_spawn_batch_voters_on_node(node_name, count, target_neuron) do
    if node_name == Node.self() do
      spawn_batch_voters_with_metrics_for_demo(count, target_neuron)
    else
      case :rpc.call(
             node_name,
             __MODULE__,
             :spawn_batch_voters_with_metrics_for_demo,
             [count, target_neuron],
             :infinity
           ) do
        {:badrpc, reason} ->
          raise "failed to start batch voters on #{inspect(node_name)}: #{inspect(reason)}"

        startup_report ->
          startup_report
      end
    end
  end

  defp ensure_remote_modules_loaded(node_name, modules) do
    all_modules = modules ++ [BatchVoter]

    if node_name == Node.self() do
      :ok
    else
      Enum.each(all_modules, fn module ->
        case :code.get_object_code(module) do
          {^module, binary, beam_path} ->
            case :rpc.call(node_name, :code, :load_binary, [module, beam_path, binary], :infinity) do
              {:module, ^module} ->
                :ok

              {:error, reason} ->
                raise "failed to load #{inspect(module)} on #{inspect(node_name)}: #{inspect(reason)}"

              {:badrpc, reason} ->
                raise "failed to reach #{inspect(node_name)} while loading #{inspect(module)}: #{inspect(reason)}"
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
    |> Enum.map(fn {node_name, report} -> {node_name, node_summary(report)} end)
    |> Map.new()
  end

  defp node_summary(report) do
    %{
      started: report.started_count,
      duration_ms: report.duration_ms,
      node_rss_mb: report.node_rss_mb
    }
    |> maybe_put_pythonx_voters(report)
  end

  defp maybe_put_pythonx_voters(summary, report) do
    case Map.fetch(report, :pythonx_batch_voters) do
      {:ok, voters} -> Map.put(summary, :pythonx_batch_voters, voters)
      :error -> summary
    end
  end

  # Printed after the prediction, so that every Pythonx node has initialized its
  # interpreter and the residency reported here includes it.
  defp pythonx_run_summary(started_neurons) do
    voter_reports =
      started_neurons
      |> Map.values()
      |> Enum.filter(&Map.has_key?(&1, :pythonx_batch_voters))

    if voter_reports != [] do
      rss_mb = Enum.map(voter_reports, &fetch_node_rss_mb(&1.node))

      IO.inspect(
        %{
          python_interpreters: length(voter_reports),
          node_rss_mb: %{
            min: Enum.min(rss_mb),
            max: Enum.max(rss_mb),
            avg: div(Enum.sum(rss_mb), length(rss_mb))
          },
          note: "OS-process residency; CPython is in-process and invisible to :erlang.memory/1"
        },
        label: "Pythonx run summary"
      )
    end
  end

  @doc false
  def node_rss_mb, do: NodeMemory.rss_mb()

  defp fetch_node_rss_mb(node_name) do
    if node_name == Node.self() do
      node_rss_mb()
    else
      case :rpc.call(node_name, __MODULE__, :node_rss_mb, [], :infinity) do
        {:badrpc, reason} ->
          raise "failed to read memory of #{inspect(node_name)}: #{inspect(reason)}"

        rss_mb ->
          rss_mb
      end
    end
  end

  defp neurons_per_gb_of_growth(0), do: :unbounded
  defp neurons_per_gb_of_growth(kb_per_neuron), do: div(1024 * 1024, kb_per_neuron)

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
        {:badrpc, reason} ->
          raise "failed to fetch config #{inspect(key)} from #{inspect(node_name)}: #{inspect(reason)}"

        value ->
          value
      end
    end
  end

  defp put_config_on_node(node_name, key, value) do
    if node_name == Node.self() do
      Application.put_env(:elixir_ne, key, value)
    else
      case :rpc.call(node_name, Application, :put_env, [:elixir_ne, key, value], :infinity) do
        {:badrpc, reason} ->
          raise "failed to set config #{inspect(key)} on #{inspect(node_name)}: #{inspect(reason)}"

        _result ->
          :ok
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
