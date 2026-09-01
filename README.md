# Dart Terminal

`dart_appkit` を土台に、Dart で独立実装する macOS 向けターミナル
エミュレーターです。Ghostty は機能・品質の比較基準としてのみ参照し、
Ghostty や `libghostty` を製品へ組み込みません。

現在の通常エントリーポイントはまだ command console ですが、Phase 0 の
feasibility gate と仕様凍結は完了しています。release AOT、worker isolate、
安全な PTY child、64 KiB batching、Metal、CoreText、日本語 IME、packed grid、
parser corpus、性能 baseline を、独立した Dart/native spike で実機検証済みです。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- キー入力、Backspace/Delete、左右移動、Home/End
- 上下キーによるコマンド履歴
- `/bin/zsh -lc` によるコマンド実行と標準出力・標準エラーの表示
- `help`、`clear`、`cd PATH`、`exit` の組み込みコマンド
- Control-C による実行中プロセスへの割り込み
- ウィンドウサイズに合わせた簡易表示行数の調整

## 起動

先に隣接する `dart_appkit` リポジトリで Engine の準備を済ませます。

```shell
cd ../dart_appkit
make engine
```

その後、このディレクトリで依存関係を解決して起動します。

```shell
dart pub get
dart run dart_appkit:run bin/main.dart
```

開始ディレクトリを指定する場合は、Runner の `--` より後ろにアプリ用の
引数を渡します。

```shell
dart run dart_appkit:run bin/main.dart -- --working-directory=/tmp
```

3 秒で自動終了するスモーク実行:

```shell
dart run dart_appkit:run bin/main.dart -- --auto-close-after=3
```

## ローカルチェック

```shell
dart analyze
dart run test/run_tests.dart
dart compile kernel bin/main.dart -o build/dart_terminal.dill
```

Phase 0 全体（debug/JIT、全 release-AOT spike、benchmark、bundle 監査）を
再検証する場合:

```shell
make phase0-verify
```

個別の再現方法と測定結果は [`docs/phase0`](docs/phase0)、設計判断は
[`docs/adr`](docs/adr) にあります。

## 構成

```text
bin/main.dart                         エントリーポイント
lib/src/terminal_application.dart    AppKit ウィンドウとキーイベント
lib/src/terminal_session.dart        コマンド実行バックエンド
lib/src/terminal_buffer.dart         入力、履歴、スクロールバック
test/run_tests.dart                  UI 非依存部分の最小テスト
```

## 製品実装へ進む際の境界

通常エントリーポイントは一つのコマンドごとに `zsh -lc` を起動する
「コマンドコンソール」です。現時点の `dart_appkit` 公開 API は
単一 `TextView` へのプレーンテキスト描画までなので、対話型 TUI を含む
本格的なターミナルエミュレーターには、次の実装が必要です。

1. `forkpty(3)` / `openpty(3)` を扱う macOS FFI ブリッジ
2. 継続するシェルセッションとウィンドウサイズ通知 (`TIOCSWINSZ`)
3. ANSI / VT シーケンスのパーサーと画面バッファ
4. 色・属性・カーソル・選択・スクロールを描画する AppKit ビュー
5. IME、クリップボード、キーバインドの仕上げ

`TerminalSession` が将来の PTY バックエンドとの交換点、`TerminalBuffer` が
ANSI 画面モデルへ発展させる場所になるよう分離しています。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
