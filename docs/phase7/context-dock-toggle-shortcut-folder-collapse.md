# Context Dock toggle shortcut and folder collapse

- Status: complete
- Date: 2026-09-15
- Scope: Context Dockの既定表示切替shortcutとDirectory Navigatorのfolder開閉操作
- Related: UI-05、AX-02、CFG-03、CFG-07

## 目的と背景

Context Dockをmenu探索なしで表示／非表示にできる既定shortcutを追加する。また、Directory Navigatorで
`Return`を使って開いたfolderを、同じ選択位置でもう一度`Return`を押して閉じられるようにする。

現状の`view.toggle-context-dock`はView menuとCommand Paletteにあるがshortcutを持たない。folderは
`Return`または`Command+Right`で展開でき、`Command+Left`で閉じられるが、`Return`は展開済みfolder上では
何も起こさない。既存の閉じる操作を維持しつつ、同じkeyによる対称な開閉を追加する。

## 範囲

- `Option+Shift+C`を`view.toggle-context-dock`の既定native menu shortcutにする
- shortcutをterminal／navigatorのfirst responderに依存せず、既存shared actionへexactly once dispatchする
- treeの空queryで`Return`を選択folderのexpand／collapse toggleにする
- `Command+Right`はexpand、`Command+Left`はselected folderまたはnearest expanded ancestorのcollapseとして維持する
- 検索結果、file row、modifier付きReturnでは誤ってtree stateを変更しない
- action catalog、key routing、directory state、reference、README、FEATURE_MATRIX、manual checklist、製品runtimeを更新・検証する

## 対象外

- Context Dockの幅、固定details、検索scope／ranking、path handoffの変更
- mouse disclosure control、double-click、breadcrumb navigationの追加
- SSH／remote directory provider
- shortcut設定UIやnative menu shortcutのremap機構追加

## 依存関係と設計方針

- `TerminalActionCatalog`がnative menu shortcutの単一authorityであり、AppKit key equivalentはraw terminal／navigator key routingより先に処理される。
  `Option+Shift+C`はcatalog metadataへ追加し、既存toggle registration／availability／focus handoffを再利用する。
- navigator key controllerは`Return`を新しいtree toggle intentへ変換する。directory controllerだけがselected rowとexpanded setを所有するため、
  実際のexpand／collapse判定はcontrollerで行い、key controllerへfilesystem stateを複製しない。
- toggle collapse後もselected rowは閉じたfolder自身に残す。既存`Command+Left`のchild rowからnearest ancestorへ戻す挙動は変更しない。
- すべてのnavigator-owned keyは従来どおりPTYへfall throughさせず、tree mutationはqueryが空かつlocal projectionがliveな場合だけ許可する。

## 完了条件

- 通常起動で`Option+Shift+C`を押すたびにContext Dockが表示／非表示になり、terminalへのPTY writeは0である。
- Navigatorがinputを所有中にshortcutでDockを閉じた場合も、terminal first responderを安全に復元してから非表示にする。
- collapsed folder上の`Return`で1 levelをlazy展開し、同じfolder上の再度の`Return`でsubtreeを閉じる。
- `Command+Left／Right`、Option+Return、検索、file selection、Escapeの既存契約に回帰がない。
- format、analysis、focused tests、generated freshness、full `make test`、Developer JIT／Release AOT製品受け入れ、通常GUI確認が成功する。

## 検証方針

- action registry testで`shift+option+c` shortcut identity、既存shortcutとの一意性、View menu projectionを固定する。
- Context Dock key/controller testでReturn toggle intent、expand→collapse、selection保持、file／search no-op、既存左右intentとOption+Returnを検証する。
- native/product acceptanceでtoggle actionとfolder stateがPTY writeなしにexactly once更新されることを確認する。
- generated keybinding/action referenceと派生acceptance hashを更新し、両runtimeと通常Developer JIT GUIで実shortcutを確認する。

## 調査記録

### 2026-09-15 着手

