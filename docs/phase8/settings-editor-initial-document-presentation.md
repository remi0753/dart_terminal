# Settings editor initial document presentation

Status: in progress (reopened 2026-09-11)

## 目的

Settings windowを開いた直後から、左editorへ全設定項目とsyntax styleを表示する。最初のkey入力を
表示の契機にせず、NORMAL/SEARCH navigationで画面外へ進んだ後のviewport追従は維持する。

## 背景

- 2026-09-11の実画面では、初回open時に右detail、status、current-line背景は描画される一方、左の
  attributed document本文だけが空に見え、key入力後に表示された。
- presenterの新規window経路は`_render()`でdocumentを設定した後に`Window.show()`を呼ぶ。
- 直前のviewport-follow実装は、navigationによる`setSelection`だけでなく初期`setDocument`も
  `selectionPublishedByDart`として扱い、まだwindowへ表示・layoutされていないeditorへ
  `scrollSelectionToVisible()`を呼ぶ。
- 初期documentのselectionは先頭でありdefault viewport内にある。ここでのrevealは不要で、
  `NSTextView.scrollRangeToVisible:`をpre-layoutに実行することが報告症状との差分である。

## 範囲

- 初期document publicationとNORMAL/SEARCH navigation selection revealの区別。
- fake presenterおよび実Developer JIT / Release AOT Settings windowの初回表示回帰検査。
- README、FEATURE_MATRIX、generated acceptance evidenceの整合。

## 対象外

- document内容、36 option補完、syntax palette、line highlight、detail/status layoutの変更。
- INSERTのAppKit-owned navigation、scroll physics、手動scroll、terminal Metal viewportの変更。
- `dart_appkit`のexplicit selection reveal API contract変更。
- Phase 9以降のprotocol実装。

## 依存関係とリスク

- 初期document設定後もselection、style runs、line highlightを同じrender内で投影する必要がある。
- revealを全面的に削除すると元のNORMAL下移動bugが再発する。document交換では要求せず、既存
  documentに対してDartがselectionを実際に変更した場合だけ要求する。
- stateだけのruntime assertionではnative初回描画regressionを見落とすため、初回open時のdocument
  publicationとreveal countをkey入力前に固定し、その後のnavigationでrevealが始まる順序を検査する。

## 完了条件

- 初回openの`setDocument`ではpre-layout selection revealを要求せず、全option document、style runs、
  selection、current-line highlightをkey入力前にnative editorへ投影する。
- NORMAL/SEARCHでselectionが変わった場合は引き続きexplicit revealを要求し、INSERTでは要求しない。
- focused test、formatter、analyzer、完全test、source/bundle audit、M1 Developer JIT / Release AOTの
  configuration integrationが成功する。
- 差分、generated evidence、文書を確認して独立commitし、Phase 8再完了後はPhase 9へ進まず停止する。

## 再調査後の分割と実施順

### 1. `dart_appkit` line-highlight prepaint layout

line-highlight rectをbackground draw中に初めてlayoutする状態を解消し、documentとhighlightがwindowへ
表示される最初のdraw passで本文glyphと背景が同時に描画できるようにする。実native windowを使い、
key/selection eventなしの初回bitmapでtext inkとline backgroundが共存することを検査して独立commitする。

### 2. product initial paint and runtime acceptance

Settings固有の不要なlifecycle workaroundを除き、初回document/style/highlightを通常のpresenter経路で
投影する。指定のDeveloper JIT通常起動でkey入力前のscreenshotを直接確認し、automated
Developer JIT / Release AOT configuration suiteにも初回paint証拠を接続してproduct commitする。

## 検証方針

1. fake AppKit presenter testで初回key入力前のdocument/style/highlightとreveal 0を固定する。
2. 最初のNORMAL navigationでselection/highlight更新とreveal 1を固定し、SEARCH/INSERTの既存境界も
   維持する。
3. product configuration exerciseの初回open assertionとviewport-follow markerを両runtimeで通す。
4. generated acceptance/compatibility evidence、完全test、source/bundle auditを再検証する。

