defmodule NodeMemoryTest do
  use ExUnit.Case

  alias NodeMemory

  test "residency grows when the node holds a large binary" do
    before_mb = NodeMemory.rss_mb()

    large_binary = :binary.copy(:binary.copy(<<0>>, 1024), 64 * 1024)

    after_mb = NodeMemory.rss_mb()
    _still_referenced = byte_size(large_binary)

    assert after_mb >= before_mb + 32
  end

  test "reports the residency the operating system reports for this process" do
    {output, 0} =
      System.cmd("ps", ["-o", "rss=", "-p", :os.getpid() |> List.to_string()])

    os_report_mb = div(String.to_integer(String.trim(output)), 1024)

    assert_in_delta NodeMemory.rss_mb(), os_report_mb, 8
  end
end
