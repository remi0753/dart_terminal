# CM-07 unified window interaction authority

日付: 2026-09-21
状態: 完了

## 目的

Native windowごとのterminal、Context Dock、system surface、将来のNote rail/editorの入力所有権を、一つの
generation-bound `TerminalWindowInteractionAuthority`へ統合する。Owner transferを
request→native first-responder acquisition→generation revalidation→confirmに固定し、stale event、hierarchy mutation中のevent、
owner終了eventをterminalへreplayしない。

## 背景

- 現在の`TerminalContextDockState`はwindowごとの`TerminalContextDockInputOwner` booleanとstate generationを持ち、native presenterが
  focus後に`confirmNavigatorInput`する。これは正しいprecedentだが、Note rail/editorとsystem surfaceが別々のbooleanを追加すると
  exactly-one ownerを保証できない。
- Command Palette、Settings、close/paste/OSC 52等のsystem surfaceは各presenter/action coordinatorが個別にterminal responder復帰を
  管理している。既存observable behaviorを維持しつつ、logical ownerだけを共通authorityへ集約する必要がある。
- CM-08/09まではNote native surface/editorが存在しない。CM-07ではowner identity、routing、stale rejectionをtest doubleで先に固定する。

## 範囲

- Windowごとのterminal、Context Dock、Note rail、Note editor、system surface owner identityとexactly-one snapshot。
- Single-flight transfer request、native focus後confirm、cancel、stale generation/hierarchy rejection、terminal fallback。
- Context Dockの分散input owner除去と既存query/navigation保持。
- Raw key/IME/menu/clipboard/Services/drop/mouse/scroll/accessibility/automationのowner別routing decision。
- Note-consumed pointer gestureのgeneration-bound identityと、close後drag/up/momentumを含むno replay。
- Terminal responder復帰、DEC 1004 delta 0、Quick Terminal、Secure Input、close/reopenをDeveloper JIT/Release AOTで確認する。

## 対象外

- Native Note surface、card、editor、Note本文、store mutation、projection acknowledgement（CM-08〜CM-11）。
- 新しいuser-facing action、menu、shortcut。
- `dart_appkit`へDart Terminal固有owner、Note identity、pane lifecycleを追加すること。汎用library変更は不要と見込む。
- Owner stack、last-write-wins、event queue/replay、checkpoint owner。

## 依存関係

- CM-06 launch-fixed Note composition、既存`TerminalApplicationState`、`TerminalWindowEventCoordinator`。
- `TerminalContextDockState`/native presenter、terminal text/key/mouse/scroll/external-content routing、system presenters。
- Gate 5 owner/input matrix、Gate 7 CM-07成果物と両runtime acceptance。

## サブタスクと順序

1. **Generation-bound pure authorityとfuture Note owner contract**
   - Bounded immutable owner/request/snapshotとwindow topology同期を実装する。
   - Exactly-one、request/confirm/cancel、single pending、stale hierarchy、Note/system priority、terminal fallbackをpure testで固定する。
   - 完了条件: authority unit/property sequenceがpassし、Noteはtest double identityだけ、`dart_appkit`変更0。
2. **Context Dock、system surface、input family routing統合**
   - Context Dockのowner booleanをauthority projectionへ置換し、query/navigation stateとnative focus confirmationを維持する。
   - System surface projectionと全input familyのfail-closed decision、consumed gesture identity/no replayを接続する。
   - 完了条件: raw key/IME/menu/clipboard/Services/drop/mouse/scroll/AX/automationとhierarchy mutation/staleをfocused testでpass。
3. **Responder、focus report、両runtime受け入れ**
   - Product compositionへwindow authorityを一つだけ置き、close/reopen/Quick Terminal/Secure Inputとpresenter復帰を検証する。
   - 同一pane内owner transferのDEC 1004 report delta 0と既存observable behavior不変を固定する。
   - 完了条件: Developer JIT/Release AOT focused acceptance、aggregate/full gate、privacy/source auditをpass。

各サブタスクは実施前にROADMAPの先頭未完了を再確認し、個別に検証、記録、ROADMAP更新、commitする。後続を先行しない。

## 設計判断

