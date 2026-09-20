# CM-07 unified window interaction authority

日付: 2026-09-21
状態: 実装中

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
