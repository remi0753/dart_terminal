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
model、および CoreText/Metal renderer は製品実装へ移行済みです。IME と入力source
受け入れmatrixに加え、terminal mouse reporting、local selection、drag autoscroll、
precision/momentum trackpad scroll、standard Copy/Pasteも製品経路へ接続済みです。
`TerminalMetalView` は同じ可視 viewport、local selection、cursor、cell metricsを
boundedなread-only text areaとしてVoiceOverにも公開します。

現在選定している製品 contract は、未改変の公式 Dart だけを使う AppKit root と、
独立して回収・再生成できる公式 Dart 子プロセス worker です。M1/arm64 Developer JIT
と Release AOT はともにこの observable contract へ移行済みです。旧 Engine 改変ファイル、
適用経路、およびそれを正当な成果物として扱う来歴・監査・test code は削除済みです。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- AppKitのphysical key、produced/unmodified text、7種のmodifier、repeatを分離し、
  menu優先後にfirst responderのtext-input clientから1回だけterminalへ配送するrouting
- 実`NSTextInputClient`のmarked text、UTF-16 selection/replacement metadata、commit、
  cancel、candidate rect。preeditはcanonical screenを変えず、Unicode 17の折り返し、
  選択背景、下線、composition caretをCoreText/Metal overlayとして描画
- US/JIS、dead key、Chinese/Japanese/Korean、emoji ZWJ、Unicode Hex相当のcommitと
  initial/repeated navigationを、実native text clientから実PTYまでexact byteで検証する
  versioned matrix。system input sourceを変更しない実機確認票も提供
- DECCKM/DECPAMを反映するbounded legacy xterm encoder（UTF-8、Control/Option、
  navigation、F1–F20、keypad）
- stable action、exact chord、conflict検出、override、unbound、passthroughを備えた
  immutable keybind engine、file/include/CLIのrepeatable typed keybind設定、AppKit menu
  shortcut優先の競合境界。全key/action/default/reserved shortcutは
  [生成リファレンス](docs/reference/keybindings-and-actions.md)から確認できる
- 19個のstable application actionを共有するbounded searchable registry、動的な
  availability/exactly-once dispatch、Application/File/Edit/Shell/View/Windowの
  native menu。Shift-Command-Pのnative command paletteはquery/selectionを独立所有し、
  dispatch完了後のavailabilityを再同期してterminal first responderを復元し、入力をPTYへ
  漏らさない。通常起動ではCommand-N/T/D、Shift-Command-DからNew Window、New Tab、
  Split Pane Right/Downを使用でき、focus traversal、tab selection、equalize、zoom、
  semantic promptへのprevious/next jumpも文脈に応じて有効になる。実製品gateではmenuと
  paletteから2 window/3 tab/5 paneを生成し、
  terminal write 0と各paneの入力分離を両runtimeで検証する
- DECSET 9/1000/1002/1003と1005/1006/1015/1016を追跡し、X10/default、UTF-8、
  URXVT、SGRのcell座標とSGR physical-pixel座標をbounded mouse reportとして実PTYへ
  送る製品routing。native logical pointへbacking scaleを一度だけ適用し、通常shellと
  Shift overrideは同じpointer eventをPTYへ重複送信せずcell-based selectionへ配送
- DECSET 1004を追跡し、native windowのfocus遷移を重複なしのbounded
  `CSI I`/`CSI O`としてactive PTYへ送る製品routing
- 完全な`DCS $ q m ST`に対し、現在のSGR属性・ANSI/256/direct色を64 byte以内の
  xterm互換形式で返すDECRQSS。外部製品固有の有効なSGR直列化差はraw証跡を保持して比較
- `CSI > q`/`CSI > 0 q`へ固定protocol identity `DartTerminal(1)`を返すXTVERSIONと、
  AppKit content viewのbounded logical pixel寸法・現在の行列数を返すXTWINOPS 14/18
