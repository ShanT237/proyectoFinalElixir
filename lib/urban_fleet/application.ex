defmodule UrbanFleet.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Registro de viajes
      {Registry, keys: :unique, name: UrbanFleet.TripRegistry},

      # User manager (autenticación y score)
      UrbanFleet.UserManager,

      # Supervisor
      UrbanFleet.TripSupervisor,

      # Main server (CLI handler)
      UrbanFleet.Server
    ]

    opts = [strategy: :one_for_one, name: UrbanFleet.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("UrbanFleet Application started successfully")

        Process.sleep(100)
        UrbanFleet.Server.start_cli()

        {:ok, pid}

      error ->
        Logger.error("Failed to start UrbanFleet Application: #{inspect(error)}")
        error
    end
  end
end