- branchは`codex/context-file-navigator-roadmap`、working treeはclean。直前の固定details改善はcommit `ebea173`で完了している。
- ROADMAPの次項目は主要ゴール後の低優先follow-upだったため、本改善をContext Dock親項目の末尾へ追加し、親を作業中へ戻した。
- `TerminalActionCatalog.standard`の`view.toggle-context-dock`はshortcutなし。`view.search-files-and-folders`はnative
  `Shift+Command+F`を持ち、native action key equivalentがfirst responderより先に共有dispatcherへ届く既存境界がある。
- `TerminalContextDockKeyController`はplain `Return`を常に`expand` intentへ変換する。directory controllerはexpanded folderへの
  `expand`をfalseで返すため、再度のReturnはno-opになる。一方、`Command+Left`の`collapse` intentはselected expanded folder、
  またはselected childのnearest expanded ancestorを既に閉じられる。
- 採用案はnative action shortcutへ`Option+Shift+C`を追加し、plain Return専用の`toggle` intentを新設する。既存left／right intentと
  directory ownershipを保ったまま最小差分で対称な操作になる。

### 2026-09-15 実装とfocused検証

- `TerminalActionCatalog.standard`の`view.toggle-context-dock`へkey equivalent `c`、Shift、Optionのnative shortcutを追加した。
  stable action ID、registration、availability、Navigatorからhideする前のterminal focus復元処理は既存実装をそのまま再利用する。
- `TerminalContextDockTreeIntent.toggle`を追加し、plain Returnだけをこのintentへ割り当てた。directory controllerはselected rowが
  expanded folderならそのpathをcollapseし、collapsed folderなら既存bounded lazy loadを開始する。file rowとnon-empty queryはfalseで
  返し、stateを変更しない。
- collapse後の共通処理をlocal helperへ集約した。Return toggleはfolder自身へselectionを残し、Command+Leftは従来どおりselected childから
  nearest expanded ancestorへselectionを戻す。Command+Right、Option+Return、Escapeのkey routingは変更していない。
- config testへ`shift+option+c`を追加し、native menu shortcutとして予約され任意keybindへ重複割当されないことを固定した。
  action registry testはshortcut identityを`shift+option+c`として固定し、catalog全体の既存duplicate検査も通る。
- Context Dock unit testはfolderのtoggle expand→collapse→reopen、selection保持、file no-op、search no-op、key controllerのReturn toggle intentを
  検証する。native-content製品scenarioにもreal local directoryをReturnで展開後、再度Returnで閉じ、PTY writeが0のままである確認を追加した。
- README、FEATURE_MATRIX、設計memo、manual checklistをshortcutとReturn開閉へ同期した。SSH／remote provider、検索、固定details、
  path handoffの仕様は変更していない。
- 最初の実装後`dart analyze`はnative-content scenarioからscope外の`actionCatalog`を参照した1件だけで失敗した。dispatcherが公開する
  同一catalogを`dispatcher.catalog`から参照するよう修正し、再解析で指摘0を確認した。shortcutの実装やruntime挙動の失敗ではない。
- 通常GUIではterminal focus中の`Option+Shift+C`によるshow／hideは成功した。その直後、hidden状態から`Shift+Command+F`で検索へ入ると、
  detached editorをfirst responderへ設定しようとして`AppKitNativeException`で終了する既存のre-show競合を再現した。hide時にnative windowが
  terminal rootをouter splitからreparentしてもDart wrapperのchild identityは残るため、再表示時のidentity比較だけでは`setChildren`が省略されていた。
- presenterの`projectedVisible == false`もroot再接続条件へ含め、hidden→visible遷移ではouter split childrenを必ず1回だけ再attachする。
  表示中の通常reconcileでは従来どおり再attachせずfirst responderを保持する。fake AppKit testへhide前後のchild attachment countを追加した。
- 再接続修正後の同じGUI手順ではeditor attachment例外は解消したが、検索focus requestがstaleとして終了した。再表示layoutの冒頭で、
  detached中にAppKitが変更したouter split fractionを`_captureNativeWidth`が読み、window-owned widthとgenerationを更新していたためである。
  native dividerはDockが実際にprojected visibleな間だけ利用者操作のauthorityになる。`projectedVisible`をwidth capture条件にも追加し、hidden splitの
  stale fractionを無視する。fake testではhidden中のfractionを意図的に0.2へ変え、search re-show後も保存済み399.5 ptとfocus requestが維持されることを固定する。
