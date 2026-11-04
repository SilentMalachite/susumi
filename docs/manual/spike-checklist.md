# すすみ 起動・配布の確認

WindowsはGitHub ActionsのCIのみで確認します。依頼者によるWindows実機確認や画面写真の提供は求めません。macOSは引き続き実機で確認します。

## Windows CI

ワークフローは `.github/workflows/windows.yml`（表示名: Windows CI）です。push、pull request、Actionsの「Run workflow」で実行します。

1. Ubuntuランナーで整形・コンパイル・ExUnitテストを確認する。
2. UbuntuからWindows向けの単体実行ファイルをクロスビルドする。
3. Windowsランナーで、Elixir・Erlangを追加インストールせずに `.exe` を起動する。
4. `/_check` のHTTP応答と、データフォルダ内のDB・設定・秘密鍵の作成を確認する。
5. Chromiumの2画面を開き、「+1」で数が増え、もう一方にも再読み込みなしで反映されることを確認する。
6. もう1つ起動し、ポート使用中の日本語の案内と異常終了を確認する。先に起動したサーバーは操作できることも確認する。
7. プロセスを停止してHTTP応答がなくなることを確認し、再起動後も数が残っていることを確認する。

確認スクリプトは `.github/scripts/release-smoke.cjs` です。CI専用の一時データフォルダを使います。実行ファイルは `susumi-windows`、起動ログとブラウザのトレースは `windows-smoke-results` のartifactから取得できます。

Windowsの合格条件は、対象コミットのWindows CIが成功することです。ワークフローを追加しただけ、ビルドだけが成功した状態は合格にしません。現時点では、このチェックリストにCI成功の記録はありません。

## Windows CIの検証範囲外

次は自動確認の対象に含めません。CI成功を、これらの確認結果として扱わないでください。

- エクスプローラーでのダブルクリックと、コンソールウィンドウを閉じる操作
- SmartScreenの警告と許可操作
- 既定のブラウザの自動起動（CIのChromiumは確認スクリプトが開く）
- 施設のファイアウォール、管理者権限、プライベート／パブリックネットワークの設定
- 同じLANの別PCからの接続（CIの2画面は同じWindowsランナー上）
- Windows 10・11それぞれでの動作（CIはWindows Server 2025）

これらはWindowsの完了条件から外し、設置手順書で必要な操作を案内します。

## macOSの実機確認

従来の記録では、ターミナルからの起動、`/_check` の表示、再起動後に数が残ること、ポート使用中の案内までを確認済みです。次の項目は実機で確認し、結果を記録してください。

1. Finderで `susumi_macos_arm`（Intel Macは `susumi_macos_intel`）をダブルクリックして起動する。開発元が未確認の旨の警告が出たら、「システム設定 → プライバシーとセキュリティ」から許可する。
2. 既定のブラウザで画面が開き、`~/Library/Application Support/Susumi/` に `susumi.db` ができる。
3. macOSのファイアウォールが「着信接続を許可しますか」と尋ねたら「許可」を押す。そのあと、別の端末から `http://<このMacのIPアドレス>:4000/_check` を開いて表示される。
4. 2つのブラウザで `/_check` を開き、片方で「+1」を押すと、もう片方の数が画面を更新しなくても変わる。

## 同じ版で作り直した実行ファイルを試すとき

すすみは、初回の起動時に中身を展開して使います。同じ版番号で作り直して確認するときは、古い展開が使われないよう、先に `susumi_windows.exe maintenance directory`（macOSでは `./susumi_macos_arm maintenance directory`）で展開先を確認して、そのフォルダを削除してください。CIは毎回新しいランナーで実行します。

展開先とは別に、利用者のデータは次の場所に保存します。

- Windows: `%LOCALAPPDATA%\Susumi\`
- macOS: `~/Library/Application Support/Susumi/`
- 環境変数 `SUSUMI_DATA_DIR` がある場合: 指定したフォルダ

中身はDBの `susumi.db`、設定の `config.json`、`secret_key_base`、バックアップの `backups/` です。
