# Context Dock command refresh stability

## 目的

Directory Navigatorの自動更新を、terminalが何もしていない時のsession変更ではなく、
ユーザーが送信したcommandの完了ごとに一回だけ実行する。再取得中も直前のdirectory／search
snapshotを表示し続け、結果が揃った時に差し替えることでContext Dockのちらつきをなくす。

## 背景

2026-09-19時点の自動更新は`TerminalPaneConfiguration.onChanged`から全session変更を
Directory controllerへ渡している。通知にはcommand outputだけでなくcursor blinkや画面状態の
変更も含まれるため、idle中にも75 ms debounce後のcwd解決とsnapshot再取得が起こり得る。
また、同じworking directoryをrefreshする際に現window stateをcancelして空の新generationへ
置き換えるため、root／child／Search結果が完成するまでlistが空またはloadingへ戻り、画面が
ちらつく。

## 範囲

- Return等でterminalへcommandを送信したpaneだけに、一回分のrefreshを予約する。
- 短いcommandはterminal activityの収束後、長い／silent commandはforeground processが
  shellへ戻った時に、同じ予約を一回だけ消費する。
- command予約のないcursor blink、描画、focus、process inventory同期ではfilesystemを再取得しない。
- 同一cwdのroot、展開済みsubtree、Searchを旧snapshot保持付きで再取得し、完了単位で差し替える。
- 手動`Refresh Directory Navigator`はcommand予約と独立して直ちに一回再取得する。

## 対象外

- filesystem watcherや一定間隔のpolling。
- remote／SSH filesystemの観測。
- command textの解析、shell種類ごとのprompt hook必須化、command内容の記録。
- Process Inspectorの表示遅延・inventory周期そのものの変更。

## 依存関係

- `TerminalPane`／`TerminalKeyEventRouter`のterminal input配送境界。
- `TerminalContextDockDirectoryController`のdebounce、generation、operation cancellation。
- `TerminalContextDockProcessController`のforegroundからshell-ownedへ戻るtransition通知。
- 既存native-content実PTY受け入れと手動refresh action。

## 実施順

1. command単位の一回更新
   - terminalへ改行を送る配送境界でpane単位のrefresh tokenをarmする。
   - tokenがあるpaneのterminal activityだけをdebounceし、観測可能になった一回のrefreshでconsumeする。
   - Process Inspector復帰経路も同じtokenを使い、先にconsume済みなら再更新しない。
2. snapshot保持付き差し替え
   - 同一cwd refresh開始時は既存root／child／Search snapshotを消さない。
   - stale operationだけをcancelし、新結果を受理した時に対応snapshotを置換する。
   - mode、query、展開、選択、input ownerを維持し、手動refreshも同じ描画契約を使う。
3. 製品受け入れ
   - idle通知ではlist回数とprojectionが変化しないこと、commandごとに一回だけ再取得することをunit testする。
   - 遅延するfake snapshotで再取得中も既存rowsが残ることを検証する。
   - 実PTYで短いcommandとsilent commandをDeveloper JIT／Release AOTの両方で確認する。

## 完了条件

- commandを送っていないidle中はDirectory Navigatorのsnapshot serviceを開始しない。
- 一つのcommandについてactivity経路とprocess復帰経路が重なっても自動refreshは一回だけである。
- command完了後のfile追加・削除・rename・metadata変更は従来どおり反映される。
- refresh開始から完了まで、直前の利用可能なtree／Search rowsを空にしない。
- manual refresh、展開状態、query、Terminal／Navigator input ownership、privacy境界を壊さない。

## 検証方針

- mutable／delayed fake snapshot serviceでcall count、token consume、旧rows保持、stale completion拒否を検証する。
- terminal input境界でReturnと通常文字入力を区別するtestを追加する。
- `dart analyze`、対象test、Developer JIT／Release AOT native-content、全`make test`、生成物freshnessを確認する。

## 判明事項・判断記録

- `TerminalPaneConfiguration.onChanged`はscreen、cursor、parser metadataなどcommand境界以外でも呼ばれる。
  現状の`changedPaneId`付き`DirectoryController.scheduleSynchronize`は、通知ごとにpaneを
  refresh対象へ追加するためidle更新の直接原因になる。
- 同一cwdのrefreshは既存`_TerminalContextDockDirectoryWindowState`をcancelしてから新stateを作る。
  `cancel()`がroot、child、Search snapshotを即座に消すため、非同期list中の空projectionがちらつきの
  直接原因になる。
- command文字列は解析せず、PTYへ配送する入力bytesにCRまたはLFが含まれた時だけtokenをarmする。
  通常文字入力、cursor key、mouse report、focus reportはarmしない。
- 長時間またはoutputのないcommandは、既存Process InspectorがDirectory Navigatorを再び観測可能にする
  transitionを完了signalとして再利用する。短時間commandのactivity debounceと同じtokenをconsumeして
  二重refreshを防ぐ。
- command tokenは`TerminalPane`のPTY入力境界でarmする。`submit()`、CR／LFを含む
  `sendInput`／text commit、およびbracketed pasteではない複数行pasteを対象とし、通常文字、cursor key、
  mouse／focus reportは対象にしない。application固有のkey code判定に依存しないため、configured keybindや
  keypad Returnにも同じ契約が適用される。
- tokenのない`TerminalPaneConfiguration.onChanged`はDirectory controllerで即時に捨てる。token付きの
  activityはtimerを毎回restartし、最後のoutput burstから75 ms後だけrefreshする。観測可能なrefreshを
  適用した時にtokenをconsumeし、Process Inspector復帰通知が後から届いても再取得しない。
