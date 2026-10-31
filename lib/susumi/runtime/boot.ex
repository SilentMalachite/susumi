defmodule Susumi.Runtime.Boot do
  @moduledoc """
  起動時の処理。自動マイグレーション（事前にDBを複製）、ポート確認、
  起動案内の文面、ブラウザを開く処理をまとめる。
  """

  @doc """
  未適用のマイグレーションを適用する。

  すでに適用済みのものがあり、未適用のものもある場合は、適用前に
  `backups_dir` へ `susumi-YYYYMMDD-HHMMSS.db` を作る。

  `opts[:migrations_path]` で、マイグレーションの置き場所を変えられる（テスト用）。
  """
  @spec migrate_with_backup!(module, String.t(), NaiveDateTime.t(), keyword) ::
          :up_to_date | {:migrated, String.t() | nil}
  def migrate_with_backup!(repo, backups_dir, now, opts \\ []) do
    paths =
      case Keyword.fetch(opts, :migrations_path) do
        {:ok, path} -> [path]
        :error -> [Ecto.Migrator.migrations_path(repo)]
      end

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        statuses = Ecto.Migrator.migrations(repo, paths)
        pending? = Enum.any?(statuses, &match?({:down, _, _}, &1))
        applied? = Enum.any?(statuses, &match?({:up, _, _}, &1))

        cond do
          not pending? ->
            :up_to_date

          true ->
            backup = if applied?, do: backup!(repo, backups_dir, now)
            Ecto.Migrator.run(repo, paths, :up, all: true, log: false)
            {:migrated, backup}
        end
      end)

    result
  end

  defp backup!(repo, backups_dir, now) do
    File.mkdir_p!(backups_dir)
    path = Path.join(backups_dir, "susumi-" <> Calendar.strftime(now, "%Y%m%d-%H%M%S") <> ".db")
    escaped = String.replace(path, "'", "''")
    Ecto.Adapters.SQL.query!(repo, "VACUUM INTO '#{escaped}'", [])
    path
  end

  @doc """
  起動前の処理を決まった順で行う。

  1. 待ち受ける場合は、先にポートを確認する。使用中なら案内を出して終了する。
  2. 自動マイグレーションが有効なら、そのあとで実行する。

  先に動いている古いすすみがあるとき、DBの複製と書き換えをしないための順序。
  `opts` の `:halt` `:sleep` `:migrate` `:port_available?` `:puts` は、テスト用に差し替えられる。
  """
  @spec startup!(keyword) :: :ok
  def startup!(opts) do
    port = Keyword.fetch!(opts, :port)
    port_available? = Keyword.get(opts, :port_available?, &port_available?/1)

    if Keyword.get(opts, :serving, false) and not port_available?.(port) do
      Keyword.get(opts, :puts, &IO.puts/1).(
        "ポート#{port}は、ほかのソフトが使っています。ほかのすすみを閉じるか、config.json の port を変えてください。"
      )

      Keyword.get(opts, :sleep, &Process.sleep/1).(30_000)
      Keyword.get(opts, :halt, &System.halt/1).(1)
    end

    if Keyword.get(opts, :auto_migrate, false), do: Keyword.fetch!(opts, :migrate).()
    :ok
  end

  @doc "ポートが空いていれば true。"
  @spec port_available?(pos_integer) :: boolean
  def port_available?(port) do
    case :gen_tcp.listen(port, [:binary, reuseaddr: false]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc "ループバック以外のIPv4アドレスから、他の端末が使うURLを作る。"
  @spec lan_urls(pos_integer, list) :: [String.t()]
  def lan_urls(port, ifaddrs) do
    for {_name, props} <- ifaddrs,
        {:addr, {a, b, c, d} = ip} <- props,
        ip != {0, 0, 0, 0},
        a != 127 do
      "http://#{a}.#{b}.#{c}.#{d}:#{port}"
    end
  end

  @doc "起動したときに表示する案内。"
  @spec banner(pos_integer, [String.t()], String.t()) :: String.t()
  def banner(port, lan_urls, version) do
    others =
      case lan_urls do
        [] -> "  （ほかのパソコンから使うアドレスは見つかりませんでした）"
        urls -> Enum.map_join(urls, "\n", &"  #{&1}")
      end

    """
    ==========================================
      すすみ（版 #{version}）が起動しました
    ==========================================

    このパソコンで使うとき:
      http://localhost:#{port}

    ほかのパソコンから使うとき:
    #{others}

    このウィンドウを閉じると、すすみが停止します。
    """
  end

  @doc "既定のブラウザでURLを開く。失敗しても何もしない。"
  @spec open_browser(String.t()) :: :ok
  def open_browser(url) do
    {cmd, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", "start", "", url]}
        {:unix, :darwin} -> {"open", [url]}
        _ -> {"xdg-open", [url]}
      end

    try do
      System.cmd(cmd, args, stderr_to_stdout: true)
    rescue
      _ -> :ok
    end

    :ok
  end
end
