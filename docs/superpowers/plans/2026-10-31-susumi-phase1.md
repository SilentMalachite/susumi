# すすみ（Susumi）第1段階 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 職員がKanbanで作業の段階を管理し、利用者さんが自分のPCで「今日の作業」を見て自分で進められる、LAN内専用のWebアプリを、Windows・macOS向けの単体実行ファイルとして作る。

**Architecture:** Phoenix LiveViewのモノリス。DBはSQLiteファイル1つで、データフォルダに置く。DB操作とPubSubのbroadcastは、コンテキスト（`Susumi.Accounts`、`Susumi.Kanban`、`Susumi.Settings`）に集約する。認証はアプリ独自の小さな仕組みで行う。セッショントークンをDBに持ち、Plugと `on_mount` で確認する。配布はBurritoでリリースを包んで単体の実行ファイルにする。

**Tech Stack:** Elixir / Phoenix 1.8 / LiveView、`ecto_sqlite3`、`pbkdf2_elixir`、`burrito`、Sortable.js（同梱）、Tailwind（Phoenix標準）

**Spec:** `docs/superpowers/specs/2026-10-31-welfare-board-phase1-design.md`（実装者は設計書と `AGENTS.md` も読むこと）

## Global Constraints

- アプリ名 `susumi`、モジュール `Susumi` / `SusumiWeb`。画面の文言は日本語。利用者さん向けはやさしい言葉で書く。
- 実行時に外部ネットワークへアクセスしない。CDN、Webフォント、外部API、テレメトリは使わない。Sortable.jsは `assets/vendor/` に同梱する。
- JavaScriptは Sortable.js のLiveView Hookのみ。
- NIF依存は `exqlite` だけにする。パスワードのハッシュ化は `pbkdf2_elixir` を使う。
- Repoの設定: `journal_mode: :wal`、`busy_timeout: 5000`
- パスワードの最小長: 利用者 4文字、職員 8文字。全角文字はNFKCで正規化してから扱う（Review Focus 4）。
- ログイン失敗の制限: 同じアカウントで続けて5回失敗したら、5分間ロックする。回数はメモリで数える。
- ログイン状態を保つ時間: 利用者は最終操作から30日。職員は最終操作から60分で、設定の `staff_idle_minutes` で変えられる。
- `board_type` は必須で、`"user_progress"` か `"staff_task"`。`staff_task` のボードには `column_type = "staff"` の列しか作れない。
- `column_type` は必須で、`"user"` か `"staff"`。`position` が最大の列を「完了」とみなす。`position` は0から始まる連番。
- 利用者さんができるのは、自分のホーム画面を見ることと、自分のカードを「進める」「戻す」ことだけ。権限の確認はサーバー側で、`mount` とすべての `handle_event` で行う。
- 起動: `0.0.0.0:4000` で待ち受ける。ポートは `config.json` で変えられる。`check_origin: :conn`。
- データフォルダ: Windowsは `%LOCALAPPDATA%\Susumi\`、macOSは `~/Library/Application Support/Susumi/`。環境変数 `SUSUMI_DATA_DIR` で上書きできる。
- 起動時に自動でマイグレーションする。実行前に日時付きのDB複製を `backups/` に作る。
- 「今日」はサーバーの現地時刻で決める（`Susumi.Clock.today/0`）。
- ふりがなは `<ruby>` で語全体に1つ付ける。自動のふりがな変換はしない。
- 配布対象: Windows x86_64、macOS aarch64 / x86_64。コード署名はしない。

## Review Focus

1. 利用者さんがホーム画面を開いたまま日付が変わる。翌朝には「今日やる作業」が新しい日付で振り分け直されているべき（Task 10）。
2. 「次の段階へ」を素早く2回押す、または通信が遅れて同じイベントが2回届く。カードが2段進んではいけない。押した時点の列を一緒に送り、ずれていれば何もしない（Task 9、Task 10）。
3. 別の職員がカードを削除・移動した直後に、古い画面からそのカードを操作する。クラッシュせず、画面を最新にして短く知らせるべき（Task 8、Task 11）。
4. 日本語入力がオンのまま、全角の「１２３４」でパスワードを入れる。半角で登録していてもログインできるべき（Task 3）。
5. ログイン中のアカウントを職員が無効化する、またはパスワードを再設定する。その人の開いている画面は、すぐにログアウトされるべき（Task 4、Task 12）。

---

### Task 1: プロジェクト作成とデータフォルダ

**Files:**
- Create（生成）: Phoenixプロジェクト一式（下記の手順で生成する）
- Create: `lib/susumi/runtime/data_dir.ex`, `lib/susumi/runtime/local_config.ex`, `docs/phoenix-usage-rules.md`
- Modify: `config/runtime.exs`, `config/dev.exs`, `config/test.exs`, `config/config.exs`, `.gitignore`, `AGENTS.md`
- Test: `test/susumi/runtime/data_dir_test.exs`, `test/susumi/runtime/local_config_test.exs`

**Interfaces:**
- Produces:
  - `Susumi.Runtime.DataDir.default_path(os_type :: {atom, atom}, env :: %{String.t() => String.t()}) :: String.t()`
  - `Susumi.Runtime.DataDir.path() :: String.t()`（`SUSUMI_DATA_DIR` があればそれを優先）
  - `Susumi.Runtime.DataDir.ensure!() :: String.t()`（フォルダと `backups/` を作り、パスを返す）
  - `Susumi.Runtime.DataDir.database_path(dir) :: String.t()`（`dir/susumi.db`）、`backups_path(dir)`（`dir/backups`）
  - `Susumi.Runtime.LocalConfig.load(dir) :: %{port: pos_integer(), staff_idle_minutes: pos_integer()}`
  - `Susumi.Runtime.LocalConfig.secret_key_base!(dir) :: String.t()`

- [ ] **Step 1: git初期化とプロジェクト生成**

Phoenix 1.8の `mix phx.new` は `AGENTS.md` を生成するため、既存のものを上書きしないよう別の場所で生成してからコピーする。

```bash
cd /Users/hiro/Projetct/GitHub/Memory-board && git init
mix archive.install hex phx_new --force
mix phx.new "$SCRATCH/susumi" --app susumi --module Susumi --database sqlite3 --no-mailer --install
rsync -a --exclude AGENTS.md --exclude .git "$SCRATCH/susumi/" ./
cp "$SCRATCH/susumi/AGENTS.md" docs/phoenix-usage-rules.md
```

`$SCRATCH` はセッションのスクラッチディレクトリを指す。`.gitignore` には `/.superpowers/` と `/burrito_out/` と `*.db*` を追加する。`AGENTS.md` の「技術スタック」の節の末尾に、次の1行を追加する。

```
- Phoenix / LiveView の一般的な書き方は `docs/phoenix-usage-rules.md`（`mix phx.new` が生成したもの）に従う。
```

- [ ] **Step 2: 失敗するテストを書く**

```elixir
# test/susumi/runtime/data_dir_test.exs
test "Windowsの既定はLOCALAPPDATA配下" do
  assert DataDir.default_path({:win32, :nt}, %{"LOCALAPPDATA" => "C:/Users/a/AppData/Local"}) ==
           "C:/Users/a/AppData/Local/Susumi"
end
test "macOSの既定はApplication Support配下" do
  assert DataDir.default_path({:unix, :darwin}, %{"HOME" => "/Users/a"}) ==
           "/Users/a/Library/Application Support/Susumi"
end
test "それ以外（開発用Linux）は ~/.local/share/susumi" do
  assert DataDir.default_path({:unix, :linux}, %{"HOME" => "/home/a"}) == "/home/a/.local/share/susumi"