- stable logical anchorを使うcharacter/word/logical-line multi-click selection、
  forward/reverse drag、1 deadlineのbounded edge autoscroll、history-aware viewport
  projection、1x/2x Metal selection overlay。CJK fallback glyphもcanonicalなwidth-two
  cellへ配置し、全角文字の左右どちらからでも同じgraphemeを選択・コピーする
- native Edit menuからのbounded plain-text Copy/Paste、wide CJKを含むexact Copy、
  bracketed paste、newline正規化、危険またはlarge pasteの再操作confirmation
- キー入力、Backspace/Delete、左右移動、Home/End、zsh自身の行編集とコマンド履歴
- 1 paneにつき1つのTTY付きinteractive login zsh
- 同じshell内での`cd`、環境変数、background job、`jobs`、`fg`/`bg`
- Control-C/Z/\\を含むtermios準拠のPTY byte入力と、追跡可能なControl-D EOF action
- Control-Dは常にPTY入力として扱い、shellの正常終了時はpane/windowを自動で閉じ、
  非0・signal・終了監視失敗時は理由を表示した非live paneを保持する終了policy
- ウィンドウサイズに追従する`TIOCSWINSZ`/`SIGWINCH`
- typed pane/session ID、単一owner、live shellの再操作close確認、process内容を読まない
  child/owning/foreground process-group snapshotと、OSC 133のcontent-free command-output
  hintを警告追加にだけ使う保守的close-risk分類、state層のidentity-bound per-pane確認
  transactionとsplit/tab/window collapse。全paneをvisual順に
  固定するaggregate Quit transactionは、Closeとの相互排他、stale/cancel/retry、AppKit
  deferred terminationへのexactly-once reply、cleanup後のprogrammatic terminationを扱う
- native handleと独立したmonotonic window/tab/split-node ID、64 paneまでのimmutable
  binary split topology、selected tab/focused pane/reverse index、collapseとordered teardownを
  持つapplication-owned state model。AppKit adapterはnative tab group、再帰split view、
  first responder、resize/equalize/zoomに加え、focused session title、bounded tab rename/
  color、local OSC 7 cwdのproxy iconを投影する。新しいtab/splitは信頼済みlocal cwdを
  継承する。zero-configの通常起動もこの階層を使い、menu/paletteからwindow/tab/splitを
  追加できる。2 tab/4 live paneの実製品gateで実zsh cwd、key/IME分離と
  PTY/Metal/text-input/native handle回収を両runtime検証する。versionedかつ
  terminal内容を含まない状態へwindow/tab/split/cwd/metadataと安全なwindow配置を保存し、
  fresh sessionとして復元する。実fullscreen enter/exit、display migration/clamp、
  Dock reopenの重複抑止に加え、2 logical window × 各2 tab × 各4 paneを2世代へ
  再生成し、16 sessionの完全回収も両runtimeで受け入れる。fake-AppKitでは同じ構成を
  3世代、合計24 sessionで通常test gate化する
- terminal内容を含めないpane state / PTY shutdown stage診断
- Control-Dのqueue受理、native write、foreground/termios、signal、waitpid、
  kernel exit status、PTY内/外のreap、exit公開をrequest IDで追えるcontent-free診断
- graceful/force/final deadlineを持つbounded PTY session teardownと型付き結果
- PTY通知欠落時もpane ownerを閉じ、status 75でhost終了するclassified recovery
- AppKit main-thread root と公式 Dart 子プロセス worker の bounded lifecycle
  （M1/arm64 Developer JIT / Release AOT）
- native event protocol v7（source generation、nanosecond timestamp、operation
  ID、focus/visibility/occlusion/backing scale/screen/frame/fullscreen state、
  application/window lifecycle/appearance、menu action、precision/momentum scroll）と、旧 v1–v6
  endpoint との compatibility negotiation
