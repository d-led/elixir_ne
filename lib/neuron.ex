defmodule Neuron do
  # starting the receive loop
  def start(outgoing_pid) do
    state = {:state, [outgoing: outgoing_pid, incoming: []]}
    expect_trigger(state)
  end

  # convenience function to request a prediction, which will be sent to outgoing_pid
  def please_predict(pid), do: send(pid, {:predict})

  defp expect_trigger(state = {:state, [outgoing: outgoing_pid, incoming: incoming_pids]}) do
    receive do
      {:predict} ->
        # some demo parameters
        delay_ms = 100
        delay = round(delay_ms + 0.1 * :rand.uniform(delay_ms))

        # pretend to take time and energy
        :timer.sleep(delay)

        # do a prediction
        prediction = predict(incoming_pids)

        # return a prediction
        send(
          outgoing_pid,
          {:prediction,
           [prediction: prediction, delay: delay, input_count: Enum.count(incoming_pids)]}
        )

        # repeat until timeout
        expect_trigger(state)
    after
      # just exit
      3_000 -> stop(incoming_pids)
    end
  end

  # on no incoming pids, just return the prediction
  defp predict([]), do: prediction()

  # request prediction (artificial) from other neurons
  defp predict(incoming_pids) do
    incoming_pids
    |> Enum.each(fn pid -> send(pid, {:predict}) end)

    # todo: expect other predictions
    prediction()
  end

  # just a random number
  defp prediction, do: :rand.uniform(1000)

  # if there are no incoming pids, we're not a root neuron
  defp stop([]), do: IO.puts("X - #{inspect(self())}")
  false

  defp stop(_), do: IO.puts("Shutting down a neuron without incoming ones: #{inspect(self())}")
end
