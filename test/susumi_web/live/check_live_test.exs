defmodule SusumiWeb.CheckLiveTest do
  use SusumiWeb.ConnCase

  import Phoenix.LiveViewTest

  test "ボタンで数が増え、別のLiveViewにも反映される", %{conn: conn} do
    {:ok, a, _} = live(conn, "/_check")
    {:ok, b, _} = live(conn, "/_check")
    a |> element("button", "+1") |> render_click()
    assert render(b) =~ "回数: 1"
  end
end
