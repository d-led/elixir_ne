defmodule Neuron do
  def start(outgoing_pid) do
    state = {:state, [outgoing: outgoing_pid, incoming: []]}
    loop(state)
  end

  defp loop(state = {:state, [outgoing: outgoing_pid, incoming: incoming_pids]}) do
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
        send(outgoing_pid, prediction)

        # repeat until timeout
        loop(state)
    after
      # just exit
      1000 -> stop(incoming_pids)
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
  defp stop([]), do: false

  defp stop(_), do: IO.puts("Shutting down a neuron without incoming ones: #{inspect(self())}")

end
