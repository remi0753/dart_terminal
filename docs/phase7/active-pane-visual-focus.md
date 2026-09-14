# Active pane visual focus

更新日: 2026-09-14

## 目的

split paneを複数表示したとき、現在keyboard inputを受け取れるpaneを視覚的に一意に
判別できるようにする。active paneだけがcursorを表示・点滅し、ほかのpaneはcursorを
表示せず、terminal内容を壊さない範囲で背景を控えめに暗くする。

## 背景

application stateはtabごとのfocused paneを保持し、native hierarchyは選択中tabの
focused paneをfirst responderへ投影している。一方、各`TerminalLiveMetalSurface`は
pane focusを受け取らず、canonical terminal modelのcursor visibility/blinkだけで
cursorを描画する。このためsplit後も複数paneのcursorが同時に点滅し、input先を判別
しにくい。

## 範囲

- renderer presentationへactive/inactive pane状態を追加する。
- inactive中はterminal output、visual bell、image animationなどの表示更新を継続し、
  cursorの表示とblink deadlineだけを停止する。
- inactive paneではframe clearとcell backgroundを同じ規則で控えめに暗くし、既存の
  background alphaを保持する。
- main interactive productでwindow focus、selected tab、focused paneから唯一のactive
  surfaceを導出し、既存surfaceと新規surfaceの全てへlive投影する。
- focusの獲得・喪失、key/text input、mouse操作、tab/window/pane構成変更に追従する。
- Developer JITとRelease AOTの両runtimeで複数window/tab/pane境界を検証する。

## 対象外

- focused paneのcanonical VT cursor mode、shape、colorの変更
- pane divider、tab、window chromeのdesign変更
- Settingsまたはcommand paletteへの暗転適用
- accessibility cursor座標やPTY focus reporting protocolの意味変更
- inactive paneのPTY、parser、damage admission、image animation、visual bellの停止

## 依存関係

- `TerminalApplicationState`のactive window、selected tab、focused pane
- `TerminalNativeHierarchyAdapter`のwindow visibility/focusとfirst responder投影
- `TerminalLiveMetalSurface`、`TerminalNewestFrameScheduler`、
  `TerminalPresentationClock`
- `TerminalScreenMetalCompositor`のframe background、cell background、cursor layer
- 共有background opacity contract。暗転でalphaを増減させてはならない。

## 分割と実施順

1. **active/inactive pane presentation contractとrenderer検証**
   - presentation clockへpane active状態を追加し、inactiveではcursorを描かずblink
     deadlineを保持しない。
   - reactivationは最新modelからvisible cursor phaseを再開する。
   - compositorはinactive時だけframe/cell backgroundのRGBを一定割合で暗くし、alpha、
     glyph、selection、image、visual bellの契約を変えない。
   - clock、scheduler、compositor、live surfaceのunit/native testで境界を固定する。
2. **全window・tab・paneへのfocus投影と両runtime受け入れ**
   - main interactive hierarchyでnative windowがvisibleかつfocusedであり、そのwindowの
     selected tabのfocused paneであるsurfaceだけをactiveにする。
   - windowがfocusを失った場合は全terminal surfaceをinactiveにする。Settingsやcommand
     paletteはterminal surfaceではないため暗転対象にしない。
   - resource生成、key/text/mouse focus変更、reconcile、close/restore後にも再計算する。
   - 複数window/tab/paneのproduct acceptanceをDeveloper JITとRelease AOTで通す。

各subtaskを上記順に実装・検証・記録・commitし、先行subtaskを完了するまで次へ進まない。

## 完了条件

- application全体で、現在input可能なterminal paneだけにcursorが表示される。
- active paneのblinking cursorだけがdeadline駆動され、inactive paneはcursor instanceを
  一切生成しない。
- inactive paneのterminal背景はactive paneより控えめに暗く、frame clearとANSI cell
  backgroundの両方へ一貫して適用される。
- 暗転前後でbackground alphaが同一であり、設定済みopacityを壊さない。
- inactive paneも新しいPTY damageとcursor以外のpresentation animationを描画できる。
- window/tab/paneの作成、選択、分割、focus移動、非focus化にliveで追従する。
- unit/native test、静的解析、関連integration、full testが通る。

## 検証方針

- `test/frame_scheduler_test.dart`でinactive cursor、deadline停止、reactivationを検証する。
- `test/terminal_screen_metal_compositor_test.dart`でcursor instance非生成、背景RGB暗転、
  alpha保持を検証する。
- live surface testでfocus変更がfull redrawを要求し、最新frameへ反映されることを検証する。
- product acceptanceで複数window/tab/paneのうちactive surfaceが常に最大1つであることを
  markerとassertionで確認し、両runtime configurationから実行する。
- `dart format`、`dart analyze`、関連test、`make test`を実行する。

## 調査記録

### 2026-09-14 着手時

- working treeはclean、branchは`main`。
- `TerminalPresentationClock`はwindow visibility/occlusion/system suspensionを理由に
  pauseできるが、pauseはvisual bellなど全presentation deadlineを止める。pane inactive
  は画面上に見えたままなので、このpause contractを流用しない。