- Authorityはproduct-owned `dart_terminal`へ置く。Window/pane/Note ownerは製品概念であり、generic `dart_appkit`へ入れない。
- Logical ownerとnative first responderを同一視しない。Transfer request中は旧ownerをsnapshotとして保持するが、routingはtransition中として
  fail closedにし、confirm後だけ新ownerへ切り替える。
- Topology同期はwindow/tab/pane/focusのbounded signatureを比較し、変化時にpending requestを無効化する。Current owner targetが
  live/focusedでなくなった場合だけterminal(focused pane)へ戻し、無関係なbackground mutationで有効ownerを不要に破棄しない。
- System surfaceはpriority ownerだが、暗黙stackで以前のDock/Noteへ戻さない。Dismiss後はcurrent focused terminalへ明示transferする。
- Note editorのdirty hierarchy guardはauthorityがcontent-free booleanとして所有し、Note body/revisionは保持しない。

## 完了条件

- Implementation planのCM-07成果物、完了条件、必須検証を満たす。
- 分散owner booleanが残らず、一window一owner、一pending transfer、monotonic generationが全経路で成立する。
- Note surface/store/bodyを実装せず、`dart_appkit`にTerminal固有codeを追加しない。
- 全検証、失敗、代替案、残る制約を本書へ記録し、全サブタスクcommit後だけ親を完了にする。

## 検証方針

- Pure authority unit/property sequence、Context Dock/action/presenter、native hierarchy、text input/native content/system automation focused tests。
- Developer JIT/Release AOTのfocused product acceptanceでowner/responder/focus report/Quick Terminal/Secure Input/close/reopenを確認する。
- `dart format`、`dart analyze`、`dart test/run_tests.dart`、`make test`、generated source freshness。
- Diagnostics/log/privacy sentinelと隣接`dart_appkit`差分audit。

## 2026-09-21: 第1サブタスク着手

- 着手前にROADMAP、README、FEATURE_MATRIX、CM-07 implementation plan、Gate 5/7仕様を再確認し、先頭未完了がCM-07であることを確認した。
- 既存Context Dockはrequest→native focus→confirmとstale generationを既に実装している一方、ownerはDock state内部の
  `TerminalContextDockInputOwner`に閉じている。System presenterも個別にresponder復帰を持つため、将来Noteを足す前に共通ownerが必要である。
- タスクはstate model、既存routing統合、real product acceptanceの3層へまたがるため、上記3サブタスクへ分割した。

## 2026-09-21: 第1サブタスク完了

### 実装結果

- Product-owned `TerminalWindowInteractionAuthority`を追加した。Application hierarchyを参照し、standard/Quick Terminalを含む
  live windowごとにexactly one owner、one pending transfer、monotonic authority/topology/request generationをboundedに保持する。
- `terminal(pane)`、`contextDock(pane)`、`noteRail(pane,surface generation)`、
  `noteEditor(pane,surface/draft generation)`、`systemSurface(surface generation)`をimmutableなcontent-free owner identityにした。
  Note ID/body/revisionやsystem surface内容はauthorityへ保持しない。
- Transferはrequest時に旧ownerを保持し、native focus結果と同じtokenをconfirmした場合だけ新ownerへcommitする。Cancel、second pending、
  wrong/late token、topology変化、window closeは固定dispositionで処理し、stale eventを新ownerやterminal actionとしてreplayしない。
- Topology signatureはwindow role、selected tab、tab order、focused/zoomed pane、pane traversalだけから作り、同期時だけ比較する。
  Targetがlive focused paneでなくなった場合はcurrent focused terminalへfallbackする一方、別windowのmutationではconfirmed ownerを保持する。
- Future Note editor用にcontent-freeなclean/dirty/confirm-discard guardを実装した。Dirty/confirmation中はowner exitとhierarchy mutationを拒否する。
  System surfaceはowner stackを作らず、dismiss後は明示的にcurrent terminalへtransferする。
- Pure acceptanceでrequest→confirm、cancel、single-flight、Dock→Note直接transfer、dirty guard、system priority、topology stale、
  unrelated-window retention、Quick Terminal、close/reopen、application shutdownを検証した。Fixed seed 10,000 stepで全owner種別の
  request/confirm/cancelを反復し、one owner、pending 0、generation単調増加を固定した。

