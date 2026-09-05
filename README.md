# Dart Terminal

`dart_appkit` を土台に、Dart で独立実装する macOS 向けターミナル
エミュレーターです。Ghostty は機能・品質の比較基準としてのみ参照し、
Ghostty や `libghostty` を製品へ組み込みません。

主要な開発・実機受け入れ baseline は Apple M1/arm64 です。x86_64 cross-build、
Rosetta、Universal、Intel-native 実機確認は、M1 の製品 contract が完了した後の
低優先 follow-up であり、M1 の完了を阻害しません。

現在の通常エントリーポイントは、再利用可能な `dart_pty_macos` を使う
pane-owned persistent login shell です。Phase 0 の native spike source は移行時に削除し、
成立性と測定結果は `docs/phase0` に保存しています。Dart-only VT parser と screen
model は製品実装へ移行済みで、CoreText/Metal renderer、IME は後続 Phase です。

現在選定している製品 contract は、未改変の公式 Dart だけを使う AppKit root と、
独立して回収・再生成できる公式 Dart 子プロセス worker です。M1/arm64 Developer JIT
と Release AOT はともにこの observable contract へ移行済みです。旧 Engine 改変ファイル、
適用経路、およびそれを正当な成果物として扱う来歴・監査・test code は削除済みです。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- window単位で選択できるAppKit/Dart key routingと、terminalのDart専有入力
- キー入力、Backspace/Delete、左右移動、Home/End
- zsh自身の行編集と上下キーによるコマンド履歴
- 1 paneにつき1つのTTY付きinteractive login zsh
- 同じshell内での`cd`、環境変数、background job、`jobs`、`fg`/`bg`
- Control-C/Z/\\、Control-Dによるsignal/EOF入力
- Control-Dは常にPTY入力として扱い、shellの正常終了時はpane/windowを自動で閉じ、
  非0・signal・終了監視失敗時は理由を表示した非live paneを保持する終了policy
- ウィンドウサイズに追従する`TIOCSWINSZ`/`SIGWINCH`
- typed pane/session ID、単一owner、live shellの再操作close確認
- terminal内容を含めないpane state / PTY shutdown stage診断
- Control-Dのqueue受理、native write、foreground/termios、signal、waitpid、
  kernel exit status、PTY内/外のreap、exit公開をrequest IDで追えるcontent-free診断
- graceful/force/final deadlineを持つbounded PTY session teardownと型付き結果
- PTY通知欠落時もpane ownerを閉じ、status 75でhost終了するclassified recovery
- AppKit main-thread root と公式 Dart 子プロセス worker の bounded lifecycle
  （M1/arm64 Developer JIT / Release AOT）
- native event protocol v4（source generation、nanosecond timestamp、operation
  ID、focus/visibility/occlusion/backing scale/screen state、application/window
  lifecycle、menu action）と、旧 v1/v2/v3 endpoint との compatibility negotiation
- generic `View` / `TextView` 境界と、型を保った content-view attachment
- `dart_terminal_renderer_macos` の公開 facade から dependency-owned
  `TerminalMetalView : MTKView` を生成・attach できる custom-view 境界
  （renderer、shader、frame submission は Phase 4）
- `dev.dart-terminal` の macOS Unified Logging と、終了状態を判定できる
  privacy-safe なローカル実行メタデータ（M1/arm64 Developer JIT / Release AOT）
- generation／AppKit-main domain付きnative handle registryと、off-domain
  releaseを即時無効化してmain queueで完了するasynchronous destruction
- 最小の Application/File/Edit menu、明示的な Paste 時だけ行う plain-text
  pasteboard read、非同期 reply 付き Close/Quit request
- chunk境界に依存せず不正byteからdeterministicに復帰するDart-only streaming
  UTF-8 decoderと、宣言的specから再生成・freshness検査できるtable-driven VT parser
- C0/C1、ESC、CSI、OSC、DCS、SOS/PM/APCのtyped action、CAN/SUB/ESC recovery、
  parameter/subparameter保持、固定bufferとsequence/payload/count/value上限