- Navigator input中に自動更新を保留した場合はtokenも保持し、Terminalへ戻った時の一回のrefreshでconsumeする。
  pane close／Dock非表示ではtokenを破棄し、後の無関係な操作へ持ち越さない。
- 同一cwd refreshはlive window stateを空のstateへ置き換えず、専用のstaging batchへroot、全展開済み
  subtree、現在のSearchを読み込む。batch中のprogressは表示snapshotへ投影せず、全operation完了時に
  一つのgenerationとしてroot／child／Searchをまとめてcommitする。失敗したpathは直前のsnapshotを保持する。
- staging中は旧treeのstatus、rows、展開、metadata、Search結果、selectionをそのまま投影する。
  child operationも通常の`isLoadingChildren`へ含めないため、既存folder行へ一時的なLoading suffixを出さない。
  manual refreshも同じatomic batchを使う。
- terminal session変更時の一般的なappearance refreshは削除した。palette／theme／opacityの実変更には
  専用callbackとconfiguration reload経路が既にあるため、idle screen通知からpresentationを触る必要はない。
  hierarchy再投影でdocumentが同一の場合は、選択行highlightも現在値と比較し、同じnative highlightを
  再設定しない。これにより同一documentの再描画要求を出さない。
- command送信直後に575 msのfallbackを予約する。これは250 msのprocess poll二回分と通常の75 ms
  output debounceを合わせた値で、画面出力もforeground transitionも観測できない短いsilent commandを
  取りこぼさない。実際のoutput通知はこのtimerを通常debounceへ置き換え、foregroundを観測した場合は
  privacy projectionを維持したままprocess復帰後の一回へ引き継ぐ。
- foreground PGID中は既存のSEC-05境界どおりDirectory snapshotを破棄する。process復帰直後の一時的な
  idle sampleで一般reconcileが先にlistを開始しないよう、command-completion timerが所有するrefreshまで
  content-free projectionを維持する。tokenはrefresh開始時ではなくatomic commit時にconsumeするため、
  foreground検出でcancelされたbatchが後続refreshを失わせない。
- process復帰用timerを予約した後のcursor／screen通知は、そのtimerを延長しない。これにより継続する
  idle通知がcompletion refreshを飢餓させず、command一回につきatomic commitも一回に限定される。

## 検証記録

### command単位の一回更新

- `dart format`（変更したDart source／test）: source format完了。sandbox外のtelemetry session更新だけが
  拒否されたため、同じsourceを後続analyzeで確認した。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  command tokenなしのidle通知でgenerationとroot／child list回数が不変であること、二つのactivity通知を
  一回へまとめること、次commandは別の一回として更新すること、Navigator ownership中の保留を確認した。
- `TerminalKeyEventRouter`からReturnを送った時だけpane command observerが一回呼ばれ、通常入力では
  呼ばれない回帰testを全test entryへ追加した。全gateは最終subtaskで実行する。
- `git diff --check`: 成功。

### snapshot保持付き差し替え

- `dart format lib/src/terminal_application.dart lib/src/terminal_context_dock_directory.dart
  test/terminal_context_dock_test.dart`: 成功、変更なし。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  delayed root list中に旧generation／ready status／全rows／展開済みchildが残り、Loading suffixと
  projection notificationが発生しないこと、rootとchild完了後にnotification一回だけで新snapshotへ
  切り替わることを確認した。Searchのmanual refreshも旧resultを保持し、完了時に一回だけ差し替える。
- `make phase7-appkit-acceptance`: 成功。変更source／test hashを持つ受け入れ証跡を更新した。
- `make phase7-appkit-acceptance-check`: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/phase7_appkit_acceptance_test.dart`: 成功、
  `PHASE7_APPKIT_ACCEPTANCE_PASS criteria=5 source_refs=20 unit_tests=16 integration_tests=5 ui_assertions=11`。
- `git diff --check`: 成功。

### 製品受け入れ

- `CI=true DART_SUPPRESS_ANALYTICS=true dart format ...`: 成功、変更なし。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。tokenなしのidle通知では
  generation／list回数／commit countが不変、重複activityはatomic commit一回、遅延list中は旧tree／Searchを
  維持、画面出力のないcommandも575 ms fallbackで一回更新することを確認した。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 成功、
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... elapsed_ms=16018`。idle安定、短いcommand、silent command、
  manual refreshの各commit数と非loading projectionを実PTYで受け入れた。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功、
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... elapsed_ms=15034`。Developer JITと同じ条件を受け入れた。
- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`: すべて成功し、変更source hashを
  持つ生成証跡を更新した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功、`dart_terminal tests passed`。
- `git diff --check`: 成功。

### 失敗した試行と切り分け

- process実行中も旧Directory snapshotを保持する案は、foreground PGID変更時にretained snapshotを破棄する
  SEC-05 privacy契約に反するため不採用とした。process中はcontent-freeとし、復帰後だけ新snapshotを公開する。
- process復帰後325 msで更新する試行は、次のpollで再びforegroundと判定されるtransitionを吸収できなかった。
  二回のprocess pollとoutput debounceを待つ575 msへ変更した。
- 575 ms timerを全screen通知でrestartする試行は、Release AOTで継続通知によりrefreshが実行されない状態に
  なった。process-completion timerの所有元を記録し、一般通知では延長しないようにした。
- 最終Developer JITの初回は既存Process Inspector fixtureがnative window focusを失い、argv document待機で
  非決定的に失敗した。Directory refresh判定へ到達する前の失敗で、同一binaryの再実行は上記のとおり成功した。
- Release AOTの途中試行ではECHO-off fixture終了直後にNavigator action availabilityを即時評価して失敗した。
  process completion settling後にactionが復帰することを明示的に待つ受け入れへ修正し、その後のJIT／AOTと
  全gateが成功した。
