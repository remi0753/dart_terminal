# Context Dock configuration and terminal appearance

- Status: complete
- Date: 2026-09-16
- Scope: Phase 7 Context Dock、Phase 8 configuration、terminal theme projection

## 目的と背景

Context Paneを通常の作業支援として初期表示し、表示と幅を設定できるようにする。
Directory Navigator／Process Inspectorともfocused terminalと同じ背景、通常文字色、フォント、styleへ揃える。
同色の背景にしても境界が消えないよう、境界は透過しない通常文字色（低contrast時は明確に見えるfallback）を使う。
ユーザーの「背景色の保護色」は境界の視認性を求める表現として扱い、明示された通常文字色を優先する。

## 範囲、対象外、依存関係

- context-dock-visible: boolean、default true、新しいstandard windowの初期表示。手動toggleとinput ownershipは保持する。
- context-dock-width: logical points、default 380、既存220–640 pt範囲、live。明示的な設定値変更時は既存幅へ適用する。
- boolのreloadは次のwindowの初期値だけへ反映し、既存windowの手動開閉を上書きしない。dividerによるwindow-owned幅は設定値が変わるまで保持する。
- theme／fontはfocused paneの実際のpalette／regular faceを使い、system appearance、pane focus、live background opacityへ追従する。
- filesystem／argv観測、検索、process操作、SSH、terminal VT semanticsは対象外。
- typed config／Settings／reference、pure Dock state、native presenter、AppKit text editor／split primitivesとterminal rendererを利用する。

## 分割と実施順

1. 設定とstate接続。新option二つのparser／precedence／policy／localization、初期表示・幅、reload、新window、標準fixtureの明示opt-out、reference／build／両runtimeを検証してcommitする。
2. appearance共有と境界。既存native resourceのidentity、focus、selection、scrollを維持して配色／fontを更新し、境界を着色する。
   必要なgeneric AppKit API、dependency repoの規約／既存変更／権限を確認してから実装し、テーマ・pane追従／cleanup／両runtimeを検証してcommitする。

両方の成果物が揃うまで親taskは未完了とする。後者の先行実装はしない。

## 完了条件、リスク、検証方針

- config file／include／CLI／Settingsの一貫したdefault／型／validation／適用policyとreferenceが揃う。
- initial true／false、configured width、terminal最小幅／小window fail-safe、toggle、divider、reload、newwindowでstateが正しい。
- Directory Navigatorの固定details、Process Inspectorの全高表示、keyboard routing、PTY zero／exact input、privacy／bounded cleanupを保つ。
- 配色／fontがfocused terminalと一致し、light／dark／custom palette／opacityでも境界が常に見える。
- focused tests、format／analysis、generated freshness、full make testと関連Developer JIT／Release AOT native suiteを通す。
- native resource再生成によるquery focus／scrollの喪失、隠れたdivider、config default変更による既存matrix geometry崩れが主要リスク。
  VoiceOver読み上げ品質と主観的視覚確認は既存manual checklistに記録する。

## 調査記録

### 2026-09-16 着手

- branchはcodex/context-file-navigator-roadmap、working treeはclean。README、ROADMAP、FEATURE_MATRIX、AGENTS、関連code／test／Makefile、既存layout／processメモを確認した。
- schemaは53 options。Context Dockにconfig optionはなく、productはTerminalContextDockState()を一度生成してstandard windowへ同期する。
  internal stateの初期非表示とwindow-owned380 pt幅が固定されている。
- typed newSession／live policy、config authorityのaccepted reload経路、schema-driven Settings／locale／referenceを再利用できる。
- presenterは上段14 pt／下段12 ptのmonospaced system text editor、system label／window background色を固定で生成している。
  terminalはpane-owned palette、font catalog、theme projectionとshared live opacityを持つ。
- 現在の隣接dart_appkit APIではTextEditor.configurationがfinalで、setDocument／style runs／selection／line highlight／editableのみ更新可能。
  TwoPaneSplitViewもaxis／fraction／children／zoomだけでdivider color指定がない。見た目追従にはgeneric native部品の更新APIが不足している。