- generic/custom `View` 境界と、型を保った content-view attachment
- `dart_terminal_renderer_macos` の公開 facadeからdependency-owned
  `TerminalMetalView : MTKView`を通常起動で生成・attachし、live terminal screenを
  CoreText shaping、bounded glyph atlas、Metal frame submissionへ接続する製品表示
- `dev.dart-terminal` の macOS Unified Logging と、終了状態を判定できる
  privacy-safe なローカル実行メタデータ（M1/arm64 Developer JIT / Release AOT）
- generation／AppKit-main domain付きnative handle registryと、off-domain
  releaseを即時無効化してmain queueで完了するasynchronous destruction
- registryから投影するApplication/File/Edit/Shell/View/Window menu、明示的な
  Paste時だけ行うplain-text pasteboard read、非同期reply付きClose/Quit request
- chunk境界に依存せず不正byteからdeterministicに復帰するDart-only streaming
  UTF-8 decoderと、宣言的specから再生成・freshness検査できるtable-driven VT parser
- C0/C1、ESC、CSI、OSC、DCS、SOS/PM/APCのtyped action、CAN/SUB/ESC recovery、
  parameter/subparameter保持、固定bufferとsequence/payload/count/value上限
- 通常parserへ分岐を追加せずopt-inできるbounded parser inspectorと、文字本文・
  control-string payload・入力hash・時刻・path・環境を保持せず、canonical header byte、
  payload長、recovery分類、全limitをversion 1 JSONへ出力するdeterministic trace CLI
- ADR-003準拠の非公開SoA cell/row storage、cursor save/restore、default/custom
  tab stop、coalesced row damage/versionとmonotonic screen generation基盤
- top/bottom・optional left/right margin、origin/insert/autowrap/reverse-video、
  wrap-pending、cursor shape/blink/visibilityのtyped stateとatomic reset/clamp
- bounded style ID table、current/saved rendition、P0 text attributes、ANSI
  16/256色・truecolor・default colorのsemicolon/colon SGR適用
- typed xterm-256 palette、logical default foreground/background、独立cursor color、
  bounded OSC 4/10/11/12/104/110/111/112 color mutation/query/reset、
  palette-aware row damageとcursor-only presentation damage
- bounded OSC 52 selector/data分類とdeny-by-default clipboard境界。queryは
  clipboard dataを含まない空応答だけを返し、write/clearはAppKit pasteboardへ到達しない
- session-ownedなbounded title/icon/OSC 7 file-URI metadata、OSC 0/1/2、
  10段title stack、strict UTF-8/control/bidi境界、OSC 0/2からAppKit window titleへの
  root-isolate同期とRIS後のproduct title復帰
- shared style/palette資源と独立したgrid/stateを持つprimary/alternate screen、
  DEC private mode 47/1047/1048/1049、切替時full-snapshot contract
- Unicode 17 grapheme境界・幅判定、bounded grapheme intern、wide/continuation
  invariantとprimary historyを含むatomic resize/reflow
- fixed-page SoA scrollback、独立line/byte cap、O(1) page eviction、primary
  history/active gridを投影するbounded viewportとstable logical anchor
- end-exclusive cell/word/logical-line selection、soft/hard wrap準拠のbounded
  text extraction、cell-aligned exact scalarのforward/backward bounded search
- 最大64 byteのreply encoderと、DA/DA2、DSR/CPR、DECRQM、DECRQSS SGR、
  XTVERSION、XTWINOPS 14/18、OSC palette/default color queryのterminal-core dispatch
- ncurses 6.6で固定生成・能力監査した`xterm-256color` terminfoを両runtime bundleへ同梱し、
  起動時にheader/name/layoutを検証してlocal `TERMINFO`へ接続する環境contract。欠落・破損時と
  SSHのremote PTYでは私有pathを送らず標準`TERM=xterm-256color`へfallback。G0/G1、SO/SI、
  DEC Special Graphicsをscreen stateとして処理し、XTGETTCAPには監査済みcapability方針でbounded応答
