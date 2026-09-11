# Retina terminal / Settings typography parity

Status: complete (2026-09-11)

## 目的

zero-config terminal本文とSettings editor本文が、同じsystem monospace regular / 14ptを
metadata上だけでなくRetina実表示でも同じ論理寸法として描画されるようにする。point size、
cell metrics、raster bitmap、Metal viewportのscale関係を検証し、glyphのinkが小さくなる回帰を
pixel-level acceptanceで防ぐ。

## 背景と再現情報

- ユーザー提供の`スクリーンショット 2026-09-11 12.00.09.png`は、terminal起動直後に
  Settingsを開いた状態である。
- Settings documentには`font-family = system`、`font-size = 14`が表示されているが、背後の
  terminal promptはSettings editorより明らかに小さく、glyph間の空間に対してinkも小さい。
- 直前の`shared-terminal-settings-typography`タスクは、schema、renderer catalog、Settings
  editorがsystem monospace / regular / 14ptを選ぶことだけを検査した。実rasterの1x/2x間の
  ink寸法は比較しておらず、ユーザーが求めたobservable parityの完了根拠として不十分だった。
- native `RasterizeGlyph`はscaleを使ってbitmap boundsとglyph originを拡大する一方、現状の
  `CGBitmapContext`には対応するCTM scaleが見当たらない。2x bitmap内へ1x glyphを描いている
  可能性が第一仮説である。
- 既存native testは2xのpixel storage増加と非zero coverageを確認するだけで、2x ink boundsが
  1xの約2倍になることを検査していない。product display acceptanceもfont point metadataと
  正のscale値だけを確認し、surfaceが公開したscaleやink extentを固定していない。

## 分割と実施順

### 1. renderer CoreText raster scale

対象は`../dart_appkit/packages/dart_terminal_renderer_macos`。1x/2xの同一glyphをpixel計測して
仮説を確定し、CoreText描画へ正しいdevice scaleを一度だけ適用する。alpha glyphとcolor glyph、
top-down orientation、origin、bounded buffer、既存ABIを維持し、native/Dart testで論理ink寸法が
scale間で一致することを検査する。

完了条件:

- 修正前の1x/2x ink boundsが不一致であることを再現記録できる。
- 2x rasterのink width/heightが1xのおよそ2倍になり、scaleで割った論理寸法が許容誤差内で一致する。
- 既存orientation、mixed alpha/color、buffer/generation testが成功する。
- `dart_appkit`側のworklog/verificationを更新し、独立コミットする。

### 2. product observable acceptance

renderer修正後、dart_terminal側でnative backing scaleとactual glyph inkの関係を検査する回帰を追加する。
実AppKit Developer JIT / Release AOTのterminal displayとSettings configurationを再実行し、README、
feature matrix、generated evidenceを事実に合わせて更新する。

完了条件:

- shared 14pt policyに加え、1x/2x rasterのlogical ink parityをproduct testで確認する。
- runtime display acceptanceがsurfaceのRetina scale適用を具体値で確認し、単なる正数をpassにしない。
- formatter、analyzer、全test、source/bundle audit、両runtimeのdisplay/configurationが成功する。
- スクリーンショットで報告された縮小原因と修正境界を記録し、Phase 8を再完了できる。

## 範囲

- CoreText glyph rasterのpoint-to-device-pixel変換。
- glyph origin、bitmap extent、top-down pixel orientationの整合。
- terminal productのbacking-scale伝播とobservable raster scaleの受け入れ。
- alpha/CJK/color emojiを含む関連regression、文書、生成証拠。

## 対象外

- 14ptというproduct default自体の変更。
- terminalとSettingsで異なるline height、padding、syntax colorを同一化すること。
- user指定font、theme、shell promptのデザイン変更。
- Metal shader、atlas ABI、font catalog ABIの不要な変更。

## 依存関係とリスク

- native修正は`dart_appkit` repository内のdependency-owned rendererへ行う。terminal repositoryへ
  native sourceを持ち込まない。
- CGContextへscaleを追加する位置や座標変換を誤ると、二重scale、上下反転、clipping、color emojiの
  premultiplied/straight alpha変換に回帰し得る。修正前後のink boundsと既存pixel goldenを併用する。
- 2x ink boundsはhinting/antialiasingで厳密な整数倍にならない可能性があるため、logical extentの
  量子化を考慮した狭い許容誤差を実測から定める。
- 修正にABI追加は不要と見込む。既存scale parameterの実装契約を正す変更として扱う。

## 検証方針

1. 同一glyphの1x/2x alpha bounds、coverage、originを修正前に計測する。
2. `dart_terminal_renderer_macos`のDart testとnative capability testを実行する。
3. `dart_appkit`全体のformat/analyze/test、必要なruntime bundle testを実行する。
4. dart_terminalのfocused font/compositor/native hierarchy testと全`make test`を実行する。
5. M1 arm64 Developer JIT / Release AOTのdisplay、configuration、bundle/source auditを実行する。

## 現在の仮説

`RasterizeGlyph`がscaled bitmapを作成した後に`CTFontDrawGlyphs`をunscaled CGContextへ描くため、
Retina 2xでもglyph coverageは1xのpixel寸法に留まる。一方、cell positionとbitmap record extentは
scaleされるため、文字間隔に対してinkだけが小さいスクリーンショットの特徴と一致する。pixel計測で
この仮説を確認してから修正する。

## 調査・実装ログ

