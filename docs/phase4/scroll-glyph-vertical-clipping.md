# Phase 4 — Scroll glyph vertical clipping follow-up

Status: complete (2026-09-11)

## 目的

primary scrollbackをwheelまたはprecision trackpadで移動しても、同じterminal rowのglyphが下端で欠けず、
停止位置や直前のscroll deltaに依存しない安定したCoreText/Metal表示を保証する。

## 背景

- 2026-09-11に提供された2枚の通常製品screenshotでは、中央付近のMarkdown fence
  `````shell`` 行が同じ内容にもかかわらず、一方だけ` shell`の下側が切れて見える。
- `/Users/remi/Desktop/スクリーンショット 2026-09-11 14.55.14.png`はscroll位置によって複数glyphの
  descender側が浅くなり、`/Users/remi/Desktop/スクリーンショット 2026-09-11 14.55.32.png`では同じ行が
  正常な高さに戻っている。
- terminal modelの文字内容は保持され、scroll後に表示が変化するため、parserやfont選択よりviewport座標、
  glyph quad/atlas UV、native scissor、またはdamage/frame reuseの可能性を優先して調べる。

## 範囲

- primary historyを含むviewport projectionからpacked Metal glyph instanceまでのrow/glyph座標。
- 1x/2x backing scale、fractional scroll accumulator、viewport row offset、content paddingの相互作用。
- glyph atlas bitmap/UVとMetal clip/scissor、damage更新、新旧frameの再利用境界。
- 原因を旧実装で再現するpixelまたはpacked-instance regressionと、M1 Developer JIT / Release AOT実画面受け入れ。

## 対象外

- terminal text内容、VT parser、scrollback eviction/reflow semantics、font familyやfont sizeの仕様変更。
- smooth pixel scrolling、elastic overscroll、scrollbarなど、新しいscroll UIの追加。
- Settings editorの`NSTextView`描画、Phase 9のmodern protocol実装。

## 依存関係

- `TerminalViewport`が整数row単位の可視screenを所有し、`TerminalScrollRouter`がprecision deltaをrow移動へ集約する。
- `TerminalLiveMetalSurface`、`TerminalScreenMetalCompositor`、`dart_terminal_renderer_macos`が実表示を構成する。
- canonical cell metrics、CoreText raster origin、atlas slice、packed Metal instanceの座標単位を1回だけscaleする必要がある。
- renderer capability側の欠陥なら、隣接`dart_appkit` repositoryを同じ現在タスクの依存修正として扱い、独立commitする。

## リスク

- glyph bitmap boundsは文字ごとに異なるため、特定文字だけのgoldenではrow境界clipを見逃す。
- screenshot比較だけではstale frame、fractional座標、atlas欠損を区別できないため、各境界の数値を直接固定する。
- clipを広げるだけの修正は隣接rowへのbleedやselection/cursor layerのずれを生む可能性がある。

## 完了条件

- 提供画像の差を説明できる再現条件と、欠ける層・座標境界を特定する。
- 修正前に失敗し修正後に通る、複数scroll位置と上下非対称glyphを使う決定論的回帰テストを追加する。
- glyph、background、selection、cursor、preeditのlayer順と1x/2x論理位置を回帰させない。
- formatter、focused test、analyzer、完全test、source/bundle auditが成功する。
- M1 Developer JIT / Release AOTの通常製品でscroll前後のglyph全高を実pixel確認し、resourceをcleanに解放する。
- README、FEATURE_MATRIX、検証記録、ROADMAPを更新し、タスク単位のcommit後にPhase 4と次タスクを再確認する。

## 検証方針

1. 提供画像の同一glyphをpixel単位で比較し、欠損がrow全体、glyph bitmap、またはviewport edgeのどこに現れるか測る。
2. scroll routing、viewport projection、compositor、packed encoder、Metal shader/native viewportを順に追跡する。
3. 最小fixtureでscroll位置を切り替え、同じlogical rowのinstance/CPU oracle/GPU readbackが一致することを固定する。
4. focused Dart/native test、完全suite、M1両runtimeの実GUI再現手順を実行する。

## 実装分割

1. `dart_appkit` に native `NSWindow.contentLayoutRect` の read-only API を追加する。
   C ABI、FFI/fake binding、Dart `Window` API、native/unit test を同じ contract として
   完了し、sibling repository で個別に commit する。
2. terminal hierarchy が初回から各 native tab window の content size を layout の
   available size に使うよう修正する。単一 pane、native tab、resize 後の既存経路を
   regression test し、実機 screenshot の glyph pixel 安定性を確認して main
   repository で commit する。

1は2の依存であり、順序を逆転しない。親項目は両方の検証が終わるまで完了にしない。

## 調査ログ

- 2026-09-11: `TerminalScrollAccumulator` は precision scroll delta を
  `cellHeight` で割って residual を保持し、product viewport へは `truncate()` した
  整数 row delta だけを渡すことを確認した。したがって、scroll 後の glyph origin に
  fractional viewport offset が直接残る、という仮説は成立しない。
- 2026-09-11: compositor は可視行を `0..rows-1` に再配置し、glyph baseline を
  logical row と cell metrics から計算する。glyph quad は個別の row rect では clip
  されず、content viewport 全体との交差だけで除外されることを確認した。
- 2026-09-11: 画像の定量比較に Pillow を使う案を試したが、開発環境に
  `PIL` module がなく `ModuleNotFoundError` となった。追加 dependency は導入せず、
  `sips` で生成した 32-bit BMP を標準 API だけで解析する方針へ変更した。
- 2026-09-11: 2枚を `sips` で 32-bit BMP へ変換し、標準 Dart API の一時解析器で
  中央の同一 `shell` を比較した。2枚目を `(x + 2, y - 25)` へ平行移動すると大半の
  pixel は一致する一方、1枚目では `s` などの最下段、2枚目では最上段側が欠ける。
  screenshot の縮小表示による錯視ではなく、scroll で同じ glyph が別の physical row
  へ移ったときに実 pixel が間引かれていることを確認した。
- 2026-09-11: `make RUNTIME_ARCH=arm64 developer-jit-run` を一時診断 log 付きで実行し、
  起動時と2つ目の tab 追加後の pane layout が常に `920.0 x 580.0` の outer window
  frame を使う一方、native `WindowResizedEvent` が1度も届かないことを確認した。
  実画面では title bar と native tab bar を除いた Metal view の高さは約511 pointで
  あり、frame header の約580 point相当の viewport が drawable へ縦縮小されている。
  `MTKView` は実 bounds から drawable を自動 resize するが、vertex shader は Dart
  frame header の viewport を NDC 変換に使うため、この不一致が行位置ごとの pixel
  間引きを生む根本原因である。
- 2026-09-11: 現在の `dart_appkit` は outer `Window.frame` だけを Dart API に公開し、
  native `contentLayoutRect` を初期 layout 前に取得する API を持たない。初回 content
  size を正確に投影するには、`dart_appkit` に read-only content layout rect を追加し、
  terminal hierarchy の初回/fallback layout に利用する必要がある。
- 2026-09-11: `dart_appkit` に `da_window_get_content_layout_rect` と
  `Window.contentLayoutRect` を追加した。C ABI は main-thread、null output、wrong handle
  kind を既存 status contract で拒否し、FFI は additive symbol を optional lookup して
  legacy bridge では明示的な unsupported error を返す。fake binding と Dart API の
  native error propagation も同じ contract に揃えた。
- 2026-09-11: sibling 検証は `make dart-test`（analyze、Dart API、launcher）、
  `make native-test`（Objective-C++ bridge）、`make contract-check`（C/C++ header）が成功した。
  最初の sandbox 内 `dart format` は sibling file の上書き権限と telemetry timestamp
  更新で失敗したため、承認済みの repository 外書き込みとして再実行し成功した。
- 2026-09-11: terminal hierarchy の順序を window生成、native tab grouping、content
  layout query、split layout、content view attach、presentationへ変更した。各tabは現在の
  native content width/heightを問い合わせ、成功値をcacheしてpane gridとMetal frameに
  使用する。additive symbolを持たない旧bridgeだけはstatus 8を境界に既存cache/outer
  frame fallbackへ戻し、それ以外のnative errorや非finite/非正寸法は隠さない。
- 2026-09-11: fake AppKitに69 pointのtitle/tab chrome差を持つfixtureを追加した。
  outer `920 x 580`の2 native tabがresize eventを1度も受けなくても、両paneの初回layoutが
  `920 x 511`になり、各windowのcontent queryが1回実行されることを固定した。このtestは
  修正前のouter-frame fallbackではheight 580となる回帰を直接検出する。
- 2026-09-11: focused testの最初のsandbox実行はMetal compilerのmodule cacheを
  `~/.cache/clang`へ作れず停止した。承認済みのbuild cacheアクセスで同じcommandを再実行し
  成功した。
- 2026-09-11: 一時診断付きの通常Developer JITを実行した。修正前は単一/2 tabとも
  `920 x 580`だったが、修正後は単一tab `920 x 548`、native tab bar追加直後に両tab
  `920 x 512`を取得した。2 tabで`cat README.md`を実行し、precision scrollを複数位置へ
  往復してLatin、日本語、backtick、`shell`を目視比較したところ、同じglyphの上下pixelは
  停止位置に依存せず全高を維持した。Command-Q後は2 PTY、worker、Metal/native ownerが
  cleanに解放された。一時診断出力は差分から除去した。
- 2026-09-11: 最初の完全`make test`は変更対象を追跡するPhase 7 AppKit acceptance SHAが
  staleとして意図どおり停止した。`make phase7-appkit-acceptance`で再生成し、差分が
  `terminal_native_hierarchy.dart`とそのtestの既存参照SHAだけであることを確認した。
- 2026-09-11: main repositoryの最初のcommit試行はsandboxが`.git/index.lock`を作成できず
  停止した。差分とstage済み内容は保持されており、承認済みのgit metadata書き込みとして
  同じcommitを再実行する。
- 2026-09-11: 最終検証結果:
  - `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_native_hierarchy_test.dart`: 成功。
  - `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、issue 0。
  - `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功、246 filesのformat差分0、全test成功。
  - `make RUNTIME_ARCH=arm64 release-aot-display release-aot-hierarchy`: 成功。
    Retina scale 2x、2 tab/4 pane hierarchy、100 MiB fairness、resource cleanupを受け入れた。
  - `make RUNTIME_ARCH=arm64 runtime-source-check developer-jit-audit release-aot-audit`: 成功。
    product native source 0、両bundleともhelper 1、asset 1、capability 1を確認した。

## 結論

欠けていたのはCoreText glyph bitmapやscroll row計算ではない。outer window frameで作った
Metal frameを、title/tab chromeを除いた小さいdrawableへCore Animationが縦縮小していたため、
glyphがscrollで別のphysical yへ移るたびに異なるpixel rowがresamplingで間引かれていた。
native content layoutを初回からframe viewportの正本にしたことで、Metal pixelとdrawable
pixelが1対1になり、scroll停止位置に依存する上下欠損を解消した。

- 2026-09-11: `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、repository構成、作業treeを確認した。
  Phase 8完了後の最初の未完了はPhase 9だったが、本件は既完了Phase 4 rendererのcorrectness条件を破るため、
  Phase 4末尾へ追補として登録した。着手時のworktreeはcleanだった。
- 2026-09-11: 添付2画像を原寸で確認した。window/frame/font/contentは同一で、primary historyの表示開始rowだけが
  異なる。文字列の欠落ではなく同一glyphの垂直ink extentがscroll停止位置で変化しているため、screen modelより
  render geometryを優先して調査する。
