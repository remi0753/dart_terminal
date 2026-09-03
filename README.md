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
と Release AOT はともにこの observable contract へ移行済みです。旧 Engine 改変ファイル、
適用経路、およびそれを正当な成果物として扱う来歴・監査・test code は削除済みです。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- キー入力、Backspace/Delete、左右移動、Home/End
- 上下キーによるコマンド履歴
- `/bin/zsh -lc` によるコマンド実行と標準出力・標準エラーの表示
- `help`、`clear`、`cd PATH`、`exit` の組み込みコマンド
- Control-C による実行中プロセスへの割り込み
- ウィンドウサイズに合わせた簡易表示行数の調整
- AppKit main-thread root と公式 Dart 子プロセス worker の bounded lifecycle
  （M1/arm64 Developer JIT / Release AOT）
- native event protocol v4（source generation、nanosecond timestamp、operation
  ID、focus/visibility/occlusion/backing scale/screen state、application/window
  lifecycle、menu action）と、旧 v1/v2/v3 endpoint との compatibility negotiation
- generic `View` / `TextView` 境界と、型を保った content-view attachment
- 登録名から terminal-owned `TerminalMetalView : MTKView` を生成・attach できる
  custom-view 境界（renderer、shader、frame submission は Phase 4）
- `dev.dart-terminal` の macOS Unified Logging と、終了状態を判定できる
  privacy-safe なローカル実行メタデータ（M1/arm64 Developer JIT / Release AOT）
- generation／AppKit-main domain付きnative handle registryと、off-domain
  releaseを即時無効化してmain queueで完了するasynchronous destruction
- 最小の Application/File/Edit menu、明示的な Paste 時だけ行う plain-text
  pasteboard read、非同期 reply 付き Close/Quit request

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

## Runtime diagnostics

Developer JIT と Release AOT は、起動直後から終了までの固定イベントを macOS Unified
Logging の subsystem `dev.dart-terminal`、category `runtime` / `crash` に記録します。
イベント名、実行形態、CPU architecture、launch ID、lifecycle phase、終了種別と終了コード
だけが対象です。terminal の表示内容、入力、コマンド、引数、環境変数、cwd、ファイルパス、
worker stderr、例外詳細はログへ渡しません。直近1時間のイベントは次のように確認できます。

```shell
log show --style compact \
  --predicate 'subsystem == "dev.dart-terminal"' --last 1h
```

同時に、各実行形態の最新状態を次のローカルファイルへ atomic に保存します。

```text
~/Library/Application Support/Dart Terminal/Diagnostics/developer-jit/current-run.json
~/Library/Application Support/Dart Terminal/Diagnostics/release-aot/current-run.json
```

JSON は format/version、launch ID、bundle/version、実行形態、architecture、Dart SDK
revision、PID、開始/更新時刻、最後の lifecycle phase、outcome、exit code だけを持ち、
16 KiB 以下です。ディレクトリは所有者だけが参照できる `0700`、ファイルは `0600` です。
正常終了は `outcome=clean`、既知の非ゼロ終了は `outcome=failure` になります。

次回起動時に前回の `current-run.json` が `outcome=running` のままなら、同じ実行形態の
`previous-unclean-run.json` として1件だけ保存します。これは終了記録まで到達しなかった
ことを示すだけで、crash の断定ではありません。強制終了、電源断、ストレージ障害などでも
同じ状態になり得ます。記録は端末内だけに留まり、自動送信、minidump、stack memory、
symbolication は行いません。アプリ終了中であれば `Diagnostics` フォルダを削除でき、次回
起動時に空の状態から再作成されます。crash/hang report、dSYM、利用者同意を含む完全な診断
workflow は Phase 11 の範囲です。

## Release AOT

M1/arm64 Release bundle の build、監査、起動は次のとおりです。

```shell
make RUNTIME_ARCH=arm64 release-aot-build
make RUNTIME_ARCH=arm64 release-aot-audit
make RUNTIME_ARCH=arm64 release-aot-run
```

