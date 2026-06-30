defmodule Models.FaultMessageType do
  @type t :: :cpu_intensive | :ram_intensive | :error | :random | :none

  @spec from_string(String.t()) :: t()
  def from_string(value) do
    case value do
      "cpu_intensive" -> :cpu_intensive
      "ram_intensive" -> :ram_intensive
      "error" -> :error
      "random" -> :random
      "none" -> :none
      _ -> raise ArgumentError, "Invalid FaultMessageType: #{value}"
    end
  end

  @spec to_string(t()) :: String.t()
  def to_string(type) do
    case type do
      :cpu_intensive -> "cpu_intensive"
      :ram_intensive -> "ram_intensive"
      :error -> "error"
      :random -> "random"
      :none -> "none"
    end
  end
end

defmodule Models.TestType do
  @type t :: :throughput | :reconnection_time | :detection_time

  @spec from_string(String.t()) :: t()
  def from_string(value) do
    case value do
      "throughput" -> :throughput
      "reconnection_time" -> :reconnection_time
      "detection_time" -> :detection_time
      _ -> raise ArgumentError, "Invalid TestType: #{value}"
    end
  end

  @spec to_string(t()) :: String.t()
  def to_string(type) do
    case type do
      :throughput -> "throughput"
      :reconnection_time -> "reconnection_time"
      :detection_time -> "detection_time"
    end
  end
end

defmodule Models.Params do
  @enforce_keys [
    :test_type,
    :test_duration_seconds,
    :num_supervisor,
    :chats_per_sup,
    :clients_per_server,
    :msg_type,
    :fault_pause_ms,
    :client_base_rate,
    :client_ceil_rate
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          test_type: Models.TestType.t(),
          test_duration_seconds: integer(),
          num_supervisor: integer(),
          chats_per_sup: integer(),
          clients_per_server: integer(),
          msg_type: Models.FaultMessageType.t(),
          fault_pause_ms: integer(),
          client_base_rate: integer(),
          client_ceil_rate: integer()
        }

  @spec new(
          test_type :: Models.TestType.t(),
          test_duration_seconds :: integer(),
          num_supervisor :: integer(),
          chats_per_sup :: integer(),
          clients_per_server :: integer(),
          msg_type :: Models.FaultMessageType.t() | String.t(),
          fault_pause_ms :: integer(),
          client_base_rate :: integer(),
          client_ceil_rate :: integer()
        ) :: t()
  def new(
        test_type,
        test_duration_seconds,
        num_supervisor,
        chats_per_sup,
        clients_per_server,
        msg_type,
        fault_pause_ms,
        client_base_rate,
        client_ceil_rate
      ) do
    msg_type =
      if is_binary(msg_type), do: Models.FaultMessageType.from_string(msg_type), else: msg_type

    test_type =
      if is_binary(test_type), do: Models.TestType.from_string(test_type), else: test_type

    %__MODULE__{
      test_type: test_type,
      test_duration_seconds: test_duration_seconds,
      num_supervisor: num_supervisor,
      chats_per_sup: chats_per_sup,
      clients_per_server: clients_per_server,
      msg_type: msg_type,
      fault_pause_ms: fault_pause_ms,
      client_base_rate: client_base_rate,
      client_ceil_rate: client_ceil_rate
    }
  end
end
