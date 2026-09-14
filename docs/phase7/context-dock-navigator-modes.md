# Context Dock Navigator modes and tree reveal

- Status: in progress
- Date: 2026-09-15
- Scope: Directory NavigatorのSearch／Go To／Move mode、native caret、検索結果からtree操作へ戻る経路
- Related: UI-05、AX-01、AX-02、IN-09、SEC-01

## 目的と背景

Directory Navigatorで`Shift+Command+F`を使ってquery入力へ移ったことを、点滅するnative input caretで明確にする。
また、広域検索結果は現在tree rowではないため、選択したfolderをReturnで展開できない。検索とは別に、current working
directoryのtreeを表示したまま文字列で選択位置へ移るGo Toと、文字入力せずtreeだけを操作するMoveを追加する。

## 操作モデル

- **Search** — `Shift+Command+F`。current subtreeからrecent／explicit root／system indexまでの既存progressive
  search resultを表示する。query末尾にnative caretを表示して点滅させ、文字入力とBackspaceはSearch queryだけを変更する。
- **Go To** — `Shift+Command+G`。working-directory treeを表示したまま、独立したqueryに一致するfile／folderへ選択を移す。
  深いmatchはcurrent subtreeだけをbounded searchし、必要なancestorだけをlazy展開してrevealする。対象folder自体は選択に留め、
  Returnで明示的に展開できる。
- **Move** — `Shift+Command+M`。working-directory treeを表示し、文字入力用caretを出さない。Up／Down／Page、Return、
  `Command+Left／Right`、path actionだけを受け付ける。
- Search result上のReturn／`Command+Right`は、選択pathがcurrent working directory配下ならMoveへ切り替え、ancestorを展開して
  tree rowを選択する。folderなら対象自体も展開し、直後からchildrenを操作できる。working directory外の広域resultは暗黙に
  tree rootやterminal cwdを変更せず、Searchと選択を維持する。
- `Escape`はどのmodeでもqueryとtree contextを保持してterminalへ戻る。各native shortcutはterminal／Navigatorのどちらが
  first responderでも同じshared actionをexactly once実行し、PTYへbyteを送らない。

## UI／caret contract

- Navigator documentに現在のmodeを文字で表示し、SearchとGo Toだけにmode固有のquery行を表示する。Moveではtree操作のhintを表示する。
- Search／Go ToでNavigatorがfirst responderの間だけnative text editorをeditableかつzero-length selectionにし、AppKit標準の
  insertion caret／blinkを使う。windowは`dartOnly` key routingのままなので、入力はnative documentを直接変更せずDart-owned
  bounded queryへ一度だけ適用される。
- result selectionは既存のfull-width line highlightで示し、caretとは同時に区別できる。resultをscroll into viewするための一時selectionは
  scroll後にquery caretへ戻す。Moveまたはterminal ownershipではeditorをread-onlyへ戻し、caretを残さない。
- `Command+A`はSearch／Go To queryだけを選択する。Moveでは消費するがtree stateやterminal inputを変更しない。

## 範囲

- per-pane Navigator modeとSearch／Go Toの独立query retention
- `view.goto-file-or-folder`と`view.move-in-directory-navigator`のstable action、View menu、palette、既定native shortcut
- mode-aware key routing、document copy、native editable／selection projection、accessibility state
- visible tree match、bounded current-subtree Go To、search resultからtreeへのgeneration-safe reveal、ancestor lazy load
- mode切替、query変更、pane／cwd変更、hide、privacy、dispose時のsearch／reveal cancellation
- unit、fake AppKit、native-content product scenario、通常GUI、reference／README／FEATURE_MATRIX／manual checklist更新

## 対象外

- terminal scrollbackの検索、file content検索、Finder起動、preview／editor
- working directory外のresultを新しいtree rootにするbrowse history
- terminal processのcwd変更、自動`cd`、Returnによるshell command実行
- SSH／remote provider、network filesystem mirror
- configurable keybindへのnative shortcut移行

## 依存関係とリスク

