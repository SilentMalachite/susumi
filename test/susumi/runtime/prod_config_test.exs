defmodule Susumi.Runtime.ProdConfigTest do
  use ExUnit.Case, async: true

  test "prod は force_ssl を使わない（LAN内の別PCからHTTPで届くため）" do
    config = Config.Reader.read!("config/prod.exs")
    endpoint = config |> Keyword.get(:susumi, []) |> Keyword.get(SusumiWeb.Endpoint, [])
    refute Keyword.has_key?(endpoint, :force_ssl)
  end
end
