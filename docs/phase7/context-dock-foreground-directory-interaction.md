# Phase 7 — Foreground-process Directory interaction

## 目的

foreground process実行中にProcess InspectorからDirectory Navigatorへ手動切替した場合も、
通常時と同様にkeyboardでtreeを移動し、folderを展開／折り畳みできるようにする。

## 背景

現在の手動切替はcommand開始前のDirectory snapshotをread-only表示するだけで、terminalがinputを所有し続ける。
また、ECHO-offまたはmanual Secure Input中はsnapshotを凍結し、tree intentと新規filesystem operationを拒否する。
このためDirectory表示へ切り替わっても、矢印移動や未展開folderの読み込みを操作できない。

## 範囲

- 明示的にDirectory Navigatorへ切り替えた時はNavigatorへinput focusを移す。
- 上下／Page移動、Return／Command-Right／Leftによるfolder展開・折り畳みを利用可能にする。
- Shift-Command-F／G／MのSearch／Go To／Moveとhidden file切替、明示refreshを通常のNavigatorと同じ
  bounded operationとして扱う。
- 同じcontent toggleでProcess Inspectorへ戻る時、およびEscape時はterminal inputを復元する。
- ECHO-off／manual Secure Input中も、利用者が明示的にDirectory表示を選んだ間だけlocal filesystemの
  bounded observationを許可する。

## 対象外

- foreground processへのpath insertion、自動`cd`、command実行。
- Directory表示を選んでいない間のfilesystem observationまたはbackground polling。
- SSH先filesystem、remote process introspection、rootを暗黙に全走査する検索。

## 依存関係

- `TerminalContextDockProcessController`のcontent overrideとDirectory observation authority。
- `TerminalContextDockActionCoordinator`／presenterのNavigator focus ownership。
- `TerminalContextDockDirectoryController`のfrozen snapshot、lazy subtree、Search／Go To operation。
- path handoffのforeground-process fail-closed policy。

## リスク

- Navigator操作キーが同時にPTYへ送られるとinteractive processを意図せず操作する。
- Process Inspectorへ戻った後もfilesystem operationやNavigator focusが残る可能性がある。
- ECHO-off中の自動観測まで許可すると、利用者の明示操作なしにprivacy境界が広がる。
- process終了とDirectory operation完了が競合するとstale resultを投影する可能性がある。

## 完了条件

- 手動切替直後にMove modeでNavigatorがinputを所有し、選択移動とfolder展開／折り畳みが動作する。
- Search／Go To／Move、hidden切替、manual refreshは既存boundとcancel条件を維持する。
- Directory操作中のkey eventはPTY write 0で、Process Inspectorへ戻るとterminal inputが復元される。
- foreground process中のpath insertionは引き続き拒否する。
- app focus、pane、session、PGID、Dock visibility、process終了の境界でoperationをcancelまたは通常状態へ戻す。

## 検証方針

- controller unitでmanual override中だけfresh Directory observationを許可し、解除時に停止することを固定する。
- action／presenter testでtoggle時のMove focus、tree selection、lazy expansion、Process Inspector復帰時のterminal focus、
  PTY write 0を確認する。
- native-content integrationでECHO-off foreground process中の実menu action、folder expansion、Search／Go To／Move、
  path insertion拒否をDeveloper JIT／Release AOTの両方で確認する。
- formatter、静的解析、生成証跡、repository全体testを実行する。

## 調査記録

### 2026-09-20 — 着手時

- 現行仕様はcontent toggle後もterminal inputを維持し、frozen Directoryのtree intentとfilesystem operationを
  意図的に停止している。
- 新仕様では「明示的なDirectory表示」と「自動的なprocess実行中」を分離し、前者の期間だけNavigator focusと
  bounded observationを有効にする。path insertionはforeground process policyで独立して拒否する。

### 2026-09-20 — 原因と採用設計

- `TerminalContextDockProcessController.toggleActiveWindowContent()`はcontent overrideだけを変更し、
  Navigator focus requestを発行していなかった。このためnative windowは`appKitOnly` routingのままで、矢印や
  Returnはterminal側へ残っていた。
- application側のDirectory observation／Navigator focus admissionは、process controllerの状態を確認する前に
  `TerminalContextDockPrivacyPolicy.canObserve()`を要求していた。ECHO-offまたはmanual Secure Input中は、利用者が
  明示的にDirectory表示を選んでもこの前段で拒否され、保持済みtreeは`isFrozen`のままだった。
- content toggleでDirectoryを選んだ時は、同じpane・session・foreground job・可視Dockに限定したoverrideを
  filesystem observation authorityとして扱う。通常のidle Directoryは従来どおりprivacy policyを通し、
  Process Inspector表示中や非表示／非active windowではauthorityを与えない。
