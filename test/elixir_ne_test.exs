defmodule ElixirNeTest do
  use ExUnit.Case

  test "allocates all neurons across unique nodes" do
    allocations = Demo.allocate_neurons(100, [:"a@127.0.0.1", :"b@127.0.0.1", :"a@127.0.0.1"])

    assert Map.keys(allocations) |> Enum.sort() == Enum.sort([:"a@127.0.0.1", :"b@127.0.0.1"])
    assert Enum.sum(Map.values(allocations)) == 100
  end

  test "spawning zero neurons returns no pids" do
    assert Demo.spawn_neurons_for_demo(0, self()) == []
  end

  test "spawning with metrics reports zero neurons" do
    assert %{node: node_name, neurons: [], started_count: 0, started_at_ms: started_at_ms, duration_ms: duration_ms} =
             Demo.spawn_neurons_with_metrics_for_demo(0, self())

    assert node_name == Node.self()
    assert is_integer(started_at_ms)
    assert duration_ms >= 0
  end
end