- ADR-003準拠の非公開SoA cell/row storage、cursor save/restore、default/custom
  tab stop、coalesced row damage/versionとmonotonic screen generation基盤
- top/bottom・optional left/right margin、origin/insert/autowrap/reverse-video、
  wrap-pending、cursor shape/blink/visibilityのtyped stateとatomic reset/clamp
- bounded style ID table、current/saved rendition、P0 text attributes、ANSI
  16/256色・truecolor・default colorのsemicolon/colon SGR適用
- typed xterm-256 palette、logical default foreground/background、bounded
  OSC 4/10/11/104/110/111 color mutationとpalette-aware damage
- shared style/palette資源と独立したgrid/stateを持つprimary/alternate screen、
  DEC private mode 47/1047/1048/1049、切替時full-snapshot contract
- Unicode 17 grapheme境界・幅判定、bounded grapheme intern、wide/continuation
  invariantとprimary historyを含むatomic resize/reflow
- fixed-page SoA scrollback、独立line/byte cap、O(1) page eviction、primary
  history/active gridを投影するbounded viewportとstable logical anchor
- end-exclusive cell/word/logical-line selection、soft/hard wrap準拠のbounded
  text extraction、cell-aligned exact scalarのforward/backward bounded search
- 最大64 byteのreply encoderと、DA/DA2、DSR/CPR、DECRQM、OSC palette/default
  color queryのterminal-core dispatch
- session-owned screen set/parserへのraw PTY byte feed、従来text projectionとの
  single-subscription共存、generated replyのnative bounded write queue接続
- historyとprimary/alternate grid、Unicode resource、mode/cursor/parser countを
  網羅し、行・cell・resource・出力上限を持つversion 1 terminal-state snapshotと、
  最初の相違位置・escaped contextを返すbounded comparison diagnostics
- 厳密検証するbyte-exact product parser corpus manifest、shell/less/top/vimの
  review済み記録snapshotをwhole・全single split・bytewiseで再生する非書換えharness、
  固定seedのproperty testと境界別fuzz seed/mutation corpus
- Phase 0 mixed workloadを使うcapture-disabled product parserのRelease AOT
  100 MiB/s regression gate（同一seedのexact counter/integrity検証付き）
- 1x/2xの決定論的integer alpha合成、固定layer順、solid/mask/color bitmapを扱う
  Dart-only reference rendererと、checksum付きversion 1 golden image oracle
- generation-owned CoreText font catalog、actual/synthetic 4-style policy、
  CJK/color emoji fallback、bounded text resolveとcell/decorations metrics、
  versioned whole-run shaping、UTF-16 cluster mapping、Dart-owned byte/entry LRU、
  batched 1x/2x CoreText alpha8/straight-RGBA8 glyph raster boundary
- alpha8/straight-RGBA8を分離したbounded glyph atlas、決定論的配置、page/byte/
  entry上限、unpinned LRU、submission token pin、resource generation検証、
  矩形差分uploadと実CoreText文字コーパスの1x/2x pixel golden
- build時にコンパイルしたMetal shader、全terminal layer用packed draw list、
  bounded texture array、3つのnative frame slot、即時backpressure、GPU完了retire、
  Dart encoder/facade、stable atlas slice bridge、CPU oracleとの1x/2x readback比較
- ADR-003準拠のstrict damage codec v2（row/cell差分、cursor状態、monotonic BEL、
  metadata-only packet）、atomic retained render model、1-paneにつき1件の
  TransferableTypedData/ACK、newest-modelだけを保持するframe scheduler、native
  stale/backpressure追従と世代番号の非折り返し
- resize/backing scale/font変更を最新1件へ集約し、CoreText catalog/cache、1x/2x
  glyph atlas、native Metal atlas、full damageを同じ公開世代で切り替えるatomic rebuild
