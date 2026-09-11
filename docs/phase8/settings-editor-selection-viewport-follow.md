# Settings editor selection viewport follow

Status: in progress (2026-09-11)

## 目的

Settings editorのNORMALまたはSEARCHでDartがcaretを画面外の行へ移動したとき、native editorの
viewportも追従させ、current-line背景と選択中の設定項目を常に表示範囲へ入れる。INSERTのAppKit
標準caret scrollは維持し、document、selection、syntax style、detailの意味論を変更しない。

## 背景

- NORMAL/SEARCHは`KeyEventRouting.dartOnly`であり、矢印や検索結果移動を
  `TerminalSettingsEditorState`が処理する。presenterはそのUTF-16 selectionを
  `TextEditor.setSelection`へ投影するが、viewportを動かす操作はない。
- INSERTは`KeyEventRouting.dartAndAppKit`であり、`NSTextView`自身のcaret navigationが標準の
  scroll-to-visibleを行う。そのため同じdocument surfaceでもNORMALだけが画面外へ進める。
- `dart_appkit` native `da_text_editor_set_selection`はchecked `selectedRange`を設定するだけで、
  `scrollRangeToVisible:`を呼ばない。これは報告されたmode差をsource上で説明できる直接原因である。
- 汎用`setSelection`に常時scrollを暗黙追加すると、selectionだけを更新してviewportを保持したい
  consumerの挙動を変える。selection mutationとrevealを別操作にし、必要なproductが明示的に選ぶ。

## 分割と実施順

### 1. `dart_appkit` explicit selection reveal API

generic `TextEditor`へ現在のchecked native selectionを表示範囲へ入れる明示操作を追加し、C ABI、
FFI current/legacy、fake、native window testを同じcontractへ接続する。nativeはselectionを変更せず
`NSTextView.scrollRangeToVisible:`を実行する。

完了条件:

- public APIからrevealが明示的に呼べ、legacy symbol欠落、invalid/released handle、off-main-threadを
  従来のtyped failureとして扱う。
- 小さい実scroll viewportと複数行documentで、末尾selectionのlogical lineがvisible rectへ入り、
  selection、style run、line highlightが不変である。
- siblingのREADME/worklog/verification、focused test、完全`make test`を成功させ、独立コミットする。

### 2. product navigation projection and acceptance

presenterがNORMAL/SEARCHでDart-owned selectionをnativeへ変更した直後だけrevealを要求する。INSERTの
native-owned navigationには追加投影せず、marked text中のdocument/selectionをDartから変更しない。

完了条件:

- NORMALの`↓`/`j`、`↑`/`k`とSEARCH result移動で、画面外へ進んだcurrent lineがvisibleになる。
- revealはselectionを変更せず、current-line背景、syntax foreground、diagnostic underline、detail
  targetを同じcaretへ保つ。
- fake presenter test、formatter、analyzer、完全test、source/bundle audit、M1 Developer JIT / Release
  AOTの実Settings acceptanceが成功する。

## 範囲

- generic attributed `TextEditor`の明示的selection reveal。
- Settings NORMAL/SEARCHのDart-owned selectionからnative viewportへの同期。
- fake/native/runtimeのviewport-follow回帰検査と利用者向け説明。

## 対象外

- INSERTのnative key/IME/selection ownership、scroll physics、scrollbar designの変更。
- viewport内でのcaret位置を中央へ固定するcentered scrolling。
- horizontal column policy、page-up/down、mouse wheel、terminal Metal viewportの変更。
- Phase 9以降のprotocol実装。

## 依存関係とリスク

- 直前の`TextEditorLineHighlight`と同じlogical caretを使うが、revealはhighlight描画やstyle attributesを
  所有しない。
- AppKitのrangeはUTF-16である。reveal対象はnative editorが保持する既に検証済みのselectionとし、
  新しいunchecked offsetをABIへ渡さない。
- `scrollRangeToVisible:`はview attachment/layout後に検証する。collapsed selectionがdocument末尾や
  newline直後でも対象lineを表示できることをnative testで固定する。
- presenterは同じselectionを毎renderでrevealして利用者の手動scrollを奪わず、Dart-owned selectionが
  実際に変更された場合だけ実行する。

## 検証方針

1. sibling public/fake/FFI/native testで明示呼び出し、実viewport移動、状態不変、異常系を固定する。
2. fake AppKit presenter testで十分なNORMAL/SEARCH移動を行い、selection更新ごとのreveal要求と
   INSERTでは追加要求しないことを固定する。
3. product configuration exerciseで画面外相当の複数行移動と新しいacceptance markerを検査する。
4. 両repositoryの完全test、dart_terminalのsource/bundle audit、M1両runtime configuration suiteを
   実行する。

## 調査・実装ログ

- 2026-09-11: 着手時に両repositoryはcleanで、Phase 8は直前のdisabled/current-line追補まで完了、
  Phase 9 Kitty keyboard protocolが最初の未完了項目だった。本依頼をPhase 8末尾へ登録してPhase 8を
  再度開き、Phase 9には先行しない。
