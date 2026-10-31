defmodule SusumiWeb.CheckLive do
  @moduledoc "起動確認用の画面（Task 14 で削除する）。"
  use SusumiWeb, :live_view

  alias Susumi.Settings

  @topic "check"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Susumi.PubSub, @topic)
    {:ok, assign(socket, :count, load())}
  end

  @impl true
  def handle_event("inc", _params, socket) do
    Settings.put("check_counter", Integer.to_string(load() + 1))
    Phoenix.PubSub.broadcast(Susumi.PubSub, @topic, {:check_changed})
    {:noreply, assign(socket, :count, load())}
  end

  @impl true
  def handle_info({:check_changed}, socket), do: {:noreply, assign(socket, :count, load())}

  defp load, do: "check_counter" |> Settings.get("0") |> String.to_integer()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p class="text-2xl">回数: {@count}</p>
      <button phx-click="inc" class="btn btn-primary">+1</button>
    </Layouts.app>
    """
  end
end
