defmodule Neuron do
  # starting the receive loop
  def start(outgoing_pid) do
    state = {:state, %{outgoing: outgoing_pid, incoming: []}}
    expect_trigger(state)
  end

  # convenience function to request a prediction, which will be sent to outgoing_pid
  def please_predict(pid), do: send(pid, {:predict})
  def connect_input_from(pid, neuron), do: send(pid, {:connect, neuron})

  # a state, expecting connections and a request to predict
  defp expect_trigger(state = {:state, %{outgoing: outgoing_pid, incoming: incoming_pids}}) do
    receive do
      # connect and continue
      {:connect, neuron} ->
        expect_trigger({:state, %{outgoing: outgoing_pid, incoming: [neuron | incoming_pids]}})

      {:predict} ->
        # some demo parameters
        delay_ms = Application.get_env(:elixir_ne, :neuron_simulate_computation_ms)
        delay = round(delay_ms + 0.5 * :rand.uniform(delay_ms))

        # make a prediction
        prediction = predict(incoming_pids)

        # pretend to take time and energy
        :timer.sleep(delay)

        # return a prediction
        send(
          outgoing_pid,
          {:prediction,
           %{prediction: prediction, delay: delay, input_count: Enum.count(incoming_pids)}}
        )

        # repeat until timeout
        expect_trigger(state)
    after
      # just exit
      3_000 -> stop(incoming_pids)
    end
  end

  # on no incoming pids, just return the prediction
  defp predict([]), do: [value: prediction()]

  # request prediction (artificial) from other neurons
  defp predict(incoming_pids) do
    incoming_pids
    |> Enum.each(fn pid -> send(pid, {:predict}) end)

    deadline_ms =
      Application.fetch_env!(:elixir_ne, :prediction_deadline_ms)

    Process.send_after(self(), {:deadline}, deadline_ms)
    wait_for_predictions(Enum.count(incoming_pids))
  end

  # waiting for predictions (signature)
  defp wait_for_predictions(n, received_predictions \\ [])

  # just
  defp wait_for_predictions(0, received_predictions) do
    [
      value: Enum.max(received_predictions, fn -> -1 end),
      reason: :all_received,
      inputs_used: Enum.count(received_predictions)
    ]
  end

  # waiting for n more predictions
  defp wait_for_predictions(n, received_predictions) do
    receive do
      {:prediction, %{prediction: [value: value]}} ->
        # todo: e.g. a numerical threshold for the value
        wait_for_predictions(n - 1, [value | received_predictions])

      {:deadline} ->
        # IO.puts "received predictions: #{inspect(received_predictions)}"

        [
          value: Enum.max(received_predictions, fn -> -1 end),
          reason: :deadline,
          inputs_used: Enum.count(received_predictions)
        ]

      unknown ->
        IO.puts("received an unknown: #{inspect(unknown)}")
        wait_for_predictions(n - 1, [received_predictions])
    after
      # timeout
      200 ->
        [
          value: Enum.max(received_predictions, fn -> -1 end),
          reason: :timeout,
          inputs_used: Enum.count(received_predictions)
        ]
    end
  end

  # just a random number
  defp prediction, do: abs(:rand.normal(50, 20))

  # if there are no incoming pids, we're not a root neuron
  defp stop([]) do
    # IO.puts("X - #{inspect(self())}")
    false
  end

  defp stop(_), do: IO.puts("Shutting down a neuron without incoming ones: #{inspect(self())}")
end