- `TerminalContextDockState`がper-pane mode/query/selection generationを所有し、directory controllerはfilesystem resultとtree expansionを所有する。
- `TerminalFileSearchService`の既存entry／directory／depth／deadline capをGo Toにも再利用する。Go Toはcurrent subtree以外を走査しない。
- reveal対象はnormalized absolute pathかつresolved working directoryのdescendantだけを受理し、最大expanded directory数を越える場合は無変更で拒否する。
- editable native editorにcanonical stateを持たせない。key routingはNavigator ownership中ずっと`dartOnly`とし、再projectionでDart documentをauthorityにする。
- mode／query切替中の非同期resultはmode、pane、cwd、query、generationを再検証し、staleなら破棄する。

## 分割と実施順

1. **Search／Go To／Move modeとnative input caret**
   - mode、独立query、2つのaction／shortcut、mode-aware editing／tree key、表示copyをpure Dartとfake AppKitで固定する。
   - Go Toは現在visibleなtree rowに一致した時点でselectionを移し、Moveはquery mutationを行わない。
   - native editorはSearch／Go To ownership時だけeditableなzero-length caretを投影し、terminal／Moveでread-onlyへ戻す。
   - focused test、format、analysis、reference freshness、task memo、ROADMAPを更新して個別commitする。
2. **Search／Go To resultからtreeへのrevealとfolder展開**
   - Go Toをbounded current-subtree matchへ拡張し、ancestor snapshotをlazy loadしてselectionをrevealする。
   - Searchのcurrent-root resultをReturn／Command+RightでMove treeへ移し、folder targetは展開する。外部resultはfail closedにする。
   - product runtime、通常GUI、full gate、docs／generated artifactを更新し、親項目を完了して個別commitする。

先行subtaskが完了するまで後続subtaskへ着手しない。

## 完了条件

- `Shift+Command+F`でSearch query末尾のnative caretが見え、AppKit標準周期で点滅する。result highlightとcaretを同時に識別できる。
- `Shift+Command+G`でtreeを保ったままGo To queryを入力し、current subtree内のmatchへ移動できる。
- `Shift+Command+M`でtree-only Moveへ入り、printable／BackspaceはqueryやPTYを変更せず、navigation／folder開閉は動作する。
- Searchで選んだcurrent-root folderをReturnするとtree上へ移動して展開され、そのchildrenを続けて選択できる。
- Search／Go To queryはmode別に保持され、mode切替やEscapeで失われない。pane／cwd変更ではstale resultを適用しない。
- shortcut、editing、navigation、reveal、failure、focus復元の全経路で、明示したOption-Return以外のPTY writeは0。
- format、analysis、focused/full tests、generated freshness、Developer JIT／Release AOT、通常GUI確認が成功する。

## 検証方針

- state/action test: mode別query保持、shortcut identity／重複、focus generation、Move editing no-op、Search／Go To caret selection。
- directory test: visible match、deep descendant reveal、ancestor ordering、folder target expand、file target select、external／stale／cap rejection、cancellation。
- fake AppKit: `isEditable`、zero-length selection、line highlight、scroll追従、first responder、mode切替後read-only、balanced teardown。
- product acceptance: 実plain local sh cwdで3 modeを切り替え、Search folderからtree childへ進み、全操作のPTY write delta 0を照合する。
- actual GUI: caretの表示と2 phase以上のblink、shortcut、mode copy、deep reveal、Escape／Dock hide/showをDeveloper JITで目視する。

## 調査記録

### 2026-09-15 着手

- branchは`codex/context-file-navigator-roadmap`、working treeはclean。直前のContext Dock shortcut／folder toggleはcommit
  `5992521`で完了している。
- 現在のstateはpaneごとにqueryを1つだけ持ち、non-emptyなら常にwide searchへ切り替わる。Navigator ownership自体にmodeはない。
- presenterはread-only `NSTextView`へqueryとrowを1 documentとして投影し、first responder取得時はquery全体をselectionする。
  resultがあればnative zero-length selectionをrow先頭へ置くため、query insertion caretは表示されない。