- 現在の`TerminalFramePresentation.cursorDrawn`はterminal modelとblink phaseだけで決まり、
  pane focusを含まない。
- compositorはdefault backgroundをframe clear、ANSI backgroundをcell background instance、
  cursorを最終layerとして構成する。背景暗転はRGBだけを変更しalphaを保持すれば、terminal
  background opacityと独立に合成できる。
- main interactive productはraw key入力時に`focusPane`後reconcileするが、committed text経路は
  `focusPane`後にreconcileしていない。window focus loss時もhierarchy reconcileを呼ばないため、
  surface focus投影にはfocus獲得・喪失の両方を扱う同期処理が必要。
- `dart_appkit`の`AppKitApplication`と`Window`はそれぞれ`isActive`、`isFocused`、
  `isVisible`をevent受信時に保持する。selected tabのnative windowを照合すれば、logical
  focusだけに依存せず実際にinput可能なpaneを導出できる。

## 設計判断

- pane inactiveはwindow occlusionと異なる状態として扱う。PTY/model/frame更新は継続し、
  cursor blink workだけを抑制する。
- dimmingは背景colorのRGBへだけ適用しalphaを保存する。半透明black overlayは透明背景の
  alphaを増やして共有opacity設定を壊すため採用しない。
- inactive background brightnessはactive RGBの82%とした。glyph、decoration、selection、
  image、visual bellは暗転せず、default clearとexplicit ANSI backgroundだけへ適用する。
- active surfaceはDart application stateだけで決めず、対応するnative windowのvisible/focused
  状態も含める。これにより別window、Settings、command palette、application切替時に複数cursorが
  残らない。

## 検証結果

### 2026-09-14 presentation contract（進行中）

- `DART_SUPPRESS_ANALYTICS=true dart run test/frame_scheduler_test.dart`: 成功。
- 同testの初回sandbox内実行はMetal build hookが
  `~/.cache/clang/ModuleCache`へ書き込めず失敗した。実装失敗ではなくsandbox境界であり、
  同じcommandを許可済みsandbox外で再実行して成功した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_screen_metal_compositor_test.dart`:
  初回はinactive presentationへ意図的に`cursorDrawn: true`を渡したtestでcursor instanceが
  残り失敗した。clockだけで抑止してcompositor最終境界にguardがなかったことが原因。
  compositorも`isPaneActive`を必須条件にして矛盾した入力をfail-safeに非表示へ寄せた。
- 上記compositor testを修正後に再実行: 成功。base clearとANSI backgroundのRGB暗転、
  alpha不変、active cursor生成、inactive cursor非生成を確認した。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- `git diff --check`: 成功。

### 2026-09-14 product focus projection（進行中）

- `make developer-jit-actions`初回: 失敗。5 paneを順にfocusするacceptanceで、同一window
  内のpane/tabは通過したが、最後の別window paneへlogical stateを直接切り替えた後にnative
  key-window focusが移らず、`focus projection did not isolate active pane 5`となった。
  surface投影はnative `Window.isFocused`を正しく要求しており、testがlogical stateだけを変更して
  実native focus遷移を起こしていないことが原因候補。native hierarchyのpresent/reconcile契約と
  acceptance操作を追加確認する。
- `TerminalNativeHierarchyAdapter.reconcile`は既存windowのlogical active ID変更だけでは
  key windowを切り替えない。実user操作ではAppKitのwindow focus eventが先に発生する境界であり、
  acceptanceでは既存の`Window.show/selectTab/makeFirstResponder` contractを使って実native focus
  遷移を起こしてから唯一のactive surfaceを検証する。
- Developer JIT 2回目はapplication acceptanceの全assertionを通過したが、既存
  `TERMINAL_USER_ACTIONS_TEST`行へfieldを追加したためdriverのexact marker checkだけが失敗した。
  既存markerを維持し、active pane contractは独立した
  `TERMINAL_ACTIVE_PANE_FOCUS_TEST` markerとしてdriverでexact検証する。
- 上記marker分離後の`make developer-jit-actions`: 成功。1/1/1初期状態、split、tab、
  window、Update画面、command palette、5 paneのfocus移譲、close後の再focusでactive surfaceが
  0または正確に1であることを確認した。
- `make release-aot-actions`初回: focus assertionはpane 5生成まで進んだが、pane start中に
  `ApplicationScreenSetChangedEvent`の遅延drainが入り、logical stateへ追加済みでまだnative
  projection前のwindow 2を`recoverDisplaySet`が要求して終了status 70となった。新規window/tab/
  paneはPTY start成功後にprojectするため、screen-set callbackと非同期hierarchy mutationの間に
  既存raceがあった。
- screen recovery callbackはlogical/native window・pane数が一致しない間だけ`false`を返し、
  controllerがpending recoveryを保持する。次のhierarchy reconcile完了時に明示retryし、成功時
  だけrecovery countとwake後resumeを進める。失敗したpaneを一時表示せず、screen-set eventも
  欠落させない設計を採用した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_system_recovery_test.dart`: sandbox内では
  Metal module cacheへ書き込めず失敗。通常のuser権限で再実行し成功した。hierarchy不一致時の
  pending保持、reconcile後のexactly-once retry、重複schedule抑止を確認した。
