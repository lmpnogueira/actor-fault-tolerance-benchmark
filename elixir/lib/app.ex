defmodule ChatApp do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    test_id = Application.get_env(:chat_app, :test_id) || System.get_env("TEST_ID")
    role_str = System.get_env("ROLE")

    # Validate test_id
    if is_nil(test_id), do: raise("Missing required configuration: TEST_ID")
    if is_nil(role_str), do: raise("Missing required environment variable: ROLE")

    role =
      case String.to_atom(role_str) do
        :main -> :main
        :servers -> :servers
        :clients -> :clients
        _ -> raise "Invalid ROLE: #{role_str}"
      end

    IO.puts("Starting server node #{role}")
    IO.puts("Starting on node #{Node.self()}")

    # Load config

    config_file =
  System.get_env("BENCHMARK_CONFIG", "./../configs/config.yml")

    case ConfigReader.read_config(config_file) do
      {:ok, params} ->
        log_message = """

        ################## TEST [Elixir] ##################
        Test id: #{test_id}
        Test type: #{params.test_type}
        Test duration: #{params.test_duration_seconds} seconds
        Number of supervisors: #{params.num_supervisor}
        Chats per supervisor: #{params.chats_per_sup}
        Clients per server: #{params.clients_per_server}
        Message type: #{Models.FaultMessageType.to_string(params.msg_type)}
        Fault pause (ms): #{params.fault_pause_ms}
        ###################################################
        """

        Logger.info(log_message)

        args = %{
          test_type: params.test_type,
          test_id: test_id,
          duration: params.test_duration_seconds,
          msg_type: params.msg_type,
          fault_pause: params.fault_pause_ms,
          num_sup: params.num_supervisor,
          num_chat_per_sup: params.chats_per_sup,
          clients_per_server: params.clients_per_server,
          client_base_rate: params.client_base_rate,
          client_ceil_rate: params.client_ceil_rate
        }

        children =
          case role do
            :main -> [{Orchestrator, args}]
            :servers -> [ServersManager]
            :clients -> [ClientsManager]
          end

        Supervisor.start_link(children, strategy: :one_for_one, name: ChatApp.Supervisor)

      {:error, reason} ->
        Logger.error("Failed to start ChatApp: #{reason}")
        {:error, reason}
    end
  end
end
