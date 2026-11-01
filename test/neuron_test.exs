defmodule NeuronTest do
  use ExUnit.Case

  alias Neuron

  test "counts every vote of a batch as an input that was used" do
    neuron = start_collecting_neuron()
    input_answering(neuron, [{:prediction_batch, [10.0, 20.0, 30.0]}])

    Neuron.please_predict(neuron)

    assert_receive {:prediction, %{prediction: prediction}}, 1_000
    assert prediction[:inputs_used] == 3
    assert prediction[:reason] == :all_received
  end

  test "a message that is not a vote does not stand in for a vote" do
    neuron = start_collecting_neuron()
    input_answering(neuron, [:not_a_vote, {:prediction_batch, [42.0]}])

    Neuron.please_predict(neuron)

    assert_receive {:prediction, %{prediction: prediction}}, 1_000
    assert prediction[:value] == 42.0
    assert prediction[:inputs_used] == 1
  end

  defp start_collecting_neuron do
    {:ok, neuron} = Task.start(Neuron, :start, [self()])
    neuron
  end

  # connects an input that knows the collecting neuron, so it can answer it
  defp input_answering(collector, messages) do
    input =
      spawn_link(fn ->
        receive do
          {:predict} -> Enum.each(messages, &send(collector, &1))
        end
      end)

    Neuron.connect_input_from(collector, input)
  end
end
