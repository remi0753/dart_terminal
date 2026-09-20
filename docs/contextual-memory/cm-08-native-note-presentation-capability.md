# CM-08 native Note presentation capability

日付: 2026-09-21
状態: 完了

## 目的

CM-05のcontent-bounded projectionとCM-07のwindow interaction authorityに従う、製品所有のmacOS native Note
presentation capabilityを実装する。Collapsed badge、trailing rail、opaque sticky-note-like card、appearance、geometry、
read-only accessibilityを提供し、terminal grid、Metal drawable、PTY winsize、input ownerを変更しない。

## 背景

- 利用者が示したMiro画像は、色と面で短い情報を認識できるcard affordanceの参考であり、infinite canvas、自由座標、
  collaboration、toolbar、brandを複製する要件ではない。
- CM-05はpersistent IDをnativeへ渡さないephemeral card tokenとatomic surface portを実装済みで、CM-07はfuture Note
  rail/editor ownerとconsumed gestureを実装済みである。
- Existing `dart_appkit`は汎用libraryである。Dart Terminal固有のprojection、card、Note lifecycleを追加してはならない。
- CM-10までapplication manifest登録とproduction authority wiringは行わないため、本タスクはmanifest-independentに検証できる
  `dart_terminal_notes_macos` packageとして成立させる。

## 範囲

- Native Note surface ABI v1のC/Objective-C header、strict bounded binary projection codec、atomic apply、last-good保持。
- Pane bounds内のcollapsed badge、trailing rail、最大32 materialized card、opaque six-color card presentation。
- 1x/2x geometry、small-pane fallback、system badge top inset、hit region、light/dark、Increase Contrast、
  Differentiate Without Color、Reduce Motion、12〜24 pt body font。
- Collapsed/expandedのread-only accessibility tree。Bodyはcollapsed/background/occluded時に公開しない。
- Direct FFI/native capability test、header compile、sanitizer、bitmap/geometry/appearance/accessibility acceptance、missing capability fallback。

## 対象外

- Editor、IME、Undo、Save/Cancel、semantic intent/result、reorder/resolve/delete/reattach（CM-09）。
- Application manifest registration、production Note authority/action/menu wiring、durable acknowledgement（CM-10）。
- Store mutation、trigger delivery判断、persistent Note/Context ID、diagnosticsへのbody/color/time出力。
- `dart_appkit`へのDart Terminal固有code、whiteboard/container API、Note owner追加。

## 依存関係

- CM-05 `TerminalNoteSurfaceProjection` bounds/ephemeral token/atomic surface port。
- CM-07 `TerminalWindowInteractionAuthority`とconsumed gesture identity。
- Existing `dart_appkit` native extension API、AppKit/CoreGraphics/CoreText、code-assets build hook。
- Gate 5 D-27/D-28/D-32〜D-34、Gate 7 native ABI v1、G/B/P/T/A/L verification vector。

## サブタスクと実施順

1. **Package、ABI v1、strict projection codec**
   - `packages/dart_terminal_notes_macos`を作成し、Dart encoder、C header、native decoder/state、direct FFI facadeを実装する。
   - Unknown version/flag、duplicate token、body 4,096 bytes、64 cards、256 KiB、collapsed body、generation/staleを全体rejectし、
     failed applyでlast-good generation/countを保持する。
   - 完了条件: package analyze、header compile、codec/native unit、fuzz/limit±1、live owner 0。Application manifest登録0。
2. **Badge、rail、card、appearance、read-only accessibility**
   - Native `NSView` presentationとfixed layer orderを実装し、badge/hit target、rail/card geometry、small-pane fallback、最大32 card、
     six-color opaque token、contrast/non-color cue/reduced-motion stateをsnapshotとbitmapで固定する。
   - CollapsedはNotes buttonだけ、expandedはgroup/list/ordered card static textを公開し、hidden bodyをAXから除外する。
   - 完了条件: 1x/2x、light/dark/contrast/non-color/reduced motion、12/15/24 pt、narrow/normal/wide/small paneをpass。
