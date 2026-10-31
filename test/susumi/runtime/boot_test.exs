defmodule Susumi.Runtime.BootTest do
  use ExUnit.Case, async: false

  alias Susumi.BootTestRepo
  alias Susumi.Runtime.Boot

  @migrations Path.expand("../../support/boot_migrations", __DIR__)

  # テスト用マイグレーションを複数回読み込むので、モジュール再定義の警告を止める
  setup_all do
    previous = Code.compiler_options()[:ignore_module_conflict]
    Code.compiler_options(ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(ignore_module_conflict: previous || false) end)
  end

  test "lan_urls はループバック以外のIPv4だけを返す" do
    ifaddrs = [
      {~c"lo0", [addr: {127, 0, 0, 1}]},
      {~c"en0", [addr: {192, 168, 1, 20}, addr: {0xFE80, 0, 0, 0, 0, 0, 0, 1}]}
    ]

    assert Boot.lan_urls(4000, ifaddrs) == ["http://192.168.1.20:4000"]
  end

  test "banner に停止の注意と版番号が入る" do
    text = Boot.banner(4000, ["http://192.168.1.20:4000"], "0.1.0")
    assert text =~ "http://192.168.1.20:4000"
    assert text =~ "このウィンドウを閉じると、すすみが停止します。"
    assert text =~ "0.1.0"
  end

  test "使用中のポートは false" do
    {:ok, s} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(s)
    refute Boot.port_available?(port)
    :gen_tcp.close(s)
  end

  describe "startup!" do
    defp opts(extra) do
      me = self()

      Keyword.merge(
        [
          port: 4000,
          serving: true,
          auto_migrate: true,
          migrate: fn -> send(me, :migrated) end,
          puts: fn msg -> send(me, {:puts, msg}) end,
          sleep: fn ms -> send(me, {:sleep, ms}) end,
          halt: fn code -> throw({:halted, code}) end
        ],
        extra
      )
    end

    test "ポートが空いていれば、そのあとでマイグレーションする" do
      assert :ok = Boot.startup!(opts(port_available?: fn _ -> true end))
      assert_received :migrated
    end

    test "ポートが使用中なら、マイグレーションせずに終了する" do
      assert catch_throw(Boot.startup!(opts(port_available?: fn _ -> false end))) == {:halted, 1}
      assert_received {:puts, "ポート4000は" <> _}
      assert_received {:sleep, 30_000}
      refute_received :migrated
    end

    test "待ち受けない（serving: false）ならポートは確認しない" do
      assert :ok =
               Boot.startup!(
                 opts(serving: false, port_available?: fn _ -> flunk("確認してはいけない") end)
               )

      assert_received :migrated
    end

    test "auto_migrate が false ならマイグレーションしない" do
      assert :ok = Boot.startup!(opts(auto_migrate: false, port_available?: fn _ -> true end))
      refute_received :migrated
    end
  end

  describe "migrate_with_backup!" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      Application.put_env(:susumi, BootTestRepo,
        database: Path.join(dir, "boot.db"),
        pool_size: 1,
        busy_timeout: 5000,
        journal_mode: :delete
      )

      on_exit(fn -> Application.delete_env(:susumi, BootTestRepo) end)
      :ok
    end

    test "未適用のマイグレーションがあり既存DBなら、複製を作ってから適用する", %{tmp_dir: dir} do
      backups = Path.join(dir, "backups")
      File.mkdir_p!(backups)

      # 最初の1本だけ適用した状態にする
      first = Path.join(dir, "only_first")
      File.mkdir_p!(first)

      File.cp!(
        Path.join(@migrations, "20260101000001_create_first.exs"),
        Path.join(first, "20260101000001_create_first.exs")
      )

      assert {:migrated, nil} =
               Boot.migrate_with_backup!(BootTestRepo, backups, ~N[2026-10-31 08:00:00],
                 migrations_path: first
               )

      now = ~N[2026-10-31 09:00:00]
      expected = Path.join(backups, "susumi-20261031-090000.db")

      assert {:migrated, ^expected} =
               Boot.migrate_with_backup!(BootTestRepo, backups, now, migrations_path: @migrations)

      assert File.exists?(expected)

      assert :up_to_date =
               Boot.migrate_with_backup!(BootTestRepo, backups, now, migrations_path: @migrations)
    end

    test "新規DB（適用済みが0件）なら複製は作らない", %{tmp_dir: dir} do
      backups = Path.join(dir, "backups")
      File.mkdir_p!(backups)

      assert {:migrated, nil} =
               Boot.migrate_with_backup!(BootTestRepo, backups, ~N[2026-10-31 09:00:00],
                 migrations_path: @migrations
               )

      assert File.ls!(backups) == []
    end
  end
end
