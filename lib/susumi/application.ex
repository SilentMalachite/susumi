defmodule Susumi.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Susumi.Runtime.{Boot, DataDir}

  @impl true
  def start(_type, _args) do
    port = configured_port()

    Boot.startup!(
      port: port,
      serving: serving?(),
      auto_migrate: Application.get_env(:susumi, :auto_migrate, false),
      migrate: fn ->
        Boot.migrate_with_backup!(
          Susumi.Repo,
          DataDir.backups_path(Application.fetch_env!(:susumi, :data_dir)),
          NaiveDateTime.local_now()
        )
      end
    )

    if System.get_env("__BURRITO") == "1", do: keep_alive_under_cli()

    children = [
      SusumiWeb.Telemetry,
      Susumi.Repo,
      {DNSCluster, query: Application.get_env(:susumi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Susumi.PubSub},
      # Start a worker by calling: Susumi.Worker.start_link(arg)
      # {Susumi.Worker, arg},
      # Start to serve requests, typically the last entry
      SusumiWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Susumi.Supervisor]
    result = Supervisor.start_link(children, opts)

    if match?({:ok, _}, result) and Application.get_env(:susumi, :open_browser, false) do
      version = to_string(Application.spec(:susumi, :vsn))
      {:ok, ifaddrs} = :inet.getifaddrs()
      IO.puts(Boot.banner(port, Boot.lan_urls(port, ifaddrs), version))
      Boot.open_browser("http://localhost:#{port}")
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SusumiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Burrito は `elixir start_cli` でVMを起動する。この方式は、コマンドの処理が終わると
  # VMを止める。`--no-halt` を渡せず、`System.no_halt/1` も上書きされる。
  # 終了時の処理（この時点の `:init.get_status/0` は `{:starting, :started}`）で
  # 待ち続けて、VMが止まらないようにする。
  # Burrito の起動ファイルが `__BURRITO=1` を設定したときだけ使う。
  # `mix run` などでアプリを起動したときに、止まらなくなるのを防ぐ。
  defp keep_alive_under_cli do
    System.at_exit(fn _status -> Process.sleep(:infinity) end)
  end

  defp configured_port do
    :susumi
    |> Application.get_env(SusumiWeb.Endpoint, [])
    |> Keyword.get(:http, [])
    |> Keyword.get(:port, 4000)
  end

  defp serving? do
    :susumi |> Application.get_env(SusumiWeb.Endpoint, []) |> Keyword.get(:server, false)
  end
end
