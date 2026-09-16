# Phase 7 — Process Inspectorの入力保護と情報表示の分離

## 目的・背景

利用者本人向けのread-only process情報表示を、秘密入力の保護と独立させる。
現行のECHO-off／manual Secure Keyboard Entryによる一律非表示はNode REPLなどでも
発生する。取得対象はOSのprocess metadataであり、stdinや入力中のpasswordではない。
ECHO状態はargvに秘密が含まれるかの判定には使えない。

## 範囲

- ECHO-offとmanual／automatic Secure Keyboard Entry中もProcess Inspectorを表示する。
- 引数の表示を既定で有効にし、入力保護とは独立した利用者操作で切り替える。
- Secure Keyboard Entry、Navigatorのpath insertion保護、focus／session／PGID／visibility失効、
  bounded sampling、diagnostics／export／restorationへの非記録を維持する。
- native UI、English／Japanese、unit／privacy／両runtime受け入れ、referenceを更新する。

## 対象外

- stdin、password、environment、terminal outputの取得・記録。
- remote SSH観測、process操作、新たなキーボード監視。
- argv中の秘密の自動推測、既存Secure Keyboard Entry policyの変更。

## 依存関係・リスク

`TerminalContextDockPrivacyPolicy`、product bootstrap、process coordinator、native presenter、
action/menu/palette、既存process metadata capabilityを使う。表示と入力保護を共有したまま
緩和するとpath insertionまで許可してしまうため、process専用判定を分離する。
画面共有等ではargvだけでなくpathにも露出リスクがあり、Dock自体の非表示操作は維持する。

## 実施順・個別完了条件

1. process観測の入力保護判定を分離する。ECHO-off／manual secureでもmetadataを表示し、
   Navigator/path insertionとSecure Keyboard Entryの既存保護が維持されることをunit／
   privacy gateと両runtimeの実PTY／native documentで確認してcommitする。
2. 入力保護から独立したargv表示切替を実装する。menu／paletteからkeyboard-onlyで操作でき、
   非表示時にnative visual／accessibility documentへargvを出さず、process名／path／PID／elapsedは
   維持する。focus／runtime regression、localization、reference、全体検証後にcommitする。

## 検証方針

対象unit test、format／analyze、diagnostics privacy audit、arm64 Developer JIT／Release AOT
native-content integrationを実行する。ECHO-off fixtureは既存のbounded sh commandを使い、
利用者のscriptを実行しない。視覚／外部VoiceOverの未実施事項はmanual checklistで区別する。

## 調査・判断記録

### 2026-09-16 — 着手

- branchは`codex/context-file-navigator-roadmap`。tracked差分なし。untracked `cat`は利用者所有として
  参照・変更・stageしない。
- README／FEATURE_MATRIXは未改変runtime、Dart-only product logic、native capability境界と
  local-only process metadata表示を契約としている。ROADMAP上の既存主要機能は完了済みで、
  新規作業をProcess Inspector直下、低優先external follow-upより前へ登録する。
- `lib/src/terminal_context_dock_path_handoff.dart`の`canObserve`がfilesystem観測とprocess観測の両方に
  接続されている。manual secureとECHO-off foregroundを拒否し、idle shellだけ例外にしている。
- `lib/src/terminal_application.dart`のproduct native-content fixtureがECHO-off時の`Protected input`と
  argv破棄をassertする。この期待値を新方針へ置き換え、filesystem停止／terminal input ownerは維持する。
- 既存のSecure Keyboard Entry取得・indicator・balanced release実装は変更しない。
- argv表示切替に新しい既定chordは割り当てず、View menu／command paletteのshared actionと
  任意keybindで提供する。既存shortcutとの競合を避ける。

### 2026-09-16 — process専用観測authority

- `canObserveProcess`をSecure Keyboard Entry状態を受け取らないlive identity判定として追加し、
  productのprocess resolverだけを接続した。filesystemとpath handoffは従来の`canObserve`を維持する。
- coordinator unit fixtureはECHO-offを常用するように変更し、表示、refresh、PGID／focus失効を
  実入力保護状態から独立したexplicit vetoでも検証する。
- native-content fixtureはECHO-off foreground commandを表示し、その途中でmanual secureを取得して
  process情報と`ownedEnabled`の両方を確認する。stdin内容は観測しない。最大待機時間は従来どおり。
- 初回format／analyzeはSDK analyticsがsandbox外のtelemetry logへアクセスして終了code 1になった。
  formatterの変更とanalyzeの`No issues found`は得られたが、成功扱いにはせず通常の権限で再実行する。
  対象unitとprivacy auditは成功。runtime buildはSDK／native buildの通常権限で実行する。
- Developer JITの初回native-contentはmanual取得直後の即時`ownedEnabled` assertionで失敗した。
  native leaseの反映は非同期であり、既存Secure Keyboard Entry suiteもwait条件で確認している。
  fixtureをreconcile付きのbounded waitへ修正する。製品のlease／入力保護policyは変更しない。
- 2回目は旧fixtureの「Search actionがdisabled」という期待値で失敗した。Process Inspectorでは
  shortcutをbeep／PTY writeなしで消費するためactionはenabledだがNavigatorへfocusを移さない。
  新方針でこの経路がECHO-off中にも使われるため、実dispatch後のterminal ownership／write countで
  入力を奪わないことを検証する。directory snapshot停止条件は維持する。
