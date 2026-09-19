# macOS application icon

## 目的

Dart Terminalの主機能であるterminal surfaceと右側Context Dock／Directory Navigatorを、
Dock、Finder、Command-Tab、小サイズ表示で判別できるmacOS application iconとして生成し、
Developer JIT、Release AOT、Universal、Developer ID配布物へ同じbytesで組み込む。

## 背景

現在のapplication manifestとbundleには`CFBundleIconFile`および`.icns` resourceがなく、
macOSの既定application iconが表示される。製品はTerminalに重ならない右側Context Dock、
Directory Navigator、Process Inspectorを個性として持つため、その二領域構造を視覚的な識別子にする。

## 範囲

- image generationでoriginal 1024 px square master artworkを作成する。
- terminal promptを想起させるchevron／cursorと、右側のdirectory treeを単純な形で構成する。
- macOS iconsetの16、32、128、256、512 pxと各2x PNGをmasterから生成し、`.icns`へ変換する。
- generic `dart_macos_runtime` manifestへoptionalでboundedな`.icns` declarationを追加する。
- builderがiconを`Contents/Resources`直下へstageし、`CFBundleIconFile`とbuild evidenceを生成する。
- product manifest、distribution policy、bundle audit、関連unit／integration testを更新する。

## 対象外

- 製品名や文章をicon内へ描くこと。
- Apple、他terminal、Dartロゴなど既存商標の模倣。
- window内UI、tab icon、OSC icon-title、document iconの変更。
- `.app`以外のinstaller／DMG artwork。

## 依存関係

- imagegen built-in toolによるproject-bound raster generation。
- macOS標準`iconutil`と`sips`。
- `/Users/remi/dart/dart_appkit/packages/dart_macos_runtime`のmanifest parserとbundle builder。
- productのUniversal assembly、distribution resource inventory、final audit。

## 完了条件

- 1024 px masterは正方形、alphaを持ち、文字／watermark／第三者logoを含まない。
- 16 px相当でもterminal chevronと右側Dockの二領域が潰れず区別できる。
- iconsetの全10 PNGと有効な`.icns`が生成される。
- manifestがmissing、oversized、wrong extension、resource collisionをfail closedにする。
- built bundleの`Info.plist`がexact icon filenameを持ち、同名`.icns`がResources直下に存在する。
- Developer JIT、Release AOT、Universal／distribution auditがiconをneutral resourceとして受理する。
- genericとterminalのformat、analyze、unit、全repository gateが成功する。

## 検証方針

- masterを視覚確認し、alpha、寸法、corner／small-size silhouetteを確認する。
- generic parser／builder fakeでpositive、invalid declaration、missing／oversized sourceを検証する。
- `iconutil --convert icns`後に`iconutil --convert iconset`で全representationを往復確認する。
- product manifest／policy testへexact icon resourceとInfo.plist keyを追加する。
- Developer JITとRelease AOT bundleを生成し、`plutil`、resource hash、bundle auditで確認する。

## 判明事項・判断記録

- 採用コンセプトは、dark graphiteのmacOS rounded-square tile、左のterminal surface、右の細い
  Context Dock、mint／cyanのabstract prompt chevronとcursor、tree nodeである。製品固有の
  二領域UIを表しつつ、文字を読ませない強いシルエットを優先する。
- `.icns`は生成可能な派生asset、1024 px PNGは将来の再生成・レビュー用masterとして管理する。
- imagegenの出力はprojectへcopyし、default生成directoryだけを参照する実装にはしない。
- 最初の生成案は構図を満たしたが、透過余白上辺にcyanの微小な生成artifactが残った。
  その画像を参照した二回のcleanup editは、内部構図までfile browser寄りへ変化したため不採用とした。
  最終的には外周へ12%以上の余白、bright accentへ8%以上の内側距離、exterior glow禁止を
  明示した新規生成を採用した。terminal promptと三つのdirectory nodeは32 pxでも分離して見える。
