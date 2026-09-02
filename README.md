# Dart Terminal

`dart_appkit` を土台に、Dart で独立実装する macOS 向けターミナル
エミュレーターです。Ghostty は機能・品質の比較基準としてのみ参照し、
Ghostty や `libghostty` を製品へ組み込みません。

主要な開発・実機受け入れ baseline は Apple M1/arm64 です。x86_64 cross-build、
Rosetta、Universal、Intel-native 実機確認は、M1 の製品 contract が完了した後の
低優先 follow-up であり、M1 の完了を阻害しません。

現在の通常エントリーポイントはまだ command console ですが、Phase 0 の
feasibility gate と仕様凍結は完了しています。release AOT、worker isolate、
安全な PTY child、64 KiB batching、Metal、CoreText、日本語 IME、packed grid、
parser corpus、性能 baseline は、独立した Dart/native spike で実機検証済みです。
これは過去の成立性証拠であり、現在の製品 runtime topology ではありません。

現在選定している製品 contract は、未改変の公式 Dart だけを使う AppKit root と、
独立して回収・再生成できる公式 Dart 子プロセス worker です。M1/arm64 Developer JIT
はこの contract へ移行済みです。Release AOT は同じ observable contract への移行中で、
完了するまでは既存の Release/Universal 経路を製品受け入れ証拠として扱いません。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- キー入力、Backspace/Delete、左右移動、Home/End
- 上下キーによるコマンド履歴
- `/bin/zsh -lc` によるコマンド実行と標準出力・標準エラーの表示
- `help`、`clear`、`cd PATH`、`exit` の組み込みコマンド
- Control-C による実行中プロセスへの割り込み
- ウィンドウサイズに合わせた簡易表示行数の調整
- AppKit main-thread root と公式 Dart 子プロセス worker の bounded lifecycle
  （M1/arm64 Developer JIT）

## 起動

先に隣接する `dart_appkit` リポジトリで、公開APIだけを使う未改変 Engine host を
準備します。

```shell
cd ../dart_appkit
make engine
```

その後、このディレクトリで依存関係を解決し、製品の developer JIT
bundle を起動します。thin runtime target は architecture の省略や推測を
許可しないため、`RUNTIME_ARCH=arm64` または `RUNTIME_ARCH=x86_64` を必ず
指定します。

```shell
dart pub get
make RUNTIME_ARCH=arm64 developer-jit-run
```

開始ディレクトリなどのアプリ引数は `RUNTIME_ARGUMENTS` で渡します。

```shell
make RUNTIME_ARCH=arm64 developer-jit-run \
  RUNTIME_ARGUMENTS="--working-directory=/tmp"
```

自動終了を含む integration smoke:

```shell
make RUNTIME_ARCH=arm64 developer-jit-integration
```

developer JIT は、application Kernel、独立した worker Kernel、および未改変の
JIT Engine を含む開発専用 bundle です。worker は build provenance に固定された
公式 SDK の Dart 実行ファイルで起動します。成果物は
`build/runtime/<architecture>/developer-jit/DartTerminalDeveloper.app` に
作られ、配布物には使用しません。

## Runtime lifecycle

M1/arm64 Developer 起動では、root isolate が AppKit へ attach した後に、公式 SDK の
Dart 実行ファイルを別プロセスとして起動します。親は PID、stdin/stdout/stderr、
versioned frame、世代番号を所有し、同時受付を64件に制限して過負荷を明示的に
呼び出し元へ返します。終了は stop acknowledgement だけで完了扱いにせず、OS が
通知する process exit と stdout/stderr の drain を回収します。期限超過時だけ
`SIGKILL` し、障害後の worker は別PID・次世代として再生成します。

worker の uncaught error/exit は子プロセス内へ封じ込め、root/host fatal とは別に
扱います。root が異常終了する場合も親の pipe close により child が終了し、統合試験は
記録した全 worker PID がアプリ終了後に存在しないことを確認します。Dart/Engine source、
生成物、SDK commit へ製品用の変更は加えません。

integration で検証する終了状態は、正常または worker-contained failure が `0`、
不正な application option が `64`、root/host fatal が `70`、shutdown timeout による
forced cleanup が `75` です。fault scenario の選択は integration-test gate がない通常
起動では拒否されます。

Developer の通常 smoke、lifecycle fault suite、bounded traffic を個別に実行する場合:

```shell
make RUNTIME_ARCH=arm64 developer-jit-integration
make RUNTIME_ARCH=arm64 developer-jit-lifecycle
make RUNTIME_ARCH=arm64 developer-jit-traffic
```

## Release AOT

M1/arm64 Release AOT は、Developer と同じ「stock AppKit root + 独立した公式 Dart
worker process」contract へ移行する次の ROADMAP 項目です。リポジトリに残る従来の
Release/Universal target は patch 依存実装を削除するための移行対象であり、現時点では
実行・配布・受け入れの手順ではありません。移行、M1横断検証、patch関連コードの削除が
完了した時点で、ここへ有効な build/audit/run 手順を戻します。

### 低優先の Intel-native handoff

x86_64 cross-build、Rosetta、Universal、Intel-native handoff は、stock-runtime の
M1 JIT/AOT 移行と patch 削除が完了してから再検証します。既存 target は移行前 contract
の残存物であり、現在の手順としては使用しません。この follow-up の未実施は M1 baseline の
完了を阻害しません。

## ローカルチェック

```shell
make runtime-source-check
make RUNTIME_ARCH=arm64 developer-jit-audit
make RUNTIME_ARCH=arm64 developer-jit-integration
make RUNTIME_ARCH=arm64 developer-jit-lifecycle
make RUNTIME_ARCH=arm64 developer-jit-traffic
```

Release を含む `runtime-bundle-audit`、`runtime-integration`、`runtime-verify`、
`runtime-matrix-verify` は未改変 runtime への移行が終わるまで受け入れ gate として
使用しません。Intel-native、Rosetta、Universal の再検証も、M1 JIT/AOT の移行完了後に
行う低優先 follow-up です。

Phase 0 の debug/JIT、release-AOT、worker-isolate、benchmark、bundle 監査は
歴史的な feasibility evidence としてのみ参照します。旧 `phase0-verify` target は
patch 適用経路を含む移行対象なので実行しません。

個別の再現方法と測定結果は [`docs/phase0`](docs/phase0)、設計判断は
[`docs/adr`](docs/adr)、runtime matrix と Universal assembly の契約は
[`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)
にあります。

## 構成

```text
bin/main.dart                         エントリーポイント
lib/src/terminal_application.dart    AppKit ウィンドウとキーイベント
lib/src/runtime_lifecycle.dart       root/worker lifecycle coordinator
native/macos/runtime/                JIT/AOT lifecycle host integration
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
