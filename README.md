# Dart Terminal

`dart_appkit` を土台に、Dart で独立実装する macOS 向けターミナル
エミュレーターです。Ghostty は機能・品質の比較基準としてのみ参照し、
Ghostty や `libghostty` を製品へ組み込みません。

主要な開発・実機受け入れ baseline は Apple M1/arm64 です。Release AOT は
x86_64 cross-build と Rosetta 実行、arm64/x86_64 Universal bundle の厳密監査と
M1-native 実行まで確認します。Intel-native の no-rebuild 実機確認だけを主要ゴール後の
低優先 follow-up とし、M1 の完了を阻害しません。

現在の通常エントリーポイントは、再利用可能な `dart_pty_macos` を使う
pane-owned persistent login shell です。Phase 0 の native spike source は移行時に削除し、
成立性と測定結果は `docs/phase0` に保存しています。Dart-only VT parser と screen
model、および CoreText/Metal renderer は製品実装へ移行済みです。IME と入力source
受け入れmatrixに加え、terminal mouse reporting、local selection、drag autoscroll、
precision/momentum trackpad scroll、standard Copy/Pasteも製品経路へ接続済みです。
`TerminalMetalView` は同じ可視 viewport、local selection、cursor、cell metrics、
effective padding originをboundedなread-only text areaとしてVoiceOverにも公開します。

現在選定している製品 contract は、未改変の公式 Dart だけを使う AppKit root と、
独立して回収・再生成できる公式 Dart 子プロセス worker です。M1/arm64 Developer JIT
と arm64/x86_64 thin・Universal Release AOT はこの observable contract へ移行済みです。
旧 Engine 改変ファイル、
適用経路、およびそれを正当な成果物として扱う来歴・監査・test code は削除済みです。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- AppKitのphysical key、produced/unmodified text、7種のmodifier、press/repeat/releaseを分離し、
  menu優先後にfirst responderのtext-input clientから1回だけterminalへ配送するrouting
- 実`NSTextInputClient`のmarked text、UTF-16 selection/replacement metadata、commit、
  cancel、candidate rect。preeditはcanonical screenを変えず、Unicode 17の折り返し、
  選択背景、下線、composition caretをCoreText/Metal overlayとして描画
- US/JIS、dead key、Chinese/Japanese/Korean、emoji ZWJ、Unicode Hex相当のcommitと
  initial/repeated navigation、Option+Left／Rightのshell word navigationを、実native text
  clientから実PTYまでexact byteで検証するversioned matrix。system input sourceを変更しない
  実機確認票も提供
- DECCKM/DECPAMを反映するbounded legacy xterm encoder（UTF-8、Control/Option、
  navigation、F1–F20、keypad）に加え、主/代替画面ごとの16段stack、query/set/push/pop、
  flags 1/2/4/8/16、canonical text/functional/keypad、alternate/base-layout、associated text、
  press/repeat/releaseを扱うKitty keyboard protocol。既定flags=0ではlegacy byteを維持し、
  xterm modifyOtherKeys 1–3とapplication Escapeも独立して処理する。query reply、画面分離、
  Control-D releaseのexact byteは実PTY/AppKit経路をDeveloper JIT/Release AOTの両方で検証。
  既定のOption-as-EscapeではOption+Left／Rightを`ESC b`／`ESC f`として送り、shell上で
  `D`／`C`を入力せず前／次の単語へ移動する
- stable action、exact chord、conflict検出、override、unbound、passthroughを備えた
  immutable keybind engine、file/include/CLIのrepeatable typed keybind設定、AppKit menu
  shortcut優先の競合境界。全key/action/default/reserved shortcutは
  [生成リファレンス](docs/reference/keybindings-and-actions.md)から確認できる
- 44個のstable application actionを共有するbounded searchable registry、動的な
  availability/exactly-once dispatch、Application/File/Edit/Shell/View/Windowの
  native menu。Shift-Command-Pのnative command paletteはquery/selectionを独立所有し、
  dispatch完了後のavailabilityを再同期してterminal first responderを復元し、入力をPTYへ
  漏らさない。通常起動ではCommand-N/T/D、Shift-Command-DからNew Window、New Tab、
  Split Pane Right/Downを使用できる。Quick Lookは標準Control-Command-Dを予約した
  shared action contractを持つ。Command+矢印はsplit layout上で最も近い同方向のpaneへ
  active focusを移し、Shift+Command+矢印はfocused paneに最も近い同方向のsplit dividerを
  1 cellずつ動かしてdescendantの最小寸法で停止する。8つのchordはrepeatable `keybind`で
  別action、unbind、passthroughへ上書きできる。focus traversal、
  tab selection、equalize、zoom、semantic promptへのprevious/next jumpも文脈に応じて
  有効になる。実製品gateではmenuとpaletteから2 window/3 tab/5 paneを生成し、Retina
  scale継承、divider command後の固定font metricsとgrid resize、terminal write 0、
  各paneの入力分離を両runtimeで検証する
- terminalに重ならない、初期表示true／既定380 pt幅の右側Context DockとDirectory Navigator。
  `context-dock-visible = false`で新しいwindowの初期表示を無効にでき、
  `context-dock-width = 420`のように220–640 ptの幅を指定できる。幅の設定変更は既存windowにも反映する。
  通常時はfocused
  local paneのtrusted working directory、dotfileを含むfile/folder tree、lazy subtreeを上段の
  bounded scroll領域へ表示し、選択file/folderのpermission・owner・size・mtime・symlink metadataと
  path操作は下段の固定read-only領域へ表示する。
  Option-Shift-CでDockだけを表示／非表示にし、terminal／Navigatorのどちらが入力中でも同じ
  shared actionを実行する。tree上のfolderはReturnで開閉でき、Command-Right／Leftでも展開／折り畳みできる。
  Shift-Command-Hはfocused paneのdot-prefixed file/folderとそのsubtreeを、現在のinput focusを変えずに
  tree、Search、Go Toで一括表示／非表示にする。初期状態は表示で、Dock内に現在状態を明示する。
  Shift-Command-FでSearchへ移るとquery末尾にnativeの点滅caretが現れ、同じlistがcurrent subtree、recent location、明示root、
  Spotlight metadata indexのprogressive検索結果へ切り替わる。source/coverageとpartial・
  unavailableを区別し、filesystem rootを暗黙にwalkしない。current working directory配下のSearch結果はReturn／Command-Rightで
  Move treeへrevealでき、folderなら展開するが、外部resultはrootを変更せずSearchに残る。Shift-Command-GのGo Toはtreeを保ち、
  current subtreeをbounded探索して必要なancestorだけをlazy展開し、一致rowへ選択を移す。Shift-Command-MのMoveはquery入力を止めて
  tree navigationだけを所有する。SearchとGo Toのqueryはpaneごとに独立して保持する。
  EscapeでNavigator modeとqueryを保ったままterminalへ戻り、Dockの表示は`Mode: Terminal`へ切り替わる。
  矢印/Page/Command+矢印の操作中はPTY write 0を保つ