- session-owned screen set/parserへのraw PTY byte feed、従来text projectionとの
  single-subscription共存、generated replyのnative bounded write queue接続
- historyとprimary/alternate grid、Unicode resource、mode/cursor/character-set/parser countを
  網羅し、行・cell・resource・出力上限を持つversion 3 terminal-state snapshotと、
  最初の相違位置・escaped contextを返すbounded comparison diagnostics
- 厳密検証するbyte-exact product parser corpus manifest、shell/less/top/vimの
  review済み記録snapshotをwhole・全single split・bytewiseで再生する非書換えharness、
  固定seedのproperty testと境界別fuzz seed/mutation corpus
- DEC文字セット、XTGETTCAP、OSC metadata/color/clipboard、focus/mouse、DECRQSS、
  XTVERSION/XTWINOPSの9修正familyを390 input byte・417 chunk planで固定するversion 1
  compatibility regression corpus。inventory、differential、実アプリの所有者付きgap、
  parser traceを一つの決定論的coverage reportで照合し、通常`make test`でfreshnessを検証
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
- renderer ABI v10のtyped device/shader/command failure state、bounded drawable
  unavailable観測、READY frameを保持する明示的on-demand presentation retry、
  最大3回のrenderer再生成、旧submission pinの一括解放、全atlas再公開とfull redraw、
  native GPU completion時間と受理済みatlas upload count/bytes、Dart frame
  build/submit時間、atlas hit rate、世代整合済みのimmutable aggregate metrics
- canonical screenを唯一の表示元とするlive Metal surface owner。SGR/DEC sequenceを
  cell stateとして描画し、terminal soft wrapとresize reflowで行を決め、履歴位置が
  bottomの間は大量出力後も最新prompt/cursorを最終表示行に保つ。zero-configでは
  macOS system monospaceを読みやすい14ptで使用し、native windowのRetina backing
  scaleをCoreText rasterにも一度だけ適用する。bitmapはtop-downでatlasへ公開し、
  1x/2xで同じ論理ink寸法を保って非対称glyphも上下反転せず表示する。fallbackの
  自然字送りには依存せず、
  各CoreText clusterをcanonicalなnarrow/wide cell原点へ配置する
- bounded immutable OSC 8 linkをscreen/history/reflowへ保持し、visible cellのhoverを
  Metal underlineで表示する。exact Command-primary-clickだけを再解決して所有し、
  `http`/`https`/`mailto` allowlistをDart/AppKitの両境界で通ったtargetだけを開く
- 現在の可視physical rowだけをUTF-16 documentへ投影し、terminal column境界、local
  selection、独立cursor、logical cell geometry、first-responder focusを、完全コピー済みの
  `TerminalMetalView` accessibility text areaから同期的なDart再入なしでVoiceOverへ公開する

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

## Configuration

設定ファイルがなくても従来どおり起動します。既定では
`$XDG_CONFIG_HOME/dart-terminal/config` を使用し、`XDG_CONFIG_HOME` が未指定なら
`~/Library/Application Support/Dart Terminal/config` を探索します。存在しない既定ファイルは
エラーにしません。別のファイルを使う場合は `--config=PATH`、設定ファイルを一切読まない
場合は `--no-config` を指定します。

zero-config terminal本文とSettingsの主編集面は、同じmacOS system monospace regular / 14ptを
共有し、Retina上でも同じ論理文字サイズで表示します。Settingsのstatus/detailは情報階層を
保つため、補助的な小さい文字サイズのままです。

`--help` は設定ファイルを読まず、typed schemaから生成した全optionの構文と適用policyを表示して
終了します。`--show-config` は通常と同じfile/include/CLI priorityを解決し、application、PTY、
renderer、worker、native windowを作らずに、全effective value、source、line/column、policy、
repeat occurrence、diagnosticをversionedかつboundedな一行形式で表示して終了します。値とpathは
JSON escapeされます。

