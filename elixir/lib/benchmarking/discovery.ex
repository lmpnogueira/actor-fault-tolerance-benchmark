defmodule DiscoveryServer do
  use GenServer
  require Logger

  @registry_name {:global, __MODULE__}

  ## Public API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @registry_name)
  end

  def register_chat(discovery_pid, name, sup_pid) do
    GenServer.call(discovery_pid, {:register, name, sup_pid})
  end

  def get_chat(discovery_pid, name) do
    GenServer.call(discovery_pid, {:get_chat, name})
  end

  ## GenServer Callbacks

  @impl true
  def init(_) do
    Logger.info("[DiscoveryServer] Ready to accept registrations")
    {:ok, %{chats: %{}, refs: %{}}}
  end

  @impl true
  def handle_call({:register, name, sup_pid}, {pid, _}, state) do
    case Map.fetch(state.chats, name) do
      :error ->
        ref = Process.monitor(pid)

        updated_chats = Map.put(state.chats, name, {pid, ref, sup_pid})
        updated_refs = Map.put(state.refs, ref, name)

        updated_state = %{state | chats: updated_chats, refs: updated_refs}

        {:reply, :ok, updated_state}

      {:ok, {_existing_pid, _existing_ref, _}} ->
        {:reply, {:error, :name_already_in_use}, state}
    end
  end

  @impl true
  def handle_call({:get_chat, name}, _from, state) do
    case Map.fetch(state.chats, name) do
      {:ok, {pid, _ref, _sup_pid}} ->
        if Helper.pid_alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          {:reply, {:error, :process_not_alive}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.fetch(state.refs, ref) do
      {:ok, name} ->
        updated_state = %{
          state
          | chats: Map.delete(state.chats, name),
            refs: Map.delete(state.refs, ref)
        }

        {:noreply, updated_state}

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:end_test_info, end_time}, state) do
    ms_until_end = max(0, DateTime.diff(end_time, DateTime.utc_now(), :millisecond))
    Process.send_after(self(), :stop, ms_until_end)

    {:noreply, state}
  end
end