- race修正後の`make release-aot-actions`: 成功。Developer JITと同じactive-pane marker、
  5 paneのinput分離、全session/native owner回収を確認した。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 通常のuser権限で成功、issue 0。
- formatterへ誤って`README.md`と`FEATURE_MATRIX.md`も渡した試行はMarkdown parse errorで
  終了した。対象Dart 6 fileは同じ出力で0 changeだったが、この試行は検証成功に数えず、
  source-onlyのformatterと`make test`の全Dart format gateで再確認する。
- 最初の`make test`は実装失敗ではなく、source hashを固定するPhase 7 AppKit acceptance、
  Ghostty P0/P1 gap inventory、release-candidate daily-use matrixが順にstaleで停止した。
  canonical generatorを依存順に実行し、意味上の件数を維持したままhash evidenceを更新する。
- active paneのsource、renderer unit test、`TERMINAL_ACTIVE_PANE_FOCUS_TEST`をPhase 7
  acceptance inventoryへ明示追加した後の`make test`は、checker本体の旧exact total
  （13 source／10 unit／8 UI）が新しい14／12／9を拒否して停止した。inventory出力は正しく、
  reviewed total assertionを新しい証拠件数へ更新する。

### 2026-09-14 presentation contract完了

- `TerminalFramePresentation`はpane active状態をimmutable frame metadataとして保持する。
- `TerminalPresentationClock`はinactive中もrunning状態とvisual bellを維持する一方、cursorを
  非表示にしてcursor deadlineを破棄する。reactivationは最新のcursor modelからvisible phaseを
  再開する。
- `TerminalNewestFrameScheduler.updatePaneActive`はfocus変更をfull redrawとしてcoalesceする。
- `TerminalLiveMetalSurface.updatePaneActive`はdesired stateを非同期drainへ渡し、snapshotから
  content-freeなactive状態を確認できる。
- surface生成時のdesired/published active値は同じ初期値にそろえる。初期inactive surfaceが
  最初のdrain前にactiveへ変わっても、schedulerのinactive状態を取り残さない。
- product surfaceはinactiveで生成し、native hierarchy reconcile後にactive候補を投影する。
  focus遷移中も複数paneが一時的にactiveになることを許さない。
- `TerminalScreenMetalCompositor`はinactive cursorを最終境界でも拒否し、default/ANSI背景の
  alphaを維持したRGB暗転を行う。

## 残課題・阻害要因

現時点ではなし。

## 2026-09-14 focus projection完了

- `synchronizePaneFocusPresentation`はapplication active、native window visible/focused、
  logical active window、selected tab、focused paneをすべて満たすsurfaceだけをactiveにする。
  surfaceはinactiveで生成し、reconcile、raw key、IME commit、mouse focus、window focus/
  visibility、application active、tab/window/paneの作成・closeに追従する。
- Update画面とcommand paletteがkey windowの間はactive terminal surfaceを0にし、dismiss後は
  terminal first responderと同時に正確に1 paneをreactivateする。5 paneを順にfocusする
  product acceptanceで各PTYへのraw key/IME分離も維持した。
- screen-set recoveryと非同期hierarchy mutationのraceは、controllerが未適用workをpendingに
  保持し、logical/native hierarchyの次回reconcile成功後だけretryすることで解消した。
- Phase 7 acceptance inventoryへactive focus source、frame/compositor unit tests、両runtimeの
  exact markerを追加した。最終inventoryは4 criteria、14 source、12 unit、4 integration、
  9 real-UI assertionを持つ。
- READMEとFEATURE_MATRIXのrenderer／application UX evidenceを更新し、依存するcompatibility
  coverage、Ghostty gap inventory、release-candidate matrixをcanonical generatorで再生成した。

## 最終検証結果

- source-only `dart format --output=none --set-exit-if-changed`: 6 files、0 change。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_system_recovery_test.dart`: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/phase7_appkit_acceptance_test.dart`: 成功。
- `make developer-jit-actions`: 成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=3151`。
- `make release-aot-actions`: 成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=2310`。
- `make test`: 成功。338 Dart filesはformat 0 change、analysis issue 0、
  `PHASE7_APPKIT_ACCEPTANCE_PASS criteria=4 source_refs=14 unit_tests=12 integration_tests=4
  ui_assertions=9`、`dart_terminal tests passed`を確認した。
- Phase 7 acceptance、compatibility regression coverage、Ghostty P0/P1 gap inventory、
  release-candidate daily-use matrixの4 freshness check: すべて成功、release blocker 0。
- `git diff --check`: 成功。

## 残課題・阻害要因（完了時）

なし。既存の主要ゴール後follow-up以外に新しいROADMAP項目は追加していない。
