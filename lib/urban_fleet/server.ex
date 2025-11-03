defmodule UrbanFleet.Server do
  use GenServer
  require Logger

  # ==============================
  # CLIENT API
  # ==============================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: :server)
  end

  def start_cli do
    GenServer.cast(__MODULE__, :start_cli)
  end

  # ==============================
  # SERVER CALLBACKS
  # ==============================

  @impl true
  def init(_) do
    Logger.info("UrbanFleet Server started")
    {:ok, %{current_user: nil, sessions: %{}}}
  end

  @impl true
  def handle_cast(:start_cli, state) do
    spawn(fn ->
      show_server_banner()
      cli_loop(nil)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:remote_command, input}, _from, state) do
    input
    |> String.trim()
    |> process_command(state[:current_user])
    |> case do
      {:continue, new_user} ->
        {:reply, :ok, %{state | current_user: new_user}}

      :exit ->
        {:reply, :exit, state}
    end
  end

  @impl true
  def handle_info({:new_client, pid}, state) do
    Logger.info("Nuevo cliente conectado: #{inspect(pid)}")
    {:noreply, state}
  end

  # ==============================
  # CLI LOOP
  # ==============================

  defp cli_loop(current_user) do
    prompt =
      if current_user do
        IO.ANSI.green() <>
          "[#{current_user.username}@#{Atom.to_string(current_user.role)}] > " <>
          IO.ANSI.reset()
      else
        IO.ANSI.cyan() <> "[server-admin] > " <> IO.ANSI.reset()
      end

    IO.write(prompt)

    case IO.gets("") do
      :eof ->
        IO.puts("\n👋 Saliendo del servidor...")
        :ok

      {:error, reason} ->
        IO.puts("⚠️ Error leyendo entrada: #{inspect(reason)}")
        cli_loop(current_user)

      input ->
        input
        |> String.trim()
        |> process_command(current_user)
        |> case do
          {:continue, new_user} -> cli_loop(new_user)
          :exit -> IO.puts("🖥️ Servidor detenido.")
        end
    end
  end

  # ==============================
  # COMMAND PROCESSING
  # ==============================

  defp process_command("", current_user), do: {:continue, current_user}

  # --- HELP (CLIENT/DRIVER) ---
  defp process_command("help", current_user) do
    case current_user do
      nil -> show_guest_help()
      %{role: :client} -> show_client_help()
      %{role: :driver} -> show_driver_help()
      _ -> show_guest_help()
    end

    {:continue, current_user}
  end

  # --- HELP ADMIN ---
  defp process_command("help_admin", _current_user) do
    show_admin_help()
    {:continue, nil}
  end

  # --- EXIT ---
  defp process_command("exit", _), do: :exit

  # --- SERVER COMMANDS (ADMIN) ---
  defp process_command("add_zone " <> zone, current_user) do
    UrbanFleet.Location.add_location(String.trim(zone))
    IO.puts("✅ Zona '#{zone}' agregada correctamente.")
    {:continue, current_user}
  end

  defp process_command("list_zones", current_user) do
    UrbanFleet.show_locations()
    {:continue, current_user}
  end

  defp process_command("show_stats", current_user) do
    UrbanFleet.show_stats()
    {:continue, current_user}
  end

  defp process_command("show_users", current_user) do
    IO.puts("\n📋 Usuarios registrados:\n")
    users = :sys.get_state(UrbanFleet.UserManager)
    users
    |> Map.values()
    |> Enum.each(fn u ->
      IO.puts("• #{u.username} (#{u.role}) - #{u.score} puntos")
    end)
    {:continue, current_user}
  end

  # --- CONNECTION ---
  defp process_command("connect " <> args, nil) do
    case String.split(args) do
      [username, password, role] when role in ["client", "driver"] ->
        role_atom = String.to_atom(role)

        case UrbanFleet.UserManager.register_or_login(username, password, role_atom) do
          {:ok, :registered, user} ->
            IO.puts("✨ Bienvenido #{username}! Registrado como #{role}.")
            {:continue, user}

          {:ok, :logged_in, user} ->
            IO.puts("✅ Bienvenido de nuevo #{username}!")
            {:continue, user}

          {:error, :invalid_password} ->
            IO.puts("❌ Contraseña incorrecta.")
            {:continue, nil}
        end

      _ ->
        IO.puts("✗ Uso: connect <usuario> <contraseña> <client|driver>")
        {:continue, nil}
    end
  end

  defp process_command("connect " <> _, current_user) do
    IO.puts("✗ Ya estás conectado como #{current_user.username}")
    {:continue, current_user}
  end

  defp process_command("disconnect", %{username: name}) do
    IO.puts("👋 Desconectado. Hasta luego #{name}!")
    {:continue, nil}
  end

  defp process_command("disconnect", nil) do
    IO.puts("✗ No estás conectado")
    {:continue, nil}
  end

  # --- CLIENT COMMANDS ---
  defp process_command("request_trip " <> args, %{role: :client} = user) do
    case parse_trip_args(args) do
      {:ok, origin, destination} ->
        case UrbanFleet.Location.validate_locations([origin, destination]) do
          :ok ->
            case UrbanFleet.TripSupervisor.create_trip(user.username, origin, destination) do
              {:ok, trip_id} ->
                IO.puts("""
                ✅ Viaje solicitado!
                ID: #{trip_id}
                Ruta: #{origin} → #{destination}
                Esperando conductor... (expira en 20s)
                """)

              {:error, reason} ->
                IO.puts("❌ No se pudo crear el viaje: #{inspect(reason)}")
            end

          {:error, invalid} ->
            IO.puts("⚠️ Localizaciones inválidas: #{Enum.join(invalid, ", ")}")
        end

      :error ->
        IO.puts("✗ Uso: request_trip origen=<loc> destino=<loc>")
    end

    {:continue, user}
  end

  # --- DRIVER COMMANDS ---
  defp process_command("list_trips", %{role: :driver} = user) do
    trips = UrbanFleet.Trip.list_available()

    if Enum.empty?(trips) do
      IO.puts("🚫 No hay viajes disponibles por ahora.")
    else
      IO.puts("\n🗺️  Viajes disponibles:\n" <> String.duplicate("─", 60))
      Enum.each(trips, fn trip ->
        IO.puts("""
        ID: #{trip.id}
        Cliente: #{trip.client}
        Ruta: #{trip.origin} → #{trip.destination}
        Creado: #{format_datetime(trip.created_at)}
        """)
      end)
    end

    {:continue, user}
  end

  defp process_command("accept_trip " <> trip_id, %{role: :driver} = user) do
    case UrbanFleet.Trip.accept_trip(String.trim(trip_id), user.username) do
      {:ok, trip} ->
        IO.puts("""
        ✅ Viaje aceptado!
        Cliente: #{trip.client}
        Ruta: #{trip.origin} → #{trip.destination}
        Duración: ~20s
        Ganarás +15 puntos al completarlo.
        """)

      {:error, :trip_not_available} ->
        IO.puts("⚠️ El viaje ya no está disponible.")

      {:error, reason} ->
        IO.puts("❌ Error al aceptar viaje: #{inspect(reason)}")
    end

    {:continue, user}
  end

  # --- GENERAL ---
  defp process_command("my_score", user) when not is_nil(user) do
    case UrbanFleet.UserManager.get_score(user.username) do
      {:ok, score} ->
        IO.puts("⭐ Puntuación de #{user.username}: #{score} puntos")

      _ ->
        IO.puts("⚠️ No se pudo obtener la puntuación.")
    end

    {:continue, user}
  end

  defp process_command("ranking", user) do
    show_ranking(nil)
    {:continue, user}
  end

  defp process_command("ranking " <> role, user) when role in ["client", "driver"] do
    show_ranking(String.to_atom(role))
    {:continue, user}
  end

  defp process_command(cmd, current_user) do
    IO.puts("❓ Comando desconocido: #{cmd}")
    IO.puts("Escribe 'help' o 'help_admin' para ver los disponibles.")
    {:continue, current_user}
  end

  # ==============================
  # HELPER FUNCTIONS
  # ==============================

  defp show_server_banner do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║        🖥️  URBANFLEET SERVER MODE       ║
    ╚════════════════════════════════════════╝

    Bienvenido Administrador.
    Escribe 'help_admin' para ver los comandos disponibles.
    """)
  end

  defp show_guest_help do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║        👋 BIENVENIDO A URBANFLEET       ║
    ╚════════════════════════════════════════╝
    connect <user> <pass> <client|driver> - Iniciar sesión o registrar
    help                                  - Mostrar este menú
    exit                                  - Salir
    """)
  end

  defp show_client_help do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║           📱 COMANDOS CLIENTE           ║
    ╚════════════════════════════════════════╝
    request_trip origen=<loc> destino=<loc> - Solicitar viaje
    my_score                                - Ver tu puntuación
    ranking                                 - Ver ranking global
    disconnect                              - Desconectarse
    """)
  end

  defp show_driver_help do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║           🚕 COMANDOS CONDUCTOR         ║
    ╚════════════════════════════════════════╝
    list_trips        - Ver viajes disponibles
    accept_trip <id>  - Aceptar viaje
    my_score          - Ver tu puntuación
    ranking driver    - Ver ranking de conductores
    disconnect        - Desconectarse
    """)
  end

  defp show_admin_help do
    IO.puts("""
    ╔════════════════════════════════════════╗
    ║          🧠 MODO ADMINISTRADOR          ║
    ╚════════════════════════════════════════╝
    add_zone <nombre>        - Agregar nueva zona
    list_zones               - Mostrar zonas válidas
    show_stats               - Ver estadísticas del sistema
    show_users               - Ver usuarios registrados
    help_admin               - Mostrar este menú
    exit                     - Salir del modo servidor
    """)
  end

  defp parse_trip_args(args) do
    parts = String.split(args)

    origin =
      Enum.find_value(parts, fn part ->
        case String.split(part, "=") do
          ["origen", loc] -> loc
          _ -> nil
        end
      end)

    destination =
      Enum.find_value(parts, fn part ->
        case String.split(part, "=") do
          ["destino", loc] -> loc
          _ -> nil
        end
      end)

    if origin && destination, do: {:ok, origin, destination}, else: :error
  end

  defp show_ranking(role) do
    title =
      case role do
        nil -> "🏆 RANKING GLOBAL"
        :client -> "👥 RANKING CLIENTES"
        :driver -> "🚗 RANKING CONDUCTORES"
      end

    IO.puts("\n#{title}\n" <> String.duplicate("═", 50))

    UrbanFleet.UserManager.get_ranking(role)
    |> Enum.with_index(1)
    |> Enum.each(fn {user, rank} ->
      IO.puts("#{rank}. #{user.username} (#{user.role}) - #{user.score} puntos")
    end)

    IO.puts("")
  end

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