- NavigatorのCommand-Cは選択したabsolute pathだけをcopyし、Option-Returnは既存paste
  admissionでshell literalにquoteした1 pathを改行なしで挿入してterminalへ戻る。自動cdや
  command実行はせず、stale/remote/alternate screen/foreground process/manual secure inputは
  fail closedになる。filesystem path・query・resultはdiagnosticsへ含めない。操作とVoiceOver/
  Full Keyboard Accessの実機確認は
  [Directory Navigator manual checklist](docs/phase7/context-dock-directory-navigator-manual-checklist.md)を参照
- Context Dockを表示したままlocalのforeground process groupを実行すると、Directory Navigatorとは別名の
  read-only `Process Inspector`へ自動で切り替わる。Dock全高を使う一つのscrollable表示に最大32 processの名前と経過時間、
  primary executable、shell sourceではなくprocessから観測したargv、PID／PGIDをまとめ、pipelineも同じjobとして扱う。
  terminalが入力を所有したままなのでinteractive commandを操作でき、Shift-Command-F/G/MはPTYへ送らず消費する。
  75 ms未満の短いcommandは表示を切り替えず、silent commandも250 ms以内に検出し、詳細情報の再取得は最大1秒に
  1回とする。shell builtinは推測したargvを出さず実行中statusだけを示す。ECHO-offやmanual／automatic
  Secure Keyboard Entry中もprocess情報を表示し、入力保護とは独立させる。Dock非表示、app非active、
  focus変更では保持したpath／argvを即時破棄する。終了後はfreshな
  Directory Navigatorへ戻る。SSH先のremote process introspectionは対象外。視覚・VoiceOverの実機確認は
  [Process Inspector manual checklist](docs/phase7/context-dock-process-inspector-manual-checklist.md)を参照
- View > Show Process Arguments（日本語: プロセスの引数を表示）は、入力保護とは独立して
  Process Inspectorのargvだけを表示／非表示にする。既定は表示で、menuのcheckが現在状態を示す。
  Shift-Command-Pのcommand paletteからも検索でき、任意の`view.toggle-process-arguments` keybindへ
  割り当てられる（既定shortcutなし）。非表示時もprocess名／executable／PID／PGID／elapsedは表示し、
  native visual／accessibility documentとretained snapshotからargvを除く。再表示は次のfresh inventoryを待つ。
  この選択はwindow／pane／command間で共有し、app終了まで保持するが設定やrestorationへ保存しない
- focused live paneだけを追跡するsingle-windowのread-only Terminal Inspector。
  printable textはcountのみ、string payloadはlengthのみを保持し、focus移譲時とclose時に
  旧captureをclearする。View > Open Terminal Inspector（Option-Command-I）と
  File > Export Diagnostics…（Option-Command-E）はmenu、Command Palette、任意keybindで
  shared actionを使う。明示保存するversion 1 JSONは1 MiB以内の固定allowlistで、terminal
  text、command、cwd/path、argv/environment、clipboard/notification、hyperlink/image、
  timestamp/stable ID/raw errorを含めず、sibling temporary fileからatomic replaceする。
  privacy境界、失敗分類、検証方法は
  [Terminal inspector and diagnostics reference](docs/reference/terminal-diagnostics.md)を参照
- File > Export Latest Crash Report…とCapture Hang Sample…は、生のApple `.ips`または
  現在のDart Terminalを1秒だけ採取した`.sample.txt`を、警告付きSave panelで明示選択した
  ローカルファイルにだけ保存する。Saveを確定する前にはreport directoryも`/usr/bin/sample`も
  使用せず、background scan、automatic upload、telemetryは行わない。singletonのread-only
  status画面と通常diagnosticsへ残すのは固定状態とbounded countだけで、path、PID、timestamp、
  stack、raw error、artifact内容は保持しない。Release AOTの9 code imageにはUUID/hashを照合した
  offline dSYM packageを別途生成できる。詳細は
  [Terminal inspector and diagnostics reference](docs/reference/terminal-diagnostics.md)を参照
- `application.toggle-quick-terminal`をmenu、command palette、任意のlocal keybind、
  opt-inのsystem-wide shortcutで共有するsingleton Quick Terminal。選択画面の現在の
  visible frameへclampし、最初のframe前にRetina scaleを投影する。表示・非表示のframe寸法を
  同一に保つtop-edge animation、hidden中のPTY/session保持、focus-loss autohide、通常windowとの
  独立性、shortcut変更時の競合表示と旧登録保持をDeveloper JIT/Release AOTで検証する。
  global shortcutはexclusive system hot keyだけを所有し、全keyboard monitorやAccessibility権限を
  使用しない
- focused live paneのcontent-freeなPTY ECHO状態だけを使うSecure Keyboard Entry。
  ECHO-off時の自動取得と、menu・command palette・任意のlocal keybindで共有する手動切替を
  備え、所有中だけterminal viewへaccessibleなautomatic/manual indicatorを表示する。
  Settingsにはmode・owned/yielded/released・自動/表示設定を示し、window/pane/Quick Terminal間の
  focus移譲、app非active時のyield/reacquire、終了・失敗時のbalanced releaseを行う。
  `macos-secure-input-auto`と`macos-secure-input-indication`はlive変更でき、実PTY、IME、AppKit、
  Metal、menu、Settings、Quitの経路をDeveloper JIT/Release AOTで検証する
- DECSET 9/1000/1002/1003と1005/1006/1015/1016を追跡し、X10/default、UTF-8、
  URXVT、SGRのcell座標とSGR physical-pixel座標をbounded mouse reportとして実PTYへ
  送る製品routing。native logical pointへbacking scaleを一度だけ適用し、通常shellと
  Shift overrideは同じpointer eventをPTYへ重複送信せずcell-based selectionへ配送
- DECSET 1004を追跡し、native windowのfocus遷移を重複なしのbounded
  `CSI I`/`CSI O`としてactive PTYへ送る製品routing