end
test "ensure! は backups まで作る", %{tmp_dir: dir} do
  System.put_env("SUSUMI_DATA_DIR", Path.join(dir, "d"))
  on_exit(fn -> System.delete_env("SUSUMI_DATA_DIR") end)
  path = DataDir.ensure!()
  assert File.dir?(Path.join(path, "backups"))
end

# test/susumi/runtime/local_config_test.exs  (@moduletag :tmp_dir)
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
test "secret_key_base は初回に作り、2回目は同じ値を返す", %{tmp_dir: dir} do
  a = LocalConfig.secret_key_base!(dir)
  assert String.length(a) >= 64
  assert LocalConfig.secret_key_base!(dir) == a
end
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `mix test test/susumi/runtime`
Expected: FAIL（`Susumi.Runtime.DataDir` が未定義）

- [ ] **Step 4: `DataDir` と `LocalConfig` を実装し、設定ファイルにつなぐ**

- `secret_key_base` は `:crypto.strong_rand_bytes(64) |> Base.encode64()` で作り、`dir/secret_key_base` に保存する。
- `config/runtime.exs` の `:prod` ブロックで、次を設定する。
  - `dir = DataDir.ensure!()` と `LocalConfig.load(dir)` の結果を使う。
  - `Susumi.Repo`: `database: DataDir.database_path(dir)`、`journal_mode: :wal`、`busy_timeout: 5000`、`pool_size: 5`
  - `SusumiWeb.Endpoint`: `http: [ip: {0, 0, 0, 0}, port: port]`、`url: [host: "localhost"]`、`secret_key_base: LocalConfig.secret_key_base!(dir)`、`server: true`、`check_origin: :conn`
  - `config :susumi, staff_idle_minutes: ..., data_dir: dir, open_browser: true, auto_migrate: true`
- `config/config.exs` には `config :susumi, staff_idle_minutes: 60, open_browser: false, auto_migrate: false` を置く。
- `config/dev.exs` では、Endpointの `ip` を `{0, 0, 0, 0}` にし、Repoに `journal_mode: :wal, busy_timeout: 5000` を足す。
- `PHX_SERVER` などの環境変数に頼らなくても起動するようにする。

- [ ] **Step 5: テストが通ることを確認する**