- 2026-09-11: source確認により、NORMAL/SEARCHのselectionはDart stateから
  `TextEditor.setSelection`へ更新される一方、native `da_text_editor_set_selection`は
  `selectedRange`代入だけを行うことを確認した。INSERTは`NSTextView`がkey navigationを所有するため
  自動scrollし、これがmode間の差となる。
- 2026-09-11: `setSelection`自体の意味を変更する案は全consumerのviewportを暗黙に動かすため不採用と
  した。現在のnative selectionを明示的にrevealする独立APIなら、新しいrange validationを増やさず、
  product presenterもDart-owned navigationのときだけ意図を示せる。
- 2026-09-11: `dart_appkit`に`TextEditor.scrollSelectionToVisible`とadditive C ABIを追加した。
  nativeは現在のvalidated selectionへ`NSTextView.scrollRangeToVisible:`を実行し、selection、text、
  attributed storage、line highlightを変更しない。symbolはoptional FFI lookupとし、legacy bridgeは
  status 8を返す。
- 2026-09-11: read-onlyの80 logical-line native editorで、末尾selectionが初期visible rect外にある
  こと、reveal後に行全体がvisible rect内へ入りviewport originが進むこと、selection/style/highlightが
  不変であることを検証した。wrong handle type、released handle、off-main-thread、public fake、current
  Mach-O FFI、legacy fallbackも固定した。
- 2026-09-11: siblingのfocused `make native-test dart-test ffi-smoke`と完全`make test`は成功した。
  README、ROADMAP、worklog、verificationを更新し、
  `6051a7af8f987562d7486823b834539d46eba3a5`（`Reveal programmatic text editor selections`）
  として独立コミットした。ROADMAP再確認後の現在地は第2サブタスクで、次はSettings presenterの
  Dart-owned selection更新直後へrevealを投影し、両runtimeで受け入れることである。
- 2026-09-11: product formatterは対象2 fileを0変更と確認した後、sandbox外のDart telemetry
  timestamp更新だけをpermission errorとして報告した。source formattingの失敗ではないがexit statusを
  確定するため、同じformat checkを許可済み環境で再実行する。
- 2026-09-11: presenterはdocument/selectionをDartからnativeへ実際にpublishしたかをrender内で
  追跡し、NORMAL/SEARCHのときだけ`scrollSelectionToVisible`を呼ぶようにした。同じselectionの
  再render、detail開閉、INSERT移行、native caret同期ではrevealせず、手動scrollとnative editingの
  所有権を維持する。current-line highlightはreveal前に同じstate selectionへ更新する。
- 2026-09-11: fake AppKit bindingにeditorごとのreveal countを追加し、初期Dart document、NORMAL
  navigation、SEARCH selectionで要求され、INSERT移行とnative INSERT同期では増えないことを
  hierarchy testで固定した。focused testと`dart analyze`は成功し、最終formatter checkも4 file 0変更と
  なった。
- 2026-09-11: product configuration exerciseはNORMALで64行下へ移動して最後のschema optionまで
  到達し、同じselectionへcurrent-line highlightが同期した後に検索・編集・保存を継続する。実native
  reveal symbolまたはviewport処理の失敗をconfiguration suiteが検出できるよう、exact markerへ
  `settings_viewport_follow=true`を追加した。
- 2026-09-11: `make phase7-appkit-acceptance terminal-compatibility-regression-coverage`は成功した。
  AppKit acceptance corpusは変更したhierarchy testとruntime application sourceのSHA-256だけ、
  compatibility reportはREADMEとFEATURE_MATRIXのSHA-256だけを更新し、case数やfix familyに意図しない
  変化がないことを差分で確認した。
- 2026-09-11: 最終focused testのsandbox内再実行はMetal compilerが
  `/Users/remi/.cache/clang/ModuleCache`へ書けず終了し、analyzerは`No issues found!`まで成功した後に
  Dart telemetry sessionのmtime更新権限だけでexit 1となった。いずれもsource failureではないが、成功
  statusを確定するため通常の開発環境権限で同じ検証を再実行する。
- 2026-09-11: 通常の開発環境権限でfocused hierarchy testと`dart analyze`を再実行し、いずれも
  exit 0となった。`CI=true DART_SUPPRESS_ANALYTICS=true make test`はformatter 246 files / 0 changed、
  analyzer `No issues found!`を含めて`dart_terminal tests passed`となった。
- 2026-09-11: `make runtime-source-check runtime-bundle-audit`はsource auditとDeveloper JIT / Release
  AOT両bundle auditをすべてPASSした。M1の`make runtime-configuration-integration`は両runtimeで
  `settings_viewport_follow=true`を含むexact markerを返し、Developer JIT 1917 ms、Release AOT
  1109 msで成功した。

## 完了状態

complete。NORMAL/SEARCHのDart-owned selection変更時だけnative viewportを追従させ、INSERTの
native-owned navigation、selection、syntax attributes、diagnostic underline、current-line highlightを
維持した。Phase 8の本追補に残作業はなく、Phase 9には着手しない。

- 2026-09-11: 最初のproduct commit試行はsandboxが`.git/index.lock`を作成できず失敗した。staged
  diffは保持されており、sourceや検証の失敗ではない。メモをstageへ戻した上でrepository書き込み権限を
  用いて同じcommitを再実行する。
