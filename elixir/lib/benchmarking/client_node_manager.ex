defmodule ClientsManager do
  use GenServer
  require Logger

  ## Public API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_client(client_args) do
    GenServer.call(__MODULE__, {:start_client, client_args})
  end

  def start_injector(injector_args) do
    GenServer.call(__MODULE__, {:start_injector, injector_args})
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:start_client, args}, _from, state) do
    # Logger.info("ClientsManager starting Client with args: #{inspect(args)}")

    case Client.start_link(args) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:start_injector, args}, _from, state) do
    # Logger.info("ClientsManager starting FaultInjector with args: #{inspect(args)}")

    case FaultInjector.start_link(args) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
