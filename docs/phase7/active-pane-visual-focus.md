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
- inactive paneではframe clearとcell backgroundを暗くし、さらにterminal viewport全体へ
  neutral charcoal scrimを重ねて、黒／透過背景でも文字、画像を含むpane全体をactive paneより
  暗くする。
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
- 共有background opacity contract。active paneの設定値は変えず、inactive paneだけにfocus
  presentationとして独立したneutral charcoal scrimを合成する。

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
3. **黒／透過背景でも判別できるinactive pane全体の暗転強化**
   - 既存のRGB暗転では変化しないblack backgroundと、背面が透けて差が弱い低opacityを
     viewport全体の最終black scrimで補う。
   - active paneは従来どおりの色とopacityを維持し、inactive paneだけでglyph、selection、
     decoration、Kitty imageを含む最終出力を一様に後退させる。
   - 専用のpacked Metal layerを追加し、Dart encoderとnative validatorのlayer順を一致させる。
   - compositor／renderer test、両runtime configuration、full testで検証する。
4. **inactive paneへの濃いneutral gray tint追加**
   - pure black 24% scrimを、より濃い32%のneutral charcoal grayへ調整する。
   - transparent black上でもalpha差だけでなくRGB tintが生じることを実Metal pixelで検証する。
   - active pane、cursor抑制、layer ordering、focus投影の契約は変更しない。

各subtaskを上記順に実装・検証・記録・commitし、先行subtaskを完了するまで次へ進まない。

## 完了条件

- application全体で、現在input可能なterminal paneだけにcursorが表示される。
- active paneのblinking cursorだけがdeadline駆動され、inactive paneはcursor instanceを
  一切生成しない。
- inactive paneのterminal viewport全体はactive paneより明確に暗く、blackかつ低opacityの
  default backgroundでも最終neutral charcoal scrimが濃いgray tintを加える。
- active paneのbackground alphaは設定値どおりで、inactive focus presentationだけが
  独立したscrimを加える。
- inactive paneも新しいPTY damageとcursor以外のpresentation animationを描画できる。
- window/tab/paneの作成、選択、分割、focus移動、非focus化にliveで追従する。
- unit/native test、静的解析、関連integration、full testが通る。

## 検証方針

- `test/frame_scheduler_test.dart`でinactive cursor、deadline停止、reactivationを検証する。
- `test/terminal_screen_metal_compositor_test.dart`でcursor instance非生成、背景RGB暗転、
  active側alpha保持、inactiveだけの全viewport最終scrimを検証する。
- live surface testでfocus変更がfull redrawを要求し、最新frameへ反映されることを検証する。
- product acceptanceで複数window/tab/paneのうちactive surfaceが常に最大1つであることを
  markerとassertionで確認し、両runtime configurationから実行する。
- `dart format`、`dart analyze`、関連test、`make test`を実行する。

## 調査記録

### 2026-09-14 inactive charcoal tint follow-up着手時

- user確認で、inactive paneへさらに黒／濃いgrayの色味を加える要望があった。
- 現在のscrimはpure blackの24% alphaであり、透明blackでは背面を抑えるがscrim自体のRGBは
  0のためneutral grayの色差を作らない。
- neutral dark gray `#181818`を32% alphaで最終pane scrimへ使う。既存の背景RGB 82%暗転も
  維持するため、文字・画像など明るいvisualはさらに後退し、transparent blackの空白部にも
  わずかなcharcoal tintが加わる。
- 対象範囲はcompositor定数、Metal pixel contract、README／FEATURE_MATRIX／生成済み証跡。
  対象外は設定項目の追加、focus導出、native layer kind／shader／cursor clockの変更。
- 完了条件はactive paneにscrimがないこと、inactive scrimが`#181818`／32%で全viewportの
  最終layerであること、実Metal readbackでtransparent blackにneutral RGB tintと十分なalpha差が
  現れること、両runtimeとfull testが成功することとする。
- compositorへ`inactivePaneScrimRgb = 0x181818`を追加し、opacityを24%から32%へ変更した。
  packed colorはcanonical straight-alpha `0x18181852`となり、native kind／layer順は既存の
  `paneScrim`をそのまま使う。
