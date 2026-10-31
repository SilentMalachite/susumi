defmodule Susumi.Runtime.DataDirTest do
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  alias Susumi.Runtime.DataDir

  test "Windowsの既定はLOCALAPPDATA配下" do
    assert DataDir.default_path({:win32, :nt}, %{"LOCALAPPDATA" => "C:/Users/a/AppData/Local"}) ==
             "C:/Users/a/AppData/Local/Susumi"
  end

  test "macOSの既定はApplication Support配下" do
    assert DataDir.default_path({:unix, :darwin}, %{"HOME" => "/Users/a"}) ==
             "/Users/a/Library/Application Support/Susumi"
  end

  test "それ以外（開発用Linux）は ~/.local/share/susumi" do
    assert DataDir.default_path({:unix, :linux}, %{"HOME" => "/home/a"}) ==
             "/home/a/.local/share/susumi"
  end

  test "database_path と backups_path" do
    assert DataDir.database_path("/x") == "/x/susumi.db"
    assert DataDir.backups_path("/x") == "/x/backups"
  end

  test "ensure! は backups まで作る", %{tmp_dir: dir} do
    System.put_env("SUSUMI_DATA_DIR", Path.join(dir, "d"))
    on_exit(fn -> System.delete_env("SUSUMI_DATA_DIR") end)
    path = DataDir.ensure!()
    assert path == Path.join(dir, "d")
    assert File.dir?(Path.join(path, "backups"))
  end
end