3. **Manifest-independent native acceptanceとfallback**
   - Header compile、ASan/UBSan、G1〜G3/B1〜B2/P1〜P2/T1/A2〜A3/L1相当をaggregate targetへ接続する。
   - Terminal geometry sentinelはsurface open/close前後で入力のrows/columns/drawable/winsize/SIGWINCH値が変わらないことを
     capability boundaryで固定し、missing capabilityはterminal継続・pane unavailable・last data保持とする。
   - 完了条件: package/full gate、privacy/source/resource audit、Developer JIT/Release AOTのmanifest-independent host acceptance。

## 完了条件

- Implementation planのCM-08成果物、完了条件、必須検証を満たす。
- Collapsed projectionのbody 0、expanded最大64 card/256 KiB、native materialized card最大32、atomic apply、last-good保持。
- Rail/badgeの開閉でterminal geometry sentinelがdelta 0。Small pane、alternate-screen/TUI入力状態を変更しない。
- G/B/P/T/A/L presentation vectorとmissing capability fallbackをpassする。
- Editor/intent/product wiringを先行せず、`dart_appkit`変更0。

## 検証方針

- Dart canonical encoder/property/fuzzとnative strict decoderの同一fixture比較。
- C/Objective-C header compile、native unit、ASan/UBSan、bitmap pixel/geometry snapshot、read-only AX tree。
- Package analyze/test、root `dart analyze`、`dart test/run_tests.dart`、`make test`、generated source freshness。
- Developer JIT/Release AOT manifest-independent acceptance、privacy/source/resource/bundle audit、隣接`dart_appkit`差分audit。

## 2026-09-21: 第1サブタスク着手

- 着手前にROADMAPを再確認し、先頭未完了がCM-08であることを確認した。README、FEATURE_MATRIX、implementation plan、
  overlay/editor/accessibility仕様、architecture/rollout ABI v1、CM-05 surface port、CM-07 authorityを照合した。
- CM-08はeditor/semantic intentを含めず、projectionのstrict decodeとread-only presentationだけを所有する。Application manifestと
  production compositionはCM-10まで追加しない。
- Packageをrendererへ埋め込む案はownershipと単独検証を曖昧にするため不採用とした。`dart_appkit`へNote containerを追加する案も
  汎用libraryへ製品概念を漏らすため不採用とした。独立code-assets packageとdirect native test surfaceを採用する。

## 2026-09-21: 第1サブタスク完了

### 実装と判断

- Product-owned `packages/dart_terminal_notes_macos`を追加した。Root `pubspec.yaml`と
  `macos_application.json`へは登録せず、package自身のbuild hookからdirectにcode assetをloadして検証する。
- Projection ABI v1はlittle-endianの128-byte header、32-byte card record、contiguous UTF-8 body areaとした。
  Headerはruntime pane/surface/projection generation、unsigned 64-bit store revision、badge count/cue、feature/surface state、
  visibility、Current/Detached section、page range、ephemeral selection token、editor mode、fixed message key、appearance/
  accessibility flags、12〜24 pt fontを持つ。Cardはephemeral token、body range、order、six-color key、status、trigger phaseだけを
  持ち、persistent Note/Context ID、timestamp、path、free-form error textを持たない。
- Storeはproduct modelの上限と同じunsigned 64-bitとし、Dart VMのsigned `int`へ丸めず32-bit word二つでencode/decodeする。
  Native machine snapshotもbody/color/token/timeを返さず、generation/count/fixed stateだけを返す。
- Dart/native双方でversion、known flags、zero reserved fields、canonical offset、exact packet length、enum、trigger kind/phase、
  duplicate token、selected token、page range、64-card/256-KiB aggregate、4,096-byte/64-line body、UTF-8/control/bidi、collapsed
  body 0をstrict検証する。Unknownまたはlimit超過はpacket全体をrejectする。
- Native `DtnSurface`はvalidated packetを同期copyし、同一pane/surfaceかつ単調増加projection generation、非減少store revisionだけを
  atomicにswapする。失敗時はlast-goodを保持し、materialized card countを最大32へclampする。create/destroyのlive owner countを
  test seamで監査する。
