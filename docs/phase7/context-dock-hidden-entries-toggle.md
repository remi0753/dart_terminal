# Context Dock hidden file and folder toggle

- Status: complete
- Date: 2026-09-15
- Scope: Directory Navigatorのdot-prefixed file／folder可視性と`Shift+Command+H` action
- Related: UI-05、AX-01、AX-02、IN-09、SEC-01

## 目的と背景

Context Dockは現在、working directoryと展開済みsubtreeのdot-prefixed entryを常に表示する。通常の作業では隠しentryを省いて
主要なfile／folderへ集中したい一方、設定fileやrepository metadataを参照するときは即座に再表示したい。
`Shift+Command+H`で表示／非表示を切り替え、terminal／Navigatorのどちらがinput ownershipを持つ場合も同じfocused paneへ適用する。

## 範囲

- paneごとに保持するhidden entry visibility state。既存互換のため初期値は表示
- `view.toggle-hidden-files` stable action、View menu、Command Palette、既定`Shift+Command+H` shortcut
- working-directory tree、展開済みsubtree、Search result、Go To matchへの同一visibility policy
- visibility変更後のselection clamp、pending reveal／非同期resultの安全な再投影
- English／Japaneseのaction copyとNavigator上の現在状態表示
- unit、fake AppKit、product native-content、両runtime、reference／README／FEATURE_MATRIX更新

## 対象外

- filesystem上のfile属性変更、Finder hidden flag、glob設定
- file content検索、ignore file／`.gitignore` semantics
- system-wide永続設定やpane restoration schemaの変更
- SSH／remote filesystem provider

## 依存関係とリスク

- visibilityはfilesystem snapshot取得ではなくprojection境界で適用し、再表示時に不要な再walkを行わない。
- dot-prefixed判定はpath全体ではなくentry名の先頭で行う。隠したdirectoryのdescendantはtree／current-subtree resultからも見せない。
- wide Searchの外部root resultもentry自身または検索rootからのrelative componentがdot-prefixedなら除外する必要がある。
- hidden selectionを除外した直後は既存result count更新でselectionをvisible rangeへclampする。hidden targetへのpending revealは中断し、
  hidden非表示中のGo Toはhidden entryを選択しない。
- shortcutはnative menuが先に所有し、terminalへ`Cmd+Shift+H`相当byteを送らない。actionはinput ownershipやDock visibilityを変更しない。

## 完了条件

- `Shift+Command+H`を押すたび、focused paneのdot-prefixed file／folderとそのhidden subtreeが非表示／表示になる。
- tree、Search、Go Toで同じvisibilityになり、hidden非表示中にhidden targetが選択・revealされない。
- Dock内に現在の`Hidden: Shown`／`Hidden: Hidden`相当がEnglish／Japaneseで表示される。
- toggleはterminal／Navigatorどちらからもexactly once動作し、focus、query、expanded stateを保持し、PTY writeは0。
- pane切替では各paneのvisibility stateが独立して保持され、既存paneは初期状態でhidden entryを表示する。
- format、analysis、focused/full tests、generated freshness、Developer JIT／Release AOT native-contentが成功する。

## 検証方針

- state/action: per-pane default／toggle retention、shortcut identity、availability、terminal／Navigator ownership、pane切替。
- directory: root／nested hidden entry、hidden directory descendant、Search／Go To、selection clamp、toggle round-trip、stale reveal。
- native hierarchy: View action、document copy、focus／editable不変。
- product scenario: 実plain shellのdotfileを両ownershipからtoggleし、表示とPTY write delta 0を確認する。
- docs／generated artifact freshness、両runtimeと通常full gateを実行する。

## 判明事項と判断

- 2026-09-15着手時、branchは`codex/context-file-navigator-roadmap`、基点は`c9cefba`、worktreeはcleanだった。
  `TerminalDirectoryEntrySnapshot.isHidden`はlocal snapshot時点でbasenameの先頭`.`から既に算出されており、従来のroot tree testは
  `.hidden`を表示する契約だった。このためfilesystem snapshotは全entryを保持したまま、Context Dockのtree／Search／Go To projectionで
  visibilityを適用する方式を採用した。
- visibilityは`TerminalContextDockPaneSnapshot`の`showHiddenEntries`としてpaneごとに保持し、初期値を`true`とした。focused paneを
  切り替えても値は独立して残り、新規paneは表示状態から始まる。actionはstable ID `view.toggle-hidden-files`、既定
  `shift+command+h`、View menu／Command Palette共通とし、dispatch後のterminal focus復元を無効にして現在のinput ownerを保つ。
