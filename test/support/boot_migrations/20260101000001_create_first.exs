defmodule Susumi.BootTestRepo.Migrations.CreateFirst do
  use Ecto.Migration

  def change do
    create table(:first_things) do
      add :name, :string
    end
  end
end
