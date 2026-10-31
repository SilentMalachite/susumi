defmodule Susumi.BootTestRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :susumi, adapter: Ecto.Adapters.SQLite3
end
