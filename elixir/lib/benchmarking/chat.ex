defmodule Chat do
  use GenServer
  require Logger

  @processing_delay 200

  ## Public API

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: args.name)
  end

  def connect(chat, client_pid) do
    GenServer.call(chat, {:connect, client_pid})
  end

  def message(chat, from, msg) do
    GenServer.cast(chat, {:message, from, msg})
  end

  def inject_error(chat, type) do
    # Process.exit(chat, :kill)
    GenServer.cast(chat, {:stop, type})
  end

  def end_test_info(chat, end_time) do
    GenServer.cast(chat, {:end_test_info, end_time})
  end

  ## GenServer Callbacks

  @impl true
  def init(args) do
    Logger.info("Starting chat #{args.name}")

    state = %{
      name: args.name,
      msg_type: args.msg_type,
      sup_pid: args.sup_pid,
      clients: MapSet.new(),
      client_monitors: %{},
      discovery_pid: args.discovery_pid,
      discovery_ref: nil
    }

    send(self(), :get_discovery)
    {:ok, state}
  end

  @impl true
  def handle_call({:connect, client_pid}, _from, state) do
    if MapSet.member?(state.clients, client_pid) do
      {:reply, {:error, :already_connected}, state}
    else
      ref = Process.monitor(client_pid)

      updated_state = %{
        state
        | clients: MapSet.put(state.clients, client_pid),
          client_monitors: Map.put(state.client_monitors, ref, client_pid)
      }

      {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_cast({:message, _from, _msg}, state) do
    Process.send_after(self(), :process_organic_message, @processing_delay)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:end_test_info, end_time}, state) do
    if state.msg_type != :error do
      delay = max(0, DateTime.diff(end_time, DateTime.utc_now(), :millisecond))
      Process.send_after(self(), :stop, delay)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:stop, _type}, state) do
    Process.exit(self(), :kill)
    {:noreply, state}
  end

  @impl true
  def handle_info(:get_discovery, state) do
    case get_discovery() do
      {:ok, {pid, ref}} ->
        Logger.debug(
          "[#{state.name}] Discovery found. PID: #{inspect(pid)}, Ref: #{inspect(ref)}"
        )

        send(self(), :register_chat)
        {:noreply, %{state | discovery_pid: pid, discovery_ref: ref}}

      {:error, reason} ->
        Logger.error("[#{state.name}] Discovery not found. Reason: #{inspect(reason)}")
        send(self(), :get_discovery)
        {:stop, :not_found, state}
    end
  end

  @impl true
  def handle_info(:register_chat, state) do
    case DiscoveryServer.register_chat(state.discovery_pid, state.name, state.sup_pid) do
      :ok ->
        Logger.info("[#{state.name}] Chat registered.")
        {:noreply, state}

      {:error, :name_already_in_use} ->
        Logger.error("[#{state.name}] Chat name already in use. Stopping.")
        send(self(), :register_chat)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:stop, state) do
    Logger.debug("[#{state.name}] Stopping Chat process.")
    SupChat.stop_chat(state.sup_pid, self())
    {:stop, :normal, state}
  end

  # Discovery DOWN
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{discovery_ref: ref} = state) do
    Logger.error("[#{state.name}] Discovery disconnected. Stopping ...")
    send(self(), :stop)
    {:noreply, state}
  end

  # Client DOWN
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.client_monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {client_pid, new_monitors} ->
        updated_state = %{
          state
          | clients: MapSet.delete(state.clients, client_pid),
            client_monitors: new_monitors
        }

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info(:process_organic_message, state) do
    Enum.each(state.clients, fn client_pid ->
      send(client_pid, {:receive_message, "pong"})
    end)

    {:noreply, state}
  end

  ## Private Helpers

  defp get_discovery do
    case Helper.discovery_pid() do
      discovery_pid when is_pid(discovery_pid) ->
        ref = Process.monitor(discovery_pid)
        {:ok, {discovery_pid, ref}}

      _ ->
        {:error, :discovery_not_found}
    end
  end
end
