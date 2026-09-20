# Phase 7 — Tab-focus Directory retention

## 目的

同じwindow内でforeground processを実行中のtabから別tabへ移動し、元tabへ戻った場合も、
Process InspectorからDirectory Navigatorへ手動切替できるようにする。

## 背景

同じselected tab内のsplit pane focus round tripは、非focused paneのprocess詳細、poll、filesystem
operationを停止しつつ、最小job identityとcommand開始前のDirectory snapshotを非投影で凍結保持する。
一方、tab focus変更は安全境界として保持対象外にしているため、元tabへ戻るとProcess Inspectorは再構築できても、
Directory snapshotが失われてcontent toggleを利用できない。

## 範囲

- 同じvisible window内のtab focus round tripで、旧process paneの最小job identityとDirectory snapshotを
  非投影・凍結状態で保持する。
- 元tab／paneへ戻った時にwindow、pane、session、foreground PGIDを再検証し、同一jobだけProcess Inspectorと
  Directory toggleを復元する。
- background tabではprocess詳細取得、poll、Directory投影、filesystem operationを行わない。
- tab／pane close、session／PGID変更、Dock hide、window close、app非active、disposeで保持stateを破棄する。

## 対象外

- background tabのProcess Inspector表示または継続的なprocess監視。
- 異なるwindow／session／foreground jobへのDirectory snapshot引き継ぎ。
- appが非activeな期間をまたぐ複数tab snapshotの保持。
- SSH先filesystem、foreground processへのpath insertion、自動`cd`。

## 依存関係

- `TerminalContextDockProcessController`のpane-focus suspended state、presentation suspension、poll ownership。
- `TerminalContextDockDirectoryController`のpane-focus retained snapshot、operation cancellation。
- `TerminalContextDockState`のselected tab／focused pane同期。
- application reconcileのprocess → privacy → Directory順序。

## リスク

- background tabでprocess／filesystem観測を続けるとprivacyとresource境界を破る。
- pane IDだけで復元するとtab close、session再生成、PGID置換後に古いpathを表示する可能性がある。
- tabごとの保持stateがclose／hide／app非active／disposeで解放されないと、pathまたはresourceが残留する。
- tab切替時の同期順序でdisplay authorityが一時失効すると、保持snapshotを復元前に削除する可能性がある。

## 完了条件

- tab Aでforeground processを実行し、tab Bへ移動してAへ戻った後、content toggleが利用できる。
- toggle後はAのcommand開始前rootを表示し、tree操作とmanual refreshが使える。
- Bをselected中はAのprocess rich request／pollとDirectory operationが0である。
- Aのsession／PGIDが変わった場合は保持snapshotを表示せず、toggleをfail closedにする。
- tab／pane／window close、Dock hide、app非active、dispose後に保持stateとoperationが残らない。

## 検証方針

- process controller unitでtab A→B→Aを再現し、background中のrich request停止、同一identity復帰、
  PGID変更時invalidateを固定する。
- Directory controller unitでAのsnapshotを凍結退避し、Bを表示後にAへ戻してrootをcwd再解決なしで再利用する。
- native-content integrationで実tab focus round trip、menu action availability、Directory切替、PTY write 0を
  Developer JIT／Release AOTで確認する。
- formatter、静的解析、生成証跡、repository全体testを実行する。

## 調査記録

### 2026-09-20 — 着手時

- process controllerはfocused pane変更時に旧stateを退避できるが、旧paneが現在のselected tabに属する場合だけに
  制限している。tab AからBへ移ると`sameSelectedTab`がfalseとなり、Aのretention authorityを破棄する。
- Directory controllerも同じ`sameSelectedTab`条件で旧snapshotを退避するため、tab往復ではcommand開始前rootを失う。
- tab Aへ戻った際、foreground process自体は再観測できるが、process controllerとDirectory controllerの保持authorityが
  揃わずcontent toggleがdisabledになる。ユーザー報告はこの既存境界と一致する。
- 採用方針は同一window内のpane target変更へ保持範囲を広げ、background tab中は既存split paneと同様にprocess content、
  rich request、poll、filesystem operationを全て停止する。復帰時はlive pane、window、session、PGIDを再検証する。
- 別windowへのfocus変更とapp非active化は従来どおり保持cacheを破棄し、複数window間へpath情報を引き継がない。

### 2026-09-20 — 回帰fixtureと修正前再現

- process controller unitへ実tab A／Bを作り、Aのforeground job確立後にBへ移動し、Aへ戻るfixtureを追加した。
  同一session／PGIDでtoggleが復帰する経路と、Bを表示中にAのPGIDが変わった場合のinvalidationを検証する。
- Directory controller unitへAのroot／row列を確定してretention authorityを与え、Bで独立rootを表示後、cwd resolverを
  利用不能にしてAへ戻る経路を追加した。background tab close時のcache破棄も同じfixtureで確認する。
- 最初のtest実行はsandboxがClang module cacheとDart telemetry sessionへ書けずbuild hook前に停止したため、通常の
  SDK cache権限で再実行した。fixture追加時にはworking-directory resolverの必須nullable引数2件が不足してcompileが
  2回停止し、既存contractに合わせて明示的な`null`を渡した。