- 完全な`DCS $ q m ST`に対し、現在のSGR属性・ANSI/256/direct色を96 byte以内の
  xterm互換形式で返すDECRQSS。外部製品固有の有効なSGR直列化差はraw証跡を保持して比較
- `CSI > q`/`CSI > 0 q`へ固定protocol identity `DartTerminal(1)`を返すXTVERSIONと、
  AppKit content viewのbounded logical pixel寸法・現在の行列数を返すXTWINOPS 14/18
- stable logical anchorを使うcharacter/word/logical-line multi-click selection、
  forward/reverse drag、1 deadlineのbounded edge autoscroll、history-aware viewport
  projection、1x/2x Metal selection overlay。CJK fallback glyphもcanonicalなwidth-two
  cellへ配置し、全角文字の左右どちらからでも同じgraphemeを選択・コピーする
- OSC 133で識別したprimary live input上の正確なOption-clickを、現在のcursor位置までの
  CSIまたはapplication-cursor SS3矢印へ変換する。1 gestureは最大85移動／255 byteで、
  drag、history、alternate screen、stale stateでは送信せず、terminal mouse reportingが
  有効ならreport側だけが所有する。通常のtriple-clickはprompt/input/output境界内に留まり、
  ControlまたはCommand triple-clickとdragは完全なoutput blockを選択する
- native Edit menuからのbounded plain-text Copy/Paste、wide CJKを含むexact Copy、
  bracketed paste、newline正規化、危険またはlarge pasteの再操作confirmation
- terminal mouse reportingがgestureを所有していない時だけ表示するnative context menu。
  Copy、Paste、Quick Look、Split Right/Downはmain menu・command paletteと同じactionと
  availabilityを使い、右クリック／Control-clickをselection変更やPTY入力へ重複配送しない。
  Force-clickまたはControl-Command-DのQuick Lookは、現在のviewport generationとfont/
  baselineに対応するboundedなwordだけをmacOSのdefinition popoverへ渡し、空白、切り詰め、
  staleなcellでは何も表示しない
- 現在のbounded selectionだけをmacOS Servicesへ公開し、Serviceから戻るplain textと、
  paneへdropしたplain text／local file URLをfocused targetの通常Paste policyへ配送する。
  multiline/control textは既存の再操作confirmationを経由し、file pathは空白やquoteを含んでも
  shell literalとして安全にquoteする。Finderの **New Dart Terminal Tab Here** と
  **New Dart Terminal Window Here** は、選択fileの親directoryまたは選択directoryを
  正規化・重複除去してfresh standard tab/windowのcwdにする。設定画面に専用toggleはなく、
  手動のFinder／third-party Service／Force Touch確認手順は
  [Native Content Manual Acceptance Checklist](docs/phase10/native-content-manual-checklist.md)を参照
- standard window → tab → terminalだけを公開するnative AppleScript dictionary。
  monotonicな型付きstable ID、title、trusted local cwd、selected/focused関係を同期cacheから読み、
  new window/tab、4方向split、input、focus、terminal/tab/window closeをDart所有の通常階層へ配送する。
  terminal画面/historyとQuick Terminalは公開せず、inputは既存のbounded paste確認・実PTY transport、
  closeはforeground-process確認を迂回しない。`macos-applescript`は既定有効でlive無効化・再有効化でき、
  外部senderのAutomation/TCC権限はmacOSと利用者だけが管理する。辞書、制限、例、権限境界は
  [AppleScript reference](docs/reference/applescript.md)、外部確認手順は
  [manual acceptance checklist](docs/phase10/applescript-manual-acceptance.md)を参照
- Swift App Intentsとして **New Terminal Window**、**New Terminal Tab**、
  **Quick Terminal** の3つだけをShortcutsへ公開する。すべてparameterlessかつforegroundで、
  既存の共有action dispatcherへbounded queueからexactly onceで配送する。
  `macos-app-intents`はlive無効化・再有効化でき、overflow／disabled／timeout／shutdownは
  hierarchyを変更せずfail closedになる。Developer JIT／Release AOTの両bundleでSwift image、
  compiler抽出metadata、3 actions／3 shortcutsと実queueを検証し、外部Shortcuts確認は
  [App Intents／notifications manual checklist](docs/phase10/app-intents-notifications-manual-checklist.md)を参照
- terminal output由来のdesktop signalを、pane/session所有権とglobal policyの下で投影する。
  legacy OSC 9 notificationとConEmu OSC 9;4 progress、Kitty OSC 99のplain UTF-8
  title/body・bounded ID/chunk subset、OSC 133 A/B/C/D/I/L/N/Pのcontent-free semantic
  stateを扱う。OSC 133はcommand本文を別途保持せず、content-free command IDとstable
  logical anchorによるexactなprompt/command/output rangeも固定容量・固定query上限で提供し、
  history reflowではidentityを保ち、eviction/reset後はstale rangeを返さない。通知は全pane合計
  3件/10秒（hard maximum 8）、sessionごと8 live ID、最大64
  sessionに制限し、同一IDをcoalesce、activeかつfocusedな出力を抑止する。attacker IDは
  native IDに使わず、RIS/pane closeで通知を取消し、focused paneのprogressだけをDock badgeへ
  投影する。`macos-notifications`はlive変更でき、非同期の現在設定／許可／delivery failureを
  content-freeにSettingsへ表示する。default clickは独立opaque tokenからstill-live sessionを
  再解決してwindow/tab/paneをfocusし、stale／duplicate responseはinertになる。
  2実PTYでのburst/reset/close/recoveryとnative removal/Dock cleanupに加え、許可拒否、再試行、
  click focus、disable/re-enable、owner回収をDeveloper JIT/Release AOTの両方で検証
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
  first responder、resize/equalize/zoomに加え、native divider dragをmodel/layout/Metal
  viewport/terminal grid/PTY winsizeへ同期し、drag gestureをterminal mouse入力から分離する。
  新規splitは最初のlayout前にwindowのRetina backing scaleを受け取る。applicationがactiveで、
  visibleかつfocusedなwindowのselected tabにあるfocused paneだけがcursorを表示・点滅し、
  ほかのpaneはcursorを消し、背景RGBの暗転とviewport全体の32% neutral charcoal scrimで
  文字・画像も含めて暗くする。active paneの背景alpha、PTY更新、visual bell、画像animationは
  維持する。
  focused session title、bounded tab rename/
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
- genericなnative event protocol v15（source generation、nanosecond timestamp、operation
  ID、focus/visibility/occlusion/backing scale/screen/frame/fullscreen state、
  application/window lifecycle/appearance/display preferences、menu action、
  exclusive global hot key、precision/momentum scroll、power state、screen-set
  change、memory pressure）と、旧 v1–v14
  endpoint との compatibility negotiation