- `dart_appkit`の`TextEditor`はeditable、zero-length selection、foreground色のinsertion pointを既に提供する。windowを`dartOnly` routingに
  保てばnative editorへkeyをfall throughさせず、AppKit標準caret blinkだけを利用できるためdependency追加は不要。
- directory controllerはquery non-empty時をsearch projectionとして扱い、tree intentを一律拒否する。既存search resultはabsolute pathと
  sourceを保持するため、current working directory内のpathだけをancestor expansionへ変換できる。
- 採用案はmodeをper-pane stateへ追加し、Search／Go To queryを別々に保持する。Moveはqueryを持たず、tree projectionのままkey navigationを
  所有する。wide Searchとcurrent-tree Go Toを分離することで、検索範囲を狭めずにtree操作への明示的な復帰経路を作る。

### 2026-09-15 実装中の検証環境

- 最初の`dart analyze`は解析前に`/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`への書き込みを試み、sandboxで拒否された。
  `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`へ切り替えると解析は成功し、source上のissueは0件だった。
- action／state／native hierarchy／localizationのfocused testを4 processで同時実行したところ、Metal build hookが共通の
  `/Users/remi/.cache/clang/ModuleCache`へmoduleを書けず、test本体へ到達する前に全processが失敗した。コードの失敗ではなくsandbox上の
  cache ownershipが原因だった。`CLANG_MODULE_CACHE_PATH=/private/tmp/dart-terminal-clang-module-cache`も試したが、Metal driverは引き続き
  `$HOME/.cache/clang`を参照したため回避できなかった。以後のMetal build hookを伴う検証は許可済みの通常ユーザー環境で逐次実行した。

### 2026-09-15 Search／Go To／Move modeとnative caret

- pane stateに`search`、`goTo`、`move`を追加し、SearchとGo Toのqueryを独立して保持する。Moveはquery mutationを拒否し、printable、
  Backspace、`Command+A`をPTYへ流さず消費する。既定modeはtree操作が可能なMoveとした。
- stable action `view.goto-file-or-folder`（`Shift+Command+G`）と`view.move-in-directory-navigator`
  （`Shift+Command+M`）を追加した。既存Searchを含む3 actionはいずれもNavigatorへownershipを移し、native shortcutからexactly once実行する。
- Search／Go To ownership中のnative editorだけをeditableにしてquery末尾へzero-length selectionを投影し、AppKit標準のinsertion caretと
  blinkを使う。window routingは`dartOnly`のままで、document編集のauthorityはDart stateに維持する。Move、Escape後、terminal ownership中は
  read-onlyへ戻す。
- Go Toは第一段階として現在表示済みのtree rowだけを照合し、tree projectionを置換せず最初のmatchへselectionを移す。深いdescendantの
  bounded searchとancestor revealは次の順序付きsubtaskで実施する。
- native hierarchy testの初回実行では、mode切替がresult countをresetした後もtest harnessの`onChanged`がpresenterだけをreconcileしていたため、
  selected line参照が`RangeError`になった。productionと同じくdirectory controllerの`synchronize`を先に呼ぶようharnessを修正し、再実行で成功した。

#### 検証結果

- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- `dart format --output=none --set-exit-if-changed`（変更した8 Dart file）: 成功、変更0。
- `terminal_action_registry_test.dart`、`terminal_config_test.dart`、`terminal_context_dock_test.dart`、
  `terminal_native_hierarchy_test.dart`、`terminal_localization_test.dart`: すべて成功。
- canonical generator 5種（keybind/action reference、AppKit acceptance corpus、compatibility regression coverage、Ghostty gap inventory、
  daily-use matrix）: 成功。
- freshness check 5種: すべて成功。集計はapplication actions 42、reserved shortcuts 17、AppKit criteria 5／unit tests 16／
  integration tests 5／UI assertions 11、regression cases 9、actionable P0/P1 gap 0、daily-use blockers 0。
- `git diff --check`: 成功。

第一subtaskの完了条件を満たした。deep Go ToおよびSearch resultからtreeへのrevealは未実装であり、次subtaskとして追跡を継続する。
