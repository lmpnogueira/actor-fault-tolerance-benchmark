defmodule FaultInjector do
  use GenServer
  require Logger

  @reconnect_delay 10

  ## Public API

  def start_link(args) do
    name = String.to_atom(args.name)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def inject_error(injector) do
    GenServer.cast(injector, :inject_error)
  end

  def end_test_info(injector, init_time, end_time) do
    GenServer.cast(injector, {:end_test_info, init_time, end_time})
  end

  ## GenServer Callbacks

  @impl true
  def init(args) do
    state = %{
      name: args.name,
      msg_type: args.msg_type,
      test_type: args.test_type,
      wait_ms: args.wait_ms,
      chat_pid: args.chat_pid,
      chat_topic: String.to_atom(args.chat_topic),
      chat_ref: nil,
      test_running: false,
      publisher_pid: args.publisher_pid,
      discovery_pid: args.discovery_pid,
      injection_counter: 0
    }

    # Monitor the chat process if provided
    state =
      if is_pid(args.chat_pid) do
        ref = Process.monitor(args.chat_pid)
        Logger.debug("[#{state.name}] Connected")
        %{state | chat_ref: ref}
      else
        Logger.warning(
          "[#{state.name}] No valid chat PID provided, will attempt to connect via discovery"
        )

        Process.send_after(self(), :retry_connect_to_chat, 0)
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_continue(:connect_chat, state) do
    case DiscoveryServer.get_chat(state.discovery_pid, state.chat_topic) do
      {:ok, pid} ->
        if Helper.pid_alive?(pid) do
          monitor_ref = Process.monitor(pid)
          new_state = %{state | chat_pid: pid, chat_ref: monitor_ref}
          Logger.debug("[#{state.name}] Connected")

          {:noreply, new_state}
        else
          Logger.warning(
            "[#{state.name}] Chat process #{inspect(pid)} exists but is not alive. Retrying..."
          )

          send(self(), :retry_connect_to_chat)
          {:noreply, state}
        end

      error ->
        Logger.debug("[#{state.name}] Chat not available: #{inspect(error)}. Retrying...")
        send(self(), :retry_connect_to_chat)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:inject_error, state) do
    if is_pid(state.chat_pid) and Helper.pid_alive?(state.chat_pid) and state.msg_type != :none do
      Logger.debug("[#{state.name}] sending faulty message")
      Chat.inject_error(state.chat_pid, state.msg_type)

      if(state.test_type == :detection_time) do
        Publisher.send_event(
          state.publisher_pid,
          Helper.now_timestamp(),
          Event.fault_injected(),
          state.injection_counter,
          state.chat_topic
        )
      end
    end

    if state.test_running do
      Process.send_after(self(), :inject_error_aux, state.wait_ms)
    end

    new_counter = state.injection_counter + 1
    {:noreply, %{state | injection_counter: new_counter}}
  end

  @impl true
  def handle_cast({:end_test_info, start_time, end_time}, state) do
    start_time_plus_fault = DateTime.add(start_time, state.wait_ms, :millisecond)
    left_init_ms = max(0, DateTime.diff(start_time_plus_fault, DateTime.utc_now(), :millisecond))
    Process.send_after(self(), :inject_error_aux, left_init_ms)

    left_end_ms = max(0, DateTime.diff(end_time, DateTime.utc_now(), :millisecond))
    Process.send_after(self(), :stop, left_end_ms)

    {:noreply, %{state | test_running: true}}
  end

  @impl true
  def handle_info(:inject_error_aux, state) do
    inject_error(self())
    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    Logger.debug("[#{state.name}] Stopping process...")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Process.send_after(self(), :retry_connect_to_chat, @reconnect_delay)
    Logger.debug("[#{state.name}] chat monitor trigger")

    {:noreply, %{state | chat_pid: nil, chat_ref: nil}}
  end

  @impl true
  def handle_info(:retry_connect_to_chat, state) do
    {:noreply, state, {:continue, :connect_chat}}
  end
end