### 失敗した試行と修正

- 最初のaggregate実行は新sourceを検出し、release-candidate daily-use matrixのstaleで停止した。Phase 7 acceptance、Ghostty gap
  inventory、daily-use matrixを依存順で再生成し、前二者は内容差分なし、daily-use source fingerprintだけを更新した。
- 初回analyzeは`test/run_tests.dart`のimport順にinfoを一件報告した。Alphabetical orderingへ修正後、issue 0を確認した。

### 検証結果

- `dart format`: 変更Dart source/testをformat済み。
- `dart analyze`: repository全体 issue 0。
- `terminal_window_interaction_test.dart`: exactly-one owner、request/confirm/cancel、stale hierarchy、Quick Terminal、close/reopen、
  10,000-step deterministic sequenceをpass。
- `dart test/run_tests.dart`: pass。Note store acceptanceはcommit p95 133,138 us、primitive p95 13,882 us、
  contention/recovery/privacyすべてpass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。369 filesのformat変更0、全analyze/test/native capability/
  privacy/security/compatibility/release gate pass。Note store 20 runsはcommit p95 132,833 us、primitive p95 13,218 us。
- `git diff --check`: pass。Authority/testにNote ID/body/path/time/command/checkpoint field 0。隣接`dart_appkit`は着手前からの
  3変更ファイル以外に差分0で、本サブタスクからの変更0。

### 第2サブタスクへの引き継ぎ

- `TerminalContextDockState.inputOwner`はまだ既存ownerであり、pure authorityとの二重管理期間である。次サブタスクで
  Context Dock snapshot/action/presenterをauthority projectionへ移し、このbooleanを削除する。
- Pure authorityはnative focusを操作しない。次サブタスクでowner-aware routing coordinatorを追加し、全input familyと
  consumed pointer gestureをfail closedにした後、product compositionへ一つだけ注入する。

## 2026-09-21: 第2サブタスク完了

### 現在地と設計確認

- 着手前にROADMAPを再確認し、先頭未完了がCM-07第2サブタスクであることを確認した。Native responderの実アプリ両runtime
  acceptanceは第3サブタスクへ残し、本項ではlogical owner統合とrouting decisionを対象にした。
- Existing Context Dockのpublic snapshot/action/presenter contractは多数のproduct acceptanceが参照するため、互換projectionを維持する。
  ただしprivate window stateから`inputOwner`を削除し、snapshot値は共通authority ownerから毎回導出する設計を採用した。
- Note surfaceはまだ存在しないため、Note routeはowner identityとtest double gestureだけを扱い、body/card/editor実装を追加しない。

### 実装結果

- `TerminalContextDockState`がshared `TerminalWindowInteractionAuthority`を受け取るようにした。Standalone unit testでは初回
  `synchronize`時に同じproduct authorityを内部生成できるが、owner storageは常にauthority一箇所だけである。
- Navigator focusはDock state更新→authority transfer request→native focus→Dock generation再検証→authority confirmの順になった。
  Stale/cancel/failureではpending tokenをcancelしてterminal ownerを維持する。Terminal focusもnative focus後にauthority transferを
  confirmし、Dock query/mode/result stateとは独立にownerだけを戻す。
- Private `_TerminalContextDockWindowState.inputOwner`を削除した。Public `TerminalContextDockInputOwner`はterminal/navigator/otherの
  compatibility projectionで、future Note/system owner中は`other`となり、Dock queryを保持したままinputを所有しない。
- Product composition rootがapplication-wide authority/routerを一つ生成し、Context Dockへ注入し、Dock→router→authorityの順で
  deterministicにdisposeするようにした。Quick Terminalも同じauthorityの別window stateを使用する。
- `TerminalWindowInteractionRouter`を追加し、raw key、IME、native menu key equivalent、copy、cut/paste/select-all、Services text、
  plain/rich/file drop、mouse、scroll、accessibility、automation writeをowner別の固定targetへ分類する。Transition/hierarchy mutation/
  generation mismatchはconsumeまたはstaleでfail closedとし、event queue/replayを作らない。
