defmodule ConfigReader do
  def read_config(file_path) do
    with {:ok, yaml_content} <- File.read(file_path),
         {:ok, yaml_map} <- YamlElixir.read_from_string(yaml_content),
         {:ok, params} <- extract_params(yaml_map) do
      {:ok, params}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def read_config!(file_path) do
    case read_config(file_path) do
      {:ok, params} -> params
      {:error, reason} -> raise "Failed to read config: #{inspect(reason)}"
    end
  end

  defp extract_params(%{"params" => params}) when is_map(params) do
    try do
      result =
        Models.Params.new(
          Map.get(params, "test_type"),
          Map.get(params, "test_duration_seconds"),
          Map.get(params, "num_supervisor"),
          Map.get(params, "chats_per_sup"),
          Map.get(params, "clients_per_server"),
          Map.get(params, "msg_type"),
          Map.get(params, "fault_pause_ms"),
          Map.get(params, "client_base_rate"),
          Map.get(params, "client_ceil_rate")
        )

      {:ok, result}
    rescue
      e in ArgumentError -> {:error, e.message}
      _ -> {:error, "Invalid or missing parameters in config"}
    end
  end

  defp extract_params(_) do
    {:error, "Missing or invalid 'params' section in config"}
  end
end
