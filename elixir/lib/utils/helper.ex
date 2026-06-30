defmodule Helper do
  def discovery_pid do
    :global.whereis_name(DiscoveryServer)
  end

  def now_timestamp do
    DateTime.to_unix(DateTime.utc_now(), :millisecond)
  end

  def pid_alive?(pid) when is_pid(pid) do
    case node(pid) do
      # Local PID
      node when node == node() ->
        Process.alive?(pid)

      # Remote PID
      remote_node ->
        case :rpc.call(remote_node, Process, :alive?, [pid]) do
          true -> true
          false -> false
          {:badrpc, _} -> false
        end
    end
  end
end
