defmodule Susumi.Runtime.LocalConfig do
  @moduledoc """
  データフォルダ内の `config.json` と `secret_key_base` の読み書き。

  設定ファイルが無い、壊れている、値が不正な場合は既定値を使う。
  """

  @defaults %{port: 4000, staff_idle_minutes: 60}

  @spec load(String.t()) :: %{port: pos_integer(), staff_idle_minutes: pos_integer()}
  def load(dir) do
    file = Path.join(dir, "config.json")

    case File.read(file) do
      {:ok, body} ->
        parse(body)

      {:error, :enoent} ->
        File.mkdir_p!(dir)
        File.write!(file, Jason.encode!(@defaults, pretty: true))
        @defaults

      {:error, _} ->
        @defaults
    end
  end

  defp parse(body) do
    case Jason.decode(body) do
      {:ok, %{} = map} ->
        %{
          port: positive_int(map["port"], @defaults.port),
          staff_idle_minutes:
            positive_int(map["staff_idle_minutes"], @defaults.staff_idle_minutes)
        }

      _ ->
        @defaults
    end
  end

  defp positive_int(n, _default) when is_integer(n) and n > 0, do: n
  defp positive_int(_, default), do: default

  @spec secret_key_base!(String.t()) :: String.t()
  def secret_key_base!(dir) do
    file = Path.join(dir, "secret_key_base")

    case File.read(file) do
      {:ok, key} when byte_size(key) >= 64 ->
        key

      _ ->
        key = :crypto.strong_rand_bytes(64) |> Base.encode64()
        File.mkdir_p!(dir)
        File.write!(file, key)
        File.chmod(file, 0o600)
        key
    end
  end
end
