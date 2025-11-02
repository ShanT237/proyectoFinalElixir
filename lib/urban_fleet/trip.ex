defmodule UrbanFleet.Trip do
  use GenServer
  require Logger

  @trip_duration 20_000 # 20 seconds in milliseconds

  # Client API

  def start_link(trip_data) do
    GenServer.start_link(__MODULE__, trip_data, name: via_tuple(trip_data.id))
  end

  def get_state(trip_id) do
    GenServer.call(via_tuple(trip_id), :get_state)
  end

  def accept_trip(trip_id, driver_username) do
    GenServer.call(via_tuple(trip_id), {:accept_trip, driver_username})
  end

  def list_available do
    Registry.select(UrbanFleet.TripRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.map(fn {_module, trip_id} ->
      try do
        get_state(trip_id)
      rescue
        _ -> nil
      end
    end)
    |> Enum.filter(fn
      %{status: :available} -> true
      _ -> false
    end)
  end

  # Server Callbacks

  @impl true
  def init(trip_data) do
    state = Map.merge(trip_data, %{
      status: :available,
      driver: nil,
      created_at: DateTime.utc_now(),
      started_at: nil,
      completed_at: nil
    })

    # Schedule expiration check
    Process.send_after(self(), :check_expiration, @trip_duration)

    Logger.info("Trip #{state.id} created: #{state.origin} -> #{state.destination}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:accept_trip, driver_username}, _from, %{status: :available} = state) do
    new_state = %{state |
      status: :in_progress,
      driver: driver_username,
      started_at: DateTime.utc_now()
    }

    # Schedule completion after trip duration
    Process.send_after(self(), :complete_trip, @trip_duration)

    Logger.info("Trip #{state.id} accepted by driver #{driver_username}")

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:accept_trip, _driver_username}, _from, state) do
    {:reply, {:error, :trip_not_available}, state}
  end

  @impl true
  def handle_info(:check_expiration, %{status: :available} = state) do
    # Trip expired without driver
    Logger.warn("Trip #{state.id} expired without driver")

    new_state = %{state |
      status: :expired,
      completed_at: DateTime.utc_now()
    }

    # Notify user manager about expiration (client loses points)
    UrbanFleet.UserManager.trip_expired(state.client, state.id)

    # Log result
    UrbanFleet.Persistence.log_trip_result(new_state)

    # Stop the GenServer after logging
    {:stop, :normal, new_state}
  end

  @impl true
  def handle_info(:check_expiration, state) do
    # Trip was accepted, no expiration penalty
    {:noreply, state}
  end

  @impl true
  def handle_info(:complete_trip, %{status: :in_progress} = state) do
    Logger.info("Trip #{state.id} completed successfully")

    new_state = %{state |
      status: :completed,
      completed_at: DateTime.utc_now()
    }

    # Award points to both client and driver
    UrbanFleet.UserManager.trip_completed(state.client, state.driver, state.id)

    # Log result
    UrbanFleet.Persistence.log_trip_result(new_state)

    # Stop the GenServer after completion
    {:stop, :normal, new_state}
  end

  @impl true
  def handle_info(:complete_trip, state) do
    # Trip was cancelled or already completed
    {:noreply, state}
  end

  # Helper Functions

  defp via_tuple(trip_id) do
    {:via, Registry, {UrbanFleet.TripRegistry, trip_id}}
  end
end
