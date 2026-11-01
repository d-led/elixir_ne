defmodule BatchVoter do
  @moduledoc """
  One process standing in for a whole batch of voting neurons, letting CPython
  compute the votes.

  A node runs a single `BatchVoter` because Pythonx embeds one CPython interpreter
  per BEAM node. On a `{:predict}` request it asks CPython for one vote per neuron
  it stands in for and answers with a single `{:prediction_batch, votes}` message,
  which the requesting neuron collects like the votes of many separate neurons.

  The votes come from the same distribution as `Neuron`'s vote, so both vote paths
  can be compared directly.
  """

  use GenServer

  @vote_script """
  import random
  [abs(random.gauss(50, 20)) for _ in range(count)]
  """

  def start_link(opts) do
    outgoing_pid = Keyword.fetch!(opts, :outgoing_pid)
    batch_size = Keyword.fetch!(opts, :batch_size)
    GenServer.start_link(__MODULE__, %{outgoing_pid: outgoing_pid, batch_size: batch_size})
  end

  @doc """
  `count` votes, computed by CPython in a single eval.

  Starts Pythonx on first use: an unused interpreter should not be loaded, and a
  caller measuring interpreter memory needs the moment it becomes live.
  """
  @spec votes_now(non_neg_integer()) :: [float()]
  def votes_now(count) when is_integer(count) and count >= 0 do
    {:ok, _started} = Application.ensure_all_started(:pythonx)
    {result, _globals} = Pythonx.eval(@vote_script, %{"count" => count})

    case Pythonx.decode(result) do
      nil -> []
      votes -> votes
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info({:predict}, %{outgoing_pid: outgoing_pid, batch_size: batch_size} = state) do
    send(outgoing_pid, {:prediction_batch, votes_now(batch_size)})

    {:noreply, state}
  end
end