- signed monotonic時刻でcursor blinkとvisual BELを各1 deadlineに制限するpresentation
  clock、visibility/occlusion中のbuild/submit停止、hidden tickを再生しないresume full redraw
- renderer ABI v8のtyped device/shader/command failure state、bounded drawable
  unavailable観測、READY frameを保持する明示的on-demand presentation retry

## 起動

先に隣接する `dart_appkit` リポジトリで、汎用 runtime が使う未改変 Engine を
準備します。

```shell
cd ../dart_appkit
make engine
```

その後、このディレクトリで公開 Dart package を解決し、同じ宣言ファイルから
Developer JIT bundle を起動します。`RUNTIME_ARCH` は現在の Mac を既定値とします。

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

Developer JIT は application Kernel、自己完結 worker helper、および未改変の
JIT Engine を含む開発専用 bundle です。成果物は
`build/runtime/<architecture>/developer-jit/DartTerminal.app` に作られ、
配布物には使用しません。

## Runtime lifecycle

M1/arm64 Developer 起動では、root isolate が AppKit へ attach した後に、manifest
から生成した自己完結 Dart helper を別プロセスとして起動します。親は PID、stdin/stdout/stderr、
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

Developer の通常 smoke、lifecycle fault suite、bounded traffic、1,000 組の
Window/View resource stress、shutdown fault injection を個別に実行する場合:

```shell
make RUNTIME_ARCH=arm64 developer-jit-integration
make RUNTIME_ARCH=arm64 developer-jit-lifecycle
make RUNTIME_ARCH=arm64 developer-jit-traffic
make RUNTIME_ARCH=arm64 developer-jit-resource
make RUNTIME_ARCH=arm64 developer-jit-shutdown-fault
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

通常実行の標準出力には、typed pane/session ID、PTY process ID、および固定された
lifecycle stageだけを持つ`TERMINAL_PANE_LIFECYCLE`と
`TERMINAL_PTY_LIFECYCLE`も記録します。Control-Dの受付、native exit、output drain、
close request、exit wait、stream cancel、process disposeのどこまで完了したかを判定でき、
terminal表示内容、入力文字列、command、environment、cwd、例外詳細は含みません。
Control-Dとshutdownの詳細は`TERMINAL_PTY_NATIVE`に記録され、opaque request ID、
byte/queue count、foreground process group、termios flagと`VEOF`番号、signal target/result、
`waitpid` result、exit公開境界だけを含みます。Control-Dがnative writeまで完了しても、
zshの`IGNORE_EOF`、未確定の編集行、foreground reader、raw mode、停止jobの状態によって
shellが終了しないことは正常なPTY semanticsです。
`child_status_valid=true`を伴うkernel exit通知後にDart runtimeが先にchildを回収した場合は、
`externalReapObserved`を記録して保持済みstatusから終了を一度だけ公開します。
`TERMINAL_PANE_EXIT`はshell終了を`clean`、`nonZero`、`signaled`、`failed`に分類し、
正常終了の`action=close`と、それ以外の`action=retain`を内容非依存のfieldで示します。
現在の1-pane applicationでは正常なzsh終了がwindow/applicationの終了になり、保持された
異常終了paneはstatus lineを確認した後、一度のCloseで終了できます。
終了時の`TERMINAL_SESSION_SHUTDOWN`と`TERMINAL_PANE_OWNER_SHUTDOWN`は、同じ
typed ID、固定されたdisposition、termination/cleanupの真偽だけで最終結果を示します。
最終期限を超えた場合もpaneとhostの終了処理を続け、正常終了を名乗らずstatus 75と
`outcome=failure`を記録します。

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
には依存しません。通常 smoke、failure/replacement/shutdown、bounded traffic、resource
stress、shutdown fault injection を個別に再検証する場合:

```shell
make RUNTIME_ARCH=arm64 release-aot-integration
make RUNTIME_ARCH=arm64 release-aot-lifecycle
make RUNTIME_ARCH=arm64 release-aot-traffic
make RUNTIME_ARCH=arm64 release-aot-resource
make RUNTIME_ARCH=arm64 release-aot-shutdown-fault
```

### 低優先の Intel-native handoff

x86_64 cross-build、Rosetta、Universal、Intel-native handoff は、M1 の製品 contract
完了後に再検証する後続項目です。ROADMAPには残していますが、再検証が終わるまで
M1/arm64 の主要受け入れ手順には含めません。この follow-up の未実施は M1 baseline の
完了を阻害しません。

## ローカルチェック

```shell
make product-parser-corpus
make product-parser-properties
make product-parser-benchmark
make runtime-source-check
make test
make RUNTIME_ARCH=arm64 runtime-bundle-audit
make RUNTIME_ARCH=arm64 runtime-integration
```

`make RUNTIME_ARCH=arm64 runtime-verify` は source check、両 mode の bundle audit、
smoke、lifecycle、bounded traffic、resource stress、shutdown fault suite をまとめて
実行します。resource stress は実アプリの Dart API から 1,000 組の Window/View を生成・
破棄し、毎回 native handle が基準値へ戻ることを確認します。shutdown fault suite は
malformed/late event、double dispose、worker crash を封じ込め、最終 native handle が 0、
記録した worker PID が消滅することを確認します。いずれも専用の integration-test gate が
ない通常起動では選択できません。
汎用 builder は現在、実行ホストと同じ architecture を構築します。x86_64、Rosetta、
Universal、Intel-native の再受け入れは、ROADMAP 上の低優先 follow-up です。

Phase 0 の debug/JIT、release-AOT、worker-isolate、PTY、Metal、CoreText の native
実装は歴史的な feasibility evidence として `docs/phase0` から参照します。製品
repository には native source とその旧 build target を残していません。
parser/benchmark などの Dart-only harness は後続実装の比較資料として残しています。

個別の再現方法と測定結果は [`docs/phase0`](docs/phase0)、設計判断は
[`docs/adr`](docs/adr)、runtime matrix と Universal assembly の契約は
[`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)、
診断データの設計・検証記録は
[`docs/phase1/macos-unified-logging-crash-metadata.md`](docs/phase1/macos-unified-logging-crash-metadata.md)
にあります。