## 調査・実装ログ

- 2026-09-11: 着手時に`dart_terminal`と`dart_appkit`はclean。ROADMAPはPhase 8完了、Phase 9の
  Kitty keyboard protocolが最初の未完了項目だった。本報告をPhase 8末尾の追補として登録し、
  Phase 9には先行しない。
- 2026-09-11: screenshotではdetail/status/current-line背景が初回から描画され、左本文だけがkey入力を
  待っていた。sourceでは新規windowが`_render()`後に`show()`され、初期`setDocument`直後の
  `scrollSelectionToVisible()`が直前commitで新たに加わった唯一のpre-layout viewport操作である。
- 2026-09-11: revealをwindow表示後へ一律遅延する案は、同じselectionの再renderや手動scrollまで
  奪う新しいlifecycle stateを必要とするため採用しない。初期document publicationはnavigationではなく
  先頭selectionも既にvisibleであり、既存document上のDart-owned selection変更だけをrevealする。
- 2026-09-11: presenterの判定を`selectionMovedByDart`へ狭め、`setDocument`ではrevealせず、既存
  documentへの`setSelection`時だけrevealするよう修正した。初回renderは従来どおりdocument、全style
  runs、selection、line highlight、detail/statusをkey入力前に投影する。
- 2026-09-11: fake hierarchy testは初回open直後のnative document/selection/style/highlightとreveal
  count 0を検査し、最初のNORMAL下移動でcount 1になる順序へ変更した。product configuration exerciseも
  最初のsettings key eventより前にnative snapshotのdocument、selection、read-only状態を検査し、exact
  acceptance markerへ`settings_initial_document=true`を追加した。
- 2026-09-11: 変更した4 Dart fileのformatterは0 changed、focused
  `terminal_native_hierarchy_test.dart`はexit 0、`dart analyze`は`No issues found!`となった。初回
  document/style/highlightとreveal 0、最初のNORMAL navigationでreveal 1、SEARCH/INSERTの既存境界を
  fake native bindingで確認した。
- 2026-09-11: `make phase7-appkit-acceptance terminal-compatibility-regression-coverage`は成功した。
  acceptance corpusは変更したhierarchy testとruntime application sourceのSHA-256だけ、compatibility
  reportはREADMEとFEATURE_MATRIXのSHA-256だけが更新され、criterion、case、fix familyに変化がない
  ことを差分で確認した。
- 2026-09-11: 完全`CI=true DART_SUPPRESS_ANALYTICS=true make test`はformatter 246 files / 0 changed、
  analyzer、全unit/native/integration freshness gateを含めて`dart_terminal tests passed`となった。
- 2026-09-11: `make runtime-source-check runtime-bundle-audit`は
  `DART_ONLY_SOURCE_AUDIT_PASS tracked=457 product_native_sources=0 reviewed_test_native_sources=1`、
  Developer JIT / Release AOT双方でbundle audit PASSとなった。
- 2026-09-11: M1の`make runtime-configuration-integration`は最初のSettings key event前にnative
  snapshotの全document、selection、read-only state、disabled syntaxとcurrent-line highlightを確認し、
  その後64行のNORMAL navigationと検索・編集・保存を継続した。Developer JIT（1653 ms）とRelease
  AOT（1067 ms）の双方で`settings_initial_document=true settings_viewport_follow=true`を含むexact
  markerがPASSした。

## 完了状態

complete。初回document publicationをpre-layout revealから分離し、Settingsは最初のkey入力前から
全設定項目を表示する。既存document上のNORMAL/SEARCH selection変更だけは引き続きviewportを追従し、
INSERTと手動scrollの所有権は変更しない。Phase 8の本追補に残作業はなく、Phase 9には着手しない。

## 再調査（2026-09-11）

- ユーザーの`make RUNTIME_ARCH=arm64 developer-jit-run`実行では`9540e89`後も初回本文が空で、key
  入力後に表示される。前回の「pre-layout revealが原因」という仮説は反証された。
