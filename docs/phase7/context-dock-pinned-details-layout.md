# Context Dock pinned details layout

- Status: complete
- Date: 2026-09-14
- Scope: Context Dockの既定幅とDirectory Navigatorの縦方向レイアウト
- Related: UI-02、UI-05、AX-01、PERF-06

## 目的と背景

Context Dockの既定幅を少し広げ、長いfile／directory名やpathを読みやすくする。現在はheader、query、最大512件のtree／search rows、
coverage、path actions、選択項目detailsを1つのscrollable native editorへ連結している。そのため結果が多いとdetailsが末尾へ押し出され、
選択を上下移動しても同時に確認できない。結果一覧だけをbounded scroll領域へ置き、選択項目の情報はDock下部へ固定表示する。

## 範囲

- 新規windowのContext Dock既定幅を320 ptから読みやすい範囲へ拡大する
- Dock内部をvertical native splitにし、上段をheader／query／tree・search results／coverageのscrollable editorとする
- 下段をpath actionsと選択中file／directory detailsの固定read-only viewとする
- 上段の選択、query focus、keyboard navigation、scroll-to-selection、terminalとのinput ownershipを維持する
- window resize、Dock横divider、tab reparent、hide／show、cleanupでnative view／handle ownershipを維持する
- focused unit／fake AppKit、通常Developer JIT GUI、Developer JIT／Release AOT native-content、full gateで検証する

## 対象外

- 検索件数、ranking、source、query shortcut、path handoff仕様の変更
- detailsの編集、preview、Quick Look、file content表示
- SSH／remote directory provider
- userが横dividerで保存した既存window幅を新しい既定値へ強制変更すること

## 依存関係と設計方針

- `TerminalContextDockState`のwidthはwindow-ownedであり、新規stateだけが既定値を使う。minimum／maximumとnative divider観測は維持する。
- `TerminalContextDockDirectoryPresenter`はterminalとのhorizontal outer splitに加え、Navigator editorとdetails viewを所有するvertical inner splitを持つ。
- file／directory rowsとquery selectionは上段editorだけに存在させる。下段detailsはfirst responderにならないpassive native text viewとし、
  NavigatorのDart-only key routingを変えない。
- detailsはおおむね200 ptを確保し、上段にもheaderと複数rowを表示できるminimumを設ける。利用可能高が境界を満たさない場合は既存の
  fail-safeなDock非表示条件へ還元し、不正なsplit constraintを作らない。
- details textもbounded directory snapshotだけから構築し、diagnosticsや永続stateへpathを追加しない。

## 完了条件

- 新規Context Dockの既定幅が従来より広く、既定windowでterminal minimum widthを侵害しない。
- 数百件の検索結果またはtree rowsがあっても、選択中項目のName／Kind／Path／metadataとpath actionsが下部に常時表示される。
- 上段だけが縦scrollし、選択移動時に上段のselected rowと下段detailsが同じgenerationで更新される。
- `Shift+Command+F`、query入力、上下／Page navigation、`Escape`、Copy Path、Option-ReturnのPTY zero／exactly-once契約が不変である。
- format、analysis、focused tests、generated freshness、full `make test`、両runtime native-content、通常Developer JIT GUI確認が成功する。

## 検証方針

- state testで新しいdefault widthとbounded setWidthを固定する。
- fake AppKit testでouter horizontal splitの右childがvertical splitになり、上段TextEditor／下段passive TextView、既定幅、固定details高さ、
  selection更新、hide／show／tab reparent、全handle cleanupを検証する。
- native-content scenarioで一覧editorとdetails viewの両方に選択fileの情報が正しく分離され、Navigator入力がPTYへ漏れないことを確認する。
- 通常Developer JITを起動し、結果が多いqueryで一覧のscrollと固定details、focus復帰をaccessibility treeと画面で確認する。

## 調査記録

### 2026-09-14 着手

- working treeはcleanで、branchは`codex/context-file-navigator-roadmap`。直前の通常起動回帰修正はcommit `f04f785`で完了している。
- ROADMAPの次の未完了項目は主要ゴール後の低優先follow-upだったため、本改善をContext Dock親項目の末尾へ追加し、現在の先頭未完了taskにした。
- 現状の既定幅は`TerminalContextDockLimits.defaultWidth = 320`。右Dockはterminalとのhorizontal `TwoPaneSplitView`のsecond childに、
  1つのscrollable read-only `TextEditor`を直接配置している。