- testはscrimの全viewport geometryとexact packed colorに加え、20% transparent blackの
  実Metal readbackでactive pixelはRGB 0、inactive pixelは等値かつ非0のneutral RGB、alphaは
  activeより30段階超大きいことを要求するよう更新した。
- `dart format`は変更Dart 3 files中1 fileを整形して成功した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_screen_metal_compositor_test.dart`:
  成功。新しいcharcoal tint、alpha差、active側scrimなし、cursor非生成を確認した。
- `make developer-jit-actions`初回: 失敗。rendererは起動して初期paneを生成したが、ログ上
  `application_active=false`のままactive surfaceが0で、user-action acceptanceの
  `initial terminal pane did not become the sole active surface`によりstatus 70で終了した。
  今回の変更はscrim color／opacityとそのtestだけでfocus投影へ触れておらず、前回同gateは
  成功している。AppKit activationの一時的な実行環境raceかを同command再実行で確認する。
- 同じ`make developer-jit-actions`の2回目は成功し、2 window／3 tab／4 paneの操作と
  active surface分離を完走した（elapsed 3405 ms）。初回は再現せず、AppKit activationの
  一時的な実行環境raceと確認した。
- `make release-aot-actions`: 成功。Developer JITと同じ2 window／3 tab／4 paneの操作を
  完走した（elapsed 2114 ms）。

### 2026-09-14 inactive contrast follow-up着手時

- user確認で、black backgroundと低いbackground opacityの組み合わせではactive/inactiveの
  差がほとんど判別できないことが判明した。
- 既存処理は背景RGBへ82%を乗算してalphaを保存する。blackは`0 * 0.82 = 0`のため色が
  変わらず、低opacityでは背面の寄与が残るため暗転のsignalがさらに弱い。
- 背景だけを調整してもglyph、selection、decoration、Kitty imageは同じ明るさのままであり、
  pane全体のfocus hierarchyを示すには不十分と判断した。
- packed instanceは非減少のlayer順をDart encoderとnative validatorの両方で検査する。
  cursor kindの流用は「inactive paneはcursor instanceを生成しない」契約を壊すため、solid
  `paneScrim`をcursorより後の専用layerとして追加する。
- scrimはinactive時だけviewport全体へ最後に1枚配置する。blackの24% alphaを採用し、
  active paneの色／opacityは不変、inactive paneの既存RGB暗転は維持する。
- 対象外はfocus導出、cursor clock、設定schema、pane divider／window chromeの変更。
  完了条件はblack／低opacityでもscrimが存在し、全visual layerの後に配置され、activeでは
  存在しないこと、既存cursor分離と両runtime受け入れを維持することとする。
- 初回`dart format`は対象5 fileのうち2 fileを整形した後、sandbox外の
  `~/.dart-tool/dart-flutter-telemetry-session.json`のmtime更新を拒否されstatus 1になった。
  source整形自体とは別のsandbox境界なので、analytics抑止付きcommandで再検証する。
- analytics抑止付きformatterも5 file、0 changeを確認後に同じtelemetry mtimeでstatus 1に
  なった。通常user権限で同commandを再実行し、5 file、0 change、status 0を確認した。
- compositor testのsandbox内初回実行はMetal build hookが
  `~/.cache/clang/ModuleCache`へ書き込めず失敗した。shader／test failureではないため、
  通常user権限で同commandを再実行する。
- package単体のMetal renderer testもsandbox内では同じClang module cache境界で失敗した。
  Dart/nativeの新しいlayer番号を直接検証するため、こちらも通常user権限で再実行する。
- `paneScrim`をnative value 10／layer order 9として追加し、cursorを含む既存全layerより後の
  solid primitiveとしてDart encoderとnative validatorを一致させた。shaderのsolid color
  pathはkind固有分岐を必要としないため変更していない。
- compositorはcontent offset適用後に、inactive時だけviewport原点から全幅・全高のscrimを
  追加する。paddingを含むpane surface全体を覆い、active時はinstance数も色も変えない。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_screen_metal_compositor_test.dart`を
  通常user権限で再実行し成功した。20% opacityのblack clearについて実Metal readbackの
  inactive alphaがactiveより30段階超大きいこと、RGBはblackのまま、scrimが最後の全viewport
  instanceであることを確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run packages/dart_terminal_renderer_macos/test/
  metal_renderer_test.dart`を通常user権限で再実行し成功した。scrimのnative value、最終layer
  order、atlas非参照のsolid contractを確認した。

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

## 2026-09-14 inactive contrast follow-up完了

- inactive paneの既存82%背景RGB暗転に加え、cursorより後の最終layerへ24% black scrimを
  1枚追加した。scrimはcontent insetやpaddingも含むMetal viewport全体を覆う。
- active paneにはscrimを生成せず、設定済みbackground opacityと全visual colorをそのまま
  維持する。inactive paneではblack／低opacityでもscrimが背面の透過を抑え、glyph、selection、
  decoration、Kitty image、visual bellを含む最終出力全体を一様に暗くする。
- Dart packed encoderとObjective-C native validatorへnative value 10／layer order 9を追加し、
  solid colorを処理する既存Metal shader pathを使用した。cursor instanceの意味は流用していない。
- README、FEATURE_MATRIX、Phase 7 acceptance source requirementを更新し、compatibility
  regression coverage、Phase 7 acceptance、Ghostty gap inventory、release-candidate matrixを
  canonical generatorで再生成した。

### follow-up最終検証結果

- `dart format --output=none --set-exit-if-changed`（変更Dart 5 files）: 0 change、成功。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: issue 0、成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_screen_metal_compositor_test.dart`:
  成功。active側scrimなし、inactive側の最終全viewport scrim、transparent blackの実Metal
  pixel差、既存背景RGB暗転とcursor非生成を確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run packages/dart_terminal_renderer_macos/test/
  metal_renderer_test.dart`: 成功。新しいnative kindとlayer順、solid contractを確認した。
- `make developer-jit-actions`: 成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=3168`。
- `make release-aot-actions`: 成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=2200`。
- `make test`: 成功。338 Dart filesはformat 0 change、analysis issue 0、renderer native
  capability／Dart test、Phase 7 acceptance、全freshness check、security stressを含め、最後に
  `dart_terminal tests passed`を確認した。
- `PHASE7_APPKIT_ACCEPTANCE_PASS`: criteria 4、source refs 14、unit tests 12、integration
  tests 4、real-UI assertions 9。release blockerは0のまま。
- `git diff --check`: 実装差分確認時に成功。最終文書更新後もcommit前に再確認する。
- 初回`git commit`はfilesystem sandboxが`.git/index.lock`の作成を拒否して失敗した。
  staged差分は保持されており、通常user権限で同じcommitを再実行する。

### follow-up残課題・阻害要因

なし。既存の主要ゴール後follow-up以外に未完了項目は追加していない。

## 2026-09-14 inactive charcoal tint follow-up完了

- inactive paneの最終scrimをpure black 24%からneutral charcoal `#181818` 32%へ変更した。
  active paneの色／opacityは変更せず、inactive paneだけに濃いgray tintを加える。
