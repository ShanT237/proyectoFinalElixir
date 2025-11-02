defmodule UrbanFleet.Location do
  @moduledoc """
  """

  @locations_file "data/locations.dat"

  @doc """
  Carga todas las validaciones
  """
  def load_locations do
    case File.read(@locations_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> MapSet.new()

      {:error, :enoent} ->
        # Crea las localizaciones si no existen
        default_locations = MapSet.new([
          "Parque", "Centro", "Aeropuerto", "Universidad",
          "Hospital", "Plaza", "Estadio", "Biblioteca",
          "Mercado", "Terminal"
        ])
        save_locations(default_locations)
        default_locations

      {:error, _reason} ->
        MapSet.new()
    end
  end

  @doc """
  Valida las localizaciones
  """
  def validate_locations(locations) do
    valid_locations = load_locations()

    invalid = locations
    |> Enum.reject(&MapSet.member?(valid_locations, &1))

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, invalid}
    end
  end

  @doc """
  Añadir nueva localización
  """
  def add_location(location) do
    locations = load_locations()
    new_locations = MapSet.put(locations, location)
    save_locations(new_locations)
  end

  @doc """
  Lista todas las localizaciones validas
  """
  def list_locations do
    load_locations()
    |> MapSet.to_list()
    |> Enum.sort()
  end


  defp save_locations(locations_set) do
    content = locations_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.join("\n")

    File.mkdir_p!("data")
    File.write!(@locations_file, content <> "\n")
  end
end