- `Makefile`へC/C++ header compile、native unit、package format/analyze、Dart canonical/property fuzz、direct code-asset testを追加し、
  root `make test`へ接続した。新しいMakefile hashを既存release-candidate証跡へ再生成した。
- ABI fieldを最小generation/countだけにする案は、仕様で確定済みのsection/paging/appearanceを同じv1へ後付けすることになるため
  不採用とした。Free-form dictionary/JSON案もunknown fieldのfail-closed、allocation bound、native layoutを弱めるため不採用とした。

### 境界と後続

- Presentation stateはABIへ固定したが、AppKit badge/rail/card viewとgeometryは未実装であり第2サブタスクの対象である。
- Editor modeはABI v1 enumとして予約済みだが、editor、intent/result、draft、IME、mutationはCM-09まで実装しない。
- `dart_appkit`には変更を加えていない。隣接repositoryには作業開始前から存在した3変更だけが残り、本タスクでは触れていない。

### 検証結果

- `make terminal-notes-contract-check terminal-notes-native-test`: pass。C11/C++20 header layout、valid/max packet、version/flag/
  collapsed/duplicate/UTF-8/control/body +1、stale/cross-surface/store rollback、last-good、64→32 materialization、live owner 0を確認。
- `make terminal-notes-dart-test`: pass。format 8 files 0 changed、analyze issue 0、canonical round-trip、unsigned64 max、
  limit ±1、4,096 deterministic malformed fuzz、direct native asset、last-good、owner 0を確認。
- `dart analyze`: issue 0。
- `make test`: pass。369 root files format 0 changed、root analyze issue 0、全native/package/compatibility/privacy/security testと
  `dart_terminal tests passed`を確認した。
- 初回root testはsandbox外のclang module cacheを書けず停止した。許可された実行環境で再実行した。Makefile変更により
  release-candidate matrixがstaleになったためgeneratorでhash証跡を更新し、その後checkとfull gateがpassした。

## 2026-09-21: 第2サブタスク完了

### 実装と判断

- `DtnNoteSurfaceView`をproduct package内へ実装した。透明なpane-sized rootはhit testをbadge/rail boundsへ限定し、
  native-to-native `dtn_surface_attach_to_host`でterminal hostの最前面childとしてattachする。Host frame、terminal layout、
  Metal drawable、gridを変更するAPIは持たない。Opaque pointerはDart FFIへ渡さない。
- Collapsed badgeは44×44 pt hit targetと28 pt visualをtrailing center、8 pt insetへ配置する。1〜99はexact count、100以上は
  `99+`、dueはcolorだけに依存しないready dotとread-only AX labelを持つ。264×184 pt未満ではrailを隠し、`pane too
  small`のnon-content badgeへ切り替える。
- Railはpane上へoverlayし、上下12 pt、通常320 pt、requested 240〜360 pt、system badge時top +48 ptとした。Root/rail/cardを
  flipped coordinateでlayoutし、cardは最大32件だけmaterializeする。Previewは最大8行、corner radius 10、padding/spacing
  12、border 1、通常shadow 0×2/blur 8を実装した。
- Light/dark six-color canonical sRGB surface/accentとbody text tokenを実装した。Cardは常にopaqueで、status/triggerを
  `○/●/◆/▶/✓`とtextで示す。Increase Contrastは2 pt border・shadow 0、Differentiate Without Colorでもshape/text cueを
  維持し、Reduce Motionはduration 0、それ以外の許容durationは140 msとした。Body fontは12〜24 ptをABI値で反映する。
- Read-only accessibilityはcollapsedでNotes button一つ、expandedでNotes group、toolbar、Current/Detached selector、scroll list、
  ordered card group、body/chip static textを公開する。Collapsed、small pane、background/occluded相当の
  `presentationEligible=false`ではroot accessibility childrenからrail/bodyを除く。
- Content-free presentation/card snapshotを追加した。Frame、count、fixed state、canonical RGBA、font/motionだけを返し、body、
  ephemeral token、persistent ID、timestampを返さない。Dart facadeもtyped geometry/card stateとして公開する。