- 後者は別subtaskとし、まず設定に必要な最小のstate／fixture変更だけを実装する。

### 設定とstate接続

- typed schemaへvisible（newSession）／width（live）を追加し、55 optionsへ拡張した。220–640の有限doubleとtrue／falseだけを許可する。
- pure stateの内部default非表示は低level callerとの互換性のため維持し、product生成時にtyped default true／380を明示する。
  accepted reloadでfuture windowのdefaultを更新し、width値変更時だけ既存windowをresizeする。手動hide／dragとinput ownershipは上書きしない。
- native-content acceptanceは初期表示trueを直接確認しhide／showとPTY input 0を検証する。他のruntime fixtureには明示falseを渡し既存terminal geometryの受け入れ条件を維持する。
- 関連メモの旧path configuration-reload-live-apply.mdは存在せず、safe-configuration-reload.mdをrgで特定して参照した。
- 巨大なterminal_application.dartの全体出力がtruncateしたためbulk更新を中止し、必要なcountだけtargeted patchした。truncate内容からの全文書き戻しはしない。
- 最初のanalysis／focused testsは新規testの存在しないhasErrors getterで失敗した。既存diagnosticsのseverity／isEmptyで修正した。
  include fixtureのdirectiveも既存grammarのincludeへ修正し、Settings scaffoldとnative fixtureのschema countを55へ更新した。
- 続くtestはCLI validationをfile診断と混同してFormatExceptionで停止した。既存仕様どおりinvalid CLIはusage failure、invalid fileはlocated diagnostic＋default回復を個別検証するよう修正した。
- FEATURE_MATRIXのcount更新patchはrgの行番号prefix除去が誤って失敗した。ファイルは更新されず、no-line-number出力から対象行のみ再patchした。
- precedence fixtureは既存memory filesystemがrelative includeをroot基準へ解決するためchildがmissingになった。production path解決は変更せず、このfixtureはabsolute includeで既存loader precedenceを検証する。
- semantic change-plan testのlive listにも新widthを追加した。native configuration acceptanceにはhidden状態のdrag幅500→accepted width460、次のwindowも460、opacity-only reloadで460保持の実native経路を追加した。
- 最初のbuildは汎用contextのpatchがTheme fixtureの引数へ一致したためconfiguration fixture内のstate参照がundefinedで停止した。両functionの固有contextで引数を修正した。以後はbuild前にanalysisを通す。
- help／show-configのearly exitにはfixture opt-outを渡さない。これらはwindowを作らず、CLI provenanceの行番号と実際のdefaultを維持する必要がある。
- focused config／Dock／effective-config／Settings document／Settings inspector／localization／fake native hierarchy testsとdart analyzeは修正後に全てpassした。
- Developer JIT native-content acceptanceは初期表示true／380とhide／show、Directory Navigator／Process Inspector、exact PTY、4 session cleanupをpassした（11209 ms）。
- presenterの推測path terminal_context_dock_presenter.dartは存在しないため、関連file探索はrg --filesから行う。
- native presenterはterminal_context_dock_directory.dart内にあり、terminal最小240 ptと220–640 ptのbounded Dock geometryを既存のまま利用する。
  runtime show-config fixtureの5 keybind等を含むentriesは既存56＋新scalar2の58とする（schemaは55）。
- Release AOT native-content acceptanceもpassした（10106 ms）。configuration native product内のwidth／reload／cleanup assertionsは両modeでpassしたが、外側validatorの旧19 changes／3 live期待で失敗した。
  width追加分の20 changes／4 liveへ更新し再実行する。受け入れassertion自体は削除・緩和しない。
