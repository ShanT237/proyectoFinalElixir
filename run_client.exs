defmodule Client do
  def start do
    IO.puts("🚗 Starting UrbanFleet CLIENT...")

    # Conéctate al nodo del servidor
    if Node.connect(:"server@schwarz") do
      IO.puts("✅ Conectado al servidor")

      # Verifica que el proceso :server exista
      case :rpc.call(:"server@schwarz", Process, :whereis, [:server]) do
        pid when is_pid(pid) ->
          IO.puts("✅ Servidor encontrado: #{inspect(pid)}")
          command_loop(pid)

        _ ->
          IO.puts("⚠️ No se encontró el proceso :server en el nodo remoto")
      end
    else
      IO.puts("❌ No se pudo conectar al nodo remoto")
    end
  end

  # CLI para enviar comandos
  defp command_loop(pid) do
    input = IO.gets("\n[cliente] > ") |> String.trim()

    case input do
      "exit" ->
        IO.puts("👋 Desconectando cliente...")

      _ ->
        case :rpc.call(:"server@schwarz", GenServer, :call, [:server, {:remote_command, input}]) do
          :ok -> command_loop(pid)
          :exit -> IO.puts("👋 Sesión finalizada por el servidor.")
          {:badrpc, reason} -> IO.puts("⚠️ Error RPC: #{inspect(reason)}")
          other -> IO.inspect(other, label: "Respuesta del servidor")
        end
    end
  end
end

Client.start()
