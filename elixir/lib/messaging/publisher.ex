defmodule Publisher do
  use GenServer
  require Logger

  # Configuration constants
  @reconnect_interval 5_000
  @exchange "events_exchange"
  @queue "events_queue"
  @bind "events.#"
  @rabbitmq_config [
    username: "guest",
    password: "guest",
    virtual_host: "/",
    host: "localhost",
    port: 5672
  ]

  # Client API
  def start_link(args) do
    name = String.to_atom(args.name)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def send_event(publisher_pid, timestamp, event_type, value \\ 0, name) do
    GenServer.cast(publisher_pid, {:publish, timestamp, event_type, value, name})
  end

  # Server Callbacks

  @impl GenServer
  def init(args) do
    case setup_rabbitmq_connection() do
      {:ok, conn, chan} ->
        Logger.info("Connected to RabbitMQ")
        {:ok, %{connection: conn, channel: chan, test_id: args.test_id}}

      {:error, reason} ->
        Logger.error("Failed to connect to RabbitMQ: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, @reconnect_interval)
        {:ok, %{connection: nil, channel: nil, test_id: args.test_id}}
    end
  end

  @impl GenServer
  def handle_cast({:publish, timestamp, event_type, value, name}, state) do
    new_event = Event.new(state.test_id, timestamp, event_type, value, name)

    case publish_event(new_event, state.channel) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to publish event: #{inspect(reason)}")
        {:noreply, %{state | connection: nil, channel: nil}}
    end
  end

  @impl GenServer
  def handle_info(:retry_connect, state) do
    case setup_rabbitmq_connection() do
      {:ok, conn, chan} ->
        Logger.info("Successfully reconnected to RabbitMQ")
        {:noreply, %{state | connection: conn, channel: chan}}

      {:error, reason} ->
        Logger.error("Reconnection attempt failed: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, %{connection: conn}) do
    if conn, do: AMQP.Connection.close(conn)
    :ok
  end

  # Private Functions

  defp setup_rabbitmq_connection do
    with {:ok, conn} <- AMQP.Connection.open(@rabbitmq_config),
         {:ok, chan} <- AMQP.Channel.open(conn),
         :ok <- setup_exchange_and_queue(chan) do
      {:ok, conn, chan}
    else
      error -> {:error, error}
    end
  end

  defp setup_exchange_and_queue(channel) do
    try do
      AMQP.Exchange.declare(channel, @exchange, :topic, durable: true)
      AMQP.Queue.declare(channel, @queue, durable: true)
      AMQP.Queue.bind(channel, @queue, @exchange, routing_key: @bind)
      :ok
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp publish_event(event, channel) do
    with {:ok, payload} <- Jason.encode(event),
         routing_key = generate_routing_key(event),
         properties = [content_type: "application/json", delivery_mode: 2] do
      try do
        AMQP.Basic.publish(channel, @exchange, routing_key, payload, properties)
        :ok
      rescue
        e -> {:error, e}
      catch
        :exit, reason -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_routing_key(event) do
    "events.server.#{event.event}"
  end
end