Release bundle は AppKit main thread 上の単一 stock Engine root、AOT snapshot、同じ公式
SDK が生成した自己完結 worker executable を含みます。worker は
`Contents/Helpers/dart_terminal_runtime_worker` から別 PID で起動され、配布先の Dart SDK
には依存しません。通常 smoke、failure/replacement/shutdown、bounded traffic を個別に
再検証する場合:

```shell
make RUNTIME_ARCH=arm64 release-aot-integration
make RUNTIME_ARCH=arm64 release-aot-lifecycle
make RUNTIME_ARCH=arm64 release-aot-traffic
```

### 低優先の Intel-native handoff

x86_64 cross-build、Rosetta、Universal、Intel-native handoff は、M1 の製品 contract
完了後に再検証する後続項目です。その target は残していますが、再検証が終わるまで
M1/arm64 の主要受け入れ手順には含めません。この follow-up の未実施は M1 baseline の
完了を阻害しません。

## ローカルチェック

```shell
make runtime-source-check
make RUNTIME_ARCH=arm64 developer-jit-clean-sdk-test
make RUNTIME_ARCH=arm64 release-aot-clean-sdk-test
make RUNTIME_ARCH=arm64 runtime-bundle-audit
make RUNTIME_ARCH=arm64 runtime-integration
```

`make RUNTIME_ARCH=arm64 runtime-verify` は source check、両 mode の bundle audit、
smoke、lifecycle、bounded traffic suite をまとめて実行します。
`runtime-matrix-verify` は x86_64、Rosetta、Universal、Intel-native の低優先 follow-up が
完了するまで主要 M1 gate には使用しません。

Phase 0 の debug/JIT、release-AOT、worker-isolate、benchmark、bundle 監査は
歴史的な feasibility evidence としてのみ参照します。Engine 内 child isolate を前提に
していた worker、PTY、Metal、CoreText の build/run と旧 aggregate target は廃止済みです。
残した root-only、IME、standalone benchmark/debug target は clean な公式 Engine/SDK
だけを使用します。

個別の再現方法と測定結果は [`docs/phase0`](docs/phase0)、設計判断は
[`docs/adr`](docs/adr)、runtime matrix と Universal assembly の契約は
[`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)、
診断データの設計・検証記録は
[`docs/phase1/macos-unified-logging-crash-metadata.md`](docs/phase1/macos-unified-logging-crash-metadata.md)
にあります。

## 構成

```text
bin/main.dart                         エントリーポイント
lib/src/terminal_application.dart    AppKit ウィンドウとキーイベント
lib/src/runtime_lifecycle.dart       root/worker lifecycle coordinator
native/macos/runtime/                JIT/AOT lifecycle と diagnostics host
native/macos/renderer/               TerminalMetalView shell と native contract
lib/src/terminal_session.dart        コマンド実行バックエンド
lib/src/terminal_buffer.dart         入力、履歴、スクロールバック
test/run_tests.dart                  UI 非依存部分の最小テスト
```

## 製品実装へ進む際の境界

通常エントリーポイントは一つのコマンドごとに `zsh -lc` を起動する
「コマンドコンソール」で、表示には引き続き `TextView` を使います。一方、
`dart_appkit` の登録済み custom-view provider と terminal-owned
`TerminalMetalView` の生成・attach 境界は用意済みです。対話型 TUI を含む
本格的なターミナルエミュレーターには、次の実装が必要です。

1. `forkpty(3)` / `openpty(3)` を扱う macOS FFI ブリッジ
2. 継続するシェルセッションとウィンドウサイズ通知 (`TIOCSWINSZ`)
3. ANSI / VT シーケンスのパーサーと画面バッファ
4. 色・属性・カーソル・選択・スクロールを描画する CoreText/Metal renderer
5. IME、クリップボード、キーバインドの仕上げ

`TerminalSession` が将来の PTY バックエンドとの交換点、`TerminalBuffer` が
ANSI 画面モデルへ発展させる場所になるよう分離しています。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