- sleep/wake、screen-set change、memory warning/criticalをAppKit callback後のbounded
  product policyへcoalesceする。sleep中はframe/deadlineを止め、wake時に現在のdisplay/
  backing scaleを再解決して最新canonical stateだけを再描画する。pressure時はscreen、
  scrollback、selection、preedit、PTY、Kitty image stateを保持し、再生成可能なhover/
  shaping/atlasだけをpin-safeに段階回収する。通常製品の8回反復gateでPTY、FD、root/
  worker、Metal/GPU pin、text-input/native handleの基準線をDeveloper JIT/Release AOTで
  検証する。実時間24/72時間と物理sleep/display操作は低優先follow-upとして区別する
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
- bounded style ID table、current/saved rendition、underline variant/color、
  overlineを含むtext attributes、ANSI 16/256色・truecolor・default colorの
  semicolon/colon SGR適用。DECSCAのcell protectionと、wide/graphemeを分断しない
  DECSED/DECSEL selective erase
- typed xterm-256 palette、logical default foreground/background、独立cursor color、
  bounded OSC 4/10/11/12/104/110/111/112 color mutation/query/reset、
  palette-aware row damageとcursor-only presentation damage
- bounded OSC 52 selector/data分類、read/write別の`deny|ask|allow` new-session policy
  （既定は両方`deny`）、clearのwrite-policy追従。`c` clipboardだけをstrict UTF-8/
  3,060 byte上限で扱い、askはfocused sessionのexact requestをnative window、Edit menu、
  command paletteで確認する。確認待ちは全appで1件/30秒、pasteboard世代、RIS、focus、
  pane closeで失効し、read replyは既存のordered bounded PTY FIFOを使う。Developer JIT/
  Release AOTの実PTY/AppKit gateはユーザーのpasteboardに触れないmemory adapterで検証
- session-ownedなbounded title/icon/OSC 7 file-URI metadata、OSC 0/1/2、
  10段title stack、strict UTF-8/control/bidi境界、OSC 0/2からAppKit window titleへの
  root-isolate同期とRIS後のproduct title復帰
- shared style/palette資源と独立したgrid/stateを持つprimary/alternate screen、
  DEC private mode 47/1047/1048/1049、切替時full-snapshot contract
- DEC private mode 2026 synchronized output。canonical grid・PTY reply・inputは
  継続しながら最後のaccepted Metal frameとcaret/accessibility projectionを保持し、
  end/RISまたは1,000 ms monotonic timeoutでnewest full frameだけを公開する
  constant-space presentation gate
- private DSR 996への997 dark/light応答と、DEC mode 2031でopt-inした実際の
  system appearance遷移だけを通知するbounded light/dark contract。固定theme paneと
  重複appearance eventは通知せず、RIS/session teardownでsubscriptionを解除する。
  XTWINOPS 16はlogical cell寸法、mode 2048は有効化直後と完了したresize後に
  rows/columnsとpadding-free logical viewport pixel寸法を返す。Unicode 17の
  narrow-ambiguous grapheme/width contractはmode 2027をpermanently setとして公開する
- Kitty graphicsのbounded APC grammar、process-worker direct RGB/RGBA/PNG+zlib decode、
  multipart/FIFO reply、主/代替画面別のbounded image/placement store、ID/number replacement、
  static put/transmit-and-place/delete、signed zを極端negativeのcell background下・通常negativeの
  text下・nonnegativeのtext上へ分ける3帯layer、scrollback/margin clip/erase/
  reflow/alternate/RIS lifecycle、animation frame transmit/edit/control/compose/delete、
  imageごと64 total frame・画面ごと256 extra frame/16 MiBのgeneration-safe state、
  visible imageだけを進めるmonotonic newest-only playback、hidden/occluded/synchronized/recovery
  pause、frame content generation付きimmutable viewport projection。CPU oracleと通常の
  color-atlas/Metal frame pathはanimationを含む同じnearest-neighbor tile、layer order、
  1x/2x pixel結果を使い、
  static/animation graphics、65-image pressureによる決定的resource eviction、stale atlas cleanupは
  実zsh PTYからDeveloper JIT/Release AOTの両方で受け入れる。transient/unplaced優先と
  immutable generation/ID tie-breakで他imageをwhole-resource evictionし、targetは除外、
  満たせない要求は既存stateを変えず拒否する。file/shared-memory transport、
  virtual/relative placementは対応範囲外。searchの通常/選択matchとinspectorのhyperlink/
  semantic prompt/inputは本文を保持・変更しないbounded overlayとして合成し、focus/closeで
  clearする。canonical straight-alpha RGBA8 sRGB、tag付きDisplay P3の一回変換、linear-light
  source-over、1x/2x CPU/Metal一致を固定DTGIと両runtime製品gateで検証する
- Unicode 17 grapheme境界・幅判定、bounded grapheme intern、wide/continuation
  invariantとprimary historyを含むatomic resize/reflow
- fixed-page SoA scrollback、独立line/byte cap、O(1) page eviction、primary
  history/active gridを投影するbounded viewportとstable logical anchor
- end-exclusive cell/word/logical-line selection、soft/hard wrap準拠のbounded
  text extraction、cell-aligned exact scalarのforward/backward bounded search
- 最大96 byteのreply encoderと、DA/DA2、DSR/CPR、DECRQM、DECRQSS SGR、
  XTVERSION、XTWINOPS 14/16/18、light/dark、in-band size、
  OSC palette/default color queryのterminal-core dispatch
- ncurses 6.6で固定生成・能力監査した`xterm-256color` terminfoを両runtime bundleへ同梱し、
  起動時にheader/name/layoutを検証してlocal `TERMINFO`へ接続する環境contract。欠落・破損時と
  SSHのremote PTYでは私有pathを送らず標準`TERM=xterm-256color`へfallback。G0/G1、SO/SI、
  DEC Special Graphicsをscreen stateとして処理し、XTGETTCAPには監査済みcapability方針でbounded応答
- session-owned screen set/parserへのraw PTY byte feed、従来text projectionとの
  single-subscription共存、generated replyのnative bounded write queue接続
