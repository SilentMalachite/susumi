defmodule Susumi.BootTestRepo.Migrations.CreateSecond do
  use Ecto.Migration

  def change do
    create table(:second_things) do
      add :name, :string
    end
  end
end