- 前回のruntime acceptanceはkey入力前のnative snapshotにtextがあることを確認しただけで、AppKitが
  glyphを実際に描画したことは確認していなかった。このgateを実描画の証拠として扱った判断が誤りである。
- 本項目を未完了へ戻し、指定のDeveloper JIT通常起動で症状を再現し、初回draw invalidation/layoutの
  実状態を調べる。pixelまたはnative draw lifecycleを直接確認する回帰検査が通るまで再完了にしない。
- 指定コマンドでDeveloper JITを起動し、Command-comma直後を
  `/private/tmp/dart-terminal-settings-before-input.png`へcaptureした。左editorは本文が空でcurrent-line
  背景だけが表示され、報告を再現した。下キーを1回送った後の
  `/private/tmp/dart-terminal-settings-after-down.png`では全syntax textが表示された。
- 下キー経路で初回描画と異なるnative操作は、既にwindowがvisible/layout済みの状態で行う
  `setSelection`と`scrollSelectionToVisible:`である。前回削除したのはwindow show前のrevealだけで、
  document textのsnapshotが存在しても初回glyph layout/displayを確定しないことが実画面で判明した。
- document publication前後の`needsDisplay`だけで直す案はline highlight設定でも既に実行されているため
  根拠が弱い。新規windowだけはdocument/style/highlightを投影後にshow/focusし、viewが実frameとwindowを
  得た後で現在selectionを1回revealして初回layout/displayを確定する。以後は従来どおりselection移動時
  だけrevealし、再renderや手動scrollには追加しない。
- presenterの新規window経路へshow/focus後のone-shot revealを追加した。fake hierarchy testは初回
  document/style/highlight publicationに加え、`show -> responder -> reveal`の順序と初期reveal 1、最初の
  NORMAL navigation後のreveal 2を固定する。既存window再openや通常renderにはone-shotを追加しない。
- 上記one-shotだけのDeveloper JIT再確認では初回本文が空のままで、同一selectionのrevealはlayoutを
  発火しないことを確認した。その後`dart_appkit`でline-highlight設定時にglyph layoutを先に確定すると
  key入力前から全文が描画された。product one-shotは原因を直さないworkaroundなので削除し、初期reveal
  count 0を維持する。
- `dart_appkit`の最終方式は、line highlightがある`DaTextEditorTextView.drawRect:`で`super`より前に
  text container layoutを確定し、highlight rect側のdraw中layoutを除くものとした。指定Developer JITを
  product workaroundなしで再buildし、key入力前capture
  `/private/tmp/dart-terminal-settings-native-only-before-input.png`で全syntax textと行背景を直接確認した。
- native bitmapだけは旧実装も同期cache draw内でPASSしたため、最初のbackground drawより前にlayout callが
  済んだことをswizzleで記録するorder assertionを追加した。旧sourceへ一時的に戻すnegative-controlは
  そのassertionで失敗し、修正版を復元するとPASSするため、実regressionを識別できるtestになった。

## `dart_appkit` subtask完了（2026-09-11）

- sibling repositoryへ`DaTextEditorTextView.drawRect:`のprepaint layout、旧draw順序を識別するnative
  order/bitmap regression、README/verification/worklogをまとめ、commit `0255d07 Paint attributed editor
  text on first draw`として独立commitした。
- 最終sourceで`CI=true DART_SUPPRESS_ANALYTICS=true make native-test dart-test ffi-smoke`と
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`がともにPASSした。negative-controlでは旧実装だけが
  `g_text_editor_layout_ready_before_background_draw`で失敗した。
- product workaroundを含めずに指定Developer JITを起動したkey入力前capture
  `/private/tmp/dart-terminal-settings-native-only-before-input.png`でも全文syntax glyphとcurrent-line背景の
  同時表示を確認した。依存側の初回paint順序は確定し、次はproductのM1 Developer JIT / Release AOTを
  現行sourceで受け入れる。
