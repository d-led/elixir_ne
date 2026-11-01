# Connect to worker nodes (node2, node3, ...) with retries, then run the demo.
# Called by scripts/run.sh with DEMO_SKIP_AUTO_START=1.
node_count = System.get_env("NODE_COUNT", "1") |> String.to_integer()
if node_count <= 1 do
  Demo.start([])
  System.halt(0)
end

workers = for i <- 2..node_count, do: :"node#{i}@127.0.0.1"
deadline = System.monotonic_time(:second) + 15

defmodule Connect do
  def wait(workers, deadline) do
    Enum.each(workers, &Node.connect/1)
    cond do
      Enum.all?(workers, &(&1 in Node.list())) -> :ok
      System.monotonic_time(:second) > deadline -> raise "timeout connecting to #{inspect(workers)}"
      true -> Process.sleep(500); wait(workers, deadline)
    end
  end
end
Connect.wait(workers, deadline)

Demo.start([])
System.halt(0)