- compile修正後の現行実装ではDirectory fixtureの「別tab表示中もAのsnapshotを保持する」assertionが失敗し、
  `sameSelectedTab`境界によるユーザー報告を自動再現した。

### 2026-09-20 — 実装

- process controllerの退避条件を「旧paneが現在のselected tabに属する」から「旧paneが同じlogical windowに属する」へ
  変更した。tab切替中はrich request、process path／argv、poll対象、content overrideを破棄し、pane ID、session、
  foreground PGID、Directory retention eligibilityだけを既存のoperation-free cacheへ置く。
- Directory controllerも同じwindow内のtab切替時に、全filesystem operationをcancelしたimmutable snapshotをpane IDで
  退避する。元tabへ戻る時はcwdを再解決せずcommand開始前rootを再接続する。
- cacheはlive pane集合でpruneされるためtab／pane closeで破棄される。Dock hide、window close、app非active、disposeは
  既存のwindow単位cleanupを維持し、別windowまたは非active期間へ複数tab pathを引き継がない。
- native-content acceptanceへ実`/bin/cat` foreground job中のNew Tab、Previous Tab、Directory toggle、PTY write 0、
  Next Tab、temporary tab Closeとclean session回収を追加した。

### 2026-09-20 — native tab遷移中の一時的な非投影状態

- 実AppKitのtab切替ではlogical selected tabが先に変わり、新しいnative tabがvisible／focusedになるまで短い期間がある。
  この期間はContext Dockのdisplay authorityがなく、従来のapp-focus用unpresented policyへ流すと、旧tabの最小job
  identityとDirectory snapshotを新tabの通常投影前に破棄していた。split paneだけのfixtureにはこの状態がないため、
  pane round trip修正後も実tabでのみ再発していた。
- native-content fixtureが最初に失敗した時のcontent-free診断は、logical tab選択、process／Directory retention、app active、
  native visibleが全てtrueで、native focusedだけfalseだった。これはprocess再観測やDirectory treeの不具合ではなく、
  native focus eventをまだ受けていない投影抑止期間であることを示した。
- app-focus保持policyの公開signatureは変更せず、同一logical windowのtab retarget専用policyを追加した。app activeで、
  別logical windowのselected native tabがvisibleかつfocusedではない時だけ一時保持を許可する。非投影期間はrich request、
  poll、filesystem operationを開始せず、target tabのnative focus確立後に通常のwindow／pane／session／PGID検証へ戻す。
- process controllerにはwindow単位のpending retarget markerを追加した。連続するnative focus通知でもcacheを早期破棄せず、
  native focus確立、window close、Dock hide、app非active、別windowへのfocus、disposeでmarkerを消去する。
- native-content fixtureはprogrammatic tab selectionだけに依存せず、旧native tabのfocus-outと新native tabのfocus-inを注入する。
  これによりlogical selectionとnative presentationの実際の順序を再現し、元tab復帰後のcontent toggle、保持root、Navigator
  input ownership、PTY write 0、temporary tab／session回収まで一つの受け入れ経路で固定した。

## 検証結果

### 自動検証

- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`
  - 成功。Directory snapshotのtab A→B→A復帰、process最小identityの非投影保持、pending native focus通知、
    background rich request／operation 0、PGID置換時のfail-closedを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`
  - 成功。`No issues found!`。
- `make phase7-appkit-acceptance`
  - 成功。更新したsource／unit testのhashとacceptance corpusを再生成した。
- `make terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`
  - 成功。README／FEATURE_MATRIX／acceptance／runtime integrationのhash evidenceを再生成した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  - 成功。formatterは351 files／0 changed、root analyzerは`No issues found!`、全package／security／compatibility／
    distribution contract testを含め`dart_terminal tests passed`、終了コード0だった。
- `git diff --check`
  - 成功。空白errorなし。

### 実native-content経路

- Developer JITとRelease AOTのnative-content integrationで、追加した実tab focus fixtureは両方成功した。
  `tab_focus=true`、`navigator=true`、`process_inspector=true`、`exact_pty=true`を含むpass markerと、全temporary
  sessionのclean回収を確認した。
- strict aggregateをそのまま実行すると、このtab fixtureより前に既知のmanual Secure Keyboard Entry foreground activation
  assertionで停止する場合があった。tab fixture単独の切り分けでは、その既知assertionだけを一時的に診断許容して両runtimeを
  実行し、製品コードと追加fixtureが通ることを確認した。診断用変更は全て除去済みである。
- 上記manual Secure ownerの不安定性は今回のtab保持とは独立し、直後のROADMAP項目と
  [`../phase10/native-content-secure-input-activation.md`](../phase10/native-content-secure-input-activation.md)で追跡する。
  今回の自動test gateとtab固有の両runtime受け入れには未解決失敗はない。

## 完了判断

- 同一windowのtab往復後に、同一pane／session／PGIDならProcess InspectorとDirectory Navigatorの切替を復元する。
- background tabとnative focus遷移中は旧tabのprocess詳細、poll、Directory投影、filesystem operationを保持しない。
- tab／pane close、Dock hide、window close、app非active、別window focus、session／PGID変更、disposeでは古い保持stateを
  利用しない。
- user報告のtab round trip経路をunitとDeveloper JIT／Release AOT native fixtureへ追加し、完了条件を満たした。
