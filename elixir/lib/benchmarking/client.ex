defmodule Client do
  use GenServer
  require Logger

  @next_msg_interval 200

  ## Public API

  def start_link(args) do
    name = String.to_atom(args.username)
    GenServer.start_link(__MODULE__, prepare_initial_state(args), name: name)
  end

  def send_message(client) do
    GenServer.cast(client, :send_message)
  end

  def test_info(client, init_time, end_time) do
    GenServer.cast(client, {:test_info, init_time, end_time})
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    Logger.info("[#{state.name}] Starting ...")
    send(self(), :connect_chat)
    {:ok, state}
  end

  @impl true
  def handle_cast(:send_message, state) do
    if state.chat_pid != nil and state.test_type == :throughput do
      Chat.message(state.chat_pid, self(), "ping")
    end

    Process.send_after(self(), :send_next_message, @next_msg_interval)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:test_info, start_time, end_time}, state) do
    left_init_ms = max(0, DateTime.diff(start_time, DateTime.utc_now(), :millisecond))
    left_end_ms = max(0, DateTime.diff(end_time, DateTime.utc_now(), :millisecond))

    Process.send_after(self(), :start_test, left_init_ms)
    Process.send_after(self(), :stop, left_end_ms)

    {:noreply, state}
  end

  @impl true
  def handle_info(:start_test, state) do
    new_state = %{state | started: true, test_active: true}

    if state.test_type == :throughput do
      send(self(), :send_next_message)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:connect_chat, state) do
    try do
      case DiscoveryServer.get_chat(state.discovery_pid, state.chat_topic) do
        {:ok, pid} when is_pid(pid) ->
          try do
            case Chat.connect(pid, self()) do
              :ok ->
                monitor_ref = Process.monitor(pid)

                Logger.debug(
                  "[#{state.name}] Client is connected to the chat. PID: #{inspect(pid)}, Ref: #{inspect(monitor_ref)}"
                )

                if state.disconnected_at, do: send_reconnection_event(state)

                new_state =
                  if not state.started do
                    Orchestrator.client_connected(state.main_pid)
                    %{state | started: true}
                  else
                    state
                  end

                final_state = %{
                  new_state
                  | chat_pid: pid,
                    chat_ref: monitor_ref,
                    disconnected_at: nil,
                    connected_at: DateTime.utc_now()
                }

                {:noreply, final_state}

              {:error, reason} ->
                Logger.error("[#{state.name}] Connection failed: #{inspect(reason)}")
                send(self(), :connect_chat)
                {:noreply, state}
            end
          catch
            error ->
              Logger.error("[#{state.name}] Connection error: #{inspect(error)}")
              send(self(), :connect_chat)
              {:noreply, state}
          end

        {:error, reason} ->
          Logger.error("[#{state.name}] Discovery error: #{inspect(reason)}")
          send(self(), :connect_chat)
          {:noreply, state}

        unexpected ->
          Logger.error("[#{state.name}] Unexpected discovery response: #{inspect(unexpected)}")
          send(self(), :stop)
          {:noreply, state}
      end
    catch
      :exit, {reason} ->
        Logger.error("[#{state.name}] Discovery process crashed: #{inspect(reason)}")
        send(self(), :stop)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:receive_message, _msg}, state) do
    if state.test_type == :throughput do
      Publisher.send_event(
        state.publisher_pid,
        Helper.now_timestamp(),
        Event.message_received(),
        0,
        state.name
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{chat_ref: ref} = state) do
    Logger.debug("[#{state.name}] Chat went down")

    if state.test_type == :reconnection_time and state.connected_at do
      send_connected_time_event(state)
    end

    if state.test_type == :detection_time do
      Publisher.send_event(
        state.publisher_pid,
        Helper.now_timestamp(),
        Event.fault_detected(),
        state.detection_count,
        state.chat_topic
      )
    end

    new_state = %{
      state
      | chat_pid: nil,
        chat_ref: nil,
        disconnected_at: DateTime.utc_now(),
        connected_at: nil,
        detection_count: state.detection_count + 1
    }

    send(self(), :connect_chat)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{discovery_ref: ref} = state) do
    Logger.error("[#{state.name}] Discovery disconnected. Stopping ...")
    send(self(), :stop)
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_next_message, state) do
    if state.test_active do
      GenServer.cast(self(), :send_message)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    Logger.debug("[#{state.name}] Stopping")

    timestamp =
      DateTime.utc_now()
      |> DateTime.add(1, :second)
      |> DateTime.to_unix(:millisecond)

    if state.test_type == :reconnection_time and state.connected_at do
      send_final_connected_time_event(state, timestamp)
    else
      Publisher.send_event(
        state.publisher_pid,
        timestamp,
        Event.message_received(),
        0,
        state.name
      )
    end

    {:stop, :normal, state}
  end

  ## Private Helpers

  defp prepare_initial_state(args) do
    %{
      test_type: args.test_type,
      name: String.to_atom(args.username),
      chat_topic: String.to_atom(args.chat_topic),
      chat_pid: nil,
      chat_ref: nil,
      main_pid: args.main_pid,
      sup_pid: args.sup_pid,
      publisher_pid: args.publisher_pid,
      started: false,
      test_active: false,
      disconnected_at: nil,
      connected_at: nil,
      discovery_pid: args.discovery_pid,
      discovery_ref: Process.monitor(args.discovery_pid),
      detection_count: 0
    }
  end

  defp send_connected_time_event(state) do
    connected_time_ms = DateTime.diff(DateTime.utc_now(), state.connected_at, :millisecond)

    Publisher.send_event(
      state.publisher_pid,
      Helper.now_timestamp(),
      Event.connected_time(),
      connected_time_ms,
      state.name
    )
  end

  defp send_final_connected_time_event(state, timestamp) do
    connected_time_ms = DateTime.diff(DateTime.utc_now(), state.connected_at, :millisecond)

    Publisher.send_event(
      state.publisher_pid,
      timestamp,
      Event.connected_time(),
      connected_time_ms,
      state.name
    )
  end

  defp send_reconnection_event(state) do
    reconnect_time_ms = DateTime.diff(DateTime.utc_now(), state.disconnected_at, :millisecond)

    Publisher.send_event(
      state.publisher_pid,
      Helper.now_timestamp(),
      Event.client_reconnection_time(),
      reconnect_time_ms,
      state.name
    )
  end
end