## 構成

```text
bin/main.dart                         エントリーポイント
macos_application.json               product identity、helper、native package 宣言
lib/src/terminal_application.dart    AppKit ウィンドウとキーイベント
lib/src/terminal_core/               decoder、生成VT table、parser、SoA screen/action sink
lib/src/runtime_lifecycle.dart       root/worker lifecycle coordinator
lib/src/terminal_pane.dart           pane/session ID、owner、close状態
lib/src/terminal_session.dart        persistent login shellとPTY入出力
lib/src/terminal_buffer.dart         Phase 3までのbounded plain-text投影
test/run_tests.dart                  UI 非依存部分の最小テスト
../dart_appkit/packages/              AppKit、runtime、PTY、renderer の公開 package
```

## 製品実装へ進む際の境界

通常エントリーポイントは1 paneが1つのpersistent login shellを所有します。
現在の表示はCR/LF/Backspaceだけを扱うbounded plain-text投影で、引き続き
`TextView`を使います。一方、renderer packageのcustom-view providerと
`TerminalMetalView`の生成・attach境界に加え、incremental parserのactionを
typed-array画面へ適用する`TerminalScreenParserSink`まで用意済みです。本格的な
terminal emulator表示には次の機能が必要です。

1. SGR/palette、primary/alternate screen、wide/grapheme、reflow/scrollback
2. 色・属性・カーソル・選択・スクロールを描画する CoreText/Metal renderer
3. IME、クリップボード、キーバインドの仕上げ

`TerminalPaneOwner`がpaneを、`TerminalPane`がsession generationを、
`TerminalSession`が公開`PtyProcess`を所有します。実backendとdeterministic fakeは
同じ境界で交換できます。`TerminalBuffer`はPhase 3でANSI画面モデルへ置き換えます。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
