defmodule SupChat do
  require Logger
  use DynamicSupervisor

  def start_link(name) do
    DynamicSupervisor.start_link(__MODULE__, [], name: String.to_atom(name))
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 50_000,
      max_seconds: 1
    )
  end

  def start_chat(sup_pid, chat_name, msg_type, discovery_pid) do
    args = %{sup_pid: sup_pid, name: chat_name, msg_type: msg_type, discovery_pid: discovery_pid}
    DynamicSupervisor.start_child(sup_pid, {Chat, args})
  end

  def stop_chat(sup_pid, pid) do
    DynamicSupervisor.terminate_child(sup_pid, pid)
  end
end
