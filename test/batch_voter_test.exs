defmodule BatchVoterTest do
  use ExUnit.Case

  alias BatchVoter

  @moduletag :pythonx

  test "asks for one vote per neuron it stands in for" do
    assert length(BatchVoter.votes_now(1_000)) == 1_000
  end

  test "asks for no votes when it stands in for no neurons" do
    assert BatchVoter.votes_now(0) == []
  end

  test "votes like a neuron does" do
    assert Enum.all?(BatchVoter.votes_now(100), &is_number/1)
  end

  test "answers a prediction request with the whole batch" do
    {:ok, voter} = BatchVoter.start_link(outgoing_pid: self(), batch_size: 7)

    send(voter, {:predict})

    assert_receive {:prediction_batch, votes}, 30_000
    assert length(votes) == 7
  end
end
