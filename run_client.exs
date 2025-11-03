defmodule Client do
  def start do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║       🚗 URBANFLEET CLIENT SYSTEM       ║
    ╚════════════════════════════════════════╝
    Welcome to UrbanFleet!
    Type 'help' to view available commands.
    """)

    # Conexión al nodo remoto
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

  # ============================================================
  # CLI Loop principal
  # ============================================================

  defp command_loop(pid, role \\ nil) do
    prompt =
      case role do
        :client -> IO.ANSI.green() <> "[Cliente] > " <> IO.ANSI.reset()
        :driver -> IO.ANSI.yellow() <> "[Conductor] > " <> IO.ANSI.reset()
        _ -> IO.ANSI.cyan() <> "[Invitado] > " <> IO.ANSI.reset()
      end

    input = IO.gets(prompt)

    case input do
      nil ->
        IO.puts("\n👋 Cerrando cliente...")
        :ok

      raw ->
        cmd = String.trim(raw)

        case cmd do
          "exit" ->
            IO.puts("👋 Desconectando cliente...")

          "help" ->
            show_help(role)
            command_loop(pid, role)

          _ ->
            # Enviar comando al servidor remoto
            case :rpc.call(:"server@schwarz", GenServer, :call, [:server, {:remote_command, cmd}]) do
              :ok ->
                command_loop(pid, role)

              :exit ->
                IO.puts("👋 Sesión finalizada por el servidor.")

              {:badrpc, reason} ->
                IO.puts("⚠️ Error RPC: #{inspect(reason)}")

              other ->
                IO.inspect(other, label: "Respuesta del servidor")
                command_loop(pid, role)
            end
        end
    end
  end

  # ============================================================
  # HELP MENUS
  # ============================================================

  defp show_help(:client) do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║          📱 CLIENT COMMANDS             ║
    ╚════════════════════════════════════════╝
    request_trip origen=<loc> destino=<loc> - Request a trip
    my_score                                 - View your score
    ranking                                  - View global ranking
    disconnect                               - Disconnect
    help                                     - Show this help
    exit                                     - Exit session
    """)
  end

  defp show_help(:driver) do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║          🚕 DRIVER COMMANDS             ║
    ╚════════════════════════════════════════╝
    list_trips       - View available trips
    accept_trip <id> - Accept a trip
    my_score         - View your score
    ranking driver   - View driver ranking
    disconnect       - Disconnect
    help             - Show this help
    exit             - Exit session
    """)
  end

  defp show_help(nil) do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║         👋 WELCOME TO URBANFLEET        ║
    ╚════════════════════════════════════════╝
    connect <user> <pass> <client|driver> - Log in or register
    help                                  - Show this menu
    exit                                  - Close session
    """)
  end
end

Client.start()
