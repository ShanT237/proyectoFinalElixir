#!/usr/bin/env elixir

IO.puts("🚖 Starting UrbanFleet SERVER...\n")

# Carga módulos
Code.compile_file("lib/urban_fleet/location.ex")
Code.compile_file("lib/urban_fleet/persistence.ex")
Code.compile_file("lib/urban_fleet/user_manager.ex")
Code.compile_file("lib/urban_fleet/trip.ex")
Code.compile_file("lib/urban_fleet/trip_supervisor.ex")
Code.compile_file("lib/urban_fleet/server.ex")
Code.compile_file("lib/urban_fleet.ex")

# Crea carpeta y datos iniciales
File.mkdir_p!("data")

unless File.exists?("data/locations.dat") do
  File.write!("data/locations.dat", """
  Parque
  Centro
  Aeropuerto
  Universidad
  Hospital
  Plaza
  Estadio
  Biblioteca
  Mercado
  Terminal
  """)
end

# Inicia procesos principales
{:ok, _registry} = Registry.start_link(keys: :unique, name: UrbanFleet.TripRegistry)
{:ok, _user_manager} = UrbanFleet.UserManager.start_link([])
{:ok, _trip_supervisor} = UrbanFleet.TripSupervisor.start_link([])
{:ok, _server} = UrbanFleet.Server.start_link([])

IO.puts("""
╔════════════════════════════════════════╗
║         URBANFLEET SERVER v1.0.0       ║
╚════════════════════════════════════════╝
""")

IO.puts("System Status: ✓ Running\n")
IO.puts("Waiting for clients/drivers to connect...\n")

# Mantén vivo el servidor
Process.sleep(:infinity)
