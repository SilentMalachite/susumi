defmodule Susumi.Runtime.DataDir do
  @moduledoc """
  データフォルダ（DB、設定、バックアップを置く場所）の解決と作成。

  環境変数 `SUSUMI_DATA_DIR` があればそれを使う。
  なければ OS ごとの既定の場所を使う。
  """

  @doc "OS と環境変数から既定のデータフォルダを決める。"
  @spec default_path({atom, atom}, %{String.t() => String.t()}) :: String.t()
  def default_path({:win32, _}, env), do: Path.join(env["LOCALAPPDATA"], "Susumi")

  def default_path({:unix, :darwin}, env),
    do: Path.join([env["HOME"], "Library", "Application Support", "Susumi"])

  def default_path(_os_type, env), do: Path.join([env["HOME"], ".local", "share", "susumi"])

  @doc "実際に使うデータフォルダ。`SUSUMI_DATA_DIR` を優先する。"
  @spec path() :: String.t()
  def path do
    case System.get_env("SUSUMI_DATA_DIR") do
      dir when is_binary(dir) and dir != "" -> dir
      _ -> default_path(:os.type(), System.get_env())
    end
  end

  @doc "データフォルダと `backups/` を作り、パスを返す。"
  @spec ensure!() :: String.t()
  def ensure! do
    dir = path()
    File.mkdir_p!(backups_path(dir))
    dir
  end

  @spec database_path(String.t()) :: String.t()
  def database_path(dir), do: Path.join(dir, "susumi.db")

  @spec backups_path(String.t()) :: String.t()
  def backups_path(dir), do: Path.join(dir, "backups")
end