- historyとprimary/alternate grid、Unicode resource、mode/cursor/character-set/parser countを
  網羅し、行・cell・resource・入出力上限を持つversion 4 terminal-state snapshot、
  fresh independent ownerへだけ構築してcanonicalなformat→restore→format完全一致を要求する
  strict test/debug restore oracle、最初の相違位置・escaped contextを返すbounded comparison diagnostics
- 厳密検証するbyte-exact product parser corpus manifest、shell/less/top/vimの
  review済み記録snapshotをwhole・全single split・bytewiseで再生する非書換えharness、
  固定seedのproperty testと境界別fuzz seed/mutation corpus
- Phase 9の全modern protocolを対象に、8 anchor、64 bit mutation、64 generated
  programをwhole/generated-chunk/bytewise/repeat/recoveryで比較する固定seed property
  suite（680 execution、731,150 parse byte）。OSC 52とdesktop signalの8 session authority、
  image worker/storeを合計5,120 operationでstressし、Kitty controller FIFOの圧力も加えて、
  fake native callの無権限実行0、queue/session/retained byte capとdispose後0を通常`make test`で検証する
- DEC文字セット、XTGETTCAP、OSC metadata/color/clipboard、focus/mouse、DECRQSS、
  XTVERSION/XTWINOPSの9修正familyを390 input byte・417 chunk planで固定するversion 1
  compatibility regression corpus。inventory、differential、実アプリの所有者付きgap、
  parser traceを一つの決定論的coverage reportで照合し、通常`make test`でfreshnessを検証
- Phase 0 mixed workloadを使うcapture-disabled product parserのRelease AOT
  100 MiB/s regression gate（同一seedのexact counter/integrity検証付き）
- 1x/2xのcanonical sRGB decode→linear-light straight-alpha合成→encode、固定layer順、
  solid/mask/color bitmapを扱うDart-only reference rendererと、checksum付きversion 1
  golden image oracle。明示されたDisplay P3入力はreference/atlas境界で一度だけclipped
  sRGBへ変換し、real MetalはsRGB atlas/targetと1 byte toleranceで同じ結果を検証
- generation-owned CoreText font catalog、actual/synthetic 4-style policy、
  CJK/color emoji fallback、bounded text resolveとcell/decorations metrics、
  versioned whole-run shaping、UTF-16 cluster mapping、Dart-owned byte/entry LRU、
  batched 1x/2x CoreText alpha8/straight-RGBA8 glyph raster boundary。表示中の
  cursor scalar cellはcompatible runの前後で分離し、ligatureに隠れない一方、
  wide cellとinterned graphemeはatomicに維持
- alpha8/straight-RGBA8を分離したbounded glyph atlas、決定論的配置、page/byte/
  entry上限、unpinned LRU、submission token pin、resource generation検証、
  矩形差分uploadと実CoreText文字コーパスの1x/2x pixel golden
- Box Drawing 128、Block Elements 32、Braille 256、明示したPowerline 18の
  合計434 scalarを、各grid edgeから独立に丸めたdevice-pixel cellへ描く決定論的
  alpha raster。scale／幅／高さ／線幅を含む専用atlas keyで拡大を避け、色と既存layer
  順を保持する。multi-scalar grapheme、wide cell、U+E0C0を含む隣接PUAとその他の
  Nerd FontはCoreText fallbackのまま。1x/2x DTGI、CPU oracle／real Metal比較、
  Developer JIT／Release AOTの実PTY製品受け入れは
  [terminal rendering reference](docs/reference/terminal-rendering.md)に固定
- build時にコンパイルしたMetal shader、canonical sRGB／linear-light source-over、
  全terminal layer用packed draw list、
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
- renderer ABI v11のtyped device/shader/command failure state、bounded drawable
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
  selection、独立cursor、logical cell geometry、rendererと同じeffective padding origin、
  first-responder focusを、完全コピー済みの`TerminalMetalView` accessibility text areaから
  同期的なDart再入なしでVoiceOverへ公開する。padding内／grid外pointは文字へclampせず、
  range/cursor frameはresize時のpadding縮退・復元にも追従する。外部VoiceOver、
  Accessibility Inspector、Full Keyboard Accessの確認手順は
  [manual checklist](docs/phase10/voiceover-accessibility-manual-checklist.md)を参照
