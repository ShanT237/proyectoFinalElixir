#!/usr/bin/env elixir

defmodule UrbanFleet.Client do
  def start do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║       🚗 URBANFLEET CLIENT SYSTEM       ║
    ╚════════════════════════════════════════╝
    Welcome to UrbanFleet!
    Type 'help' to view available commands.
    """)

    # Intentar conectar al servidor
    if Node.connect(:server@schwarz) do
      IO.puts("✅ Connected to UrbanFleet Server.")
      case :rpc.call(:server@schwarz, Process, :whereis, [:server]) do
        pid when is_pid(pid) ->
          IO.puts("🖥️  Remote server process found.")
          command_loop(pid, nil)

        _ ->
          IO.puts("⚠️ Server process not found. Make sure it's running.")
      end
    else
      IO.puts("❌ Could not connect to remote node (:server@schwarz)")
    end
  end

  # ============================================================
  # CLI LOOP
  # ============================================================

  defp command_loop(pid, user \\ nil) do
    prompt =
      case user do
        %{role: :client} -> IO.ANSI.green() <> "[Cliente] > " <> IO.ANSI.reset()
        %{role: :driver} -> IO.ANSI.yellow() <> "[Conductor] > " <> IO.ANSI.reset()
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
          "" ->
            command_loop(pid, user)

          "exit" ->
            IO.puts("👋 Desconectando cliente...")

          "help" ->
            show_help(user)
            command_loop(pid, user)

          _ ->
            # Enviar comando al servidor
            case :rpc.call(:server@schwarz, GenServer, :call, [:server, {:remote_command, cmd}]) do
              {:ok, response} ->
                # Mostrar el mensaje recibido
                IO.puts(response)

                # Si es login exitoso, actualizar el estado del cliente
                if String.contains?(response, "Registrado") or
                     String.contains?(response, "Bienvenido de nuevo") do
                  [_, username, _, role] = String.split(cmd)
                  new_user = %{username: username, role: String.to_atom(role)}
                  command_loop(pid, new_user)
                else
                  command_loop(pid, user)
                end

              {:error, response} ->
                IO.puts(response)
                command_loop(pid, user)

              {:badrpc, reason} ->
                IO.puts("⚠️ Error RPC: #{inspect(reason)}")
                command_loop(pid, user)

              other ->
                IO.inspect(other, label: "Respuesta desconocida del servidor")
                command_loop(pid, user)
            end
        end
    end
  end

  # ============================================================
  # HELP MENUS
  # ============================================================

  defp show_help(%{role: :client}) do
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

  defp show_help(%{role: :driver}) do
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

UrbanFleet.Client.start()