Run: `mix test && mix compile --warnings-as-errors`
Expected: PASS（生成されたテストも含めて全件）

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: Phoenixプロジェクト作成とデータフォルダの解決"
```

---

### Task 2: 起動処理・単体実行ファイル・Windows CIとmacOS実機での確認（スパイク）

**Files:**
- Create: `lib/susumi/runtime/boot.ex`, `lib/susumi/settings.ex`, `lib/susumi/settings/setting.ex`, `priv/repo/migrations/*_create_settings.exs`, `lib/susumi_web/live/check_live.ex`（Task 14で削除する）, `docs/manual/spike-checklist.md`
- Create: `.github/workflows/windows.yml`, `.github/scripts/release-smoke.cjs`
- Modify: `lib/susumi/application.ex`, `mix.exs`, `lib/susumi_web/router.ex`
- Test: `test/susumi/settings_test.exs`, `test/susumi/runtime/boot_test.exs`, `test/susumi_web/live/check_live_test.exs`

**Interfaces:**
- Consumes: `DataDir.backups_path/1`, `config :susumi, :auto_migrate / :open_browser / :data_dir`
- Produces:
  - `Susumi.Settings.get(key :: String.t(), default :: String.t() | nil) :: String.t() | nil`
  - `Susumi.Settings.put(key :: String.t(), value :: String.t()) :: :ok`
  - `Susumi.Settings.facility_name() :: String.t()`（未設定なら `""`）、`put_facility_name(String.t()) :: :ok`
  - `Susumi.Runtime.Boot.migrate_with_backup!(repo :: module, backups_dir :: String.t(), now :: NaiveDateTime.t()) :: :up_to_date | {:migrated, String.t() | nil}`
  - `Susumi.Runtime.Boot.port_available?(port :: pos_integer) :: boolean`
  - `Susumi.Runtime.Boot.lan_urls(port :: pos_integer, ifaddrs :: list) :: [String.t()]`
  - `Susumi.Runtime.Boot.banner(port, lan_urls, version :: String.t()) :: String.t()`
  - `Susumi.Runtime.Boot.open_browser(url :: String.t()) :: :ok`

- [ ] **Step 1: 失敗するテストを書く**

```elixir
# settings_test.exs
test "put した値を get で読める" do
  :ok = Settings.put("facility_name", "ひまわり作業所")
  assert Settings.facility_name() == "ひまわり作業所"
  assert Settings.get("missing", "x") == "x"
end

# boot_test.exs
test "lan_urls はループバック以外のIPv4だけを返す" do
  ifaddrs = [{~c"lo0", [addr: {127, 0, 0, 1}]}, {~c"en0", [addr: {192, 168, 1, 20}, addr: {0xfe80, 0, 0, 0, 0, 0, 0, 1}]}]
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
end
@tag :tmp_dir
test "未適用のマイグレーションがあり既存DBなら、複製を作ってから適用する", %{tmp_dir: dir} do
  # 一時DBのRepoを1つ起動し、最初のマイグレーションだけ適用した状態から呼ぶ
  # 戻り値 {:migrated, path} の path が dir/susumi-20261031-090000.db で存在すること
  # 2回目は :up_to_date
end
test "新規DB（適用済みが0件）なら複製は作らない" # 戻り値 {:migrated, nil}

# check_live_test.exs
test "ボタンで数が増え、別のLiveViewにも反映される", %{conn: conn} do
  {:ok, a, _} = live(conn, "/_check")
  {:ok, b, _} = live(conn, "/_check")
  a |> element("button", "+1") |> render_click()
  assert render(b) =~ "回数: 1"
end
```

マイグレーションのテストは、テスト専用のマイグレーションを2本、`test/support/boot_migrations/` に置いて使う。

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/settings_test.exs test/susumi/runtime/boot_test.exs test/susumi_web/live/check_live_test.exs`
Expected: FAIL（モジュールが未定義）

- [ ] **Step 3: 実装する**

- `settings` テーブル: `key :string`（unique）、`value :text`、timestamps
- `migrate_with_backup!`:
  1. `Ecto.Migrator.with_repo/2` の中で `Ecto.Migrator.migrations(repo)` を呼ぶ。
  2. `:down` が1件以上あり、かつ `:up` も1件以上あれば、`VACUUM INTO '<backups>/susumi-YYYYMMDD-HHMMSS.db'` を実行する。
  3. その後 `Ecto.Migrator.run(repo, :up, all: true)` を実行する。
- `open_browser`:
  - `:os.type()` で分岐し、`{:win32, _}` は `System.cmd("cmd", ["/c", "start", "", url])` で開く。
  - darwinは `open`、それ以外は `xdg-open` で開く。
  - 失敗しても無視する。
- `Application.start/2`:
  1. `auto_migrate` がtrueなら、子プロセスを起動する前に `migrate_with_backup!(Susumi.Repo, DataDir.backups_path(data_dir), NaiveDateTime.local_now())` を呼ぶ。
  2. ポートが使えなければ、`IO.puts("ポート#{port}は、ほかのソフトが使っています。ほかのすすみを閉じるか、config.json の port を変えてください。")` を表示する。30秒待ってから `System.halt(1)` で終了する。
  3. Supervisorを起動した後、`open_browser` がtrueなら `banner` を `IO.puts` し、`http://localhost:#{port}` を開く。
- `CheckLive`（`/_check`）:
  - `Settings` の `"check_counter"` を表示し、「+1」で増やす。
  - PubSubトピック `"check"` で `{:check_changed}` を送り、受け取った画面は再読込する。
  - 表示は `回数: N` とする。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Burritoを設定し、macOS向けにビルドして起動する**

`mix.exs` に、`{:burrito, "~> 1.0"}`（実装時点の最新版）と次のリリース設定を足す。

```elixir
releases: [
  susumi: [
    steps: [:assemble, &Burrito.wrap/1],
    burrito: [targets: [
      windows: [os: :windows, cpu: :x86_64],
      macos_arm: [os: :darwin, cpu: :aarch64],
      macos_intel: [os: :darwin, cpu: :x86_64]
    ]]
  ]
]
```

BurritoのREADMEにある前提ツール（zig の指定版、xz、7z）を入れる。そのうえで次を実行する。

Run: `MIX_ENV=prod mix assets.deploy && MIX_ENV=prod BURRITO_TARGET=macos_arm mix release`
Expected: `burrito_out/susumi_macos_arm` ができる。

これをFinderから起動して、次を確認する。
- ブラウザで画面が開く。
- `~/Library/Application Support/Susumi/susumi.db` ができる。
- `/_check` で数が増える。
- 再起動後も数が残る。
- 同じLANの別端末から `/_check` を開くと、数の変化がその場で反映される。

- [ ] **Step 6: Windows向けのビルドと起動確認をCIに追加する**

`.github/workflows/windows.yml` を追加し、push・pull request・手動実行で次を確認する。

1. Ubuntuランナーで `mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix test` を実行する。
2. Burritoが要求する版のZig、xz、7zを用意し、`MIX_ENV=prod mix assets.deploy` と `MIX_ENV=prod BURRITO_TARGET=windows mix release` で `.exe` をクロスビルドする。BurritoはWindows上でのビルドを公式にはサポートしていない。
3. `.exe` をartifactとしてWindowsランナーに渡す。Windows側にはElixir・Erlangを追加インストールせず、配布物を起動する。
4. `.github/scripts/release-smoke.cjs` で、HTTP応答、データファイル作成、SQLiteへの書き込み、2画面間のLiveView同期、二重起動の案内、停止と再起動後のデータ保持を確認する。
5. 起動ログとブラウザのトレースを、失敗時もartifactとして保存する。

`docs/manual/spike-checklist.md` にCIの確認項目と検証範囲外の項目を書く。Windowsの実機確認や画面写真の提供を依頼者に求めない。【2026-11-04 決定】

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: 起動処理・自動マイグレーション・Burritoによる単体実行ファイル"
```

- [ ] **Step 8: ゲート — Windows CIとmacOS実機確認の結果を確認する**

- Windows CIとStep 5のmacOS実機確認が通ったら、Task 3へ進む。依頼者によるWindows実機確認は待たない。
- 失敗した場合は内容を報告し、原因を修正する。配布方式の変更が必要なら、設計書6.7の代わりの案を依頼者と相談する。

---

### Task 3: アカウントとログイン失敗の制限

**Files:**
- Create: `priv/repo/migrations/*_create_accounts.exs`, `lib/susumi/accounts.ex`, `lib/susumi/accounts/account.ex`, `lib/susumi/accounts/login_throttle.ex`
- Modify: `lib/susumi/application.ex`（`LoginThrottle` をSupervisorに足す）, `mix.exs`（`{:pbkdf2_elixir, "~> 2.0"}`）
- Test: `test/susumi/accounts_test.exs`, `test/susumi/accounts/login_throttle_test.exs`, `test/support/fixtures/accounts_fixtures.ex`

**Interfaces:**
- Consumes: `Susumi.Settings.put_facility_name/1`
- Produces:
  - `%Susumi.Accounts.Account{id, name, name_kana, role :: "staff" | "client", password_hash, active :: boolean, show_furigana :: boolean}`
  - `Accounts.create_account(attrs) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}`（attrsのキー: `name, name_kana, role, password, show_furigana`）
  - `Accounts.update_account(Account.t(), attrs) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}`（`name, name_kana, show_furigana` だけ）
  - `Accounts.reset_password(Account.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}`
  - `Accounts.deactivate(Account.t()) :: {:ok, Account.t()} | {:error, :last_staff}`、`Accounts.reactivate(Account.t()) :: {:ok, Account.t()}`
  - `Accounts.authenticate(account_id :: integer, password :: String.t(), now :: integer \\ System.monotonic_time(:second)) :: {:ok, Account.t()} | {:error, :invalid | :locked}`
  - `Accounts.list_active(:staff | :client) :: [Account.t()]`（`name_kana` の昇順。`nil` は最後。同じなら `name` の昇順）
  - `Accounts.list_accounts() :: [Account.t()]`、`Accounts.get_account!(id)`、`Accounts.any_staff?() :: boolean`
  - `Accounts.create_initial_staff(facility_name :: String.t(), attrs) :: {:ok, Account.t()} | {:error, :already_set_up | Ecto.Changeset.t()}`
  - `Susumi.Accounts.LoginThrottle.check(id, now) :: :ok | {:error, :locked}`、`record_failure(id, now) :: :ok`、`reset(id) :: :ok`
  - Fixtures: `staff_fixture(attrs \\ %{})`, `client_fixture(attrs \\ %{})`（パスワードの既定値: 職員 `"password1"`、利用者 `"1234"`）

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "利用者は4文字以上で作れる" do
  assert {:ok, a} = Accounts.create_account(%{name: "田中 花子", name_kana: "たなか はなこ", role: "client", password: "1234"})
  assert a.active and not a.show_furigana
  assert {:error, cs} = Accounts.create_account(%{name: "佐藤", role: "client", password: "123"})
  assert "4文字以上で入力してください" in errors_on(cs).password
end
test "職員は8文字以上" do
  assert {:error, cs} = Accounts.create_account(%{name: "山田", role: "staff", password: "1234567"})
  assert "8文字以上で入力してください" in errors_on(cs).password
end
test "同じ役割で同じ名前は作れない" do
  client_fixture(%{name: "田中"})
  assert {:error, cs} = Accounts.create_account(%{name: "田中", role: "client", password: "1234"})
  assert "同じ名前がすでにあります" in errors_on(cs).name
end
test "役割は staff か client だけ" # role: "admin" → errors_on(cs).role != []
test "全角で入れたパスワードでも半角で登録したものと一致する" do
  a = client_fixture(%{password: "1234"})
  assert {:ok, _} = Accounts.authenticate(a.id, "１２３４")
end
test "最後の有効な職員は無効化できない" do
  s = staff_fixture()
  assert {:error, :last_staff} = Accounts.deactivate(s)
  staff_fixture()
  assert {:ok, %{active: false}} = Accounts.deactivate(s)
end
test "無効化したアカウントは正しいパスワードでも :invalid" # client → deactivate → authenticate == {:error, :invalid}
test "list_active はよみ順で、無効化した人を含まない"
test "初回設定は職員がいると :already_set_up" do
  assert {:ok, _} = Accounts.create_initial_staff("ひまわり作業所", %{name: "山田", password: "password1"})
  assert Settings.facility_name() == "ひまわり作業所"
  assert {:error, :already_set_up} = Accounts.create_initial_staff("x", %{name: "鈴木", password: "password1"})
end

# login_throttle_test.exs
test "4回の失敗ではロックしない。5回でロックし、300秒後に解ける" do
  for _ <- 1..4, do: LoginThrottle.record_failure(1, 1000)
  assert :ok = LoginThrottle.check(1, 1000)
  LoginThrottle.record_failure(1, 1000)
  assert {:error, :locked} = LoginThrottle.check(1, 1299)
  assert :ok = LoginThrottle.check(1, 1300)
end
test "ロック中は正しいパスワードでも :locked" # authenticate(a.id, "1234", now) == {:error, :locked}
test "成功すると回数が0に戻る"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/accounts_test.exs test/susumi/accounts/login_throttle_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

- `accounts` テーブル: `name` 必須、`name_kana`、`role` 必須、`password_hash` 必須、`active` 既定 true、`show_furigana` 既定 false、timestamps。`unique_index(:accounts, [:role, :name])` を張る。
- パスワードは `:unicode.characters_to_nfkc_binary/1` で正規化してから `Pbkdf2.hash_pwd_salt/1` する。照合も正規化してから `Pbkdf2.verify_pass/2` で行う。アカウントが無い場合は `Pbkdf2.no_user_verify/0` を呼ぶ。
- `LoginThrottle` はETSを持つGenServerにする。値は `{account_id, failures, locked_until}`。
- `create_initial_staff` は `Repo.transaction` の中で `any_staff?` を確認し、`role: "staff"` で作成してから施設名を保存する。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: アカウントとログイン失敗の制限"
```

---

### Task 4: セッションと認可の土台

**Files:**
- Create: `priv/repo/migrations/*_create_account_sessions.exs`, `lib/susumi/accounts/session.ex`, `lib/susumi_web/auth.ex`, `lib/susumi_web/controllers/session_controller.ex`, `lib/susumi_web/controllers/root_controller.ex`, `lib/susumi_web/live/home_live.ex`（見出しだけの仮の画面）, `lib/susumi_web/live/board_live/index.ex`（仮の画面）
- Modify: `lib/susumi/accounts.ex`, `lib/susumi_web/router.ex`, `lib/susumi_web/endpoint.ex`（セッションのCookieに `max_age: 30 * 24 * 60 * 60`）
- Test: `test/susumi/accounts/session_test.exs`, `test/susumi_web/auth_test.exs`, `test/support/conn_case.ex`（ヘルパーを追加）

**Interfaces:**
- Consumes: `Accounts.authenticate/2`, `Accounts.any_staff?/0`
- Produces:
  - `Accounts.create_session(Account.t()) :: String.t()`（生のトークン。DBにはSHA-256のハッシュを保存する）
  - `Accounts.get_account_by_session(token, now :: DateTime.t() \\ DateTime.utc_now()) :: Account.t() | nil`（期限切れのとき、または無効なアカウントのときは `nil`）
  - `Accounts.touch_session(token, now \\ DateTime.utc_now()) :: :ok`（前回から60秒以上たっているときだけ更新する）
  - `Accounts.delete_session(token) :: :ok`
  - `Accounts.delete_sessions(Account.t()) :: :ok`（その人のセッションをすべて消し、`SusumiWeb.Endpoint.broadcast("account_sessions:#{id}", "disconnect", %{})` を送る）。`deactivate/1` と `reset_password/2` の成功時にも呼ぶ。
  - Plug: `SusumiWeb.Auth.fetch_current_account/2`、`require_setup/2`（職員が0人なら `/setup` へ）
  - `on_mount`: `{SusumiWeb.Auth, :require_staff}`、`{SusumiWeb.Auth, :require_client}`、`{SusumiWeb.Auth, :redirect_if_logged_in}`。`socket.assigns.current_account` を設定する。
  - ルート: `GET /` は役割で振り分ける（利用者 → `/home`、職員 → `/boards`、未ログイン → `/login`）。`POST /login` は `SessionController.create`、`DELETE /logout` は `SessionController.delete`。
  - セッションのキー: `"session_token"`、`"live_socket_id" => "account_sessions:#{id}"`
  - ConnCaseのヘルパー: `log_in(conn, account) :: Plug.Conn.t()`

- [ ] **Step 1: 失敗するテストを書く**

```elixir
# session_test.exs
test "職員は最終操作から60分で切れる" do
  s = staff_fixture(); t = Accounts.create_session(s)
  base = DateTime.utc_now()
  assert Accounts.get_account_by_session(t, DateTime.add(base, 59, :minute))
  refute Accounts.get_account_by_session(t, DateTime.add(base, 61, :minute))
end
test "利用者は30日で切れる" # 29日後は取れる、31日後は nil
test "staff_idle_minutes の設定に従う" # Application.put_env(:susumi, :staff_idle_minutes, 10) で、11分後は nil
test "無効化するとセッションが消え、disconnect が送られる" do
  c = client_fixture(); t = Accounts.create_session(c); staff_fixture()
  SusumiWeb.Endpoint.subscribe("account_sessions:#{c.id}")
  {:ok, _} = Accounts.deactivate(c)
  refute Accounts.get_account_by_session(t)
  assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
end
test "パスワードを再設定してもセッションが消える"

# auth_test.exs
test "職員がいなければ /login は /setup へ" # get(conn, "/login") → redirected_to == "/setup"
test "未ログインで /boards は /login へ"
test "利用者が /boards を開くと /home へ", %{conn: conn} # log_in(conn, client) → {:error, {:redirect, %{to: "/home"}}} = live(conn, "/boards")
test "職員が /home を開くと /boards へ"
test "POST /login が成功すると / を経て役割の画面へ" # post(conn, "/login", %{"account_id" => id, "password" => "1234"}) → "/" → "/home"
test "パスワードが違うと flash に「名前かパスワードがちがいます」"
test "5回まちがえた後は「パスワードを5回まちがえました。5分たってから、もう一度ためしてください」"
test "職員の画面は60分操作がないと /login へ戻り、「しばらく操作がなかったため、ログアウトしました」と出る"
  # セッションの last_seen_at をDBで61分前に書き換え、send(view.pid, :idle_check) → assert_redirect(view, "/login")
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/accounts/session_test.exs test/susumi_web/auth_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

- `account_sessions` テーブル: `account_id`（`on_delete: :delete_all`）、`token_hash :binary`（unique）、`last_seen_at :utc_datetime`、timestamps
- `:require_staff` の処理:
  - `mount` 時に `touch_session` を呼ぶ。
  - `attach_hook(:touch, :handle_event, ...)` で、イベントのたびに `touch_session` を呼ぶ。
  - 接続中は `Process.send_after(self(), :idle_check, 60_000)` を繰り返し、`attach_hook(:idle, :handle_info, ...)` で `:idle_check` を処理する。セッションが `nil` になっていたら `/login` へリダイレクトし、flashを出す。
- `SessionController.create` の処理:
  - 成功したら `configure_session(renew: true)` を呼び、トークンと `live_socket_id` を保存してから `/` へ送る。
  - ログアウトでは `delete_session` を呼び、`live_socket_id` へ disconnect を送る。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: セッションと役割による画面の振り分け"
```

---

### Task 5: ふりがなの部品と固定文言

**Files:**
- Create: `lib/susumi_web/components/ruby.ex`, `lib/susumi_web/copy.ex`
- Modify: `lib/susumi_web.ex`（`html_helpers` で `import SusumiWeb.Ruby`）
- Test: `test/susumi_web/components/ruby_test.exs`

**Interfaces:**
- Produces:
  - `<.ruby text={String.t()} kana={String.t() | nil} show={boolean} />`
    - `show` が true で、`kana` が空でないときだけ `<ruby>text<rp>(</rp><rt>kana</rt><rp>)</rp></ruby>` を出す。
    - それ以外は `text` をそのまま出す。
  - `<.copy key={atom} show={boolean} />`（`SusumiWeb.Copy.get/1` の文言を `.ruby` で出す）
  - `SusumiWeb.Copy.get(key :: atom) :: {text :: String.t(), kana :: String.t()}`（未知のキーは `KeyError`）

固定文言の一覧（この表が正）:

| key | text | kana |
|-----|------|------|
| `:staff` | 職員 | しょくいん |
| `:client` | 利用者 | りようしゃ |
| `:password` | パスワード | ぱすわーど |
| `:login` | ログイン | ろぐいん |
| `:logout` | ログアウト | ろぐあうと |
| `:choose_name` | 名前をえらんでください | なまえをえらんでください |
| `:today` | 今日やる作業 | きょうやるさぎょう |
| `:other` | そのほかの作業 | そのほかのさぎょう |
| `:next_step` | 次の段階へ | つぎのだんかいへ |
| `:back_step` | 一つ戻す | ひとつもどす |
| `:now` | いま | いま |
| `:staff_review` | 職員が確認中 | しょくいんがかくにんちゅう |
| `:overdue` | 予定日を過ぎています | よていびをすぎています |
| `:done` | 完了しました | かんりょうしました |
| `:nothing` | 今の作業はありません | いまのさぎょうはありません |
| `:cannot_move` | この作業は動かせません | このさぎょうはうごかせません |

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "show かつ kana ありなら ruby を出す" do
  html = render_component(&Ruby.ruby/1, text: "写真作業", kana: "しゃしんさぎょう", show: true)
  assert html =~ "<rt>しゃしんさぎょう</rt>"
end
test "show が false なら ruby を出さない" # refute html =~ "<rt>"
test "kana が空なら ruby を出さない"     # kana: "" と kana: nil の両方
test "copy は表の文言を出す" # render_component(&Ruby.copy/1, key: :next_step, show: true) =~ "<rt>つぎのだんかいへ</rt>"
test "未知のキーは KeyError" # assert_raise KeyError, fn -> Copy.get(:nope) end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/components/ruby_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**（`Copy` は上の表をそのままmapにする）

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test test/susumi_web/components/ruby_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ふりがなの部品と利用者向けの固定文言"
```

---

### Task 6: 初回設定とログイン画面

**Files:**
- Create: `lib/susumi_web/live/setup_live.ex`, `lib/susumi_web/live/login_live.ex`
- Modify: `lib/susumi_web/router.ex`, `lib/susumi_web/components/layouts.ex`（ヘッダーに `Settings.facility_name()` を出し、ログイン中ならログアウトボタンも出す）
- Test: `test/susumi_web/live/setup_live_test.exs`, `test/susumi_web/live/login_live_test.exs`

**Interfaces:**
- Consumes: `Accounts.create_initial_staff/2`, `Accounts.list_active/1`, `POST /login`, `.ruby` / `.copy`
- Produces:
  - `/setup`: 入力欄は「施設名」「職員の名前」「よみ」「パスワード」「パスワード（確認）」。成功したら `/login` へ移り、flash「設定が終わりました。ログインしてください」を出す。すでに職員がいれば `/login` へリダイレクトする。
  - `/login`: 3段階の画面にする。
    1. 「職員」「利用者」を選ぶ大きなボタン（`phx-click="choose_role"`）
    2. 名前の一覧（`phx-click="choose_account"`）と「もどる」ボタン
    3. パスワードの入力（`phx-trigger-action` で `POST /login` に `account_id` と `password` を送る）
  - ログイン画面では、文言と名前に常にふりがなを付ける（`show={true}`）。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "初回設定で職員と施設名ができ、/login へ移る" # submit → assert_redirect(view, "/login"); Accounts.any_staff?()
test "パスワード（確認）が違うとエラー「パスワードが一致しません」"
test "設定済みなら /setup は /login へ"
test "利用者を選ぶと、有効な利用者だけがよみ付きで並ぶ" do
  staff_fixture(); client_fixture(%{name: "田中", name_kana: "たなか"}); c2 = client_fixture(%{name: "佐藤"}); staff_fixture(); Accounts.deactivate(c2)
  {:ok, v, _} = live(conn, "/login")
  html = v |> element("button", "利用者") |> render_click()
  assert html =~ "<rt>たなか</rt>"
  refute html =~ "佐藤"
end
test "名前を選ぶとパスワード欄が出て、送信で phx-trigger-action が立つ"
test "ログイン済みなら /login は / へ"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/live/setup_live_test.exs test/susumi_web/live/login_live_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

ボタンは押しやすい大きさにする（目安は `min-h-16 text-2xl`）。キーボードでも順に操作でき、フォーカスリングを消さないこと。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 初回設定とログイン画面"
```

---

### Task 7: ボードと列

**Files:**
- Create: `priv/repo/migrations/*_create_kanban.exs`（boards・columns・cardsの3テーブルをまとめて作る）, `lib/susumi/kanban.ex`, `lib/susumi/kanban/board.ex`, `lib/susumi/kanban/column.ex`, `lib/susumi/kanban/card.ex`, `lib/susumi/kanban/positions.ex`
- Test: `test/susumi/kanban/positions_test.exs`, `test/susumi/kanban_boards_test.exs`, `test/support/fixtures/kanban_fixtures.ex`

**Interfaces:**
- Produces:
  - テーブル:
    - `kanban_boards`: `name` 必須、`name_kana`、`board_type` 必須、`description :text`
    - `kanban_columns`: `board_id`（`on_delete: :delete_all`）、`name` 必須、`name_kana`、`column_type` 必須、`position` 必須
    - `kanban_cards`: `column_id`（`on_delete: :delete_all`）、`title` 必須、`title_kana`、`description :text`、`assignee_id`（`accounts`、`on_delete: :nilify_all`）、`related_user_id`（同じく）、`scheduled_on :date`、`position` 必須
    - インデックス: `(board_id, position)`、`(column_id, position)`、`related_user_id`
  - `Susumi.Kanban.Positions.move(ids :: [id], id, to_index :: integer) :: [id]`（`to_index` は `0..length-1` に丸める）
  - `Kanban.list_boards() :: [Board.t()]`（`board_type`、`name` の順に並べる）
  - `Kanban.get_board!(id) :: Board.t()`（columnsを `position` 順にpreloadし、その中のcardsも `position` 順にpreloadする。cardsには `assignee` と `related_user` もpreloadする）
  - `Kanban.create_board(attrs)`、`update_board(board, attrs)`、`delete_board(board)`。戻り値は `{:ok, Board.t()} | {:error, Ecto.Changeset.t()}`
  - `Kanban.create_column(board, attrs) :: {:ok, Column.t()} | {:error, Ecto.Changeset.t()}`（末尾に追加する）
  - `Kanban.update_column(column, attrs)`（`name, name_kana, column_type`）
  - `Kanban.move_column(column, to_index) :: {:ok, [Column.t()]}`
  - `Kanban.delete_column(column) :: {:ok, Column.t()} | {:error, :not_empty}`（削除したら残りを0..n-1に振り直す）
  - `Kanban.done_column_id(board_id) :: integer | nil`（`position` が最大の列）
  - PubSub:
    - `Kanban.subscribe_boards()`: トピック `"boards"`、メッセージ `{:boards_changed}`
    - `Kanban.subscribe_board(board_id)`: トピック `"board:#{id}"`、メッセージ `{:board_changed, board_id}`
    - `Kanban.subscribe_client(account_id)`: トピック `"client:#{id}"`、メッセージ `{:home_changed}`
  - ボードや列が変わったとき:
    - `"boards"` と `"board:#{id}"` に送る。
    - そのボードのカードを担当している利用者さん全員の `"client:#{id}"` にも送る。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
# positions_test.exs
test "同じ並びの中で動かす" # move([1,2,3], 1, 2) == [2,3,1]
test "先頭へ"               # move([1,2,3], 3, 0) == [3,1,2]
test "範囲外は末尾に丸める" # move([1,2,3], 1, 99) == [2,3,1]; move([1,2,3], 3, -1) == [3,1,2]

# kanban_boards_test.exs
test "board_type は必須で、決まった値だけ" # nil → "選んでください"、"other" → エラー
test "職員専用ボードに利用者用の列は作れない" do
  b = board_fixture(%{board_type: "staff_task"})
  assert {:error, cs} = Kanban.create_column(b, %{name: "受け取り", column_type: "user"})
  assert "職員専用ボードには職員用の列しか作れません" in errors_on(cs).column_type
end
test "列は末尾に 0,1,2 と付く"
test "move_column で並びが振り直される"
test "カードが残っている列は削除できない" # {:error, :not_empty}
test "列を削除すると残りの position が詰まる"
test "done_column_id は一番右の列"
test "列を作ると board と、カードを持つ利用者に通知が届く"
  # subscribe_board(b.id); subscribe_client(c.id); create_column → assert_receive {:board_changed, _}; assert_receive {:home_changed}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/kanban`
Expected: FAIL

- [ ] **Step 3: 実装する**

位置の振り直しは、`Positions.move` で得た並びをもとに、`Repo.transaction` の中で1件ずつ `position` を更新する。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Kanbanのボードと列"
```

---

### Task 8: カードの作成と移動

**Files:**
- Modify: `lib/susumi/kanban.ex`, `lib/susumi/kanban/card.ex`
- Test: `test/susumi/kanban_cards_test.exs`

**Interfaces:**
- Consumes: `Positions.move/3`、Task 7のPubSub
- Produces:
  - `Kanban.create_card(column, attrs) :: {:ok, Card.t()} | {:error, Ecto.Changeset.t()}`（末尾に追加する。attrsのキー: `title, title_kana, description, assignee_id, related_user_id, scheduled_on`）
  - `Kanban.update_card(card, attrs)`、`Kanban.delete_card(card)`（削除したら、同じ列の残りを詰める）
  - `Kanban.move_card(card_id, to_column_id, to_index) :: {:ok, Card.t()} | {:error, :not_found | :invalid_column}`
    - `to_column_id` は、カードと同じボードの列でなければならない。
    - 移動元と移動先の両方の列を0..n-1に振り直す。
  - カードが変わったときは、`"board:#{id}"` に送る。変更前と変更後の `related_user_id` の `"client:#{id}"` にも送る。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "担当の利用者は利用者アカウントで、利用者作業ボードのときだけ付けられる" do
  # staff_task ボードで related_user_id を付ける → "利用者作業ボードでだけ選べます"
  # related_user_id に職員を付ける → "利用者を選んでください"
  # assignee_id に利用者を付ける → "職員を選んでください"
end
test "同じ列の中で移動する" # [a,b,c] で a を index 2 へ → [b,c,a]、position は 0,1,2
test "別の列の先頭へ移動し、移動元が詰まる"
test "空の列へ移動する"
test "範囲外の index は末尾へ"
test "別のボードの列へは :invalid_column"
test "削除済みのカードは :not_found"
test "担当の利用者を変えると、変更前と変更後の両方に {:home_changed} が届く"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/kanban_cards_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

`move_card` は、`Repo.transaction` の中でカードを読み直してから計算する。カードが見つからなければ `:not_found` を返す。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: カードの作成と位置付きの移動"
```

---

### Task 9: 利用者の「進める・戻す」とホーム画面のデータ

**Files:**
- Create: `lib/susumi/clock.ex`, `lib/susumi/kanban/home.ex`
- Modify: `lib/susumi/kanban.ex`
- Test: `test/susumi/kanban_home_test.exs`

**Interfaces:**
- Consumes: `Kanban.move_card/3`, `Kanban.done_column_id/1`
- Produces:
  - `Susumi.Clock.today() :: Date.t()`（`:calendar.local_time()` から作る）
  - `Kanban.advance_card(client :: Account.t(), card_id, from_column_id) :: {:ok, %{card: Card.t(), done?: boolean}} | {:error, :not_found | :stale | :locked | :at_end}`
  - `Kanban.retreat_card(client, card_id, from_column_id) :: {:ok, %{card: Card.t(), done?: false}} | {:error, :not_found | :stale | :locked | :at_start | :staff_column}`
  - `Kanban.client_home(client :: Account.t(), today :: Date.t()) :: %{today: [Home.item()], other: [Home.item()]}`
  - `Home.item()`:

    ```
    %{card: Card.t(), board: Board.t(),
      steps: [%{column: Column.t(), state: :done | :current | :todo}],
      status: :in_progress | :staff_review,
      overdue?: boolean, can_advance?: boolean, can_retreat?: boolean}
    ```

ルール（設計書5.4のとおり）:
- `:not_found` になるのは次のとき。
  - カードがない。
  - カードの `related_user_id` が本人でない。
  - ボードが `user_progress` でない。
- `:stale` は、カードの今の列が `from_column_id` と違うとき（Review Focus 2）。
- `:locked` は、今の列が職員用のとき。
- 「進める」は、`position` の順で右隣の列の末尾へ動かす。
  - 右隣がない（完了の列にいる）ときは `:at_end`。
  - 移動先が完了の列なら `done?: true`。
- 「戻す」は、左隣の列の末尾へ動かす。
  - 左隣がないときは `:at_start`。
  - 左隣が職員用の列なら `:staff_column`。
- `client_home` の対象は、本人の `user_progress` ボードのカードのうち、完了の列にないもの。
  - `today`: `scheduled_on <= today` のもの。予定日の昇順で並べ、`overdue?` は `scheduled_on < today`。
  - `other`: `scheduled_on` が `nil`、または `> today` のもの。予定日の昇順で並べ、`nil` は最後。
  - 同じ順位のときは、ボード名、カードの `position` の順に並べる。
- `steps` には利用者用の列だけを並べる。
  - 今の列が利用者用のときは、その列を `:current` にし、左を `:done`、右を `:todo` にする。
  - 今の列が職員用のときは、`status: :staff_review` にする。その職員用の列より左の利用者用の列を `:done`、右を `:todo` にする。`:current` はなし。
- `can_advance?` / `can_retreat?` は、上のルールで `:ok` になるかどうかで決める。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
# 準備: 列 [受け取り(user), 選別(user), 確認(staff), 仕上げ(user), 完了(user)]
test "進めると右隣の末尾へ。完了の列へ入ると done?: true"
test "職員用の列へは進められる"
test "職員用の列にいると、進めるも戻すも :locked"
test "左隣が職員用なら戻せない" # 仕上げ → 戻す == {:error, :staff_column}
test "一番左では :at_start"
test "古い from_column_id なら :stale で、カードは動かない" do
  {:ok, _} = Kanban.advance_card(c, card.id, col_uketori.id)
  assert {:error, :stale} = Kanban.advance_card(c, card.id, col_uketori.id)
  assert Repo.reload(card).column_id == col_senbetsu.id
end
test "他人のカードと職員専用ボードのカードは :not_found"
test "今日と期限切れは today、予定日なしと明日以降は other。nil は最後"
test "完了の列のカードは出ない"
test "職員用の列にあるカードは :staff_review で、職員用の列は steps に含まれない" do
  # steps の列名 == ["受け取り", "選別", "仕上げ", "完了"]、状態 == [:done, :done, :todo, :todo]
end
test "利用者用の列が1つもない利用者作業ボードでも落ちない" # steps == []
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi/kanban_home_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

`advance_card` と `retreat_card` は、確認と移動を同じ `Repo.transaction` の中で行う。移動には `move_card/3` を使い、`to_index` には移動先の列の件数を渡す。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 利用者の段階操作とホーム画面のデータ"
```

---

### Task 10: 利用者のホーム画面

**Files:**
- Modify: `lib/susumi_web/live/home_live.ex`（Task 4の仮の画面を置き換える）
- Test: `test/susumi_web/live/home_live_test.exs`

**Interfaces:**
- Consumes: `Kanban.client_home/2`, `advance_card/3`, `retreat_card/3`, `subscribe_client/1`, `Clock.today/0`, `.ruby`, `.copy`
- Produces:
  - イベント `"advance"` / `"retreat"`。パラメータは `%{"card-id" => id, "column-id" => id}`（ボタンの `phx-value-card-id` と `phx-value-column-id`）。
  - メッセージ `{:new_day, Date.t()}`。
    - `mount` 時に、次の現地時刻0時0分5秒までのミリ秒で `Process.send_after(self(), {:new_day, ...}, ms)` を予約する。
    - 受け取ったら、その日付で振り分け直し、次の日の分を予約する。

画面（ブレインストーミングの案A）:
- 見出しは「おはようございます、{名前}さん」と日付（例「10月31日（金）」）。
- 「今日やる作業」と「そのほかの作業」の2つのセクションを置く。
- カードには次のものを出す。
  - 作業名とボード名（`.ruby` 付き）
  - 段階の目印（`:done` と `:current` は「●」、`:todo` は「○」。各段階の名前は `.ruby` 付き。`:current` は太字にする）
  - 「いま：{段階名}」
  - 「次の段階へ」「一つ戻す」ボタン（`can_*?` がfalseなら `disabled`）
- `:staff_review` のときは「職員が確認中」と出し、ボタンを出さない。
- 期限切れのカードには「予定日を過ぎています」を、文字と枠線の色の両方で出す。
- 0件のときは「今の作業はありません」と出す。
- ふりがなは、すべて `show={@current_account.show_furigana}` で付ける。
- 結果に応じたflash:
  - `done?: true` → 「完了しました」
  - `:not_found` / `:locked` / `:at_end` / `:at_start` / `:staff_column` → 「この作業は動かせません」
  - `:stale` → flashなしで再読込
- `{:home_changed}` を受け取ったら再読込する。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "今日と期限切れが「今日やる作業」に出て、期限切れには注意が出る"
test "show_furigana の利用者には <rt> が出て、そうでない利用者には出ない"
test "次の段階へを押すと段階が進み、職員の board トピックに通知が届く"
test "完了の列へ進めるとカードが消えて「完了しました」"
test "同じ column-id で2回押しても1段しか進まない" do
  render_click(v, "advance", %{"card-id" => card.id, "column-id" => col1.id})
  render_click(v, "advance", %{"card-id" => card.id, "column-id" => col1.id})
  assert Repo.reload(card).column_id == col2.id
end
test "他人のカードIDを送っても動かず「この作業は動かせません」"
test "職員用の列のカードは「職員が確認中」でボタンなし"
test "職員がカードを動かすと、開いている画面が更新される" # Kanban.move_card(...) → render(v) =~ 新しい段階名
test "{:new_day, date} を受け取ると、その日付で振り分け直す" do
  # scheduled_on = ~D[2026-11-01] のカードは、最初は「そのほかの作業」にある
  send(v.pid, {:new_day, ~D[2026-11-01]})
  # 「今日やる作業」のセクション（id="today"）に出ることを確認する
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/live/home_live_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

文字は大きくし（目安は本文 `text-xl`、作業名 `text-2xl`）、ボタンも大きくする。各セクションには `id="today"` と `id="other"` を付ける。

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 利用者のホーム画面"
```

---

### Task 11: 職員のボード画面とドラッグ＆ドロップ

**Files:**
- Modify: `lib/susumi_web/live/board_live/index.ex`（Task 4の仮の画面を置き換える）
- Create: `lib/susumi_web/live/board_live/show.ex`, `lib/susumi_web/live/board_live/card_form.ex`, `assets/js/hooks/sortable.js`, `assets/vendor/sortable.js`
- Modify: `assets/js/app.js`（`hooks: {Sortable}`）、`lib/susumi_web/router.ex`
- Test: `test/susumi_web/live/board_live_test.exs`

**Interfaces:**
- Consumes: Task 7と8の `Kanban` 関数すべて、`Accounts.list_active/1`、`subscribe_boards/0`、`subscribe_board/1`
- Produces:
  - `/boards`
    - 「利用者作業」と「職員専用」の2つのセクションに分けて一覧する。
    - ボード作成フォームの入力欄は、名前、よみ、種類（必須）、説明。
  - `/boards/:id`
    - 列を横に並べる。
    - 列の見出しには、種別のラベル「利用者用」「職員用」を文字で出し、背景色も変える。
    - 利用者用の列のカードには、担当の利用者さんの名前を出す。職員用の列のカードには、担当の職員の名前を太字で出す。
    - 予定日を過ぎていて完了していないカードには「予定日超過」と文字で出す。
  - イベント
    - `"move_card"`: `%{"card_id", "to_column_id", "to_index"}`。Hookと移動ボタンの両方がこれを使う。
    - `"save_card"` / `"delete_card"`
    - `"add_column"` / `"rename_column"` / `"move_column"` / `"delete_column"`（列のフォームの入力欄は、名前、よみ、種別）
  - 移動ボタン
    - 「←」「→」は、隣の列の末尾へ動かす。
    - 「↑」「↓」は、同じ列の中で1つ上・下へ動かす。
    - 端ではボタンを出さない。
  - Hook `Sortable`
    - 各列のカード一覧に `phx-hook="Sortable"`、`data-column-id`、`id` を付ける。各カードには `data-card-id` を付ける。
    - `group` は `"board-#{id}"`。
    - `onEnd` でSortableが動かした要素を元の位置に戻してから、`pushEvent("move_card", ...)` を送る。DOMの並びはサーバーの再描画に任せる。

```js
onEnd: (evt) => {
  const { item, from, to, oldIndex, newIndex } = evt
  from.insertBefore(item, from.children[oldIndex] ?? null)
  this.pushEvent("move_card", { card_id: item.dataset.cardId, to_column_id: to.dataset.columnId, to_index: newIndex })
}
```

  - flash
    - `move_card` などが `:not_found` を返したら、「ほかの人が先に変更しました。画面を更新しました」と出し、再読込する。
    - 列の削除が `:not_empty` を返したら、「カードが残っている列は削除できません」と出す。
  - カードのフォーム
    - 入力欄は、作業名、よみ、説明、担当の職員（有効な職員から選ぶ）、予定日。
    - 担当の利用者（有効な利用者から選ぶ）は、`user_progress` のボードでだけ出す。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "一覧は利用者作業と職員専用に分かれる"
test "列に「利用者用」「職員用」のラベルが出る"
test "利用者用の列は利用者名、職員用の列は担当職員名を太字で出す"
test "move_card イベントで移動し、別の職員の画面にも反映される" do
  {:ok, a, _} = live(staff_conn, "/boards/#{b.id}")
  {:ok, other, _} = live(staff_conn2, "/boards/#{b.id}")
  render_hook(a, "move_card", %{"card_id" => card.id, "to_column_id" => col2.id, "to_index" => 0})
  assert other |> element("#column-#{col2.id}") |> render() =~ card.title
end
test "→ ボタンでも同じように移動する"
test "削除済みカードを動かすと「ほかの人が先に変更しました。画面を更新しました」"
test "カードが残る列の削除は「カードが残っている列は削除できません」"
test "職員専用ボードのカードフォームには、担当の利用者の欄がない"
test "利用者の画面で次の段階へ押すと、開いているボード画面が更新される"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/live/board_live_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

`assets/vendor/sortable.js` には、npmの `sortablejs` の `Sortable.min.js`（実装時点の最新の安定版）を置く。ファイル先頭のコメントに、版番号を残す。

- [ ] **Step 4: テストが通ることを確認し、ブラウザで2つのウィンドウを並べてドラッグ＆ドロップを確認する**

Run: `mix test && mix phx.server`
Expected: テストはPASS。片方の画面でドラッグしたカードが、もう片方の画面でも同じ位置に移動し、カードが重複しない。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 職員のボード画面とドラッグ＆ドロップ"
```

---

### Task 12: アカウント管理・設定画面・アクセス制御の総点検

**Files:**
- Create: `lib/susumi_web/live/account_live/index.ex`, `lib/susumi_web/live/settings_live.ex`
- Modify: `lib/susumi_web/router.ex`, `lib/susumi_web/components/layouts.ex`（職員用のナビ「ボード」「アカウント」「設定」）
- Test: `test/susumi_web/live/account_live_test.exs`, `test/susumi_web/live/settings_live_test.exs`, `test/susumi_web/access_control_test.exs`

**Interfaces:**
- Consumes: Task 3と4の `Accounts` 関数、`Settings`、`config :susumi, :data_dir`、`Application.spec(:susumi, :vsn)`
- Produces:
  - `/accounts`
    - 職員と利用者を分けて一覧する。
    - 作成フォームの入力欄は、役割、名前、よみ、パスワード、ふりがな表示。
    - 名前、よみ、ふりがな表示を編集できる。
    - 「パスワード再設定」「無効化」「有効に戻す」の操作がある。
    - `:last_staff` のときはflash「最後の職員アカウントは無効化できません」を出す。
  - `/settings`
    - 施設名を編集できる。
    - データフォルダの場所を表示する（`:data_dir`。開発中は `Path.dirname(Repo.config()[:database])`）。
    - 版番号を表示する。
    - バックアップ手順の案内文を出す: 「すすみを閉じてから、データフォルダをまるごとコピーしてください。」

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "利用者を作るとログイン画面の一覧に出る"
test "パスワードを再設定すると、その人の開いている画面が切断される" # Task 4 と同じ topic を assert_receive
test "最後の職員の無効化は「最後の職員アカウントは無効化できません」"
test "ふりがな表示を切り替えられる"
test "設定画面に施設名・データフォルダ・版番号が出て、施設名を変えるとヘッダーも変わる"

# access_control_test.exs — 利用者でログインした conn で
for path <- ["/boards", "/boards/1", "/accounts", "/settings"] do
  test "利用者は #{path} を開けず /home へ" # {:error, {:redirect, %{to: "/home"}}} = live(conn, path)
end
test "未ログインはすべて /login へ"
test "職員専用ボードのカードは client_home に出ない"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/live/account_live_test.exs test/susumi_web/live/settings_live_test.exs test/susumi_web/access_control_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: アカウント管理と設定画面"
```

---

### Task 13: 復旧モード

**Files:**
- Create: `lib/susumi/runtime/recovery.ex`, `lib/susumi_web/controllers/recovery_controller.ex`, `lib/susumi_web/controllers/recovery_html/form.html.heex`
- Modify: `lib/susumi_web/router.ex`（`/recovery` は `require_setup` を通さないパイプラインに置く）
- Test: `test/susumi_web/controllers/recovery_controller_test.exs`

**Interfaces:**
- Produces:
  - `Susumi.Runtime.Recovery.enabled?(dir :: String.t()) :: boolean`（`dir/recovery.txt` があるかどうか）
  - `Susumi.Runtime.Recovery.finish!(dir) :: :ok`（`recovery.txt` を消す）
  - `GET /recovery`、`POST /recovery`（`account_id`、`password`）
    - 復旧モードが有効で、かつ `conn.remote_ip` が `{127, 0, 0, 1}` か `{0, 0, 0, 0, 0, 0, 0, 1}` のときだけ使える。それ以外は404を返す。
    - 選べるのは、職員アカウント（無効化されたものも含む）。
    - 成功したら `reset_password` と `reactivate` を行い、`finish!` を呼んで `/login` へ移る。flash「パスワードを再設定しました。ログインしてください」を出す。

- [ ] **Step 1: 失敗するテストを書く**

```elixir
test "recovery.txt がなければ 404"
test "LANの別PC（remote_ip 192.168.1.30）からは 404"
test "localhost から職員のパスワードを再設定でき、無効化も解け、recovery.txt が消える"
test "利用者アカウントは選べない"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/susumi_web/controllers/recovery_controller_test.exs`
Expected: FAIL

- [ ] **Step 3: 実装する**

- [ ] **Step 4: テストが通ることを確認する**

Run: `mix test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 職員パスワードの復旧モード"
```

---

### Task 14: 手順書・仕上げ・受け入れ確認

**Files:**
- Delete: `lib/susumi_web/live/check_live.ex`, `test/susumi_web/live/check_live_test.exs`（`/_check` のルートも消す）
- Create: `docs/manual/setup-windows.md`, `docs/manual/setup-mac.md`, `docs/manual/acceptance-checklist.md`
- Modify: `.github/scripts/release-smoke.cjs`（確認用カウンターを、ログイン後のカード操作による保存・同期・再起動後の保持の確認に置き換える）、`AGENTS.md`（「現在の段階」に、第1段階が完了したことを1行で書く）

**Interfaces:**
- Consumes: すべて

手順書に書くこと（設計書の6章のとおり）:
- 起動のしかた
- 初回の警告への対処
  - Windows: 「詳細情報 → 実行」
  - macOS: 「システム設定 → プライバシーとセキュリティ → このまま開く」
- ファイアウォールの許可
  - 「プライベートネットワーク」を選ぶ。
  - 管理者権限が必要な場合は、施設のパソコン管理者に依頼する。
  - LANが「パブリックネットワーク」扱いになっているときの確認と変更の方法
- 初回設定のしかた
- ほかのパソコンから開くアドレス
- データフォルダの場所とバックアップ（すすみを止めてからフォルダをコピーする）
- 新しい版への入れ替え（自動で `backups/` に複製ができること）
- 自動起動（任意。スタートアップフォルダに置く方法）
- 職員全員がパスワードを忘れたとき（データフォルダに `recovery.txt` を置いて起動し、そのパソコンで `http://localhost:4000/recovery` を開く）

画面写真は、macOSの分を実装者が撮る。Windowsの警告とファイアウォールの操作は文章で案内し、画面写真の提供は依頼者に求めない。Windows CIでは確認しない項目であることを記録する。

- [ ] **Step 1: CIの確認対象を本体機能に置き換えてCheckLiveを削除し、`mix test` と `mix compile --warnings-as-errors` と `mix format --check-formatted` を通す**

Expected: 全件PASS、警告なし

- [ ] **Step 2: 手順書と受け入れチェックリストを書く**

`acceptance-checklist.md` には、設計書8章の受け入れ基準をそのまま並べる。各項目に、確認のしかたと確認環境（Windows CIまたはmacOS実機）を添える。

- [ ] **Step 3: Windows・macOS向けに再ビルドし、macOSで受け入れ基準を確認する**

Run: `MIX_ENV=prod mix assets.deploy && for t in windows macos_arm macos_intel; do MIX_ENV=prod BURRITO_TARGET=$t mix release; done`
Expected: `burrito_out/` に3つの実行ファイルができる。Windows CIが成功し、macOS実機で対象の受け入れ基準がすべて通る。

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "docs: 設置手順書と受け入れチェックリスト"
```

- [ ] **Step 5: Windows CIとmacOS実機での受け入れ結果を記録する**

同じコミットのWindows CI成功とmacOS実機確認の結果を `docs/manual/acceptance-checklist.md` に記録する。Windowsの検証範囲外の項目も明記する。依頼者によるWindows実機確認は完了条件に含めない。