- 通常権限での再検証: `dart format`は4 file／変更0、`dart test/terminal_context_dock_test.dart`、
  `dart test/terminal_secure_keyboard_entry_test.dart`はexit 0、`dart analyze`はissue 0。
  `dart tool/terminal_diagnostics_privacy_audit.dart`はschema 190／owner 11／top-level 11で成功した。
- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`は最終再実行でDeveloper JIT
  11,125 ms／Release AOT 9,845 ms、両方exit 0。ECHO-off表示、manual secure owned、Searchの
  zero-write消費、metadata／fixed details、pipeline、elapsed、終了後Directory復帰と4 session回収を確認した。
  Node自体を必須dependencyにはせず、同じECHO-off状態の実PTY fixtureで再現する。
- サブタスク1は完了。argvの独立切替は次の未完了項目として追跡する。外部VoiceOver／視覚確認は
  manual checklistへ残し、自動native document検証と区別する。

### 2026-09-16 — argv表示切替の着手・判断

- サブタスク1を`4e94c78`（`Separate process display from keyboard input protection`）でcommit済み。
- `view.toggle-process-arguments`をView menu／command paletteへ追加する。menuは「引数を表示」の
  checked stateで現在値を示す。既定chordなし、任意keybind可能、app lifetimeのbooleanとして保持し、
  window／pane移譲や新commandでも同じ値を使う。設定ファイル／restorationへは保存しない。
- 非表示時はnative visual／AX documentから引数と省略／truncation情報を除き、retained process snapshotの
  argvも直ちに空にする。native resolverは従来のbounded metadata取得を続けるが、非表示中に完了した結果の
  argvはproduct snapshotへ保持しない。stdinやenvironmentを新たに読むことはない。
- 再表示時は古いargvを復元せず、次の最大毎秒1回のfresh inventoryを待つ。その間は「引数を再取得中」と
  明示する。入力保護との独立性とsampling上限を両立させる。
- 最初のmulti-file patchは既存Japanese literalのcontext不一致でatomicに拒否された。差分が生じていない
  ことを確認し、実際のcatalog copyを参照して再適用した。
- 初回追加unitは存在しない`_Harness.close`を呼んでcompile失敗した。既存fixtureと同じ
  `harness.state.shutdown()`へ修正し、cleanup後のowner／operation上限検証は維持する。
- 追加unitの初回refresh期待値は250 ms pollingの位相を無視して1秒経過直後にrequestを参照し、
  RangeErrorになった。既存sampling policyは1秒以上経過した次のpollでrefreshするため、fixture時間を
  1,250 msへ進める。製品の最大取得頻度・poll間隔を変更してtestを通すことはしない。
- argv切替の対象unit（Context Dock、native hierarchy、action registry、localization、Secure Keyboard
  Entry）は最終再実行で全てexit 0。`dart analyze`はissue 0。native hierarchyはhidden／refreshingの
  raw payloadを意図的に保持したfixtureでもnative visual／AX documentへ引数が出ないことを検証する。
- `make keybind-action-reference phase7-appkit-acceptance release-candidate-daily-use-matrix`は前2項目を
  更新したが、daily-use生成はFEATURE_MATRIX由来のgap inventoryがstaleで停止した。依存元inventoryを
  先に再生成し、その後daily-useを生成する。既存の判定やgap件数を緩和することはしない。
- 初回`make test`は汎用PTYの既存`live Dart child cannot steal native PTY completion`で
  `firstWhere: No element`となり停止した。並行してruntime buildが走っていたが、原因を断定しない。
  runtime build終了後に全体gateを単独再実行し、再現性を確認する。既存testは変更・削除しない。
- 単独再実行では汎用PTYの同じtestはpassし、全native capability、keybind 44 actions、localization、
  privacy 190 keys、Phase 7 acceptance、compatibility regression 9 casesまで成功した。
  次のcompatibility coverage reportがsource hash更新によりstaleで停止したため、coverage → gap inventory →
  daily-useの順で再生成する。full gateの成功は最終再実行で確認する。
- argv切替を含む`make RUNTIME_ARCH=arm64 runtime-native-content-integration`はDeveloper JIT
  11,050 ms／Release AOT 9,834 ms、両方exit 0。実native View itemのchecked state、非表示時のargv空と
  native document除外、paletteで再表示してfresh argv復帰、terminal ownershipとPTY write 0を確認した。

### 2026-09-16 — 最終検証・完了

- `make test`最終単独再実行はexit 0、`dart_terminal tests passed`。formatは347 files／変更0、
  analyzeはissue 0。native capability、unit、privacy／localization／keybind reference／Phase 7／
  coverage／compatibility／distribution policy／daily-use freshnessをすべて通過した。
- gap inventoryは102 rows、accepted 97、documented differences 2、external follow-ups 3、
  actionable P0／P1とも0のまま。更新した生成物はsource／dependency hashのみで、受け入れ分類を緩和していない。
- 実装上の入力保護、filesystem／path insertion保護、focus／session／PGID／visibility失効、sampling上限、
  stdin／environment非観測とdiagnostics／export／restorationへのargv非記録は維持した。
- 全サブタスク完了。新しい既定shortcutは追加していない。外部VoiceOverの読み上げ品質と視覚評価は
  更新したmanual checklistに残る（native visual／AX documentとkeyboard-only経路は自動検証済み）。
- 初回の汎用PTY raceは後続の単独再実行2回では再現しなかった。既存testを変更せず、trial結果と
  原因未確定の注意点を上記に保存した。今回の機能のblockerは残っていない。
