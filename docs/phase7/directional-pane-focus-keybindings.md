# Directional pane focus and configurable split keybindings

更新日: 2026-09-14

## 目的

split pane間のactive focusを方向キーで直感的に移動できるようにする。既定では
Command+Left/Right/Up/Downを方向別pane focusへ割り当て、現在同chordを使うdivider移動は
Shift+Command+Left/Right/Up/Downへ移す。focusとdividerの全chordを既存`keybind`設定で
上書き、unbind、passthrough可能にする。

## 背景

- 現在は`pane.focus-previous`／`pane.focus-next`だけがvisual orderを循環し、方向別focus
  actionはない。
- Command+矢印は`pane.move-divider-*`のnative menu shortcutである。AppKitがraw terminal
  key routingより先に消費し、config parserもreserved native chordとして拒否するため、
  `keybind`では上書きできない。
- configurable keybinding engineはpane／application action、ordered override、`unbind`、
  `passthrough`、live reloadを既に通常製品へ投影している。

## 範囲

- `pane.focus-left|right|up|down`のstable application actionとEnglish/Japanese copyを追加する。
- 選択中tabのprojected split layoutから、focused paneに最も近い同方向のpaneを決定する。
- 4方向focusと4方向divider移動をnative menu予約から外し、設定可能なstandard bindingsにする。
- 既定chordをfocusはCommand+矢印、dividerはShift+Command+矢印とする。
- config file、command line、Settings document、live reloadからの既存ordered overrideを維持する。
- menu、Command Palette、key router、focus presentation、PTY write 0を通常製品で統合検証する。
- generated keybinding/action reference、README、FEATURE_MATRIX、acceptance evidenceを更新する。

## 対象外

- split作成、divider drag、equalize、zoomのgeometry contract変更
- window間またはtab間の方向移動
- pane端でのwrap（同方向候補がなければaction unavailableとして消費する）
- key sequence、複数stroke、ユーザー別GUI shortcut editorの追加
- userがcommit `691e97c`で調整したinactive paneのbrightness／scrim opacity変更

## 依存関係

- `TerminalSplitLayout.panes`のprojected logical-point rectangle
- `TerminalNativeHierarchyAdapter`のselected tab layoutとfocus mutation
- `TerminalProductHierarchyActionCoordinator`と`TerminalActionCatalog`
- `TerminalKeyBindingEngine.standardDefinitions`、config parserのnative shortcut予約導出
- `TerminalKeyEventRouter`のapplication action dispatchとlive configuration authority

## 分割と実施順

1. **split layoutに基づく4方向pane focus action**
   - direction enum、nearest-pane query／mutation、4 action ID、localization、coordinator registrationを
     追加する。
   - 交差軸が重なる同方向候補を優先し、その中で主軸距離を最小化する。tieはcross gap、
     cross-center距離、visual pane orderで決定する。
   - edge、nested split、zoom、未project／disposed状態をfail closedで検証する。
2. **focus／divider shortcutの設定可能な既定keybindへの移行**
   - 8 actionのnative `TerminalActionShortcut`を外す。
   - focusのCommand+矢印4件とdividerのShift+Command+矢印4件をstandard definitionsへ追加する。
   - standard bindingの総上限を維持し、configured occurrence上限を自動調整する。
   - default resolution、action override、unbind、passthrough、native reservation非衝突を検証する。
3. **通常製品へのlive投影、両runtime受け入れ、reference更新**
   - raw keyの既定focus／divider dispatch、live override、focus presentation、PTY write 0を
     通常製品acceptanceへ追加する。
   - menu／paletteは同じaction catalogを維持し、shortcut ownershipだけをkeybinding engineへ
     移す。
   - generated reference、configuration/help evidence、README、FEATURE_MATRIXを更新し、
     Developer JIT、Release AOT、full suiteを通す。

各subtaskは上記順に実装、検証、記録、ROADMAP更新、commitする。先行subtaskが完了するまで
次へ進まない。

## 完了条件

- split layout内でCommand+矢印によりactive paneが同方向の最適なpaneへ移る。
- Shift+Command+矢印は従来どおりnearest matching dividerを1 cell移動する。
- 8つの既定chordは`keybind`で別action、`unbind`、`passthrough`へ上書きできる。
- native menu reservationがこれら8 chordを先に消費しない。
- edge／zoom／未projectではfocus actionがfail closedで、別window/tabやPTYへ入力を漏らさない。
- focus変更後はactive cursor／inactive tintが正しいpaneへliveで移る。
- unit/native test、generated freshness、Developer JIT、Release AOT、`make test`が成功する。

## 検証方針

- application state/native hierarchy testでnested layoutの4方向候補、tie、edge、zoomを検証する。
- action registry/coordinator/localization testでstable ID、copy、availability、exact dispatchを検証する。
- key binding/config/product configuration testで8 defaultsとordered override/unbind/passthroughを検証する。
- product acceptanceでraw keyからactionをexactly once実行し、terminal write 0とactive surface移譲を
  Developer JIT／Release AOTの両方で確認する。
