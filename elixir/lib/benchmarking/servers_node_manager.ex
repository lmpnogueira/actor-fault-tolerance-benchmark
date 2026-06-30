defmodule ServersManager do
  use GenServer
  require Logger

  ## Public API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_sup(name) do
    GenServer.call(__MODULE__, {:start_sup, name})
  end

  def start_chat(sup_pid, chat_name, msg_type, discovery_pid) do
    GenServer.call(__MODULE__, {:start_chat, sup_pid, chat_name, msg_type, discovery_pid})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:start_chat, sup_pid, chat_name, msg_type, discovery_pid}, _from, state) do
    Logger.info("ServersManager starting Chat #{chat_name} under #{inspect(sup_pid)}")

    case SupChat.start_chat(sup_pid, chat_name, msg_type, discovery_pid) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:start_sup, name}, _from, state) do
    Logger.info("ServersManager starting SupChat: #{name}")

    case SupChat.start_link(name) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, Map.put(state, name, pid)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