- Generic `dart_appkit`へoverlay/container/Note APIを追加する案は不採用とした。CM-10のcompositionはnative-to-native seamから
  product renderer hostへattachでき、汎用libraryの責務を変更しない。

### 検証結果

- `make terminal-notes-native-test`: pass。Actual AppKit view hierarchyとbitmap cacheを使い、normal 320 pt、narrow 240 pt、
  wide 360 pt、small 263×183、system badge inset、44/28 pt badge、最大32 materialization、hit region、child layer orderを確認。
- 同native testで1×/2× backing scale、12/15/24 pt、light/dark canonical bitmap token、six dark surfaces、opaque card、
  contrast shadow 0、non-color cue、reduced motion 0、background/collapsed body AX 0、collapsed button-only treeを確認。
- `make terminal-notes-dart-test`: format 8 files 0 changed、analyze issue 0、typed layout/presentation/card facadeとdirect code-asset
  loadを含めpass。
- Standalone `dart run`はAppKit process main threadではないため、surface createを許すとthread affinityを破ることが判明した。
  Native surfaceはmain-thread-onlyを維持し、direct Dart gateはABI/load/live-owner 0、actual lifecycle/presentationはmanifest-independent
  native executableで検証する形へ修正した。
- `make test`: pass。369 root files format 0 changed、root analyze issue 0、全native/package/compatibility/privacy/security test、
  `dart_terminal tests passed`を確認した。Makefile hash証跡を再生成しfresh checkもpassした。
- Root application manifest/dependency登録0、`dart_appkit`変更0。隣接repositoryは開始前からの3変更だけである。

## 2026-09-21: 第3サブタスク着手

- ROADMAPを再確認し、先頭未完了がCM-08の「manifest-independent native acceptanceとfallbackを完了する」で
  あることを確認した。CM-09以降のeditor、intent、product wiringには着手しない。
- 本サブタスクは、package単体のDeveloper JIT/Release AOT host、native AppKit host、ASan/UBSan、G/B/P/T/A/L
  verification vector、geometry sentinel、missing capability fallback、privacy/source/resource auditを一つのaggregate gateへ
  接続する。
- Application manifestへ一時登録して検証する案はCM-10を先行し、missing capabilityの検証もできなくなるため不採用とした。
  Package自身のcode assetを使うDart hostと、AppKit main threadを所有するnative hostを組み合わせる。
- Fallbackはproduct stateをnativeへ移すのではなく、native surface open結果を`available`/`nativeUnavailable`で返す
  fail-soft facadeとする。Projectionのlast dataは呼び出し側authorityが保持し、native欠落がterminal geometry/input stateを
  変更しないことをsentinelで固定する。
- 第2サブタスクのpresentation/card snapshotにcolor RGBAが含まれることをprivacy要件と再照合した。色はbodyではないが、
  machine snapshotがcolorを返さないという確定境界に反するため、production ABIから除去し、palette検証はactual bitmapへ
  移す。Geometry/count/fixed accessibility stateだけをsnapshotに残す。
- `dart_appkit`には変更を加えない。隣接repositoryには着手前から3変更があり、本作業では読み取り監査だけを行う。

### 実装中に確定した判断と結果

- Public presentation snapshotからcard color/RGBAとper-card snapshot APIを除去した。Production ABIが返すのはgeometry、count、
  fixed flags、font/motion、visible acknowledgement **eligible** generation、generic accessibility announcement countだけである。
  Six-color検証はnative test process内でactual card layerとbitmapを読み、Dart/machine境界へ値を返さない。
- Headerの未使用領域へbounded locale enum（English/Japanese）を追加した。Native fixed label、status chip、generic ready announcementを
  localeで選択し、本文はannouncementへ含めない。Visible expanded railでdue batchが初めてmaterializeされた時だけ一度通知し、
  background/small/collapsedではack eligible generation 0、body AX 0を維持する。Durable acknowledgement mutationはCM-10のままである。