- generator、`dart format`、`dart analyze`、関連test、`make test`を実行する。

## 調査記録

### 2026-09-14 着手時

- branchは`main`、working treeはclean、`origin/main`より9 commit ahead。
- 直前のuser commit `691e97c update inactive screen params`はinactive background brightnessを
  0.68、scrim opacityを0.58へ変更している。本タスクではこの値を保持する。
- action catalogには33 actionがあり、divider 4 actionだけがCommand+矢印のnative shortcutを
  持つ。focusはprevious／nextのみでshortcutなし。
- native shortcut一覧からconfig parserのreserved chordが自動生成される。divider shortcutを
  catalogから外せば、同chordは設定可能になる。
- keybinding engineは1 standard definitionと最大1023 configured definitionsを合計1024に制限する。
  standardを9件へ増やすとschemaのconfigured上限は式により1015へ自動調整される。
- native hierarchyは選択tabごとの`TerminalSplitLayout`を保持し、全paneのleft/top/width/heightを
  logical pointで参照できる。方向候補の判断はnative view handleではなくこのimmutable layoutを
  authorityにできる。

## 検討と判断

- 既存previous／nextをCommand+左右へ割り当てる案は、上下移動とnested splitの空間関係を表せない
  ため不採用。4つのstable directional actionを追加する。
- native menu shortcutをShift付きへ単純変更する案は、引き続きAppKit予約となり`keybind`で
  上書きできないため不採用。8 chordをstandard configurable bindingとして所有する。
- 方向候補はwrapしない。同方向にpaneがないとき別端へ飛ぶと空間navigationと一致せず、
  誤操作時にactive paneが大きく移るためfail closedを採用する。
- divider actionをView menuから削除せず、native `TerminalActionShortcut`だけを外す。これにより
  menu／Command Paletteからの実行可能性を保ったまま、raw chordの所有権を設定可能な
  keybinding engineへ一本化できる。
- standard bindingへ8件を追加しても既存の総定義上限1024は変更しない。設定可能件数はschemaが
  `maximumDefinitionCount - standardDefinitionCount`で導出するため、1023件から1015件へ自動で
  調整される。

## 検証結果

### 2026-09-14 split layoutに基づく4方向pane focus action完了

- `TerminalPaneFocusDirection.left|right|up|down`とstable action
  `pane.focus-left|right|up|down`を追加した。既存previous／next traversalは互換性のため維持する。
- native hierarchyは選択tabの最新`TerminalSplitLayout.panes`から候補を選ぶ。交差軸が重なる
  候補、主軸距離、cross gap、cross-center距離、visual pane orderの順でdeterministicに比較する。
- candidateはfocused rectangleの対応edgeより完全に同方向にあるpaneへ限定する。端でwrapせず、
  zoom、未project、reconcile中、disposedではavailability queryがfalseになる。
- coordinatorへ方向別availability／mutation callbackと4 registrationを追加し、成功時だけ既存の
  reconcile／onChangedをexactly once呼ぶ。
- English／Japanese action copyとWindow menu catalog順を追加した。action catalogは37 stable
  application actionsとなった。shortcut ownershipは次subtaskで変更する。
- `dart format`（変更9 files）: 成功、5 filesを整形。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_product_hierarchy_actions_test.dart`:
  成功。方向availability、exact callback、projection countを確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_action_registry_test.dart`: 成功。
  stable ID、Window menu順、日本語copyを確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_native_hierarchy_test.dart`: 成功。
  2×2 nested splitの右→下→左→上、edge非wrap、zoom／未project無効を確認した。
- generated keybinding referenceとcurrent product acceptanceは後続subtaskでshortcut ownershipを
  確定後に一度だけ更新する。現subtaskの検証は生成物を参照しない関連unit/native testで完了した。

### 2026-09-14 focus／divider shortcutの設定可能な既定keybindへの移行完了

- divider 4 actionのnative menu shortcutを外した。focus 4 actionと合わせて8 actionともmenu上の
  key equivalentを持たず、AppKitのnative shortcut予約対象ではなくなった。
- standard definitionsを9件へ増やし、Command+Left/Right/Up/Downを
  `pane.focus-left|right|up|down`、Shift+Command+Left/Right/Up/Downを
  `pane.move-divider-left|right|up|down`へ割り当てた。Control+Dの既存EOF bindingは維持した。
- parserがcatalogのnative shortcutから予約chordを導出する既存contractにより、Command+矢印と
  Shift+Command+矢印はconfig file／CLIの`keybind`で受理される。`unbind`、別application action、
  `passthrough`へのordered overrideをunit testで確認した。
- 初回の`dart analyze`／`dart run`はworkspace外の
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`更新をsandboxが拒否して停止した。
  `dart analyze`は`DART_SUPPRESS_ANALYTICS=true`、testは`CI=true
  DART_SUPPRESS_ANALYTICS=true`として再実行し、製品コード由来でない環境制約を回避した。
