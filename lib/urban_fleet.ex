defmodule UrbanFleet do
  @moduledoc """
  UrbanFleet - A multiplayer taxi fleet simulation system.

  This system simulates a real-time taxi dispatch service where:
  - Clients can request trips
  - Drivers can accept and complete trips
  - Points are awarded for successful trips
  - All operations run concurrently using OTP

  ## Usage

  Start the application:
  ```
  iex -S mix
  ```

  The CLI will start automatically. Available commands:

  ### Connection
  - `connect <username> <password> <client|driver>` - Register or login
  - `disconnect` - Disconnect from the system

  ### Client Commands
  - `request_trip origen=<location> destino=<location>` - Request a trip
  - `my_score` - View your score

  ### Driver Commands
  - `list_trips` - List available trips
  - `accept_trip <trip_id>` - Accept a trip
  - `my_score` - View your score

  ### General Commands
  - `ranking [client|driver]` - View rankings
  - `help` - Show help
  - `exit` - Exit application

  ## Scoring System
  - Client completes trip: +10 points
  - Driver completes trip: +15 points
  - Trip expires without driver: Client loses -5 points

  ## Architecture

  The system uses:
  - GenServers for stateful processes (trips, users)
  - DynamicSupervisor for managing trip processes
  - Registry for trip process lookup
  - File-based persistence for users and results
  """

  @doc """
  Returns the application version
  """
  def version do
    Application.spec(:urban_fleet, :vsn) |> to_string()
  end

  @doc """
  Displays application information
  """
  def info do
    IO.puts("""

    ╔════════════════════════════════════════╗
    ║         URBANFLEET v#{version()}           ║
    ║    Multiplayer Taxi Fleet System      ║
    ╚════════════════════════════════════════╝

    Status: #{if running?(), do: "Running ✓", else: "Stopped ✗"}

    Type 'help' for available commands.
    """)
  end

  @doc """
  Checks if the application is running
  """
  def running? do
    Process.whereis(UrbanFleet.Server) != nil
  end

  @doc """
  Gets current system statistics
  """
  def stats do
    trip_stats = UrbanFleet.TripSupervisor.count_trips()
    persistence_stats = UrbanFleet.Persistence.get_statistics()

    %{
      active_trips: trip_stats.active,
      total_trips_completed: persistence_stats.total,
      completion_rate: persistence_stats.completion_rate,
      trips_expired: persistence_stats.expired
    }
  end

  @doc """
  Displays current system statistics
  """
  def show_stats do
    stats = stats()

    IO.puts("""

    System Statistics
    ═════════════════
    Active Trips: #{stats.active_trips}
    Total Completed: #{stats.total_trips_completed}
    Completion Rate: #{stats.completion_rate}%
    Expired: #{stats.trips_expired}
    """)
  end

  @doc """
  Lists all valid locations
  """
  def locations do
    UrbanFleet.Location.list_locations()
  end

  @doc """
  Displays all valid locations
  """
  def show_locations do
    locations = locations()

    IO.puts("\nValid Locations:")
    IO.puts("═══════════════")
    Enum.each(locations, fn loc ->
      IO.puts("  • #{loc}")
    end)
    IO.puts("")
  end
end