- toggle時はMove modeのgeneration-bound focus requestを作成し、Directory documentを先に投影してからnative
  editorへfocusし、成功後だけNavigator input ownershipを確定する。Process Inspectorへ戻す時は従来どおり
  terminalへfocusを返す。
- override解除でDirectory controllerは保持済みsnapshotを再度freezeし、subtree／Search／Go To／refreshの
  operationをcancelする。process中のpath insertion拒否は別のprocess-disposition policyにより維持される。

### 2026-09-20 — Developer JIT初回検証で判明したfocus gate

- 初回`make RUNTIME_ARCH=arm64 developer-jit-native-content`は、ECHO-off content toggle後の
  `navigatorOwnsInput`を待つ受け入れで失敗した。
- process controllerとDirectory controllerは明示overrideを認可してtreeを再開できていたが、application全体の
  `enforceContextDockPrivacy()`が旧来のautomatic privacy判定だけを参照し、同じreconcile内でnative focusを
  terminalへ戻していた。
- privacy enforcementもprocess-awareなDirectory authorityを参照するよう統一した。これにより自動観測拒否中でも
  明示overrideだけはNavigator focusを維持し、override解除後は同じgateが再びfail closedになる。

### 2026-09-20 — 統合検証中の非対象fixture失敗

- 新しいMove／tree展開／Search／Go To／refresh／path insertion拒否を追加した後、Developer JITとRelease AOTは
  それぞれ`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`まで成功した。
- その後の最終combined再実行では、新しいDirectory操作を通過した後、既存manual Secure Keyboard Entry fixtureが
  `manual_requested=true`、`desired=true`、`owned=false`、`os_status=0`となって失敗した。今回変更したDirectory
  authority／focusより後段のOS-global owner取得であり、直前の同一source系統では成功しているため、同じ最終sourceを
  再実行して一過性かを確認する。

### 2026-09-20 — 実装

- process controllerへgeneration-bound Navigator focus callbackを追加し、content toggleでDirectoryを選ぶと
  Move modeを要求し、native focus成功後だけNavigator input ownershipを確定するようにした。
- explicit overrideのauthorityを、同じvisible window／pane／session／foreground job、保持済みDirectory snapshot、
  display authorityに限定した。この期間だけautomatic ECHO／manual Secure privacy vetoを越えてDirectory controllerを
  再開する。idle時は従来のprivacy policyを維持する。
- applicationのDirectory observation、Navigator action admission、input privacy enforcementを同じprocess-aware
  authorityへ統一した。これによりtree intent、Search／Go To／Move、hidden切替、manual refreshが同じ経路で動く。
- Inspectorへ戻る時、display authority失効時、foreground PGID置換時はterminal focusを復元し、Directory operationを
  freeze／cancelする。foreground processへのOption-Returnはpath handoff policyで引き続き拒否する。
- native-content acceptanceへECHO-off中のMove focus、上下移動、Returnによるlazy展開／折り畳み、3 mode遷移、
  一回manual refresh、Option-Return拒否、PTY write 0を追加した。
- README、feature matrix、manual checklistをinteractive Directory仕様へ更新し、生成証跡を再生成した。

### 2026-09-20 — 検証結果

- `dart run test/terminal_context_dock_test.dart`: 成功。explicit overrideだけのDirectory observation、Move focus、
  Inspector復帰、PGID置換時のterminal focusを確認した。
- `dart analyze`: 成功、issue 0。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功し、4種類の生成証跡を更新した。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 最終product sourceと全追加assertionで成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true sessions=4
  elapsed_ms=24198`。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 同じ最終product sourceと全追加assertionで成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true sessions=4
  elapsed_ms=23177`。
- 成功後のaggregate再実行は新しいDirectory fixtureを通過し、後段の既存manual Secure owner取得だけが、実appが
  foregroundにならない環境preconditionで3回失敗した。productのfail-closedは維持され、PTY／worker cleanupも完了した。
  再現と修正は
  [`docs/phase10/native-content-secure-input-activation.md`](../phase10/native-content-secure-input-activation.md)へ分離し、
  ROADMAPへ追跡項目を追加した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。351 fileのformatter確認（変更0）、root／package analyzer、
  unit、security stress、compatibility／generated evidence checkを完走した。
- 単独`dart format`はsource整形後にsandbox外telemetry session fileのmtime更新を拒否されたが、後続の
  repository全体formatterが351 file変更0で成功したため、format結果自体に未解決事項はない。
- `git diff --check`: 成功。