```shell
make RUNTIME_ARCH=arm64 developer-jit-run RUNTIME_ARGUMENTS="--help"
make RUNTIME_ARCH=arm64 developer-jit-run \
  RUNTIME_ARGUMENTS="--show-config --config=/path/to/config"
```

全option、CLI構文、canonical default、live/new-session policy、上限、migrationは
[Configuration and command-line reference](docs/reference/configuration-and-command-line.md)を
参照してください。このreferenceと`--help`は同じschemaから生成され、通常の`make test`が
古い生成物を拒否します。

設定はUTF-8の`key = value`形式です。空行と`#`以降のコメントを使用でき、空白や`#`を含む
値はdouble quoteで囲めます。`include`の相対pathは、それを記述した設定ファイルを基準に
解決します。include先を先に適用し、include元、command lineの順に上書きします。

```text
include = shared.conf
working-directory = "/Users/example/Terminal Work"
shell = /bin/zsh
shell-integration = detect
theme = system
font-family = "JetBrains Mono"
font-size = 15
palette-background = #101418
palette-foreground = #d8dee9
window-width = 1000
window-height = 640
window-padding-horizontal = 12
window-padding-vertical = 8
macos-option-key = text
scrollback-lines = 50000
scrollback-bytes = 128MiB
cursor-shape = bar
cursor-blink = false
keybind = control+d=unbind
keybind = shift+control+k=pane.focus-next
```

現在のschemaは`working-directory`、新しいsession用の絶対`shell` executableと
`shell-integration = detect | none | zsh | bash | fish | nushell`に加え、`theme`、
default foreground/background/cursor、
ANSI palette 0–15、font family/size/synthetic style、初期window sizeとpadding、macOS Option keyの
`escape`/`text`動作、scrollback line/byte cap、初期cursor shape/blinkを公開します。同じ名前を
`--font-size=15`のようにcommand lineでも指定できます。解決済み設定は新しいwindow/tab/splitの
各paneへ適用され、既存paneのmutable resourceを共有しません。`keybind`は複数回指定でき、
exact physical key chordをpane actionまたはapplication actionへ割り当てます。構文、全key名、
action ID、`unbind`/`passthrough`、既定binding、予約済みnative shortcutは
[Keybindings and actions](docs/reference/keybindings-and-actions.md)を参照してください。
unknown key、不正な値、読めない明示ファイル、include cycle等はpath、line、column、安定した
diagnostic code、可能な場合は修正案とともに標準エラーへ表示します。有効な最後の値または
schema defaultへ復旧して起動を続けます。一方、command line自体の不正やintegration専用
fault optionのgate違反は従来どおりusage errorです。

構文として正しくても現在のアプリケーションから利用できないファイル設定値は、
`CFG_UNAVAILABLE_VALUE`と修正案を表示し、その項目だけschema defaultへ戻して起動します。
たとえばmacOSで解決できない`font-family`は`system`として起動し、他の有効な設定は維持します。
元の記述はSettings editorに残るため、その場でインストール済みfontへ修正できます。
明示的なcommand line値はこの自動復旧の対象にせず、暗黙に別の値へ変更しません。

Applicationメニューまたはcommand paletteの`Reload Configuration`、あるいは設定した
`application.reload-configuration` keybindで、起動時と同じfile/include/CLI priorityを再解決
できます。error diagnosticが1件でもあるreloadは全体を拒否し、現在のeffective configと
pane/PTY/native resourceを保持します。warning-onlyまたは正常な候補はatomicに受理します。
`macos-option-key`と`keybind`は既存paneの次のkey eventからlive適用され、それ以外の現在の
optionは新しく作るsession/resource/windowだけに適用されます。既存palette/OSC state、cursor、
scrollback、font、padding、window frameは書き換えません。自動file watchとSIGHUP reloadは
現在の対象外です。

