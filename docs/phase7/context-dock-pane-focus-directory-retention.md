# Phase 7 — Pane-focus Directory retention

## 目的

split paneの一方でforeground processを実行し、別paneへfocusしてから同じprocess paneへ戻った場合も、
Process InspectorからDirectory Navigatorへ手動切替できるようにする。

## 背景

同じpane内のprocess pollとapplication focus round tripは保持済みDirectory snapshotを再利用できる。
一方、Context Dockはwindowごとにfocused pane一つのprocess／Directory stateしか所有しておらず、pane focus変更時に
旧paneのstateを破棄する。process paneへ戻るとProcess Inspectorは再構築されるが、command開始前のDirectory snapshotが
ないためcontent toggleが利用できない。

## 範囲

- 同じvisible window内のsplit pane focus round tripで、旧process paneの最小job identityとDirectory snapshotを
  非投影・凍結状態で保持する。
- 元paneへ戻った時にsession／foreground PGIDを再検証し、同一jobだけProcess InspectorとDirectory toggleを復元する。
- background paneではprocess詳細取得、poll、filesystem operationを行わない。
- pane close、session／PGID変更、Dock hide、window close、app disposalで保持stateを破棄する。

## 対象外

- background paneのProcess Inspector表示または継続的なprocess監視。
- 異なるwindow／tab／session／foreground jobへのDirectory snapshot引き継ぎ。
- SSH先filesystem、foreground processへのpath insertion、自動`cd`。

## 依存関係

- `TerminalContextDockProcessController`のfocused-pane state、presentation suspension、poll ownership。
- `TerminalContextDockDirectoryController`のwindow projection、frozen snapshot、operation cancellation。
- `TerminalContextDockState`のpane-local navigation stateとfocused pane同期。
- application reconcileのprocess → privacy → Directory順序。

## リスク

- background paneでprocess／filesystem観測を続けるとprivacyとresource境界を破る。
- pane IDだけで復元するとsession再生成やPGID置換後に古いpathを表示する可能性がある。
- windowごとの一状態を複数paneへ拡張する際、hide／close／disposeでstateを解放し忘れる可能性がある。
- process paneへ戻った瞬間の同期順序でdisplay authorityが一時失効すると、保持snapshotを復元前に削除する可能性がある。

## 完了条件

- pane Aでforeground processを実行し、pane Bへ移動してAへ戻った後、content toggleが利用できる。
- toggle後はAのcommand開始前rootを表示し、tree操作とmanual refreshが使える。
- Bをfocused中はAのprocess rich request／pollとDirectory operationが0である。
- Aのsession／PGIDが変わった場合は保持snapshotを表示せず、toggleをfail closedにする。
- pane／window close、Dock hide、dispose後に保持stateとoperationが残らない。

## 検証方針

- process controller unitでA→B→Aを再現し、background中のpoll／rich request停止、同一identity復帰、
  PGID変更時invalidateを固定する。
- Directory controller unitでAのsnapshotを凍結退避し、Bを表示後にAへ戻してrootを再利用することを確認する。
- native-content integrationで実split focus round trip、menu action availability、Directory切替、PTY write 0を
  Developer JIT／Release AOTで確認する。
- formatter、静的解析、生成証跡、repository全体testを実行する。

## 調査記録

### 2026-09-20 — 着手時

- process controllerはwindowごとに一つのstateを持ち、`dock.targetPaneId`が変わると旧stateを
  `_cancelState()`で破棄する。旧stateがapplication focus suspension中でない限りDirectory invalidation callbackも
  呼ばれず、retention authorityだけが失われる。
- Directory controllerもwindowごとに一つのsnapshotを持ち、focused pane変更時に旧snapshotをcancelして
  新paneのcwd snapshotへ置換する。
- Aへ戻った時、process controllerは実processからProcess Inspectorを再構築できるが、Directory controllerには
  Aの保持snapshotがない。applicationのdisplay authorityはprocess retentionと`hasRetainedSnapshot(A)`の両方を
  必要とするため、content toggleがdisabledになる。
- 採用方向は、最大64という既存pane上限内で、非focused process paneごとに最小suspended process identityと
  operationを全cancelしたDirectory snapshotを保持する。復帰時はsession／PGIDを再検証し、同一jobだけを再接続する。

### 2026-09-20 — process回帰fixture

- controller unitへ実split pane A／Bを作り、Aのforeground job確立後にBへfocusし、Aへ戻るfixtureを追加した。
- 修正前はBへfocusした時点でAのprocess stateが破棄され、
  `focus departure freezes the process pane identity without background rich observation`が失敗した。
- fixtureは同一session／PGID復帰時のtoggle availabilityとDirectory投影に加え、Bをfocused中にAのPGIDを変更した場合の
  invalidationも検証する。

### 2026-09-20 — Directory回帰fixture

- 既存Directory controller testへ、Aのroot／treeを確定してretention authorityを与え、Bへfocusして独立rootを表示後、
  cwd resolverを利用不能にしてAへ戻る経路を追加した。
- process stateだけを退避する中間実装では、A→B時にDirectory snapshotが従来どおりcancelされ、
  `focused pane change projects the new pane cwd while freezing the retained process pane`が失敗した。