- `dart format`（変更5 files）: 成功、3 test filesを整形。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_key_binding_test.dart`: 成功。
  9 defaults、exact modifier、別actionへの上書き、unbind、passthroughを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_config_test.dart`: 成功。
  両directional chordがnative reserved扱いされず、typed occurrenceになることを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_action_registry_test.dart`: 成功。
  8 actionのmenu shortcut非所有を確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_product_configuration_test.dart`: 成功。
  standard definitions増加後も既存profile／engine生成contractに回帰がないことを確認した。
- 通常製品raw key／live reload、両runtime、generated reference freshnessは次subtaskで検証する。

### 2026-09-14 通常製品へのlive投影、両runtime受け入れ、reference更新完了

- 通常製品user-action acceptanceは実`TerminalTextInputEventRouter`／`TerminalKeyEventRouter`へ
  Command+Left、Command+Right、Shift+Command+Rightを順に入力する。focusは右→左→右へ移り、
  `isPaneActive`が正確に1 surfaceへ投影されるため、既存contractによりcursor表示／inactive tintも
  同時に移る。dividerはShift付きchordで1 cell動き、font metrics／Retina scaleを維持したまま
  左右gridが再quantizeされる。
- 8 directional actionのnative menu itemはkey equivalentを持たないこと、3 raw keyが非nativeの
  shared dispatcherでexactly once実行されること、`PtyDiagnosticStage.writeEnqueued`が0件である
  ことを`TERMINAL_DIRECTIONAL_PANE_KEYBIND_TEST` markerへ固定した。
- configuration acceptanceのSettings draftへ
  `keybind = command+right=pane.focus-left`を追加した。live reload後の既存paneへCommand+Rightを
  入力するとstandard `pane.focus-right`ではなく`pane.focus-left`が実行され、active presentationが
  左paneへ移り、native invocation 0／PTY write 0になることを
  `TERMINAL_DIRECTIONAL_PANE_KEYBIND_CONFIGURATION_TEST` markerへ固定した。
- generated keybinding/action referenceは37 application action、9 standard binding、13 reserved
  native shortcut、最大1015 configured declarationを共有authorityから出力する。configuration
  referenceも同じ1015件へ更新した。
- README／FEATURE_MATRIXはCommand+矢印の方向別focus、Shift+Command+矢印のdivider移動、
  live overrideと37 actionへ更新した。Phase 7 acceptance corpusへ新markerを追加し、派生する
  compatibility regression coverage、P0/P1 gap inventory、release-candidate matrixのhashも各generatorで
  更新した。
- 関連unit実行はkey binding、config、action registry、native hierarchy、product hierarchy action、
  keybind reference、configuration referenceの7本が成功した。続けて指定した
  `test/runtime_integration_smoke_test.dart`は存在せず実行できなかったため、正規の実製品driverである
  `make runtime-user-actions-integration runtime-configuration-integration`を検証authorityとして使った。
- `make runtime-user-actions-integration runtime-configuration-integration`: 成功。
  Developer JIT user actions 3,873 ms、Release AOT user actions 2,183 ms、Developer JIT configuration
  2,276 ms、Release AOT configuration 1,554 ms。両modeでdefault focus／divider、active投影、
  menu非予約、live override、PTY write 0、clean resource回収を確認した。
- Phase 7 corpus生成のsandbox内初回はClang module cache
  `/Users/remi/.cache/clang/ModuleCache`へ書けず停止した。実AppKit／Metal検証と同じくsandbox外で
  再実行し、`PHASE7_APPKIT_ACCEPTANCE_PASS ... ui_assertions=10`を確認した。
- `KEYBIND_ACTION_REFERENCE_CHECK_PASS keys=105 pane_actions=4 application_actions=37
  standard_bindings=9 reserved_shortcuts=13`: 成功。
- `CONFIGURATION_REFERENCE_CHECK_PASS options=53 live=12 new_session=41 repeatable=6`: 成功。
- 最初の`make test`はPhase 7 corpus更新後のcompatibility regression coverage hash staleで停止し、
  正規generatorで更新した。次はP0/P1 gap inventory hash staleで停止したため同様に更新し、その依存先の
  release-candidate matrixも再生成した。生成物の意味的な件数／分類は変えず、参照hashだけが追随した。
- その後のaggregate Dart testは新UI marker追加に対する固定総数が9のままで停止した。
  `test/phase7_appkit_acceptance_test.dart`を10へ更新し、単独test成功を確認した。
- 最終`make test`: 成功。native package、generator freshness、compatibility、distribution、format
  （338 files、変更0）、`dart analyze`（issue 0）、security stress、aggregate Dart suiteを完走し、
  `dart_terminal tests passed`となった。

## 残課題・阻害要因

- 本タスクの残課題・阻害要因はない。
