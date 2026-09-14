# Context Dock Terminal mode presentation

- Status: complete
- Date: 2026-09-15
- Scope: Context Dockの表示modeとterminal／Navigator input ownershipの同期
- Related: UI-05、AX-01、AX-02、IN-09

## 目的と背景

Directory Navigatorから`Escape`でterminalへ入力を戻した後も、Dockには直前の`Mode: Search`、`Mode: Go To`、
`Mode: Move`が表示され続ける。queryとNavigator modeの保持自体は再入場時に有用だが、現在の入力先を示す表示としては誤解を招く。
terminalがinput ownershipを持つ間は`Mode: Terminal`と表示し、再度Navigatorへfocusした時だけ保持中のNavigator modeを表示する。

## 範囲

- terminal ownership中のContext Dock mode copyを`Terminal`へ切り替える
- Navigator mode／query／tree selectionの保持
- Escape、明示的なFocus Terminal action、Search／Go To／Moveへの再入場、pane切替における表示同期
- pure Dart、native hierarchy、product native-contentによる回帰検証
- README、FEATURE_MATRIX、manual checklistの操作説明更新

## 対象外

- 新しいNavigator mode enumやshortcutの追加
- terminal shell processの状態変更、PTY protocol、cwd観測の変更
- Context Dockの表示／非表示shortcut、layout、filesystem探索範囲の変更
- SSH／remote provider

## 依存関係とリスク

- `TerminalContextDockPaneSnapshot.navigatorMode`は再入場用の保持状態であり、terminal ownershipを表す値へ上書きしない。
- 表示はwindow-level `focusOwner`とpane-level `navigatorMode`から導出し、canonical stateを二重化しない。
- terminal focusが別paneへ移った場合も、focused paneのtree／query stateを保ったまま`Mode: Terminal`を投影する。
- native editorのeditable／caretは既存のownership判定と一致させ、表示だけが先行・遅延しないよう同じsnapshotから生成する。

## 完了条件

- Context Dock表示中にEscapeまたはFocus Terminal actionを実行すると、Dockを残したまま`Mode: Terminal`になる。
- terminal ownership中はmode copyを`Terminal`とし、保持中のSearch／Go To query行またはMove hintはread-onlyなtree contextとして残す。
  Navigator input caretは出ない。
- Search／Go To／Move shortcutでNavigatorへ戻ると、対応するmode copyと既存の保持query／tree stateが復元される。
- mode表示の更新によってPTY write、filesystem operation、focus requestが重複しない。
- format、analysis、focused/full test、generated freshness、Developer JIT／Release AOT native-contentが成功する。

## 検証方針

- state／presenter test: Escape、Focus Terminal、再入場、pane切替後のdocument copyと保持状態。
- native hierarchy test: terminal ownership中のread-only editor／caret消失と`Mode: Terminal`。
- product scenario: 実plain shellでNavigator→Escape→terminal→Navigatorを往復し、mode copyとPTY write delta 0を確認する。
- docs／generated artifact freshnessと通常full gateを実行する。

## 判明事項と判断

- `TerminalContextDockWindowSnapshot.inputOwner`はwindow単位の現在のinput ownershipを、
  `TerminalContextDockPaneSnapshot.navigatorMode`はpane単位の再入場用Search／Go To／Move状態を既に独立して保持していた。
  `focusTerminal`は前者だけを変更するため、保持queryやtree projectionを失わず表示を正しく導出できる。
- 選択肢としてNavigator mode enumへ`terminal`を追加する案は、query accessor、directory operation、再入場modeまでterminal状態へ
  上書きして二重のownership表現を作るため採用しない。`_TerminalContextDockDocument.build`のmode labelだけを
  `navigatorOwnsInput`から分岐し、Navigator ownership時だけ既存modeを表示する。
- Search／Go To query行は、terminalへ戻った後も現在表示中の検索結果を説明するread-only contextとして残す。Move hintもdocumentの
  行構造とselection offsetを安定させるため保持するが、先行する`TERMINAL INPUT`と`Mode: Terminal`により現在の入力先とは区別する。
- English／Japanese catalogに`Terminal`／`ターミナル`を追加した。native editorのeditable、selection、key routingは従来どおり
  `navigatorOwnsInput`で制御されるため、表示変更が新しいfocus requestやPTY routingを発生させない。

## 実装内容

- terminal ownership中のmode labelを`Mode: Terminal`／`モード: ターミナル`へ変更した。
- Escape後も直前のSearch／Go To queryとdirectory selectionを保持し、同じNavigator shortcutで再入場すると元のmode labelとqueryを復元する。
- fake AppKit hierarchyにEscape後のread-only、terminal first responder、Terminal label、保持query、Go To再入場の検証を追加した。
- product native-content scenarioに、Dockをterminal-ownedで開いた直後とNavigator Escape後の`Mode: Terminal`、保持Search query、PTY write 0の
  検証を追加した。

## 検証結果

- `dart run test/terminal_native_hierarchy_test.dart`: 成功。Escape後のterminal first responder、AppKit-only routing、read-only editor、
  `モード: ターミナル`、保持Go To queryと、Go To再入場後のmode／query復元を確認した。
- `dart run test/terminal_context_dock_test.dart`: 成功。input ownership、mode別query保持、focus失敗時の無変更、Dock hide/show契約に回帰がない。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- 正規generator 5種とfreshness gate: 成功。application actions 42、reserved shortcuts 17、Phase 7 criteria 5／source refs 19／
  unit tests 16／integration tests 5／UI assertions 11、regression cases 9、actionable P0/P1 gap 0、release blocker 0。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 成功。`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、elapsed 5026 ms。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功。`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、elapsed 4304 ms。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 最終sourceと再生成物で成功。全346 Dart fileのformatは変更0、analysis issue 0、
  native package、privacy、localization、Phase 7、compatibility、application、distributionを含む全gateが`dart_terminal tests passed`で終了した。
- `git diff --check`: 成功。

## 失敗した試行と環境上の注意

- focused native hierarchy testと最初のgenerator実行は、sandboxがMetal build hookの
  `/Users/remi/.cache/clang/ModuleCache`への書き込みを拒否し、test／generator本体へ到達する前に失敗した。これはsourceの失敗ではない。
  同じコマンドを通常ユーザー環境で再実行すると成功した。以後のMetal hookを含む検証も同環境で実行した。

## 残課題

- 本taskに残る実装・検証blockerはない。SSH／remote providerは従来どおり対象外である。
