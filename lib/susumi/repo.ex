defmodule Susumi.Repo do
  use Ecto.Repo,
    otp_app: :susumi,
    adapter: Ecto.Adapters.SQLite3
end
