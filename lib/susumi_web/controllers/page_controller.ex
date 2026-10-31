defmodule SusumiWeb.PageController do
  use SusumiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
