# Context Dock background compositing

- Status: complete
- Date: 2026-09-16
- Scope: Phase 7 Context Dock、Phase 8 background opacity、generic AppKit text editor

## 目的、背景

Context Paneの実際の背景透過をterminalと揃える。前taskではbackground-opacityを
editorの色へ投影したが、色のalphaが一致するだけでは多層の背景合成を検出できなかった。
既存の共有background-opacityを使い、別の設定やview全体のalphaは導入しない。

## 範囲、対象外、依存関係

- Directory Navigatorの一覧／固定details、Process Inspectorに同じbackground alphaを一度だけ描画する。
- font、文字／caret／selection、opaque divider、scroll／query／focus／ownership、default1を維持する。
- 汎用TextEditorの背景描画を隣接dart_appkit内で修正する。window透明policyは既存terminal rendererが所有する。
- Settings／paletteの既定不透明、blur、ANSI cell背景、SSH、terminal入力は対象外。
- ADR-005のnative境界を守る。隣接repoの既存Engine文書／script変更は触らずcommitから除外する。

## 完了条件、検証方針、リスク

- 0／中間値／1へのlive変更で実native bitmapの空白・余白・scroll後の背景alphaが指定値になる。
- nested scroll／clip／text背景の重複描画をなくし、既存のdocument／style／IME／scroll testsを保つ。
- generic native／Dart／FFI tests、focused Dock tests、format／analysis、main make test、両runtime native-content／configuration検証を通す。
- bitmap captureの座標／透明初期化、未attach viewのlayout、selection装飾を背景と誤測定することが主なtestリスク。
  主観的外観／VoiceOverは既存manual checklistで追跡する。

## 調査記録

- 着手時main treeはclean、HEAD0ec8f61。README／ROADMAP／FEATURE_MATRIX、AGENTS、opacity／appearanceメモ、ADR-005、関連code／tests／Makefileを確認した。
- Dart appearance resolverはfocused surface.backgroundOpacityを既に上下editorへ渡し、accepted reload後にもrefreshする。
- generic TextEditorはNSScrollView.drawsBackground=YESとNSTextView.backgroundColorを併用している。
  clip viewも含め、同じ半透明背景が重なって指定alphaより不透明に見える可能性がある。native bitmap regressionで先に確認する。
- terminal rendererはbase clear alpha、non-opaque layer、clear windowの経路で一回合成する。window全体alphaは使わない。
- 隣接repoの既存変更はdocs/BUILDING_DART_ENGINE.md、scripts/bootstrap_dart_engine.sh、scripts/build_dart_engine.shの3件だけ。
  generic ownership auditが製品語を禁じるため、隣接taskメモは汎用描画契約のみを記録する。
- parent AGENTS探索で範囲を広く指定しsandbox保護directoryのpermission errorが出た。以後は既知parentのファイル存在確認とdependency内だけへ限定する。関連個人directoryは記録／変更しない。
- 隣接へのscoped escalationは許可され、generic taskメモ／ROADMAPと透明bitmapの背景alpha回帰testを追加した。先に現実装で失敗を確認する。
- 追加native testは旧実装でalpha／RGB一致に失敗した。背景専用ownerを既存editor containerにし、scroll／clip／textの背景paintを無効にする。
  view全体alphaを使う案は文字／selectionまで薄くなるため不採用。window policyの変更も不要。
- container単一paint後、native bitmapのalpha期待は全てpassした。追加RGB期待はbitmap色空間の差を調査している。
  既存first-paint／foreground style／marked text／scroll testsのassertionは削除せず引き続きpassした。
- fake native Dock testへ0→0.5→1→0.3のlive往復を追加し、上下backgroundの一致とopaque foreground／divider、query／selection／focus保持を検証する。
- fake native test、Dart format（差分0）とanalyze（問題0）はpassした。
- bitmap cacheはdefault profileによりsRGB0.1／0.2／0.3が異なるRGBとして読まれ、retagだけでは改善しなかった。
  描画先を明示的なRGBA sRGB contextへ変え、同じ厳密なalpha／RGB期待のままactual hierarchyを描画する。requested scrollだけでなく実offset>0もassertする。
- bitmap convenience／explicit CGContextでもNSColor pixel decodingのcalibrated→sRGB変換が残ったため、明示RGBA8の生pixelからpremultiplyを戻して比較する。
  alpha許容0.015とRGB許容0.025、期待sRGB値自体は変更せず、display profileの解釈を測定経路から除外する。
- READMEのopacity対象と両manual checklist、FEATURE_MATRIX UI-02へ単一背景合成を記録した。推測reference pathは存在しなかったためrg --filesでdocs/reference/configuration-and-command-line.mdを確認した。
- RGBA8直接測定でnative testはexit0。空document／80行を実際にscrollしたdocument、padding／viewportで
  0.5→0→0.8→1→0.5のalphaと期待RGBが全てpassした。既存native bridge testsも全てpassした。
- Xcode実formatterで変更native範囲だけを整形した。code編集を止め、dependency全gateとmainのgenerated freshnessを直列で最終検証する。
- dependencyの整形後make testはexit0。ownership／scaffold、native bridge／runner／runtime、Dart API／launcher／example、assembly／publication、FFI／legacy smokeの全gateをpassした。
- mainのPhase7 acceptance、compatibility coverage、P0/P1 inventory、daily-use matrixは既存generatorで順に再生成し全てpassした。
- RGBの不一致は最終的にNSColor pixel decodingのcalibrated色解釈と切り分けられた。
  explicit CGContextとraw pixel測定の組み合わせはprofileに依存せず、alpha／背景色の元の期待値を満たす。
- 最新の汎用描画修正を含むarm64両runtimeをbuildし、native-contentはDeveloper JIT（11150 ms）／Release AOT（10042 ms）ともpassした。
  custom palette／Menlo16／opacity0.8の上下Navigatorと全高Process Inspector、caret／tree／search／privacy／exact PTY、4 session／全native handle cleanupを確認した。
- configuration suiteはDeveloper JIT（2023 ms）／Release AOT（4183 ms）、theme suiteはDeveloper JIT（2121 ms）／Release AOT（1338 ms）で全てpassした。
  shared live opacity、既存／後続surface、Settingsのfirst paint／style／scroll、atomic reload rejection、width／input ownershipとresource cleanupを維持した。
- 隣接dependencyの完了commitは0a960eb、Composite text editor backgrounds only once。
  汎用契約と検証は隣接repoのdocs/TEXT_EDITOR_BACKGROUND_COMPOSITING.mdを参照する。既存Engine変更3件は保持しcommitから除外した。

## 完了記録

- mainの最終make testはexit0。347 Dart filesのformat差分0、dart analyze問題0、全Dart／native capability testsと
  configuration／keybind／localization／privacy／AppKit acceptance／compatibility／distribution／generated freshness gatesはpassした。
- 同じbackground-opacityを背景だけへ使う既存Dart投影／reloadを維持し、native描画の重複を解消した。
  一覧と固定details、全高Process Inspectorのviewport／余白を単一containerで合成し、文字・caret・selection・dividerには全体alphaをかけない。
- 変更差分を見直し、diff checkはpass。追加testの元の厳密なalpha／RGB期待と既存first-paint／style／marked text／scroll assertionsを維持した。
  debug用固定color出力、不要なbuild artifacts、秘密情報、無関係な変更は含めない。
- 実装／自動検証は完了し阻害要因、追加の未完了実装項目はない。主観的な外観・VoiceOverは既存manual checklistで追跡する。
  後続のIntel実機／配布署名／実時間soakには着手しない。
