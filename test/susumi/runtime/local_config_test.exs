defmodule Susumi.Runtime.LocalConfigTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir

  alias Susumi.Runtime.LocalConfig

  test "config.json がなければ既定値で作る", %{tmp_dir: dir} do
    assert LocalConfig.load(dir) == %{port: 4000, staff_idle_minutes: 60}
    assert File.exists?(Path.join(dir, "config.json"))
  end

  test "指定した値を読む", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "config.json"), ~s({"port": 8080}))
    assert LocalConfig.load(dir) == %{port: 8080, staff_idle_minutes: 60}
  end

  test "壊れたJSONなら既定値を使う", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "config.json"), "{")
    assert LocalConfig.load(dir) == %{port: 4000, staff_idle_minutes: 60}
  end

  test "不正な値は既定値に戻す", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "config.json"), ~s({"port": "abc", "staff_idle_minutes": 0}))
    assert LocalConfig.load(dir) == %{port: 4000, staff_idle_minutes: 60}
  end

  test "secret_key_base は初回に作り、2回目は同じ値を返す", %{tmp_dir: dir} do
    a = LocalConfig.secret_key_base!(dir)
    assert String.length(a) >= 64
    assert LocalConfig.secret_key_base!(dir) == a
  end
end
