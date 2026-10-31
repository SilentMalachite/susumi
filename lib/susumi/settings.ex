defmodule Susumi.Settings do
  @moduledoc """
  施設ごとの設定（キーと値）を保存する。
  """

  import Ecto.Query, only: [from: 2]

  alias Susumi.Repo
  alias Susumi.Settings.Setting

  @spec get(String.t(), String.t() | nil) :: String.t() | nil
  def get(key, default) do
    case Repo.one(from s in Setting, where: s.key == ^key, select: s.value) do
      nil -> default
      value -> value
    end
  end

  @spec put(String.t(), String.t()) :: :ok
  def put(key, value) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(Setting, [%{key: key, value: value, inserted_at: now, updated_at: now}],
      on_conflict: [set: [value: value, updated_at: now]],
      conflict_target: :key
    )

    :ok
  end

  @spec facility_name() :: String.t()
  def facility_name, do: get("facility_name", "")

  @spec put_facility_name(String.t()) :: :ok
  def put_facility_name(name), do: put("facility_name", name)
end
