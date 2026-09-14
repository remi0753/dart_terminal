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
- `TerminalScreenMetalCompositor`はinactive cursorを最終境界でも拒否し、default/ANSI背景の
  alphaを維持したRGB暗転を行う。

## 残課題・阻害要因

現時点ではなし。