- `TerminalNotesNativeSurface.tryOpen`はABI欠落、symbol解決失敗、AppKit wrong-thread createを
  `TerminalNotesCapabilityAvailability.nativeUnavailable`へ変換する。Programming error全般を隠さないよう、捕捉は
  `StateError`/`ArgumentError`に限定した。Projection/store/sessionは所有しないため、caller authorityのlast dataを変更しない。
- Native AppKit hostへG1〜G3/B1〜B2/P1〜P2/T1/A2〜A3/L1相当を追加した。0/1/99/100/128 count、due 3件FIFO、
  system badge inset、small-pane due保持、background非通知、card identityを保つ1×/2× reflow、12/15/24 pt、英日AX label、
  alternate-screenを含むterminal geometry/input sentinel delta 0をactual hierarchyで検証する。
- Package単体hostはDeveloper JITでcode assetをdirect loadする。`dart compile exe`はnative asset mappingをbundleしないことが
  実行時に判明したため、Release AOTでは同じproduction dylibを`DYLD_INSERT_LIBRARIES`でprocessへ明示loadし、`@Native`の
  process fallbackからABIを解決する。Application manifestは両モードとも未登録であり、この差異を隠すwrapperは追加しない。
- `terminal-notes-capability-audit`はroot dependency/manifest未登録、public snapshot content-free、11-symbol export allowlist、
  resource bounds、native log sink不在、隣接`dart_appkit`へのNote code不在をfail-closedで監査する。
- `native_sanitizer_gate`へNotes library/harnessを追加した。ASan/UBSanは5 suite、11 artifactとなり、Notes library/harnessの
  両方にinstrumentation markerがあることを確認した。

### 現時点の検証

- `make terminal-notes-contract-check terminal-notes-native-test`: pass。
- `make terminal-notes-dart-test`: format 9 files 0 changed、package analyze issue 0、codec/fallback/asset pass。
- `make terminal-notes-host-acceptance terminal-notes-capability-audit`: Developer JIT/Release AOTともpass、manifest 0、
  fallback `native-unavailable`、geometry delta 0、content-free snapshot、export 11、generic `dart_appkit`を確認。
- `make product-native-sanitizer`: pass。5 suites、11 ASan artifacts、9 UBSan artifacts。Notes library/harnessはASan/UBSanとも有効。
- Root `dart analyze`: issue 0。
- Formatter単独実行は対象fileをformatした後、sandbox外のDart telemetry timestamp更新で非zeroとなった。許可された通常環境の
  package gateで再実行し、format 0 changesを確認した。Product code/testの失敗ではない。

## 2026-09-21: 第3サブタスクとCM-08完了

### 最終検証

- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。370 root files format 0 changed、root/package analyze issue 0、
  全native/package/generated/freshness/compatibility/application/distribution/security testと`dart_terminal tests passed`を確認した。
  Developer JIT/Release AOT host、capability auditもroot gate内でpassした。
- `make terminal-notes-acceptance`: pass。G1〜G3/B1〜B2/P1〜P2/T1/A2〜A3/L1、2 modes、geometry delta 0、
  ASan/UBSan 5 suites/11 artifactsを一つのaggregate markerで確認した。
- Aggregate初回は既存PTY sanitizerのforeground member取得後にburst/exit/reapが連鎖して失敗した。同一sourceの
  `make product-native-sanitizer`再実行では全suiteがpassし、その後のcomplete aggregate再実行もPTYを含めpassした。
  Notes suiteは全実行でpassしており、再現しない一時的PTY lifecycle failureとして記録する。失敗を隠すtimeout緩和や
  test削除は行っていない。
- `git diff --check`: pass。Root dependency/application manifestにNotes登録0。`dart_appkit`のNote symbol検索0、同repositoryは
  着手前からの3変更だけで、本タスクによる変更0。

### 完了境界

- CM-08のnative presentation、read-only accessibility、fail-soft fallback、manifest-independent acceptanceは完了した。
- Editor、IME、intent/result、mutationはCM-09、application manifestとproduction authority wiring、durable acknowledgementは
  CM-10として未着手のまま維持した。