Applicationメニューの`Settings…`（Command-,）、command palette、または非予約chordへ設定した
`application.open-settings` actionから、root設定ファイルを編集するnative modal editorを開けます。
新規・空・疎なファイルでも全36 optionを同じdocument内へ補完し、右のcontext panelはcaret位置の
current/draft value、構文、説明と、保存後に既存terminalへ即時反映されるか新規terminalから使われるかを
表示します。line/source行や別のvalue入力欄は持たず、panelを閉じても右端の細いrailが残ります。
コメントアウトされたoptionは行全体をdisabled色で表示し、現在のcaret行はNORMAL、`/`検索、INSERTの
すべてで淡い全幅背景として追従します。行背景はsyntax色や診断下線を変更しません。

起動時は`NORMAL`で、`i`または`a`が同じsyntax-highlight済みsurfaceを`INSERT`へ切り替え、
`Esc`が`NORMAL`へ戻します。両modeのdocument、font、色、syntax styleは同一です。`/`だけが
明示的に`SEARCH`を開始し、`↑`/`↓`で候補を移動、`]`でcontext panelを開閉します。
Command-Sはroot全体を既存schemaで事前検証します。invalid draftはeditorとlast-known-good設定を保持し、
該当箇所を下線表示してファイルもreload controllerも変更しません。valid draftだけを同一directoryで
atomic保存し、上記のshared reload actionを1回実行します。NORMALの`Esc`またはwindow closeは全native
editor ownerを解放してterminalのfirst responderを復元します。canonical provenance、include/CLI priority、
全diagnosticの機械可読表示には引き続き`--show-config`を使用できます。

`theme` は `system`、`light`、`dark` を受理し、互換記法の `default` は `system` として扱います。
`default`を使用すると`CFG_DEPRECATED_VALUE` warningと`theme = system`への修正案を表示し、
canonical effective outputは常に`system`を使用します。
組み込みの `Dart Light` / `Dart Dark` を基礎に、明示した foreground/background/cursor と
ANSI palette 0–15 だけを上書きします。OSCによる実行中のpalette変更はさらに上位のlayerとして
保持され、OSC reset時は現在のtheme値へ戻ります。`system` をcaptureした既存paneはmacOSの
effective appearanceをlive追従し、固定`light`/`dark` paneは追従しません。reloadでthemeを
変更しても既存paneのpolicyは変わらず、新しく作るwindow/tab/splitから反映されます。
shell設定と、無効・unsupported・resource欠落時に通常shellへ戻すbounded launch planは
定義済みです。zsh、bash、fish、nushell向けのversion 2 bootstrap resourceもbundleへ
宣言し、固定path、size、SHA-256、UTF-8をまとめて検証できない場合は部分適用しない
contractを設けています。resourceはcommand/prompt本文を保持せず、OSC 133 lifecycleと
local cwd/titleだけを投影します。通常起動への新しいpaneはcapture済みのshell
executable/policyから検証済みlaunch planを生成します。
macOS同梱の`/bin/bash`は`ENV` startupを無効化しているため、明示`bash` policyでも通常の
login shellへ安全にfallbackします。bundle内のzsh統合と明示的な`none`は、隔離した通常の
`.zshenv`/`.zshrc`を各1回実行する実AppKit/PTY製品としてDeveloper JITとRelease AOTの両方で
検証します。detectではprompt/command/output row mark、cwd-basename title、履歴上の
previous/next prompt action、同一process groupで動くblocking shell builtinへの追加close
warningと、その取消後のidle Quitまでを検証し、`none`では全semantic projectionが無効です。

```shell
make RUNTIME_ARCH=arm64 runtime-shell-integration
```

設定値が実際の通常製品へ反映されることは、実設定ファイルから4 paneを生成し、表示色、
font、window/padding、cursor、Option入力、scrollback上限、pane/application keybind、
unbind、Command passthrough、invalid reserved shortcutからの復旧、invalid/corrected reload、
利用不能なfontの`system`復旧と修正前reload/save拒否、live/new-session policy、native menu優先、
独立resourceに加え、worker/AppKit所有を作らない
`--show-config`、Settingsのnative menu/command palette/shared action、全option document、明示検索、
同一syntax表示のNORMAL/INSERT、invalid saveの非永続化、valid atomic saveからの1回のreload、
commented optionの全行disabled表示、modeをまたぐ全幅current-line表示、context diagnostic、
focus/handle cleanupをDeveloper JITとRelease AOTで確認します。
両runtimeのgateは
次で再実行できます。