- 2026-09-11: system monospace regular 14ptの`M`を現行native assetで計測した。
  1xはrecord `10x13`、ink `8x11`、coverage `9575`だった。2xはrecord `17x23`へ
  拡大した一方、inkは`8x11`、coverage `9574`のままで、ink originだけ`0,12`へ移動した。
  2x bitmap内へ1x glyphがそのまま描かれていることをpixel値で再現し、第一仮説を確定した。
  SettingsのNSTextViewはAppKitがRetina scaleを適用するため、この差が報告画像の見た目を生む。
- 2026-09-11: 前タスクの受け入れ不足は、`fontPointSize == 14`、system family、正のbacking
  scale、2x record byte増加だけを確認し、non-zero alphaの実boundsがscaleに比例することを
  検査しなかった点にある。修正ではmetadata assertionを残したままink bounds assertionを追加する。
- 2026-09-11: `dart_appkit`の`RasterizeGlyph`へ、point-spaceのfont/positionとdevice-pixel
  bitmapを対応させる`CGContextScaleCTM(context, scale, scale)`を追加した。公開ABI、catalog
  metrics、record layoutは変更していない。
- 2026-09-11: dependency側のDart/native testはLatin `M`、CJK `日`、color emoji clusterの
  non-zero alpha boundsとcoverageを1x/2xで比較する。修正後の実測はそれぞれ`8x11 -> 15x21`、
  `10x13 -> 20x24`、`18x18 -> 32x34`で、pixel量子化を除いたlogical extentが一致した。
- 2026-09-11: focused warning-as-error native capability test、renderer package analyze/Dart
  native-asset test、formatter(`0 changed`)に加え、`dart_appkit`の完全な`make test`が成功した。
  bridge、Runner、runtime、renderer、PTY、全package analyzer/test、launcher、Kernel、current/
  legacy FFIを含む。
- 2026-09-11: dependency修正を`dart_appkit` commit
  `6e512a03063ed15196c3856c63cc07866eb1946f` (`Scale CoreText glyph rasters for Retina`)
  として独立コミットした。第一サブタスクに残存blockerはない。
- 2026-09-11: product側の受け入れは二層にする。第一層は共有するsystem
  monospace regular / 14pt catalogのLatin、CJK、color emojiを実際に1x/2x rasterizeし、
  non-zero alphaの論理ink width/heightとcoverageを比較するpixel regressionとする。第二層は
  実AppKit windowの`backingScaleFactor`を16.16 fixed pointにし、live Metal surfaceの
  `scale16_16`と完全一致するまでbounded waitするruntime acceptanceとする。driverは両方の
  具体値を別々取得して等値比較し、従来の「正の値である」だけではpassさせない。
- 2026-09-11: runtimeのscale受け入れは2x固定にしない。1x外部displayでも正しいため、
  window/surfaceの同期をportableな完了条件とし、現在のM1 Retina実行で得た具体値を
  検証ログに残す。2xコードパス自体は第一層のpixel regressionで常に実行する。
- 2026-09-11: productのpixel regressionは修正済みnative assetで成功した。Developer JITと
  Release AOTの実display acceptanceもどちらもwindow/surface `scale16_16=131072`
  (Retina 2x)で成功し、Settings/configuration acceptanceも両runtimeで成功した。
- 2026-09-11: 初回の完全`make test`は、旧ラスタ出力を保持したchecked-in
  `atlas-2x.dtgi`が座標`(37, 24)`で新出力と不一致となり停止した。これは正しく
  大きくなった2x inkに対する想定済み証拠更新である。明示的な`--write-goldens`
  経路でtext goldenのみを再生成し、1xがbyte-identicalで2xだけが変更することを確認する。
- 2026-09-11: `dart run test/glyph_atlas_test.dart --write-goldens`で再生成した結果、
  `atlas-1x.dtgi`は非変更でSHA-256
  `d29670252e1e8885bc96082602752f5fb9fa6b7e6518c16124da124514014798`を維持し、
  `atlas-2x.dtgi`だけがSHA-256
  `c05c342c19c029834935caf80e5624ee597ddfdaa37c41e893960c6d332065d0`へ変更した。
  focused atlas/golden testは更新後に成功した。
- 2026-09-11: `make phase7-appkit-acceptance` と
  `make terminal-compatibility-regression-coverage`で、runtime source hashとREADME/
  feature matrix hashを持つ生成証拠を更新した。再実行した完全`make test`は246
  Dart filesのformat `0 changed`、analyzer `No issues found`、全test成功で完了した。
- 2026-09-11: `make RUNTIME_ARCH=arm64 runtime-source-check runtime-bundle-audit`は、
  source audit (`tracked=455`, product native source `0`)、Developer JIT bundle audit、Release AOT
  bundle auditのすべてで成功した。両bundleはrenderer native assetを新たにbuild/copyしている。

## 完了判定

- 原因は、Retina用に2x化したbitmap boundsへCoreTextの14pt glyphを1x CTMのまま描画して
  いたことである。terminalとSettingsのfont family/point sizeは元から同じだったが、terminalの
  glyph inkだけがdevice pixel寸法で半分になっていた。
- dependency側でCoreText CTMを一度だけscaleし、product側で共有14ptの実ink parityと
  native window/live surface scale同期の両方を回帰検査した。メタデータだけで同等と判定する
  受け入れ漏れも解消した。
- Phase 8の終了条件に反する失敗、未検証項目、または後続タスクは残っていない。
