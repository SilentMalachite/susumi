defmodule Susumi.Settings.Setting do
  @moduledoc false
  use Ecto.Schema

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end
end