- hidden divider captureを止めた後も、re-show reconcile中のdirectory result-count同期という正当なmodel更新によりwindow generationが進み、
  requestがstaleになった。検索要求時のquery-selection generationとtargetを保持し、hierarchy projection直後に同じtarget／visibility／selection requestで
  あることを再検証してから、最新window generationへfocus requestをrefreshする。focusからownership確定までは同期処理なので、その後にgenerationが
  変われば従来どおりfail closedになる。coordinator testではprojection callback中にresult countを変更し、このbenign generation更新を受理する。
- `dart format`: 対象7 filesを確認し、変更2 filesを整形後、再実行は変更0。
- `dart analyze`: 修正後は指摘0。
- `dart run test/terminal_action_registry_test.dart`: 成功。
- `dart run test/terminal_context_dock_test.dart`: 成功。
- `dart run test/terminal_key_binding_test.dart`: 成功。
- `dart run test/terminal_config_test.dart`: 成功。
- `dart run test/terminal_native_hierarchy_test.dart`: 成功。
- 最終コードから生成資料5件を再生成した。`keybindings-and-actions.md`は`shift+option+c`をnative予約shortcutとして反映し、
  AppKit acceptance、regression coverage、Ghostty gap inventory、daily-use matrixのsource hashも最新化した。
- 通常Developer JIT GUIの最終確認では、terminal focus中の`Option+Shift+C`でshow→hide、hide直後の`Shift+Command+F`で
  Dock再表示とNavigator focus、同じfolder行でのReturnによるexpand→collapse、Navigator focus中の`Option+Shift+C`によるhideと
  terminal focus復元がすべて成功した。終了前5秒間にruntime errorはなく、PTYへのshortcut／tree key流入もなかった。
- 最終`make RUNTIME_ARCH=arm64 runtime-native-content-integration`の1回目は、Dock scenarioへ入る前に既存の
  `plain local sh did not expose an echo-on idle-shell boundary`でDeveloper JITが終了した。PTY起動時のecho-on待機境界を観測できない
  timing failureであり、今回変更したaction、Navigator、AppKit projectionへ到達する前の失敗だった。同じコマンドを再実行して再現性と
  製品scenario本体を確認する。
- 同じ統合コマンドの2回目も同じ起動前境界で終了した。診断用に一時的なsnapshot文字列を追加したDeveloper JIT単体の3回目は
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`で完走し、一時変更を戻した最終コードで統合コマンドを再実行するとDeveloper JIT／Release AOTの
  両方が成功した。最終成功結果はそれぞれ`navigator=true`、`exact_pty=true`、`sessions=4`。起動fixtureのecho-on観測にはtiming上の揺らぎが
  あるが、最終製品コードで今回のshortcut／folder toggleを含む両runtime scenarioが通ることを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。346 filesのformat変更0、`dart analyze`指摘0、全unit／integration／security／
  generated checksが成功した。
- 生成物freshnessを個別に再確認した。keybind referenceは`standard_bindings=9`、`reserved_shortcuts=15`、Phase 7 AppKit acceptanceは
  `criteria=5`、`source_refs=19`、`unit_tests=16`、`integration_tests=5`、`ui_assertions=11`。regression coverage、Ghostty gap inventory、
  daily-use matrixもすべてPASSした。
- `git diff --check`: 空出力で成功。変更は本タスクのaction／Context Dock実装、対応test／docs／生成物だけで、debug用の一時変更は残していない。

## 完了判断

- `Option+Shift+C`はterminal／Navigatorのどちらがfirst responderでもContext Dockをshow／hideし、hide時はterminalへfocusを戻す。
- plain Returnは選択folderをexpand／collapseし、collapse後もそのfolderを選択したままにする。file／検索結果はno-opで、既存の
  `Command+Left／Right`と`Option+Return`を維持した。
- unit、native hierarchy、通常GUI、Developer JIT、Release AOT、full suite、生成物freshnessの完了条件を満たした。未実装の残作業や阻害要因はない。