- 最終imagegen promptは次である。

  ```text
  Use case: logo-brand
  Asset type: final macOS application icon master artwork for a terminal emulator named Dart Terminal
  Primary request: Create an original, polished macOS app icon that instantly communicates a terminal surface paired with a narrow right-side Context Dock / directory navigator.
  Subject: One dark graphite rounded-square app tile with a thick, quiet, unlit border. Inside, a large left terminal pane contains a bold mint-to-cyan command chevron and short cursor bar. A clearly separated slim right pane contains exactly three simple directory nodes connected by one vertical tree line. Use geometric symbols, not typography.
  Style/medium: premium vector-like 3D app icon, crisp geometry, subtle depth, restrained soft material lighting, modern macOS visual language, original design.
  Composition/framing: centered square tile, at least 12% transparent canvas padding on every side, terminal pane about three quarters and navigator about one quarter. Strong silhouette readable at 16 px. All bright accents must remain well inside the tile, at least 8% away from its outer edge.
  Lighting/mood: calm, precise, developer-focused. No exterior glow.
  Color palette: charcoal and near-black base, mint green and cyan accents, one tiny warm amber status dot only if balanced.
  Constraints: genuine fully transparent background outside the rounded-square tile; exterior transparency must be perfectly clean with zero colored pixels, specks, smudges, glow, shadow, or halo; no window traffic-light controls; no words, letters, numbers, readable text, Apple logo, Dart logo, third-party marks, watermark, device mockup, or background scene; clean antialiased edges and symmetric corner radius.
  ```
- imagegen built-in toolをgeneration modeで使用し、生成artifactを1024×1024 RGBAの
  `resources/DartTerminalIcon.png`へcopy／resizeした。派生する
  `resources/DartTerminal.icns`だけをbundle resourceとして使い、master PNGは再生成とreview用に保つ。
- `iconutil`の初回変換はsandboxが生成fileへ付与した`com.apple.provenance`属性により
  `Invalid Iconset`となった。生成iconsetだけから属性を除去すると変換でき、ICNSから10 PNGへの
  往復にも成功した。製品assetの内容や通常source fileのmetadataは変更していない。
- generic `dart_macos_runtime`へoptionalな`icon.path` contractを追加した。relative `.icns`、
  1,024-byte path、16 MiB file、resource-root collisionをfail closedにし、legacy manifestは
  icon metadataを持たないままにする。builderはexact bytesをResources直下へcopyし、
  `CFBundleIconFile`とruntime build manifestのsource／bundleName／bytesを同時に生成する。
- Universal assemblerはiconをcode imageではなくneutral resourceとして扱う。thin間のbytes差は
  既存inventory照合で拒否され、Universal manifestのapplication contract、top-level contract、
  resource evidenceへ同じiconが残る。

## 検証記録

- `sips`でmasterが1024×1024、alphaありであることを確認した。
- `iconutil --convert icns`と逆方向`--convert iconset`を実行し、16、32、128、256、512 pxと
  各2xの全10 PNGが復元されることを確認した。最終ICNSは1,354,568 bytesである。
- master SHA-256: `eab627a3c2933f6a6916c49c4147a910fb1fcbcacce7f909e8cb317330b521a0`
- ICNS SHA-256: `ec489a3d27cd7670eed54ff7739797d3c91bb0dfcfb2eea88e34cae66800da52`
- generic packageの`dart analyze`、manifest／JIT／AOT builder test、Universal assembler testは成功した。
  generic commitsは`e0a0a98 Add bounded macOS application icon support`と
  `815a141 Verify icons in Universal bundle evidence`である。
- productの`dart analyze`、distribution policy unit、source auditは成功した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit release-aot-universal-audit`は、
  最初のsandbox実行ではMetal compilerが利用するuser cacheへの書き込みを拒否されて停止した。
  sandbox外で同じcommandを再実行し、Developer JIT arm64、Release AOT arm64、Universal
  Release AOTの全bundle auditが成功した。この失敗はsource／bundleの不具合ではない。
- 三つのbundleすべてで`CFBundleIconFile`は`DartTerminal.icns`となり、bundle内iconの
  SHA-256はreview済みsourceの
  `ec489a3d27cd7670eed54ff7739797d3c91bb0dfcfb2eea88e34cae66800da52`と一致した。
- 既存bundleを直接使ったDeveloper JIT、Release AOT arm64、Universal Release AOTの
  `runtime_integration_smoke --suite=smoke`はすべて成功した。
- Universal appと空entitlementに対するdistribution policy preflightは
  `TERMINAL_DISTRIBUTION_POLICY_PASS code=9 entitlements=0`で成功した。新しいDeveloper ID
  submissionは外部Apple serviceへ状態を作るため、このUI asset taskでは再送信していない。
- 最初の`make test`はREADME／FEATURE_MATRIX hashに従属するregression coverageがstaleとして停止した。
  正規生成targetで更新後、二回目はそこを通過し、同じ入力へ依存するgap inventoryがstaleとして停止した。
  regression coverage、gap inventory、daily-use matrixを正規targetで再生成し、三回目の
  `make test`はformat 348 files 0 change、analyze no issues、全unit／auditを含め成功した。

## 残課題

- なし。次回の通常Developer ID配布は、Universal resource evidenceで固定したiconをそのまま署名・
  公証対象へ含める。既存の過去公証artifactはimmutableなので置き換えない。