- transparent black 20%の実Metal pixel testを更新し、inactive pixelに等値・非0のneutral
  RGBが生じ、alphaもactiveより30段階超大きくなることを確認した。scrimは引き続き全viewportの
  最終layerであり、inactive cursor instanceは生成しない。
- README、FEATURE_MATRIX、Phase 7 acceptance source requirementを更新した。compatibility
  regression coverage、Phase 7 acceptance、Ghostty gap inventory、release-candidate matrixは
  canonical generatorで再生成した。

### charcoal tint最終検証結果

- `dart format`（変更Dart 3 files）: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_screen_metal_compositor_test.dart`:
  成功。exact `0x18181852` scrim、実Metal RGB／alpha差、active側不変を確認した。
- `make developer-jit-actions`: 2回目成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=3405`。
  初回の一時的なAppKit activation raceは上記調査記録のとおりで、再現しなかった。
- `make release-aot-actions`: 成功、
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS ... windows=2 tabs=3 panes=4 elapsed_ms=2114`。
- `make test`: 成功。338 Dart filesのformat 0 change、analysis issue 0、native renderer、
  Phase 7 acceptance、互換性freshness、security stressを含め`dart_terminal tests passed`を確認。
- `PHASE7_APPKIT_ACCEPTANCE_PASS`: criteria 4、source refs 14、unit tests 12、integration
  tests 4、real-UI assertions 9。release blocker 0。

### charcoal tint残課題・阻害要因

なし。既存の主要ゴール後follow-up以外に未完了項目は追加していない。