```shell
make RUNTIME_ARCH=arm64 runtime-configuration-integration
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
make RUNTIME_ARCH=arm64 developer-jit-hierarchy
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
`TERMINAL_APPLICATION_QUIT_SNAPSHOT`と`TERMINAL_APPLICATION_QUIT`もpane数、固定process
分類、opaque operation ID、cleanup分類だけを示し、terminal内容やprocess名を含みません。
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
make RUNTIME_ARCH=arm64 release-aot-display
make RUNTIME_ARCH=arm64 release-aot-hierarchy
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
make RUNTIME_ARCH=arm64 runtime-terminal-display-integration
make RUNTIME_ARCH=arm64 runtime-native-hierarchy-integration
make RUNTIME_ARCH=arm64 runtime-user-actions-integration
make RUNTIME_ARCH=arm64 runtime-configuration-integration
make RUNTIME_ARCH=arm64 runtime-theme-integration
make RUNTIME_ARCH=arm64 runtime-restoration-integration
```

`make RUNTIME_ARCH=arm64 runtime-verify` は source check、両 mode の bundle audit、
smoke、real-PTY live Metal display、native tab/4-pane hierarchy、通常製品のuser action、
effective-config early exit/Settings/configuration reload、light/dark/system appearance、
fullscreen/migration/restoration/reopen、lifecycle、bounded traffic、resource stress、
shutdown fault suiteをまとめて実行します。display suiteは
SGR除去、style、soft wrap、
bottom prompt、newest-only frame boundに加え、PTY由来のvisible text、local selection、
cursor、native accessibility selector/geometry/focus/notificationをDeveloper JIT/
Release AOTの実GUIで確認します。
native hierarchy suiteは2つのnative tabと4つのlive Metal paneを作り、splitの
resize/equalize/zoom、first-responder focus、OSC title/cwd、tab rename/color、proxy icon、
子zshへのlocal cwd継承、raw key/IMEのpane分離を確認します。Shift-Command-Pのnative
command paletteから`Focus Next Pane`をexactly-onceで実行してterminal write 0、対象pane
だけのfocus変更、正しいfirst responder復元も確認します。さらに実native menu/window
Closeでforeground確認とnon-live即時closeを、実native terminationの拒否・再試行と
aggregate menu Quitでatomic teardownを通し、4つのPTYと全native resourceの回収を
Developer JIT/Release AOTの両runtimeで検証します。4つのsurfaceは1 pane 1 pending、
4 work/4 ms turnの共有round-robin schedulerを使い、個別timerによる競合を避けます。
user action suiteは通常起動と同じdispatcher、hierarchy、pane resource factory、Close/Quit
経路を使い、native menuのSplit Right/New Tab/New Window/Close/Quitと、command paletteの
Split Downを操作します。2 window/3 tab/5 paneの生成、各paneへのraw key/IME分離、
1 paneを閉じた後の4-pane階層、5つのPTY世代と全Metal/text-input/native handleの回収を
Developer JIT/Release AOTで要求します。
theme suiteはv7 appearance eventを通常製品へ注入し、初期light、live dark/light、custom ANSI
overlay、system/fixed pane、reloadのnew-session境界を実Metal frameで検査します。同じpaneの
PTY、screen、palette/style/scrollback、surface、renderer/atlas resourceを維持し、3 session、
text-input、event subscription、worker、native handleを両runtimeで完全回収することを要求します。
同じsuiteは1 paneから正確に100 MiBを出力している間に別paneの入力を既存のtext-input
routeからPTY、parser、Metal受理まで測り、同一launchのidle baselineの2倍以内、flood
完了前の応答、schedulerのyield増加、pending/work/frame上限を両runtimeで要求します。
terminal parser向けPTYは4 KiB/0のread high/low watermark、4 KiB delivery、1 Dart
event-loop turnあたり2 callbackを選びます。同期consumerの完了後にACKし、2 callback
ごとに次のturnへ譲るため、1つのflood portがready timerや別PTYを飢餓状態にしません。
このturn budgetは`dart_appkit`の汎用per-command設定で、既定値0は従来どおり即時ACKです。
他アプリは既定動作を保つか、用途に応じて1〜8を独立に選択できます。
restoration suiteは実fullscreen enter/exit後にdisplay migrationを適用し、
2 logical window × 各2 tab × 各4 paneをcontent-freeなversioned stateへ保存してfresh
ownerで再生成します。重複Dock reopenのcoalescing、cwd継承、2世代16 PTYと
Metal/text-input/native handle/workerの完全回収をDeveloper JIT/Release AOTで同じ契約として
確認します。Phase 7の4終了条件はversioned coverage inventoryがunit、fake-AppKit
integration、real-AppKit UIの各証拠と通常`make test`への収録を照合します。
resource stress は実アプリの Dart API から 1,000 組の Window/View を生成・
破棄し、毎回 native handle が基準値へ戻ることを確認します。shutdown fault suite は
malformed/late event、double dispose、worker crash を封じ込め、最終 native handle が 0、
記録した worker PID が消滅することを確認します。いずれも専用の integration-test gate が
ない通常起動では選択できません。
汎用 builder は現在、実行ホストと同じ architecture を構築します。x86_64、Rosetta、
Universal、Intel-native の再受け入れは、ROADMAP 上の低優先 follow-up です。