- macOSのReduce Motion、Increase Contrast、Differentiate Without Colorを起動時と
  live変更時に受け取り、Quick Terminalのtransitionとvisual bell、Settings、cursor、
  selection、link underlineへ投影する。設定値やfont/cell寸法、PTY/sessionは変えず、
  同一値の通知もownerを再生成しない。Application/File/Edit/Shell/View/Window menu、
  context menu、Command Palette、Settings、confirmation/status、Finder Services、
  App Intents/Shortcutsはtyped catalogからEnglish/Japaneseを選び、未対応localeはEnglishへ
  fallbackする。RTLはapplication UIの構成だけを反転し、terminal cell、PTY文字列、
  path、shell出力は並べ替えない。外部macOS設定での実機確認は
  [display/localization checklist](docs/phase10/accessibility-display-localization-manual-checklist.md)を参照

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
font-variation-regular = wght=500
font-variation-bold = wght=700
font-codepoint-override = U+2500..U+257F=Menlo
palette-background = #101418
background-opacity = 0.9
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
quick-terminal-shortcut = control+option+command+f18
quick-terminal-screen = main
quick-terminal-animation-duration = 0.2
quick-terminal-autohide = true
macos-applescript = true
keybind = control+d=unbind
keybind = shift+control+k=pane.focus-next
```

現在のschemaは`working-directory`、新しいsession用の絶対`shell` executableと
`shell-integration = detect | none | zsh | bash | fish | nushell`に加え、`theme`、
default foreground/background/cursor、全terminal surfaceで共有する`background-opacity`、
ANSI palette 0–15、font family/size/synthetic style、style別のOpenType variation axis、
Unicode scalar rangeごとの明示的なfont family、初期window sizeとpadding、macOS Option keyの
`escape`/`text`動作、scrollback line/byte cap、初期cursor shape/blinkを公開します。同じ名前を
`--font-size=15`のようにcommand lineでも指定できます。解決済み設定は新しいwindow/tab/splitの
各paneへ適用され、既存paneのmutable resourceを共有しません。`keybind`は複数回指定でき、
exact physical key chordをpane actionまたはapplication actionへ割り当てます。構文、全key名、
action ID、`unbind`/`passthrough`、既定binding、予約済みnative shortcutは
[Keybindings and actions](docs/reference/keybindings-and-actions.md)を参照してください。

`macos-option-key = escape`（既定）では、OptionをMeta/Escape prefixとして扱い、
Option+Left／Rightはshellの前／次の単語へ移動します。OptionをmacOSの文字入力へ使う場合は
`macos-option-key = text`を選べます。

`background-opacity` は0（完全透過）から1（不透明）で指定し、既定値は1です。
reload時は既存の全window/tab/split paneへ同時に反映され、その後に作るterminalや
Quick Terminalも同じ値を使います。透過するのはterminalの既定backgroundのみで、
文字、cursor、selection、明示ANSI cell background、画像、Settings、Command Paletteには
透過度を適用しません。
`font-variation-{regular,bold,italic,bold-italic}`は4-byte OpenType tagごとに最大16件、
`font-codepoint-override`はinclusive Unicode scalar rangeと明示familyを最大256件受理します。
同じstyle/tagは後の宣言が有効になり、重なるscalar rangeも後の宣言が優先されます。
利用不能なaxis/family/glyphは通常のCoreText fallbackへ戻り、新しいpaneごとの不変font catalogに
適用結果を記録します。既存paneが元のcatalogを保持し、reload後の新しいwindow/tab/splitだけが
新しいaxis/overrideを受け取る境界と、適用／利用不能診断をDeveloper JITとRelease AOTで検証します。
`quick-terminal-shortcut`の既定値は`none`で、設定した場合だけsystem-wide shortcutを
exclusiveに登録します。`quick-terminal-screen`は`main | mouse | macos-menu-bar`、animationは
0から5秒で0なら即時表示、autohideは既定で有効です。shortcutをlive reloadした際に新しい
登録が競合または失敗した場合は、動作中の旧shortcutを維持し、Settingsのstatusへ理由を表示します。
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
`background-opacity`、`macos-option-key`、`keybind`、4個の`quick-terminal-*`、2個の`macos-secure-input-*`、
`macos-applescript`はlive適用され、
それ以外の現在のoptionは新しく作るsession/resource/windowだけに適用されます。既存palette/OSC state、cursor、
scrollback、font、padding、window frameは書き換えません。自動file watchとSIGHUP reloadは
現在の対象外です。

Applicationメニューの`Settings…`（Command-,）、command palette、または非予約chordへ設定した
`application.open-settings` actionから、root設定ファイルを編集するnative modal editorを開けます。
最初のkey入力を待たず、新規・空・疎なファイルでも全55 optionを同じdocument内へ補完して表示し、
右のcontext panelはcaret位置の
current/draft value、構文、説明と、保存後に既存terminalへ即時反映されるか新規terminalから使われるかを
表示します。line/source行や別のvalue入力欄は持たず、panelを閉じても右端の細いrailが残ります。
コメントアウトされたoptionは行全体をdisabled色で表示し、現在のcaret行はNORMAL、`/`検索、INSERTの
すべてで淡い全幅背景として追従します。NORMALと`/`検索で選択行が表示範囲を越えた場合は、同じnative
editorのviewportも自動で追従します。行背景とviewport移動はsyntax色や診断下線を変更しません。

起動時は`NORMAL`で、`i`または`a`が同じsyntax-highlight済みsurfaceを`INSERT`へ切り替え、
`Esc`が`NORMAL`へ戻します。両modeのdocument、font、色、syntax styleは同一です。`/`だけが
明示的に`SEARCH`を開始し、`↑`/`↓`で候補を移動、`]`でcontext panelを開閉します。
Command-Sはroot全体を既存schemaで事前検証します。invalid draftはeditorとlast-known-good設定を保持し、
該当箇所を下線表示してファイルもreload controllerも変更しません。valid draftだけを同一directoryで
atomic保存し、上記のshared reload actionを1回実行します。NORMALの`Esc`またはwindow closeは全native
editor ownerを解放してterminalのfirst responderを復元します。canonical provenance、include/CLI priority、
全diagnosticの機械可読表示には引き続き`--show-config`を使用できます。
Settingsのruntime statusにはQuick Terminal shortcutに加え、Secure Keyboard Entryの
automatic/manual/disabled/failed mode、owned/yielded/released、自動取得・indicator設定、
font axis/overrideの適用・利用不能・fallback・missing件数、および最大4個の長さを制限した
安全なPostScript face名を表示します。terminal本文や設定したcodepoint値は診断へ含めません。
AppleScriptの現在値とlive policyは同じ53-option document/context detailに表示されます。
無効化するとscriptable collectionを空にして新規commandを拒否し、再有効化すると生存中の
standard hierarchyを同じIDで再公開します。設定変更はmacOS Automation/TCC権限を付与、取消、resetしません。

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

OSC 52 suiteは通常hierarchyと実zsh PTYを使い、`ask` writeをnative Edit menuで
allow、`ask` readをcommand paletteでallow、`ask` clearをmenuでdenyします。
application-local memory adapterだけを注入するため、検証中に利用者のpasteboardを
読み書きしません。exact reply、承認前のzero authority、transient confirmation window、
first responder、PTY/worker/native handleの回収を両runtimeで確認します。

```shell
make RUNTIME_ARCH=arm64 runtime-osc52-integration
```

設定値が実際の通常製品へ反映されることは、実設定ファイルから4 paneを生成し、表示色、
font、window/padding、cursor、Option入力、scrollback上限、pane/application keybind、
unbind、Command passthrough、invalid reserved shortcutからの復旧、invalid/corrected reload、
利用不能なfontの`system`復旧と修正前reload/save拒否、live/new-session policy、native menu優先、
独立resourceに加え、worker/AppKit所有を作らない
`--show-config`、Settingsのnative menu/command palette/shared action、全option document、明示検索、
同一syntax表示のNORMAL/INSERT、invalid saveの非永続化、valid atomic saveからの1回のreload、
commented optionの全行disabled表示、modeをまたぐ全幅current-line表示、context diagnostic、
key入力前のinitial document表示、NORMAL/検索selectionのviewport追従、focus/handle cleanupを
Developer JITとRelease AOTで確認します。
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

利用者が明示的に保存するTerminal Inspectorのcontent-freeな診断JSONは、以下の起動ごとの
local metadataとは別物です。Inspector/exportの操作、固定schema、除外対象、atomic保存は
[Terminal inspector and diagnostics reference](docs/reference/terminal-diagnostics.md)を参照してください。

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
起動時に空の状態から再作成されます。生のcrash reportとhang sampleは、このmetadataとは
分離された明示操作と警告付きSave panelからだけ保存できます。通常diagnosticsには固定状態と
件数だけが入り、生のartifact、path、PID、timestamp、stack、raw errorは入りません。

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

host-architecture の Release bundle を個別に build、監査、起動する場合は次のとおりです。

```shell
make RUNTIME_ARCH=arm64 release-aot-build
make RUNTIME_ARCH=arm64 release-aot-audit
make RUNTIME_ARCH=arm64 release-aot-run
```

arm64/x86_64 thin と Universal の配布構造をまとめて生成・監査・通常起動する場合は
次を使用します。x86_64 smoke は M1 上で Rosetta と明示されます。

```shell
make release-aot-thin-builds
make release-aot-universal-build
make release-aot-distribution-audit
make release-aot-distribution-integration
# source gate、全build、全audit、全smokeを一括実行
make release-aot-distribution-verify
```

Release bundle は AppKit main thread 上の単一 stock Engine root、main AOT snapshot、
汎用 native worker host、製品 manifest が指定した外部 worker AOT payload を含みます。
worker は `Contents/Helpers/dart_terminal_runtime_worker` から別 PID で起動され、
`Contents/Resources/DartHelpers/dart_terminal_runtime_worker.aot` を読み込みます。thin では
全コードが指定した1 slice、Universal では全9コードイメージが正確に arm64/x86_64 の
2 slice です。配布先の Dart SDK や `lipo` には依存しません。

通常 smoke 以外の failure/replacement/shutdown、bounded traffic、resource stress、
shutdown fault injection を host architecture で個別に再検証する場合:

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

x86_64 cross-build、Rosetta 実行、Universal 構造監査と M1-native 実行は通常の配布
受け入れに含まれます。残る Intel-native handoff は、ここで生成・監査した immutable
x86_64 thin／Universal 成果物を Intel Mac へ no-rebuild で渡す主要ゴール後の確認です。
この follow-up の未実施は M1 baseline の完了を阻害しません。

### Developer ID 配布 preflight

Release AOT 配布は、空の [`resources/DartTerminal.entitlements`](resources/DartTerminal.entitlements)
を唯一の entitlement 入力とします。JIT、debug、unsigned executable memory、library validation
bypass などの追加権限はありません。credential を使わずに fresh Universal bundle、製品
contract、全9 code image、全resource evidence、entitlement policy を検証する場合:

```shell
make release-distribution-preflight
```

実配布 gate は、Keychain に有効な Developer ID Application identity と `notarytool` profile
が存在する環境で次を実行します。password や API private key を Make 変数へ渡さず、profile
名だけを指定します。現在は実credentialとApple公証の正の受け入れを主要ゴール後の
低優先follow-upへ移しており、上記preflightの成功を署名済み・公証済み配布物とは扱いません。

```shell
make release-distribution-verify \
  DEVELOPER_ID_APPLICATION="Developer ID Application: Example Company (ABCDE12345)" \
  DEVELOPER_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=example-notary-profile