- configuration suite再実行はDeveloper JIT（2237 ms）／Release AOT（1424 ms）ともpassした。Settings初期55-option document、atomic save、invalid候補拒否、accepted width460、既存／後続window、opacity-only reload、5 session／全native handle cleanupを確認した。
- reload後の実Navigator input ownershipとinvalid更新後のfuture defaults、including file優先順位を追加検証しfocused testsはpassした。
  全gate実行中のtest追加でgenerated source hashがstaleとなり、最初のmake testはgap inventory freshnessで停止した。全編集を止めて再生成後に直列で全gateをやり直す。

### 設定subtaskの完了

- 再生成後のmake testはexit 0。347 Dart filesのformat差分0、dart analyze問題0、全Dart／native capability tests、configuration／keybind／locale／privacy／compatibility／distribution freshness gatesはpassした。
- README、FEATURE_MATRIX、設定reference、両manual checklistと関連schema countを更新した。CLIは`--context-dock-visible=false`／`--context-dock-width=420`、fileは同名assignmentを使う。
- git diff --checkと対象差分を確認し、無関係な変更、debug出力、生成build artifacts、秘密情報がないことを確認した。
- 次はappearance subtask。設定部分は完了、配色／font／境界はまだ未実装。主観的外観／VoiceOver確認はmanual checklistの未完了項目として残る。

### appearance subtask着手

- 設定完了commitはb49fb42、Configure Context Dock visibility and width。terminal working treeはcleanになった。
- 隣接dart_appkitとparent directoriesに追加AGENTS.mdはない。README／ROADMAP、公開API、native bindings、FFI、bridge／objects、tests／Makefileを確認した。
  dependency既存変更はdocs/BUILDING_DART_ENGINE.mdとscripts/bootstrap_dart_engine.sh／build_dart_engine.shだけで、本taskは変更しない。
- 実コードのpresenterは上下とも12 ptのsystem monospaceだった（初回メモの上段14 ptという記述を訂正）。focused terminalのregular face／sizeとpaletteへ両段を揃える。
- native部品を再生成する案はfocus／selection／scroll／ownershipを不安定にするため採用しない。optional追加APIで既存TextEditorのbase presentationを更新し、TwoPaneSplitViewのdivider色を指定する。
  既存ABI structs／event protocol、defaultの他application外観は変更せず、旧bridgeはunsupportedを明示する。terminal固有policyはDart presenterへ残す。
- 境界はopaqueな通常文字色、backgroundとのcontrastが3:1未満の場合だけblack／whiteの高contrast側へfallbackする。Dock背景はterminalと同じlive opacity、caretは通常文字色とする。
- APIはtext／editable／selection／marked text／scroll／line highlight／明示style runsを保持し、parameter validationとmain-thread／generation-safe handle checksを通す。
  隣接repoへの必要最小限の編集はsandbox escalationで権限を確認して行う。
- escalationは許可され、隣接repoにoptional汎用APIとtaskメモ／ROADMAP subitemを追加した。16個までのregular OpenType font descriptor coordinateも渡せる。
  明示foreground runをprivate attributed markerで保持しbase更新後に再適用する。透明editorはopaqueと誤申告しない。
- initial native／Dart API testsはpass、公開export listの新variation型不足を修正しfull Dart API／launcher testsもpassした。
  真にscrolled viewport、marked text、stale handle、off-thread、color validationのnative確認も追加した。
- Dart presenterはfocused surfaceのfont selection／size／regular coordinates／padding、実paletteのforeground／backgroundと最新opacityを参照する。
  decorate時、theme／OSC／session変更、accepted live opacityで既存上下editorとdividerをin-place更新する。同じ値はnative no-opとしfont IOは追加しない。
