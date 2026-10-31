defmodule Susumi.SettingsTest do
  use Susumi.DataCase, async: false

  alias Susumi.Settings

  test "put した値を get で読める" do
    :ok = Settings.put("facility_name", "ひまわり作業所")
    assert Settings.facility_name() == "ひまわり作業所"
    assert Settings.get("missing", "x") == "x"
  end

  test "同じキーに put すると上書きされる" do
    :ok = Settings.put("k", "1")
    :ok = Settings.put("k", "2")
    assert Settings.get("k", nil) == "2"
  end

  test "施設名が未設定なら空文字" do
    assert Settings.facility_name() == ""
    :ok = Settings.put_facility_name("あおぞら")
    assert Settings.facility_name() == "あおぞら"
  end
end