```

この gate は監査済み ad-hoc Universal を変更せず、別の staging copy を全nested codeから
outer appの順にhardened runtime・secure timestamp付きで署名します。Apple公証のAccepted
statusとissue 0のlogを確認し、appへticketをstaple・検証してGatekeeper評価を通した後だけ
最終ZIPを作成します。出力directoryにはstapled `.app`、そのZIP、source／entitlement／
archive／全code hashを束縛するmanifestだけがatomicに公開されます。失敗時は既存の
last-good配布物を保持します。

### ソフトウェアアップデート

ApplicationメニューとCommand Paletteの`Check for Updates…`は同じ共有actionを使い、
read-onlyのSoftware Update画面へ固定status、認証済みversion/build、boundedな平文
release notesだけを表示します。Returnで再確認または検証済みcandidateの準備、Escで
cancel／close／terminal focus復元を行い、操作やfeed内容をPTYへ書きません。

checked-in buildにはproduction endpoint、private key、fixture trust rootを含めません。
release buildがpinned public keyを使うproduct update serviceを明示注入しない限り、actionは
`not configured`のままnetwork／filesystemへ触れません。signed feed、candidate監査、
same-volume atomic replacement、health acknowledgement、last-good rollback、privacy境界、
release運用の詳細は[software update reference](docs/reference/terminal-updates.md)を参照してください。
実Developer IDとApple公証済みcandidateによる正の受け入れは低優先follow-upであり、
credential-independent gateの成功をpublic release readinessとは扱いません。

## ローカルチェック

```shell
make product-parser-corpus
make product-parser-properties
make phase9-protocol-properties
make phase9-security-stress
make product-sanitizer-fuzz-fault-gate
make product-parser-benchmark
make product-performance-regression-gate
make RUNTIME_ARCH=arm64 ghostty-p0-p1-gap-closure
make RUNTIME_ARCH=arm64 release-candidate-daily-use-gate
make runtime-source-check
make terminal-localization-check
make test
make RUNTIME_ARCH=arm64 runtime-bundle-audit
make RUNTIME_ARCH=arm64 runtime-integration
make RUNTIME_ARCH=arm64 runtime-terminal-display-integration
make RUNTIME_ARCH=arm64 runtime-native-hierarchy-integration
make RUNTIME_ARCH=arm64 runtime-bounded-reliability-integration
make RUNTIME_ARCH=arm64 runtime-user-actions-integration
make RUNTIME_ARCH=arm64 runtime-native-content-integration
make RUNTIME_ARCH=arm64 runtime-applescript-integration
make RUNTIME_ARCH=arm64 runtime-system-automation-integration
make RUNTIME_ARCH=arm64 runtime-configuration-integration
make RUNTIME_ARCH=arm64 runtime-theme-integration
make RUNTIME_ARCH=arm64 runtime-osc52-integration
make RUNTIME_ARCH=arm64 runtime-restoration-integration
```

`make product-sanitizer-fuzz-fault-gate` は通常リポジトリgate、固定seedの12件の
review済みfuzz seed／192 mutation／1,296 execution、4つのproduct-owned native
ownerを通る9 artifactのASan/UBSan capability、PTY allocationとDart parser／Kitty
queue／Metal ownerのbounded fault recovery、Developer JIT／Release AOTのshutdown
faultを直列に検証します。sanitizer artifactとtest-only fault seamは配布物に含めず、
隣接する汎用`dart_appkit`へ製品固有コードを追加しません。Apple公証と実時間
24/72時間の検証は、このbounded correctness gateとは別の低優先follow-upです。

`make product-performance-regression-gate` は Release AOT の実製品 parser、damage、
key→PTY、通常windowのstartup/input/visible frame、短時間RSS/CPU、100 MiBのpane間
fairnessを再計測し、固定M1 baselineとpinned Ghostty証跡へ同一実行内で照合します。
入力結果のSHA-256だけをaggregate証跡へ束縛し、terminal内容、command、path、PID、
timestamp、raw sampleは保持しません。比較対象の再captureは別の明示的なレビュー工程です。

`make RUNTIME_ARCH=arm64 ghostty-p0-p1-gap-closure` は、102件のpinned P0/P1 matrix
rowと全checked-in evidenceのfreshness、通常のnative/Dart/format/analyze gateを確認した後、
同じ実AppKit／zsh PTY／Metal display受け入れをDeveloper JITとRelease AOTで直列実行します。
現在は97件が直接accepted、2件が非破壊のdocumented difference、3件が明示承認済みの
external follow-upで、actionable P0/P1とsilent misbehaviorは0です。後者5件を製品動作の
成功と読み替えず、実Developer ID／Apple公証、Intel-host、物理・実時間soakはこのgateの
対象外です。

`make RUNTIME_ARCH=arm64 release-candidate-daily-use-gate` は、versioned matrixの
8 program（7 clean agreementとmoshの非破壊な既知差分1件）と8 workflow family／31 gateを
fail-closedに確認し、Universal distribution、Release AOT performance、sanitizer／fuzz／fault、
pinned parity、および通常製品のDeveloper JIT／Release AOT受け入れを共有依存1回の直列graphで
集約します。成功時点のblocker／crash／data-loss／security bug、actionable P0/P1、silent
misbehaviorは全て0です。これはM1上のbounded automationとchecked-in program replayによる
release-candidate判断であり、外部programのfresh launch、30日の日常利用、物理sleep／display
変更／OS memory pressure、実Developer ID／Apple公証、Intel-native実行を合格済みとは主張しません。

`make RUNTIME_ARCH=arm64 runtime-bounded-reliability-integration` は通常製品の同一
window/pane/session/Metal surfaceで、sleep、重複screen-set通知、交互のwarning/critical
memory pressure、wake、normal復旧を8回繰り返します。sleep中のframe/deadline停止、wake後の
newest-only redraw、canonical screen/scrollback/preeditとowner identityの保持、atlas capと
GPU pinのretire、PTY/FD/root isolate/worker/text-input/native handle基準線、および終了後0を
Developer JIT/Release AOTで検証します。typed eventによるbounded代替であり、物理的なsleep、
display着脱、OS pressure、または24/72時間経過を実行したという証跡ではありません。

`make RUNTIME_ARCH=arm64 runtime-verify` は source check、両 mode の bundle audit、
smoke、real-PTY live Metal display、native tab/4-pane hierarchy、通常製品のuser action、
AppleScript dictionary/object lifecycle、
App Intents metadata/shared actionsとnotification permission/response lifecycle、
effective-config early exit/Settings/configuration reload、light/dark/system appearance、
shell/semantic、desktop notification/progress、OSC 52 confirmation、
fullscreen/migration/restoration/reopen、clipboard、lifecycle、bounded traffic、
bounded system reliability、resource stress、shutdown fault suiteをまとめて実行します。display suiteは
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
経路を使い、native menuのCheck for Updates/Split Right/New Tab/New Window/Close/Quitと、
command paletteのSplit Downを操作します。認証済み平文release notes、candidate準備、
update操作のPTY write 0とfocus復元、2 window/3 tab/5 paneの生成、各paneへのraw key/IME分離、
1 paneを閉じた後の4-pane階層、5つのPTY世代と全Metal/text-input/native handleの回収を
Developer JIT/Release AOTで要求します。
theme suiteはv7 appearance/geometry eventとv14 accessibility preference eventを通常製品へ
注入し、初期light、live dark/light、custom ANSI overlay、system/fixed pane、reloadの
new-session境界を実Metal frameで検査します。Japanese catalogがmenu、Command Palette、
Settings、statusへ届くことに加え、Reduce Motion、Increase Contrast、Differentiate Without
Colorが既存Quick Terminal、Settings、全Metal surfaceへ届き、同一通知を重複適用せず
owner identityと設定値を維持することも検査します。configuration suiteは`C` localeの
English UIを検査し、bundle auditはEnglish/Japanese各4 family、合計8 resourceがmanifestと
bundleでbyte一致することを要求します。
実zshは996/997、XTWINOPS 16、mode 2048の即時/resize応答をPTYからexact byteで読み、2031の
disable/RIS、2048 disableとsession teardown後のsubscription解除も検査します。同じpaneの
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
汎用 builder は host architecture に加え、Release AOT の明示的な arm64/x86_64 thin
target と、監査済み thin pair からの atomic Universal assembly を提供します。
Intel-native の no-rebuild 実機受け入れだけが ROADMAP 上の低優先 follow-up です。

Phase 0 の debug/JIT、release-AOT、worker-isolate、PTY、Metal、CoreText の native
実装は歴史的な feasibility evidence として `docs/phase0` から参照します。applicationの
`bin/`／`lib/` とruntime host buildは直接FFIを持たず、native／FFI境界は製品所有の
`packages/dart_process_resource_macos`、
`packages/dart_pty_macos`、`packages/dart_terminal_renderer_macos`、
`packages/dart_terminal_applescript_macos`、`packages/dart_terminal_app_intents_macos`
だけに閉じています。process resource packageは内容を保持せず現在processのCPU時間、RSS、
open FD件数だけを返します。外部application比較で使うreview済みncurses fixture、macOS
activation helper、Ghostty performance captureはtest/tool専用で、製品bundleへcompile/linkしません。
parser/benchmarkなどの Dart-only harness は後続実装の比較資料として残しています。

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
packages/dart_process_resource_macos/ current-process CPU/RSS/FDの汎用FFI境界
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
初回描画からnative windowのcontent layout寸法をMetal viewportへ使うため、title/tab barを
含むouter frameとの差でdrawableが拡縮されず、scroll後もglyph pixelを等倍表示します。

`TerminalPaneOwner`がpaneを、`TerminalPane`がsession generationを、
`TerminalSession`が公開`PtyProcess`を所有します。実backendとdeterministic fakeは
同じ境界で交換できます。`TerminalBuffer`はcontent-free lifecycle fixtureの補助として
のみ残り、表示行やpixelを決めません。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