- pure projectionはlight／dark／custom／同色fg-bg／opacity 0 fallbackをpassした。fake nativeは上下style一致、query caret／selection／focus／resource identity保持、no-op、selected tabの別fontへの追従をpassしanalysis問題0。
- native-content fixtureにはMenlo16、custom foreground/background、opacity0.8を明示し、default true／380を保ったままDirectory NavigatorとProcess Inspectorの両方でterminal style共有を直接検証する。
- custom styleのnative-contentはDeveloper JIT（11128 ms）／Release AOT（10387 ms）ともpassした。全height process切替、caret、tree／search、exact PTYと4 session／全native handle cleanupも維持した。
- generic APIのnative／Dart API／launcher／FFI／legacy smokeもpassした。全dependency gateは新task文書の製品用語をownership auditが検出して停止したため、汎用boundaryの説明へ変更しaudit条件を維持して再実行する。
- depot_toolsのclang-format wrapperはChromium checkoutを要求して無変更で失敗した。Xcode実バイナリを特定し、変更native範囲だけをformatした。
- 最終reviewでvariation数の上限超過を既存LimitExceeded statusへ揃え、C側の17件拒否testを追加した。公開Dart側は引き続きnative mutation前にRangeErrorを返す。
- tool outputのcontext切替で終了済みdependency test sessionを再pollできなかったため、成功を推測せず、編集を止めてmake testを再実行する。
  process一覧はsandboxのps制限で取得できなかった。生成reportは既存generatorを直列で再実行し4件ともpassした。
- native／Dart変更範囲の最終diffを確認した。不要なdocument wrapperは削除し既存setDocument本体を維持した。
  配色refreshは同値ならnative no-opであり、query入力の文書／focus mutationや追加font filesystem IOを行わない。
- dependencyの最終make testはexit 0。ownership／scaffold、native bridge／runner／runtime、assembly／publication、Dart API／launcher／example、FFI／legacy smokeを全てpassした。
  変更した8 Dart filesのformat差分0、native変更範囲format、diff checkもpassした。既存Engine文書／scriptの3変更はステージ対象から除外した。
- dependency完了commitはf711731、Support live text presentation and divider colors。
  汎用APIの目的、契約と検証は隣接repoのdocs/DYNAMIC_TEXT_PRESENTATION.mdに記録し、当該subitemだけを完了とした。
- 最終reference確認で推測したdocs/configuration-reference.mdは存在しなかった。codeのreference generatorはlib/src/terminal_configuration_reference.dartであり、最終報告は確認済みtaskメモを参照する。
- dependency完了commit後の最新sourceをarm64で再buildし、native-contentはDeveloper JIT（11149 ms）／Release AOT（10006 ms）ともpassした。
  true／380のinitial state、Menlo16／custom palette／opacity0.8、Directory Navigator／Process Inspector、exact PTY／caret／tree／search／privacy／4 session cleanupを再確認した。

### appearance subtaskの完了

- 再buildした両runtimeのconfiguration suiteはDeveloper JIT（2036 ms）／Release AOT（1171 ms）でpassした。
  width460のaccepted reload、manual width保持、future window、Settings／atomic rejection、input ownershipと全native cleanupを確認した。
- theme suiteはDeveloper JIT（2086 ms）／Release AOT（1277 ms）でpassした。
  3 pane、3 appearance／accessibility preference、Japanese localizationとlive palette／opacityの既存経路を維持した。
- 最終make testはexit 0。347 Dart filesのformat差分0、dart analyze問題0、全Dart／native capability testsと
  configuration／keybind／localization／privacy／AppKit acceptance／compatibility／distribution／generated freshness gatesをpassした。
- README、FEATURE_MATRIX、Directory Navigator／Process Inspectorのmanual checklist、4 generated reportsを更新した。
  境界は通常文字色のopaque divider、configured backgroundとの3:1未満のcontrastだけblack／whiteへfallbackする。
  regular font／size／variation／padding、foreground／background、live opacityをfocused terminalから共有する。
- diff checkと対象変更のreviewはpass。不要なwrapper、debug用変更、秘密入力／argvの追加log、無関係な生成物は含まれない。
  隣接repoの既存Engine文書／script変更は保持し、先のAPI commitにも含めていない。
- 親taskと両subtaskの実装・自動検証は完了。追加の未完了実装項目や阻害要因はない。
  主観的な外観／VoiceOver品質は両manual checklistの未完了項目で追跡し、Intel実機／配布署名等の後続項目へは着手しない。
