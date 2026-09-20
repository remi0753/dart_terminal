# Phase 7 — Context Dock manual content switch

## 目的

foreground processの実行中にContext DockがProcess Inspectorを表示していても、keyboardだけで
Directory Navigatorへ切り替え、必要なら同じ操作でProcess Inspectorへ戻せるようにする。

## 背景

2026-09-20時点では、foreground processが75 ms以上安定すると
`TerminalContextDockProcessController`がDock contentをProcess Inspectorへ自動切替し、command終了まで
Directory Navigatorをsuspendする。Search／Go To／Move shortcutはProcess Inspector中にPTYへ漏れないが、
長時間commandを実行しながらfile treeを参照する操作経路はない。

## 範囲

- liveなforeground jobについて、Process InspectorとDirectory Navigatorの表示を手動で切り替える。
- 同じforeground identityの間だけoverrideを保持し、job終了、別pane／session／PGID、Dock非表示、
  privacy失効、disposeで解除する。
- process inventoryのbounded観測は継続し、Process Inspectorへ戻した時に同じjobの情報を表示する。
- 切替自体はterminal input focusを維持し、PTYへbytesを書かない。Directory表示後のSearch／Go To／Moveは
  既存actionを明示した時だけNavigator inputへ移す。
- View menu、Command Palette、設定可能なstable action、既定native shortcutを同じdispatcherへ接続する。
- English／Japanese localization、生成keybinding reference、README、feature matrix、manual checklistを更新する。

## 対象外

- foreground processのcwdを新たに推測すること、remote／SSH filesystem provider。
- process sampling interval、argv表示policy、Secure Keyboard Entry policy、path insertion admissionの緩和。
- overrideの設定／restorationへの永続化、processごとの初期表示設定。

## 依存関係

- `TerminalContextDockProcessController`のwindow／pane／session／PGID identityと250 ms poll。
- `TerminalContextDockDirectoryController`のtrusted local cwd、privacy、generation-safe snapshot。
- shared `TerminalActionCatalog`、native View menu、Command Palette、keybind reference generator。
- `TerminalContextDockDirectoryPresenter`のcontent-mode排他的projection。

## shortcut選定

- 採用候補は`Control+Shift+Command+N`。NをNavigatorのmnemonicとする。
- 現行catalogのnative shortcut／11 standard keybindに同じchordはない。
- AppleのmacOS／Terminal標準一覧では`Shift+Command+N`がFinderのNew FolderおよびTerminalのNew Command、
  `Control+Command+N`がFinderのselection folderおよびTerminalのsame-command windowに使われる。
  三修飾の`Control+Shift+Command+N`は掲載された標準shortcutと重複しないため、単純なN系shortcutを避けて採用する。