- Note railはIMEとmutation contentをconsume/rejectし、Note editorだけがdraft input targetになる。Automation writeはNote owner中
  `interactionBusy`、Context Dock中は既存explicit terminal targetを維持し、system surface中は全local familyをsystem ownerへ送る。
- Note childが開始したpointer/scroll sequence用にopaque consumed gesture identityを追加した。最大64件、authority/surface generationを
  固定し、owner変更後のdrag/up/momentum、duplicate up、window close後eventも`consumedStale`でterminalへ0 replayとした。

### 検証結果

- `dart format`: 変更Dart source/testをformat済み。
- `dart analyze`: repository全体 issue 0。
- `terminal_window_interaction_test.dart`: shared Dock request/confirm、query retention、terminal/other projection、12 input family×5 owner、
  transition/stale/hierarchy mutation、Note gesture owner-change/momentum/up/duplicate no-replayをpass。
- `terminal_context_dock_test.dart`、`terminal_native_hierarchy_test.dart`: 既存query/navigation/native responder contractをpass。
- Text input、action menu、native content（clipboard/Services/drop）、mouse、scroll、accessibility presentation、system automationの
  focused suites: すべてpass。
- `dart test/run_tests.dart`: pass。Note store acceptanceはcommit p95 146,204 us、primitive p95 19,902 us、
  contention/recovery/privacyすべてpass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。369 filesのformat変更0、全analyze/test/native capability/
  privacy/security/compatibility/release gate pass。Note store 20 runsはcommit p95 144,485 us、primitive p95 18,104 us。
- Phase 7 acceptance、Ghostty gap inventory、release-candidate daily-use matrixはsource fingerprintを再生成し、behavior/evidence数は不変。
- `git diff --check`: pass。新router/gestureにNote ID/body/path/time/checkpoint field 0。隣接`dart_appkit`は着手前からの
  3変更ファイル以外に差分0で、本サブタスクからの変更0。

### 第3サブタスクへの引き継ぎ

- Product rootはshared authorityを所有するが、system presenterのpresent/dismissとterminal raw/IME callbackでのroute assertionは
  まだreal runtime acceptanceへ固定していない。次はfocused product scenarioを追加し、native first responder、DEC 1004、Secure Input、
  Quick Terminal、close/reopenをDeveloper JIT/Release AOTで確認する。

## 2026-09-21: 第3サブタスク着手

### 現在地と実装方針

- 着手前にROADMAPを再確認し、先頭未完了がCM-07第3サブタスクであること、完了条件がterminal responder復帰、同一pane内
  owner transferのDEC 1004 delta 0、Context Dock/Quick Terminal/Secure Input/close/reopenのDeveloper JIT・Release AOT
  focused acceptanceであることを確認した。
- 既存のnative-content、Quick Terminal、Secure Keyboard Entry各suiteを個別に再利用する案は、機能自体の回帰は検証できても、
  同じshared authority generationと実callbackのfail-closedを一つの実行で証明できないため不採用とした。Native-content suiteへ
  追加する案も、長時間のDirectory/process fixtureとauthority invariantを一体化して失敗原因を曖昧にするため不採用とした。
- 専用のgated product acceptanceを追加し、ordinary product composition rootのauthority/routerを直接使ってContext Dockのnative
  responder、system surfaceのopen/dismiss、rogue terminal raw/IME callback遮断、DEC 1004、Quick Terminal、Secure Input、window
  close/reopenを一続きに検証する。
- System surfaceはpresenter別booleanを持たせず、opaqueなsurface identityだけをbounded coordinatorへ通知する。最後のsurfaceが閉じ、
  presenterがterminal responderを復帰した後にterminal ownerへ明示transferする。複数surfaceをowner stackとして復元しない。
- Terminal inputの実経路はshared routerのdecisionを境界で確認する。Raw key/IME、Services/drop/AppleScript、paste、mouse、scrollは
  terminal targetのときだけ既存処理へ進め、transition/stale/他ownerではqueue/replayせず終了する。Note surface/bodyは実装しない。
- `dart_appkit`には製品owner、pane、Note、acceptance flagを追加しない。必要なnative操作は既存の汎用APIを
  `dart_terminal`側から呼び、全パラメータをproduct compositionから注入する。

### 実機fixtureで判明した事項