- 修正後はB表示中もAのsnapshotを非投影・operation 0で保持し、A復帰時にcwd resolverを呼ばず同じrow列を再開する。

### 2026-09-20 — native fixture作成時の型修正

- 実split pane acceptanceへforeground job、右pane移動、左pane復帰、Directory toggle、PTY write 0を追加した。
- 初回compileはControl-C fixtureを`List<int>`で渡したため、`TerminalPane.sendInput`が要求する`Uint8List`と一致せず
  失敗した。既存のtyped input境界に合わせて`Uint8List.fromList`へ修正した。

### 2026-09-20 — Developer JIT初回実行

- 追加したsplit focus／Directory toggle assertionを含むnative-content本体は最後の
  `TERMINAL_NATIVE_CONTENT_TEST ... process_inspector=true ... sessions_clean=4`まで到達し、全pane／sessionをcleanに
  回収した。
- ただし長い`stty -echo; sleep 8` fixtureにより60秒のruntime wrapper deadlineを越え、shutdown後の遅延active eventが
  disposal済みSecure Keyboard Entry controllerへ届く既存teardown raceも発生してtargetは失敗した。
- pane focus検証にECHO-offや実時間sleepは不要なため、既存実績のある`/bin/cat` foreground fixtureへ短縮し、
  toggle確認後にEOFで終了させる。これにより受け入れ内容を維持してsuiteのbounded runtimeへ戻す。

### 2026-09-20 — Release AOT初回実行

- 短縮後のDeveloper JITは`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`まで成功した。
- Release AOTは右paneへ移動した後のassertionでtimeoutした。assertionがcontroller全体の
  `activeOperationCount == 0`を要求しており、非focused旧paneではなく、現在表示する右pane自身の正当なDirectory loadまで
  禁止していたためruntime timingに依存していた。
- 受け入れを「旧paneの保持authorityがある」「window projectionは右paneのDirectoryでprocess contentがnull」という
  ownership条件へ修正した。旧pane operationのcancelはcontroller unitで直接検証し、current paneの通常loadは許可する。

### 2026-09-20 — 最終Developer JIT再実行中の既存fixture揺らぎ

- ownership assertion修正後のRelease AOTは`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`まで成功した。
- 同sourceのDeveloper JIT再実行は追加したsplit fixtureへ到達する前の既存silent-command refreshで、期待1 commitに対し
  2 commitとなり失敗した。直前のDeveloper JITは追加fixtureを含め成功しており、今回変更したpane retention経路より
  前段の既存refresh timing fixtureである。product回帰か一過性かを同source再実行で確認する。

### 2026-09-20 — 実装

- process controllerへpane-focus suspended stateを追加した。focused process paneから同じwindow／selected tab内の
  別split paneへ移る時、rich request、process path／argv、poll対象、content overrideを破棄し、sessionとforeground PGID、
  Directory retention eligibilityだけをpane IDごとに保持する。
- 元paneへ戻る時はlive pane、window、tab、sessionを照合し、foreground PGIDを再取得して一致した場合だけ新しい
  Process Inspector generationへ復帰する。PGID／session変更、pane close、別tab／window、Dock hide、app非active、disposeは
  cached stateとDirectory snapshotをinvalidateする。
- Directory controllerもwindowの可視slotから旧pane snapshotを外し、全operationをcancelしたfrozen stateとして
  pane IDごとに保持する。`hasRetainedSnapshot`は非投影stateもauthority確認に使い、元pane復帰時はforeground cwdを
  再解決せずcommand開始前rootを再接続する。
- cache数はapplication既存上限の最大64 live paneに拘束される。background paneではrich request／poll／filesystem operationを
  開始せず、現在focused paneの通常Directory loadだけを許可する。
- README、feature matrix、manual checklistを、同じselected tab内のsplit focus round tripとtab／window境界を区別する仕様へ
  更新した。

### 2026-09-20 — 検証結果

- `dart run test/terminal_context_dock_test.dart`: 成功。実split A→B→Aでprocess retention、background rich request 0、
  toggle復帰、Directory投影、PGID置換時invalidateを確認した。Directory側はAのrow列を凍結保持し、cwd resolverを
  呼ばず復帰することを確認した。
- `dart format`（変更した4 Dart files）: 最終format済み。repository全体checkでも351 files変更0。
- `dart analyze`: 成功、issue 0。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 最終再実行で成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true ... elapsed_ms=27366`。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 最終再実行で成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true ... elapsed_ms=26403`。
- native acceptanceは実splitを使い、`/bin/cat`実行paneから別paneへ移動中の旧process非投影、元pane復帰後の
  Directory toggle、同じroot、Navigator focus、PTY write 0、EOF後のclean shell復帰を確認した。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功し、最終sourceに対応する生成証跡を更新した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。package／root analyzer、unit、security stress、
  compatibility／generated evidence checkを完走した。
- `git diff --check`: 成功。
- final docs／ROADMAP更新後の生成証跡checkは、初回sandbox内でDart telemetry session fileのmtime更新を拒否され
  `dependencies` targetが停止した。source／evidence failureではないため、通常のSDK cache権限で同じcheckを再実行する。

残存するtask固有の阻害要因、未検証事項、追加ROADMAP項目はない。
