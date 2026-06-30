defmodule Event do
  @derive Jason.Encoder
  defstruct [:test_id, :timestamp, :event, :value, :name]

  def new(test_id, timestamp, event, value \\ 0, name) do
    %Event{
      test_id: test_id,
      timestamp: timestamp,
      event: event,
      value: value,
      name: name
    }
  end

  def message_received, do: :message_received
  def test_started, do: :test_started
  def end_info, do: :end_info
  def client_reconnection_time, do: :client_reconnection_time
  def connected_time, do: :connected_time
  def fault_injected, do: :fault_injected
  def fault_detected, do: :fault_detected
end
