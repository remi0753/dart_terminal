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