- Developer JIT の初回実行では、LaunchServices によるapplication active化だけでは通常ウインドウの
  `WindowFocusChangedEvent`が保証されず、受け入れ開始条件がタイムアウトした。
- 製品owner遷移に入る前のfixture不足であり、既存のQuick Terminal実機受け入れと同じテスト専用native focus eventを
  一度だけ注入して、activeかつfocusedの確定状態から測定を始める。
- Release AOTの初回実行では、prompt表示直後にContext Dockの非同期観測状態がaction registryへ反映される前に
  `search-files-and-folders`をdispatchし、一時的なdisabledで停止した。JIT/AOTで同じsettled stateを測るため、専用fixtureの
  共通dispatchはactionがenabledになるまで待ってから一度だけ実行する。入力やactionのreplayは行わない。

## 2026-09-21: 第3サブタスク完了

### 実装結果

- Product rootで一つだけ生成するauthority/routerに、terminal text input、Context Dock native key、copy/paste、Services、drop、
  mouse、scroll、AppleScript external pasteの実callback境界を接続した。Ownerが対象でない場合は処理を終了し、queue/replayしない。
- Command Palette、Settings、Diagnostics、Incident、Update、OSC 52の各presenterへcontent-freeなvisibility callbackを追加した。
  Product-owned `TerminalWindowSystemSurfaceCoordinator`は最大32個のopaque identityだけを保持し、同じwindowの複数surfaceを一つの
  system ownerとして扱う。最後の通常dismissでterminal responder復帰後にcurrent terminalへ明示transferする。
- External pasteには汎用的なadmission callbackを注入できるようにし、planning前後の両方でauthorityを再確認する。Stale ownerは既存の
  `staleTarget`でfail closedとなり、Services/drop/AppleScript/file pathの内容や製品固有identityをcontrollerへ保持しない。
- `--runtime-window-interaction-test`と環境gate、専用integration suite/Make targetを追加した。1/1/1 hierarchyからDEC 1004を有効化し、
  Context Dock移譲、12 input family matrix、rogue raw/IME zero-delivery、terminal復帰、system surface responder復帰、future Note rail
  test double、Secure Input projection不変、Quick Terminal、window close/reopen、4 session cleanupを一続きで検証する。
- Future Note検証はcontent-free owner identityだけをauthorityへ渡し、native Note surface、card、editor、store、bodyは実装していない。
  `dart_appkit`には本タスクの変更を加えていない。

### 検証結果

- `dart format`: 369 filesで変更0。
- `dart analyze`: repository全体issue 0。
- `terminal_window_interaction_test.dart`: system surface identity/lifecycle、close同期、terminal復帰を含めpass。
- `terminal_native_content_test.dart`: external paste admissionのplanning後再検証とzero writeを含めpass。
- `dart test/run_tests.dart`: pass。Note store acceptanceはcommit p95 145,461 us、primitive p95 19,011 us、
  contention/recovery/privacyすべてpass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。全format/analyze/unit/native capability/privacy/security/
  compatibility/release gateを完走。Note store 20 runsはcommit p95 147,017 us、primitive p95 17,371 us。
- `make RUNTIME_ARCH=arm64 runtime-window-interaction-integration`: Developer JITとRelease AOTを連続pass。
  最終実行はそれぞれ2,334 msと988 msで、両方ともDEC 1004 delta 0、4 clean sessions、text client/native handle 0を確認した。
- Phase 7 acceptance、Ghostty gap inventory、release-candidate daily-use matrixを依存順で再生成した。受け入れ件数・gap数は不変で、
  変更されたsource fingerprintだけを更新した。
- `git diff --check`: pass。Authority/testにNote ID/body/text/path/timestamp/checkpoint/command field 0。
  隣接`dart_appkit`は着手前からの3変更ファイルのみで、本タスクによる変更0。

### 後続への境界

- CM-08は本authorityの`noteRail` ownerとconsumed gesture identityを使ってnative presentation capabilityを実装する。
  Owner storageやsystem surface stackを別に追加しない。
- CM-09でeditor/AX interactionを接続する際も、native focus取得後に同じgeneration-bound requestをconfirmし、stale eventをterminalへ
  replayしない。Note本文やdraftはauthority/routerへ格納しない。
