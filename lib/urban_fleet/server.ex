defmodule UrbanFleet.Server do
  use GenServer
  require Logger

  # Client API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: :server)
  end

  def start_cli do
    GenServer.cast(__MODULE__, :start_cli)
  end

  # Server Callbacks

  @impl true
  def init(_) do
    Logger.info("UrbanFleet Server started")
    {:ok, %{current_user: nil, sessions: %{}}}
  end

  @impl true
  def handle_cast(:start_cli, state) do
    spawn(fn -> cli_loop(nil) end)
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

  # CLI Loop

  defp cli_loop(current_user) do
    prompt =
      if current_user do
        "[#{current_user.username}@#{current_user.role}] > "
      else
        "[guest] > "
      end

    IO.write(prompt)

    case IO.gets("") do
      :eof ->
        IO.puts("\nGoodbye!")
        :ok

      {:error, reason} ->
        IO.puts("Error reading input: #{inspect(reason)}")
        cli_loop(current_user)

      input ->
        input
        |> String.trim()
        |> process_command(current_user)
        |> case do
          {:continue, new_user} -> cli_loop(new_user)
          :exit -> IO.puts("Goodbye!")
        end
    end
  end

  # Command Processing

  defp process_command("", current_user), do: {:continue, current_user}

  defp process_command("help", _current_user) do
    IO.puts("""

    Available Commands:
    -------------------
    connect <username> <password> <role>  - Connect as client or driver
    disconnect                             - Disconnect from system

    Client Commands:
    request_trip origen=<loc> destino=<loc> - Request a trip
    my_score                                 - View your score

    Driver Commands:
    list_trips                               - List available trips
    accept_trip <trip_id>                    - Accept a trip
    my_score                                 - View your score

    General:
    ranking [client|driver]                  - View rankings
    help                                     - Show this help
    exit                                     - Exit application
    """)

    {:continue, nil}
  end

  defp process_command("exit", _current_user), do: :exit

  defp process_command("connect " <> args, nil) do
    case String.split(args) do
      [username, password, role] when role in ["client", "driver"] ->
        role_atom = String.to_atom(role)

        case UrbanFleet.UserManager.register_or_login(username, password, role_atom) do
          {:ok, :registered, user} ->
            IO.puts("✓ Welcome #{username}! You've been registered as a #{role}.")
            {:continue, user}

          {:ok, :logged_in, user} ->
            IO.puts("✓ Welcome back #{username}!")
            {:continue, user}

          {:error, :invalid_password} ->
            IO.puts("✗ Invalid password")
            {:continue, nil}
        end

      _ ->
        IO.puts("✗ Usage: connect <username> <password> <client|driver>")
        {:continue, nil}
    end
  end

  defp process_command("connect " <> _, current_user) do
    IO.puts("✗ You are already connected as #{current_user.username}")
    {:continue, current_user}
  end

  defp process_command("disconnect", current_user) when not is_nil(current_user) do
    IO.puts("✓ Disconnected. Goodbye #{current_user.username}!")
    {:continue, nil}
  end

  defp process_command("disconnect", nil) do
    IO.puts("✗ You are not connected")
    {:continue, nil}
  end

  defp process_command("request_trip " <> args, %{role: :client} = current_user) do
    case parse_trip_args(args) do
      {:ok, origin, destination} ->
        case UrbanFleet.Location.validate_locations([origin, destination]) do
          :ok ->
            case UrbanFleet.TripSupervisor.create_trip(current_user.username, origin, destination) do
              {:ok, trip_id} ->
                IO.puts("✓ Trip requested! ID: #{trip_id}")
                IO.puts("  Route: #{origin} → #{destination}")
                IO.puts("  Waiting for a driver... (expires in 20s)")

              {:error, reason} ->
                IO.puts("✗ Failed to create trip: #{inspect(reason)}")
            end

          {:error, invalid_locs} ->
            IO.puts("✗ Invalid locations: #{Enum.join(invalid_locs, ", ")}")
        end

      :error ->
        IO.puts("✗ Usage: request_trip origen=<location> destino=<location>")
    end

    {:continue, current_user}
  end

  defp process_command("request_trip " <> _, current_user) do
    IO.puts("✗ Only clients can request trips")
    {:continue, current_user}
  end

  defp process_command("list_trips", %{role: :driver} = current_user) do
    trips = UrbanFleet.Trip.list_available()

    if Enum.empty?(trips) do
      IO.puts("No available trips at the moment.")
    else
      IO.puts("\nAvailable Trips:")
      IO.puts(String.duplicate("-", 70))

      Enum.each(trips, fn trip ->
        IO.puts("ID: #{trip.id}")
        IO.puts("  Client: #{trip.client}")
        IO.puts("  Route: #{trip.origin} → #{trip.destination}")
        IO.puts("  Created: #{format_datetime(trip.created_at)}")
        IO.puts("")
      end)
    end

    {:continue, current_user}
  end

  defp process_command("list_trips", current_user) do
    IO.puts("✗ Only drivers can list trips")
    {:continue, current_user}
  end

  defp process_command("accept_trip " <> trip_id, %{role: :driver} = current_user) do
    trip_id = String.trim(trip_id)

    case UrbanFleet.Trip.accept_trip(trip_id, current_user.username) do
      {:ok, trip} ->
        IO.puts("✓ Trip accepted!")
        IO.puts("  Route: #{trip.origin} → #{trip.destination}")
        IO.puts("  Client: #{trip.client}")
        IO.puts("  Duration: ~20 seconds")
        IO.puts("  You'll earn +15 points upon completion")

      {:error, :trip_not_available} ->
        IO.puts("✗ Trip is no longer available")

      {:error, reason} ->
        IO.puts("✗ Failed to accept trip: #{inspect(reason)}")
    end

    {:continue, current_user}
  end

  defp process_command("accept_trip " <> _, current_user) do
    IO.puts("✗ Only drivers can accept trips")
    {:continue, current_user}
  end

  defp process_command("my_score", current_user) when not is_nil(current_user) do
    case UrbanFleet.UserManager.get_score(current_user.username) do
      {:ok, score} ->
        IO.puts("Your score: #{score} points")

      {:error, _} ->
        IO.puts("✗ Could not retrieve score")
    end

    {:continue, current_user}
  end

  defp process_command("ranking", current_user) do
    show_ranking(nil)
    {:continue, current_user}
  end

  defp process_command("ranking " <> role, current_user) when role in ["client", "driver"] do
    show_ranking(String.to_atom(role))
    {:continue, current_user}
  end

  defp process_command(cmd, current_user) do
    IO.puts("✗ Unknown command: #{cmd}")
    IO.puts("Type 'help' for available commands")
    {:continue, current_user}
  end

  # Helper Functions

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

    if origin && destination do
      {:ok, origin, destination}
    else
      :error
    end
  end

  defp show_ranking(role) do
    title =
      case role do
        nil -> "Global Ranking"
        :client -> "Client Ranking"
        :driver -> "Driver Ranking"
      end

    IO.puts("\n#{title}")
    IO.puts(String.duplicate("=", 50))

    UrbanFleet.UserManager.get_ranking(role)
    |> Enum.with_index(1)
    |> Enum.each(fn {user, rank} ->
      IO.puts("#{rank}. #{user.username} (#{user.role}) - #{user.score} points")
    end)

    IO.puts("")
  end

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
