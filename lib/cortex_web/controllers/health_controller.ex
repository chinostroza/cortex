defmodule CortexWeb.HealthController do
  use CortexWeb, :controller

  def check(conn, _params) do
    # Obtener el estado de salud con timeout para evitar bloqueos
    health_status = try do
      case GenServer.call(Cortex.Workers.Pool, :health_status, 2000) do
        health when is_map(health) -> health
        _ -> %{}
      end
    catch
      :exit, _ -> %{}
    end
    
    # Calcular estado general
    {overall_status, http_code} = case health_status do
      health when map_size(health) == 0 ->
        {"no_workers", 503}
      
      health ->
        available_count = health
        |> Enum.count(fn {_name, status} -> status == :available end)
        
        total_count = map_size(health)
        
        cond do
          available_count == 0 -> {"unhealthy", 503}
          available_count < total_count -> {"degraded", 200}
          true -> {"healthy", 200}
        end
    end
    
    response = %{
      status: overall_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      workers: health_status,
      summary: %{
        total: map_size(health_status),
        available: Enum.count(health_status, fn {_name, status} -> status == :available end),
        unavailable: Enum.count(health_status, fn {_name, status} -> status != :available end)
      }
    }
    
    conn
    |> put_status(http_code)
    |> json(response)
  end
end