Phase 0 の debug/JIT、release-AOT、worker-isolate、PTY、Metal、CoreText の native
実装は歴史的な feasibility evidence として `docs/phase0` から参照します。製品・bundle
build path には native source とその旧 build target を残していません。Phase 6 の外部
application比較で使ったreview済みncurses fixture sourceだけは、prebuilt fixtureの来歴を
固定するtest corpusとして保持し、製品へcompile/link/bundleしません。parser/benchmark
などの Dart-only harness は後続実装の比較資料として残しています。

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
lib/src/terminal_renderer/           CoreText/atlas/Metalのlive製品表示
lib/src/terminal_buffer.dart         lifecycle診断用のlegacy text projection
test/run_tests.dart                  UI 非依存部分の最小テスト
../dart_appkit/packages/              AppKit、runtime、PTY、renderer の公開 package
```

## 現在の製品境界

通常エントリーポイントは1 paneが1つのpersistent login shellを所有します。
PTY bytesはincremental parserからtyped-array画面へ適用され、そのcanonical screenが
通常起動の`TerminalMetalView`へdamageとして渡ります。SGR/palette、primary/alternate
screen、wide/grapheme、soft wrap、resize reflow、cursor、visual bellをCoreText/Metalで
表示します。`TextView`やnewline単位のtext projectionは製品表示に使いません。

viewportはbottom-followを既定とし、primary historyをprecision/momentum trackpadや
wheelで移動できます。terminal mouse tracking中はwheel reportをPTYへ排他的に送り、
Shift overrideとalternate-screen cursor-key emulationも同じbounded routingで扱います。
standard clipboardとkeybind設定は製品経路へ接続済みです。
通常の大量出力後に最新promptが表示範囲外へ隠れることはありません。

`TerminalPaneOwner`がpaneを、`TerminalPane`がsession generationを、
`TerminalSession`が公開`PtyProcess`を所有します。実backendとdeterministic fakeは
同じ境界で交換できます。`TerminalBuffer`はcontent-free lifecycle fixtureの補助として
のみ残り、表示行やpixelを決めません。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