- 確認資料はApple公式の
  [Macのキーボードショートカット](https://support.apple.com/en-au/102650)と
  [Terminalのキーボードショートカット](https://support.apple.com/en-ke/guide/terminal/trmlshtcts)。
- macOSは利用者がshortcutを変更できるため、user-defined overrideとの絶対的な非衝突までは保証しない。

## 完了条件

- stable foreground jobで既定shortcut、menu、palette、custom keybindのいずれからもDirectory表示へ切り替わる。
- 同じactionを再実行すると、同一jobのProcess Inspectorへ戻る。
- 切替の前後でterminal focus、process identity、elapsed更新、Navigator stateを保ち、PTY writeは0である。
- job終了後はfresh Directory Navigatorへ戻り、次のjobではProcess Inspector自動表示が復帰する。
- manual secure input、ECHO-off privacy、stale pane／session／PGID、hidden DockではDirectoryを表示しない。
- unit、native hierarchy、action／menu／localization、Developer JIT／Release AOT product acceptanceが成功する。

## 検証方針

- process controller unitでtoggle、同一job sampling、toggle back、identity／privacy／visibility失効を検証する。
- action registry／menu／localization testでstable ID、48 action、shortcut uniqueness、両言語を固定する。
- Context Dock presenter／native hierarchy testでDirectory／Processの排他的layoutとfocusを検証する。
- native-content runtime fixtureで実PTY foreground pipeline中にshortcutをdispatchし、tree表示、戻し、
  terminal focus、zero PTY write、終了後復帰をDeveloper JIT／Release AOTで確認する。
- format、analyze、全testと生成証跡freshnessを通す。

## 調査記録

### 2026-09-20 — 現行境界

- process controllerはforeground候補を75 ms待って`foregroundJob`へ入り、同じPGIDを最大1秒ごとに
  rich snapshot更新する。directory permissionはcontent modeが`directoryNavigator`かつ
  `directorySuspended == false`の場合だけ開く。
- presenterはcontent snapshotがdirectory modeならNavigator＋固定details、その他なら全高Process
  documentを排他的に表示する。切替用にnative viewを追加する必要はない。
- process中のNavigator actionは現在terminal focusへ戻され、PTY writeなしで消費される。
  表示override時だけ既存Navigator actionを再び利用可能にすればよい。
- filesystem privacyはprocess metadataより厳しく、manual secure inputまたはcommand中のECHO-offでは
  directory観測を拒否する。表示切替はこの境界を緩和しない。
- process snapshotを破棄してDirectory modeへ移すと戻す際に再取得待ちが生じる。内部process modeと
  bounded samplingを維持し、snapshot projectionだけをDirectoryへoverrideする方式を採用する。

## 実装記録

### 2026-09-20 — shared actionと表示override

- stable action `view.toggle-context-dock-content`をView menu、Command Palette、custom keybind、
  native shortcutへ追加した。英語名は`Toggle Directory Navigator / Process Inspector`、既定shortcutは
  `Control+Shift+Command+N`である。
- process controllerはforeground jobとrich snapshotを内部に保持したまま、window単位の
  `directoryNavigatorOverride`で外向きsnapshotだけをDirectory Navigatorへ切り替える。同じactionを
  再実行すると、再取得待ちなしで同じprocess identityへ戻る。
- Directoryへ表示を切り替えただけではNavigator inputを取得しない。Process Inspectorへ戻す時は、
  Search／Go To／MoveでNavigator input中だった場合もterminalへ確実に戻す。
- Directoryのprivacy callbackをprocess controllerへ渡した。manual secure input、command中のECHO-off、
  callback例外ではactionを無効化し、表示中にprivacyを失った場合もoverrideを即時解除する。
- job／pane／session／PGID／Dock visibilityの変更とdisposeは、既存のtransient-state cancellationと一緒に
  overrideを破棄する。次のjobは従来どおりProcess Inspectorから始まる。
- native content acceptanceへ、menu enable／checked state、Directory treeと固定details、同一jobへの復帰、
  terminal focus、zero PTY writeの検証を追加した。

## 検証記録

### 2026-09-20

- `dart run test/terminal_action_registry_test.dart`: 成功。
- `dart run test/terminal_context_dock_test.dart`: 成功。
- `dart run test/terminal_localization_test.dart`: 成功。
- `dart analyze`: `No issues found!`。
- `make keybind-action-reference`: 成功。application action 48件と既定shortcutを生成資料へ反映した。
- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`: 成功。Developer JIT／Release AOTの両方で
  Process InspectorからDirectory Navigatorへ切り替え、同一processへの復帰、terminal input維持、
  PTY write不変を実PTY pipelineで確認した。Release AOT証跡は
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... process_inspector=true exact_pty=true`。
- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`: すべて成功し、生成証跡を更新した。
- 初回の`make test`は無関係なPTY timing test
  `live Dart child cannot steal native PTY completion`が`Bad state: No element`で一度失敗した。
  `make dpty-dart-test`単独では全項目成功し、その後の`make test`再実行も全工程成功したため、
  今回の変更に起因する再現性のある失敗ではない。
- `dart format`は変更0件、最終`dart analyze`は成功、全体結果は`dart_terminal tests passed`。
- 文書編集時、manual checklistの周辺文言が想定と異なり複数ファイルpatchが一度適用されなかった。
  部分適用はなく、対象行を再確認して小さいpatchへ分けて更新した。
