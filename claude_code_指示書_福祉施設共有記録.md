# 福祉施設向け共有記録＋Kanbanシステム 指示書（Claude Code用）

## 結論
LAN内完結の福祉施設向けシステムを実装する。施設全体の共有ノートと、利用者作業進捗・職員タスクの両方に対応したKanbanを、Phoenix LiveView + SQLiteで構築する。

## 前提
- 利用場所：福祉施設のLAN内
- 同時接続：最大約8人
- 外部公開・外部サービス連携は行わない
- DBはSQLite（ファイル1つで完結、バックアップ容易）
- リアルタイム性はPhoenix PubSubで担保
- 実装はLiveViewを主とし、JavaScriptは必要最小限

## スコープ
### 実装範囲
- 共有ノート機能（施設全体用、複数ノート）
- Kanban機能（複数ボード）
  - 列を「利用者用」と「職員用」で明確に分けられる
  - 利用者の作業進捗と職員のタスクの両方に対応
- リアルタイム同期（ノート編集・カード移動）
- 参加者表示（Presence）
- SQLite永続化
- LAN内アクセス可能な起動設定

### 初期スコープ外
- 高度なCRDTによる完全な同時編集
- 細かいロールベース権限
- 外部API連携
- モバイルネイティブ対応

## 仕様

### スキーマ

```elixir
# notes
schema "notes" do
  field :title, :string
  field :content, :string
  field :updated_by, :string
  timestamps()
end

# kanban_boards
schema "kanban_boards" do
  field :name, :string
  field :board_type, :string  # "user_progress" | "staff_task"
  field :description, :string
  has_many :columns, KanbanColumn
  timestamps()
end

# kanban_columns
schema "kanban_columns" do
  field :name, :string
  field :column_type, :string  # "user" | "staff"
  field :position, :integer
  belongs_to :board, KanbanBoard
  has_many :cards, KanbanCard
  timestamps()
end

# kanban_cards
schema "kanban_cards" do
  field :title, :string
  field :description, :string
  field :assignee, :string
  field :related_user, :string
  field :position, :integer
  belongs_to :column, KanbanColumn
  timestamps()
end
```

### 共有ノート
- 一覧・詳細・作成・更新・削除
- 詳細画面で `phx-change` により内容を更新し、PubSubで他のLiveViewにブロードキャスト
- 編集中ユーザーをPresenceで表示
- 任意でMarkdownプレビュー

### Kanban
- ボード作成時に必要に応じて `board_type` を選択可能（任意）
- カラム作成時に `column_type`（"user" または "staff"）を必ず指定
- 表示時は利用者用列と職員用列を視覚的に分離する（色・ラベル・セクションなど）
- カラムは位置付きで管理
- カードはカラム内で位置付きで管理
- ドラッグ＆ドロップは Sortable.js + LiveView Hook で実装
- 移動時に `position` を再計算して保存し、PubSubで同期
- 利用者用列では `related_user` を表示
- 職員用列では `assignee` を強調表示

### リアルタイム要件
- 同一リソースを開いているクライアント間で変更を即時反映
- 同時8人程度で体感遅延が目立たないこと
- サーバー再起動後もデータが残ること

### デプロイ・起動
- `config/runtime.exs` または起動時オプションで `0.0.0.0` バインド
- 例：`mix phx.server` で施設内IPからアクセス可能にする
- SQLiteファイルはプロジェクト内または指定パスに配置

## TDD
1. コンテキスト層（Notes, Kanban）のユニットテスト
2. 位置更新・移動ロジックのテスト
3. LiveViewのイベント処理テスト
4. PubSub購読・ブロードキャストの動作確認
5. 複数セッションでの手動同期確認

## 制約
- 外部ネットワークへの依存を持たない
- `ecto_sqlite3` を使用し、WALモードを有効にする
- JavaScriptはSortable.jsのフックとLiveView標準の範囲に留める
- サーバー側を単一の真実源とする（初期は上書き方式で可）
- コードは読みやすく、副作用を明示し、テストを書きやすい構造にする
- 不要な抽象化や過剰な汎用化は避ける

## 受け入れ基準
- [ ] SQLiteでマイグレーションが成功し、データが永続化される
- [ ] 共有ノートの編集が複数ブラウザでリアルタイム同期される
- [ ] Kanbanでカードのドラッグ＆ドロップ移動が動作し、他端末に即時反映される
- [ ] 「利用者進捗」ボードと「職員タスク」ボードの両方を作成・運用できる
- [ ] Kanbanの列を「利用者用」と「職員用」で分けて作成・表示できる
- [ ] 同一ボード内に利用者用列と職員用列を混在させ、視覚的に区別できる
- [ ] 5〜8人が同時に開いても実用的な速度を維持する
- [ ] LAN内の別PCからアクセスできる
- [ ] アプリケーション再起動後もデータが保持される
- [ ] 現在の閲覧者がPresenceで確認できる

## 推奨実装順序
1. Phoenixプロジェクト作成と `ecto_sqlite3` 導入
2. マイグレーションとスキーマ定義
3. NotesコンテキストとLiveView（リアルタイム更新）
4. Kanbanコンテキスト（ボード・カラム・カード）
5. Sortable.jsフックによるドラッグ＆ドロップ
6. PubSub同期とPresence
7. ナビゲーションと基本レイアウト
8. LANバインド確認と複数端末テスト

## 実装時の注意
- カード移動時は `position` を正しく再計算すること（同一カラム内移動とカラム間移動の両方）
- LiveViewの `stream` を使う場合は、再配置後のDOM更新に注意
- 同時編集で内容が上書きされる可能性はあるが、初期段階では許容する（必要なら後から操作単位同期へ拡張）
- アクセシビリティを意識し、キーボード操作やフォーカスを考慮したUIにする

## 拡張ポイント（受け入れ後）
- 簡易認証の追加
- Markdownプレビュー強化
- 印刷・CSVエクスポート
- より高度な競合解決（`y_ex` 等）
- 検索機能（SQLite FTS5）