- treeでは各levelの`isHidden` entryをprojection時に除外する。Search／Go Toはcwdからのrelative path componentを調べ、dot-prefixed
  directory配下のvisible basenameも同時に除外する。cwd自体が`.config`などのhidden path配下でも、そのcwdより上のcomponentを理由に
  全entryを隠さない。system index由来でcwd外の結果はabsolute path componentを同じpolicyで確認する。
- hiddenをoffにした時はhidden subtreeのin-flight child loadとGo Toをcancelするが、取得済みsnapshotとexpanded setは保持する。
  これにより再表示は不要なroot再walkなしで復元できる。結果数の再公開を通してhidden row上のselectionをvisible rangeへclampし、
  pending revealもhidden targetなら中断する。Search query、Go To query、Navigator mode、terminal／Navigator ownershipは変更しない。
- Navigator documentにはmode行の直後へEnglish `Hidden entries: Shown/Hidden`、Japanese `隠し項目: 表示/非表示`を追加した。
  query caret offsetはdocument構築後の位置から算出されるため、status行追加後もzero-length caret contractを維持する。

## 検証記録

- `dart format`は対象8 Dart fileを処理し、4 fileを整形した。続けたsandbox内`dart analyze`はcode解析自体で
  `unnecessary_non_null_assertion`を1件検出し、修正した。一方、analytics session fileのmtimeを
  `/Users/remi/.dart-tool`へ書けずcommandは失敗した。
- sandbox内のfocused testはMetal module cacheを`/Users/remi/.cache/clang`へ作れずbuild hookで失敗した。code failureではなく
  filesystem制約なので通常cache accessで再実行した。
- 通常cache accessで`test/terminal_context_dock_test.dart`、`test/terminal_action_registry_test.dart`、
  `test/terminal_native_hierarchy_test.dart`を個別実行し、すべてexit 0。pane-local default／toggle、Terminal／Navigator focus不変、
  nested hidden directoryのSearch／Go To、selection clamp、shortcut identity、Japanese document copyを受け入れた。
- 正規generator 5種を再生成し、freshness gateも成功した。keybind/action referenceはphysical key 105、pane action 4、
  application action 43、standard binding 9、reserved shortcut 18。Phase 7 acceptanceはcriteria 5、source reference 19、unit test 16、
  integration test 5、UI assertion 11。compatibility regressionは9 case／390 input byte／417 split run／9 fix family、
  actionable P0/P1 gap 0、release blocker 0を維持した。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=release-aot ... navigator=true exact_pty=true sessions=4 elapsed_ms=4430`。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 最終再実行で成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=developer-jit ... navigator=true exact_pty=true sessions=4 elapsed_ms=5583`。
  両modeで実plain shのcwdに作ったhidden file／folderをTerminal ownershipから非表示、Navigator ownershipから再表示し、
  native status copy、focus維持、PTY write delta 0を確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。346 Dart fileのformat変更0、analysis issue 0、全native package、
  localization/privacy、generated freshness、compatibility/application/distribution testを完走し、`dart_terminal tests passed`で終了した。
- `git diff --check`: 成功。

## 失敗した試行と確認結果

- 最初のgenerator実行はsandbox内でanalytics session fileのmtimeを更新できず、dependency targetで終了した。通常cache accessで
  同じ5 targetを再実行し、すべて生成・freshness検証に成功した。
- Developer JIT native-contentの1回目は新しいhidden toggleへ到達する前のplain-sh echo-on idle境界、2回目はhidden toggleを含む
  Navigator一連の検証後に既存context Quick Look dispatch timingで失敗した。Release AOTは同じsourceで全scenarioに成功し、
  Developer JITの3回目も全scenarioに成功したため、新機能の決定的な失敗ではなく既存の非同期製品fixture境界と判断した。

## 実装結果

- `Shift+Command+H`は`view.toggle-hidden-files`としてnative View menu、Command Palette、生成keybind referenceへ公開した。
- hidden visibilityはfocused paneごとのstateで、従来互換の表示状態から始まる。切替はDock visibility、input owner、mode、query、
  expanded setを変更しない。
- root／lazy subtree、Search、Go Toへ同じdot-component policyを適用し、hidden directory配下の通常名entryも除外する。
  非表示時のhidden load／revealをcancelし、selectionをvisible rangeへ補正する。再表示時は保持snapshotから復元する。
- Dock documentはEnglish／Japaneseで現在のhidden visibilityを常時示す。SSH／remote provider、Finder hidden flag、`.gitignore`、
  永続設定は対象外のままである。

## 残課題

- 本taskに残る実装・検証blockerはない。外部VoiceOver／Full Keyboard Accessでの読み上げと物理key確認は既存の
  [Directory Navigator manual checklist](context-dock-directory-navigator-manual-checklist.md)へ追加した。