- `_TerminalContextDockDocument.build`はheader／query、全rows、partial／coverage、path actions、detailsを1文字列へ順番に連結する。
  selected rowへscrollするとdetailsはさらに下へ離れ、多件数時に一覧とdetailsを同時表示できない構造である。
- 採用案は既存outer splitの右childをvertical inner splitへ置き換え、上段TextEditorへnavigation document、下段passive TextViewへ
  path actions／details documentを分離する。既存のnative split/view primitiveを再利用でき、overlayや独自描画を追加しない。

### 2026-09-15 実装

- 新規Context Dockの既定幅を320 ptから380 ptへ変更した。220–640 ptの既存clamp、利用者がdividerで変更したwindow-owned width、
  terminal側の240 pt minimumは変更していない。
- presenter-ownedな右Dockの内側へvertical `TwoPaneSplitView`を追加した。上段は従来のread-only `TextEditor`であり、header、input owner、
  cwd、query、最大512件のtree／search rows、partial／coverageだけを保持する。下段はfirst responderを受け取らないread-only `TextView`で、
  path action availabilityと選択項目のName／Kind／Path／metadataだけを保持する。
- detailsの目標高を210 pt、minimumを140 pt、上段minimumを120 ptとした。各reconcileで目標高を再投影するため、長い一覧のscroll、
  selection reveal、outer divider操作、tab reparentでdetails viewのidentityと下端位置を変えない。縦方向のminimumを満たさないwindowでは、
  不正なsplit constraintを作らず既存のfail-safeと同様にDock projectionを抑止する。
- document更新をnavigation／detailsの2文字列へ分離した。query selection、selected-line highlight、scroll-to-selectionは上段だけへ適用し、
  details更新はinput ownershipやfirst responderを変更しない。disposeではouter split、inner split、details、editorを一度ずつ回収する。
- native-content製品scenarioは、検索結果名が上段に、選択absolute pathとpath actionが下段にだけ存在することを確認するよう更新した。
  fake AppKit testは512件のrow、380 pt既定幅、horizontal＋vertical split、210 pt details、passive view、選択更新、reconcile後の固定高、
  scroll reveal、hide／show、tab reparent、冗長なchild再attachなしを固定した。
- README、FEATURE_MATRIX、設計memo、manual checklistを新しい既定幅とscrollable list／fixed details構造へ同期した。SSH／remote providerは
  引き続き対象外であり、検索scope、ranking、件数、path handoff、PTY入力契約は変更していない。

### 2026-09-15 検証途中結果

- `dart format`は対象5ファイルを整形した。sandbox内の初回実行と`DART_SUPPRESS_ANALYTICS=true`付き再試行は、formatter処理後に既存
  `~/.dart-tool/dart-flutter-telemetry-session.json`のmtime更新を拒否され終了code 1になった。権限を拡張して同じformatterを再実行し、
  変更0・成功を確認した。ソース内容の問題ではなく、sandbox外にあるDart telemetry session更新だけが原因だった。
- `dart analyze`: 指摘0。
- `dart run test/terminal_context_dock_test.dart`: 成功。
- `dart run test/terminal_native_hierarchy_test.dart`: 成功。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、navigator／exact PTYを含め成功。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、navigator／exact PTYを含め成功。
- exact通常起動の`make RUNTIME_ARCH=arm64 developer-jit-run`を実行した。初回表示で右Dockが380 pt相当まで広がり、上段一覧と
  下段210 pt相当のPath actions／Detailsが同時表示された。多数の検索結果を表示して上段scrollbarを約49%まで移動しても、下段は
  window下端に残った。`Escape`後はterminal text inputがfirst responderへ戻り、Dockとqueryは保持された。

### 2026-09-15 完了検証

- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`を実行し、変更したsource／README／FEATURE_MATRIXに対応する
  hashだけを生成物へ反映した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。346 Dart filesのformat変更0、analysis指摘0、focused testを含む全Dart test、
  native capability test、security stress、およびPhase 7／regression coverage／Ghostty gap／daily-useを含む全generated freshness checkが通った。
- `git diff --check`: 指摘0。生成物差分は入力source／documentationのhash更新だけで、件数、classification、既存acceptance内容に変化はない。
- 完了条件を再確認し、380 pt既定幅、上段のbounded scroll領域、下段の固定details、keyboard input ownership、PTY zero、両runtime、
  ownership／cleanupをすべて自動または通常GUIで確認した。未検証事項と追加のROADMAP項目はない。
