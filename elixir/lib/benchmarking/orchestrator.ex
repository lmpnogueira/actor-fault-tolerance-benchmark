defmodule Orchestrator do
  use GenServer
  require Logger

  @default_startup_delay 300
  @setup_buffer_time 20

  @servers_node :"servers@127.0.0.1"
  @clients_node :"clients@127.0.0.1"

  # Client API

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def client_connected(pid) do
    GenServer.cast(pid, :client_connected)
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    Logger.info("[Main] Starting benchmarking system...")

    status_srv = Node.connect(@servers_node)
    Logger.info("[Main] Connection status with servers: #{status_srv}...")

    status_clients = Node.connect(@servers_node)
    Logger.info("[Main] Connection status with clients: #{status_clients}...")

    if status_clients != true or status_srv != true do
      exit(0)
    end

    {:ok, discovery_pid} = DiscoveryServer.start_link([])
    Process.sleep(@default_startup_delay)

    {:ok, publisher_pid} = start_publisher(args.test_id)
    state = init_state(args, publisher_pid, discovery_pid)

    {:ok, state, {:continue, :create_chats}}
  end

  @impl GenServer
  def handle_continue(:create_chats, state) do
    Logger.info("[Main] Creating test groups...")

    groups = create_test_groups(state)

    Logger.info("[Main] All #{state.num_sup} supervisors created")
    Logger.info("[Main] All #{state.total_chats} chats created")
    Logger.info("[Main] All #{state.total_clients} clients created")

    {:noreply, %{state | groups: groups}}
  end

  @impl GenServer
  def handle_cast(:client_connected, state) do
    new_state = %{state | connected_clients: state.connected_clients + 1}

    if all_clients_connected?(new_state) do
      Logger.info("[Main] All #{new_state.total_clients} clients connected")
      send(self(), :init_test)
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:init_test, state) do
    {init_time, end_time} = calculate_test_timeframe(state.duration)

    send_time_events(state.publisher_pid, init_time, end_time)
    Logger.info("[Main] Test will run from #{init_time} to #{end_time}")

    configure_test_timers(state.groups, init_time, end_time)
    Logger.info("[Main] Setup completed")

    {:noreply, state}
  end

  # Private functions

  defp init_state(args, publisher_pid, discovery_pid) do
    %{
      test_type: args.test_type,
      test_id: args.test_id,
      duration: args.duration,
      msg_type: args.msg_type,
      fault_pause: args.fault_pause,
      num_sup: args.num_sup,
      num_chat_per_sup: args.num_chat_per_sup,
      clients_per_server: args.clients_per_server,
      client_base_rate: args.client_base_rate,
      client_ceil_rate: args.client_ceil_rate,
      total_chats: args.num_sup * args.num_chat_per_sup,
      total_clients: args.num_sup * args.num_chat_per_sup * args.clients_per_server,
      connected_clients: 0,
      publisher_pid: publisher_pid,
      discovery_pid: discovery_pid,
      groups: %{}
    }
  end

  defp start_publisher(test_id) do
    publisher_args = %{name: "publisher_main", test_id: test_id}
    Publisher.start_link(publisher_args)
  end

  defp create_test_groups(state) do
    Enum.reduce(1..state.num_sup, %{}, fn sup_index, acc ->
      sup_name = "sup_#{sup_index}"

      sup_pid =
        case :rpc.call(@servers_node, ServersManager, :start_sup, [sup_name]) do
          {:ok, pid} ->
            Logger.info("Started SupChat remotely with PID #{inspect(pid)}")
            pid

          {:error, reason} ->
            Logger.error("Failed to start SupChat: #{inspect(reason)}")
            raise "Remote SupChat start failed: #{inspect(reason)}"

          {:badrpc, reason} ->
            Logger.error("RPC call to ServersManager failed: #{inspect(reason)}")
            raise "RPC error: #{inspect(reason)}"

          unexpected ->
            Logger.error("Unexpected RPC response: #{inspect(unexpected)}")
            raise "Unexpected RPC return"
        end

      group_list =
        create_chat_groups(
          sup_pid,
          sup_name,
          state.num_chat_per_sup,
          state.clients_per_server,
          state
        )

      Map.put(acc, sup_pid, group_list)
    end)
  end

  defp create_chat_groups(sup_pid, sup_name, chat_count, clients_per_chat, state) do
    Enum.map(1..chat_count, fn chat_index ->
      chat_topic = "#{sup_name}_chat_#{chat_index}"
      chat_topic_atom = String.to_atom(chat_topic)

      chat_pid =
        case :rpc.call(@servers_node, ServersManager, :start_chat, [
               sup_pid,
               chat_topic_atom,
               state.msg_type,
               state.discovery_pid
             ]) do
          {:ok, pid} ->
            Logger.info("Successfully started Chat on remote node with PID: #{inspect(pid)}")
            pid

          {:error, reason} = error ->
            Logger.info("ServersManager.start_chat failed on remote node: #{inspect(reason)}")
            exit(error)

          {:badrpc, reason} ->
            Logger.info("RPC call failed: #{inspect(reason)}")
            exit(reason)

          unexpected ->
            Logger.info("Received unexpected response from RPC call: #{inspect(unexpected)}")
            exit(unexpected)
        end

      injector_pid =
        create_fault_injector(
          chat_pid,
          chat_topic,
          state.test_type,
          state.fault_pause,
          state.msg_type,
          state.publisher_pid,
          state.discovery_pid
        )

      client_pids =
        create_clients(
          chat_pid,
          chat_topic,
          sup_pid,
          clients_per_chat,
          state
        )

      %{
        chat: chat_pid,
        injector: injector_pid,
        publisher: state.publisher_pid,
        clients: client_pids
      }
    end)
  end

  defp create_fault_injector(
         chat_pid,
         chat_topic,
         test_type,
         fault_pause,
         msg_type,
         publisher_pid,
         discovery_pid
       ) do
    injector_args = %{
      name: "injector_#{chat_topic}",
      wait_ms: fault_pause,
      test_type: test_type,
      chat_pid: chat_pid,
      chat_topic: chat_topic,
      msg_type: msg_type,
      publisher_pid: publisher_pid,
      discovery_pid: discovery_pid
    }

    injector_pid =
      case :rpc.call(@clients_node, ClientsManager, :start_injector, [injector_args]) do
        {:ok, pid} ->
          Logger.info("Started Injector remotely with PID #{inspect(pid)}")
          pid

        {:error, reason} ->
          Logger.error("Failed to start Injector: #{inspect(reason)}")
          raise "Remote SupChat start failed: #{inspect(reason)}"

        {:badrpc, reason} ->
          Logger.error("RPC call to Injector failed: #{inspect(reason)}")
          raise "RPC error: #{inspect(reason)}"

        unexpected ->
          Logger.error("Unexpected RPC response: #{inspect(unexpected)}")
          raise "Unexpected RPC return"
      end

    injector_pid
  end

  defp create_clients(chat_pid, chat_topic, sup_pid, client_count, state) do
    Enum.map(1..client_count, fn client_index ->
      client_args = %{
        test_type: state.test_type,
        username: "client_#{client_index}_#{chat_topic}",
        chat_topic: chat_topic,
        chat_pid: chat_pid,
        main_pid: self(),
        sup_pid: sup_pid,
        publisher_pid: state.publisher_pid,
        client_base_rate: state.client_base_rate,
        client_ceil_rate: state.client_ceil_rate,
        discovery_pid: state.discovery_pid
      }

      client_pid =
        case :rpc.call(@clients_node, ClientsManager, :start_client, [client_args]) do
          {:ok, pid} ->
            Logger.info("Started Client remotely with PID #{inspect(pid)}")
            pid

          {:error, reason} ->
            Logger.error("Failed to start Client: #{inspect(reason)}")
            raise "Remote SupChat start failed: #{inspect(reason)}"

          {:badrpc, reason} ->
            Logger.error("RPC call to Client failed: #{inspect(reason)}")
            raise "RPC error: #{inspect(reason)}"

          unexpected ->
            Logger.error("Unexpected RPC response: #{inspect(unexpected)}")
            raise "Unexpected RPC return"
        end

      client_pid
    end)
  end

  defp all_clients_connected?(state) do
    state.connected_clients == state.total_clients
  end

  defp calculate_test_timeframe(duration) do
    now = DateTime.utc_now()
    init_time = DateTime.add(now, @setup_buffer_time, :second)
    end_time = DateTime.add(init_time, duration + 1, :second)
    {init_time, end_time}
  end

  defp send_time_events(publisher_pid, init_time, end_time) do
    Publisher.send_event(
      publisher_pid,
      DateTime.to_unix(init_time, :millisecond),
      Event.test_started(),
      "main"
    )

    Publisher.send_event(
      publisher_pid,
      DateTime.to_unix(end_time, :millisecond),
      Event.end_info(),
      "main"
    )
  end

  defp configure_test_timers(groups, init_time, end_time) do
    Enum.each(groups, fn {_sup_pid, group_list} ->
      Enum.each(group_list, fn group ->
        Chat.end_test_info(group.chat, end_time)
        FaultInjector.end_test_info(group.injector, init_time, end_time)

        Enum.each(group.clients, fn client ->
          Client.test_info(client, init_time, end_time)
        end)
      end)
    end)
  end
end
