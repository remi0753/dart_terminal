# CM-10 S1 Basic memory product integration

日付: 2026-09-21
状態: 実装中

## 目的

CM-01〜CM-09で個別に固定したNote domain/store/authority/configuration/window interaction/native surfaceを、
Dart Terminalのapplication composition rootでS1 Basic memoryとして接続する。Internal `notes=true`のときだけ
paneとQuick Terminalへnative Note surfaceを作り、create/open/edit/reorder/resolve/reopen/delete、Detached/reattach、
explicit exportをdurable authorityに接続する。Default-offではentry/surface/store resourceを0に保つ。

## 背景と確認済みの事実

- `TerminalNoteCompositionRoot` はlaunch-fixed `notes` admissionとlive font projectionを持つが、production factoryと
  `TerminalApplication` wiringはまだない。Disabled branchはfactory自体を呼ばない。
- `TerminalNoteAuthority` はapplication-rootのsole durable ownerで、pane/context binding、projection/token、visible ack、
  serial mutation、ordered shutdownを既に所有する。User mutationはbounded `submitMutation` transitionに変換する必要がある。
- `dart_terminal_notes_macos` はproduct-ownedのABI v1 capabilityで、strict projection、native editor/actions、
  intent/result/focusを持つが、root `pubspec.yaml`、`macos_application.json`、bundle/distribution auditには未登録である。
- Existing product hierarchyは`TerminalApplicationState`、`TerminalNativeHierarchyAdapter`、
  `TerminalWindowInteractionAuthority`、menu/palette dispatcherをcomposition rootが個別所有する。Note modelをこれらのclassへ
  埋め込まず、薄いproduct subsystem/adapterを並列に所有する。
- Restoration v1自体へNote ID/bodyを追加せず、既存exact-byte artifactとNote storeのbindingを照合する。
- `dart_appkit` は汎用libraryである。Note model、Dart Terminal action、store path、trigger、product surface lifecycleを
  絶対に追加せず、既存の汎用Window/View/manifest/native-extension contractのみを使用する。

## 範囲

- Notes native capabilityのroot dependency、application manifest、bundle/source/distribution/privacy auditへの登録。
- Product-owned Note subsystem adapterとstrict pure↔native projection/intent/result conversion。
- Lazy store location/worker/authority startup、restoration binding、pane/Quick Terminal surface attach/update/detach。
- Native intentからS1 create/edit/color/reorder/resolve/reopen/delete/reattach/copy/exportへの一回限りmutation接続。
- Hidden/internal create/open actions、localized menu/palette projection、explicit export warning/save、content-free diagnostics。
- Dirty pane/window/application close確認、ordered shutdown、exact context restart、faultと両runtime acceptance。

## 対象外

- S2 On Returnのarm/focus delivery、S3 At Next Prompt、shell integration v3、自動通知。
- Public configuration/reference/Settings露出、default-on、rollout promotion。
- Autosave/durable draft、rich text/Markdown/attachment/import。
- `dart_appkit`へのDart Terminal固有code。

## 依存関係

- CM-01〜CM-06 domain/store/authority/configuration、CM-07 sole window input authority、CM-08/09 native surface/editor ABI。
- Existing application hierarchy、restoration lifecycle、Quick Terminal singleton、action/menu/palette、explicit save panelのproduct contract。
- `dart_macos_runtime` application manifestの汎用native capability registration。

## サブタスクと実施順

1. **Native capability manifestとproduct Note subsystem adapter**
   - Root dependency/manifest/bundle policyにNotes capabilityを登録する。
   - Authority projectionとnative projection、native intent/resultとauthority mutationの間にproduct-owned bounded adapterを作る。
   - 個別のpaneやapplicationへの接続前に、token/revision/generation、last-good、fault、owner 0をfocused testで固定する。
   - 完了条件: production bundleがnative Notes imageをstrict登録し、adapterがpersistent IDをnativeへ渡さず、
     format/analyze/focused/full gateと`dart_appkit` generic auditがpassする。
2. **Application compositionとpane/Quick Terminal surface lifecycle**
   - `TerminalNoteCompositionRoot`のproduction factory、lazy store/authority startup、topology/restoration bindingを接続する。
   - Pane create/split/tab/window/Quick Terminal singletonとnative hierarchy reconciliationへsurface attach/update/detachを接続する。
   - Window interaction authorityのNote adapterとfont live projectionを接続し、disabled resource 0を維持する。
   - 完了条件: default-off entry/surface/store 0、enabled pane/Quick Terminal lifecycleのexact owner、
     renderer/grid/PTY geometry delta 0、adapter-before-view teardown。
3. **S1 mutation、Detached、export、localized action**
   - Create/open/edit/color/reorder/resolve/reopen/delete、Detached selection/reattach、copy/exportをsemantic intentから接続する。
   - Hidden/internal action ID、menu/palette enablement/localization、save panel warning、conflict/recovery固定表示を追加する。
   - 完了条件: acceptedはdurable commit後にだけnative result/projectionへ反映し、busy/conflict/faultは
     draft/selection/Undoを維持、explicit export/copy以外のcontent egress 0。
4. **Restart、fault、close/quit、両runtime product acceptance**
   - 2 window/3 tab/5 pane、Quick Terminal、close/quit dirty、store/native fault、restart exact contextのS1 product vectorを作る。
   - Developer JIT/Release AOT、sanitizer、bundle/privacy/restoration/shell/diagnostics sentinelをnamed aggregateへ接続する。
   - 完了条件: S1全flowがdurable、restart後exact context、default-off zero-cost、terminal bytes/geometry 0、
     store/native/adapter/interaction owner 0、full gate pass。

## 完了条件

- Implementation planのCM-10成果物、完了条件、必須検証を満たす。
- `notes=true`のS1だけを接続し、S2/S3のtrigger deliveryを先行しない。
- Authorityが唯一のdurable owner、native surfaceがvolatile UI owner、window interaction authorityが唯一のinput ownerである。
- Note body/ID/time/pathをrenderer/grid/PTY/shell/restoration/general diagnostics/log/machine lineへ渡さない。
- Root productとproduct-owned Notes packageだけを変更し、`dart_appkit`へDart Terminal固有codeを追加しない。

## 検証方針

- Pure adapter/unit、real worker/filesystem、actual native surface、fault injection、privacy/source/bundle/resource audit。
- Applicationの2 window/3 tab/5 pane/Quick Terminal、dirty close/quit、restart/reopen、JIT/AOT、ASan/UBSan。
- Package/root format/analyze/test、generated freshness、distribution policy、`git diff --check`、隣接repository差分監査。

## 2026-09-21: 第1サブタスク着手

- ROADMAPを再確認し、先頭未完了がCM-10、その先頭サブタスクが
  「native capability manifestとproduct Note subsystem adapter」であることを確認した。
- README、FEATURE_MATRIX、implementation plan、Gate 3/5/7、CM-05〜CM-09の記録と実装を照合した。
- Native packageをapplicationから直接store mutationさせる案は、durable sole ownerとcommit-before-publishに反するため
  不採用とする。Product adapterはnative intentをauthorityのbounded transitionに変換し、resultと新projectionを別段階で返す。
- Native packageに`PaneId`やpersistent Note/Context ID、store pathを持たせる案は不採用とする。変換とidentity resolutionは
  `dart_terminal` product adapterに限定する。
- Manifest登録によりbundle/distribution/source auditのexact capability setが変わる。テストを通すためだけ
  検査を弱めず、Notes imageとABI/initializerを既存capabilityと同等のstrict allowlistへ追加する。
- Product native source境界のfocused auditで、CM-03から存在する汎用`dart_durable_file_macos` packageのnative rootが
  owned package allowlistから漏れていたことを検出した。application層へのnative source混入ではないため、package rootを
  exact allowlistへ追加する。Notes rootと同様にpackage外へ逸脱したnative sourceは引き続きfail closedとする。
- 最初のfull gateでは正規release-candidate evidenceのsource hashがstaleとして拒否されたため、generatorで再生成した。
  再実行ではrelease symbol fixtureだけが旧9-image machine lineを期待して失敗した。Notes dylib追加後のexact inventoryは
  10 imageであり、定数由来の個数検証と一致する期待値へ更新する。missing/extra image rejectionは変更しない。

## 2026-09-21: 第1サブタスク完了

### 実装

- Root packageへ`dart_terminal_notes_macos`を直接依存として追加し、application manifestへABI version symbol、
  initializer symbolを含む3番目のnative capabilityとして登録した。Developer JIT/Release AOTのbuild hookはNotes dylibを
  app bundleへ配置する。
- Notes capabilityへ汎用`da_native_extension_services_v1`を受け取る`dtn_initialize`を追加した。main-thread、service ABI、
  struct size、同一serviceによるidempotenceをfail closedで検証する。Dart facadeの`TerminalNotesMacos.initialize`は
  `MacosNativeCapability.load`だけを使用し、generic runtimeへ製品型を追加しない。
- Product側に`TerminalNoteNativeSurfaceAdapter`とinjectable channelを追加した。Authority projectionのpane-local ID、
  surface/projection generation、store revision、ephemeral card token、bounded body/style/triggerだけをnative ABIへ変換し、
  persistent Note/Context ID、store path、timestampは渡さない。Nativeがacceptしたprojectionだけをlast-goodに保持し、
  intent/result/focus/layoutを同じsurface channelへ限定し、disposeはidempotent、dispose後eventは拒否する。
- Source/bundle/capability/distribution/update/symbolのstrict inventoryへNotesを追加した。Release AOT code imageは9から10へ
  増え、Notes dylibもarchitecture、link path、署名、UUID、SHA-256、dSYMのexact検査対象になる。
- `dart_appkit`は一切変更していない。Notes packageは既存の汎用native extension header/runtime APIをconsumerとして使う。

### 検証

- Focused analyze: adapter、capability/source/bundle/distribution/update関連8 file、issue 0。
- Adapter unit: projection/appearance/enum/token変換、persistent-ID-free境界、native rejection時last-good、intent/result、
  focus/layout、二重dispose、late event rejectionがpass。
- `make terminal-notes-capability-audit`: `manifest=registered snapshot=content-free exports=16 dart_appkit=generic`。
- `dart run tool/dart_only_source_audit.dart`: application native source 0、owned package native source 32でpass。
- `make RUNTIME_ARCH=arm64 developer-jit-audit`: app bundleの`capabilities=3` exact auditがpass。
- `make RUNTIME_ARCH=arm64 developer-jit-integration`: 実起動が`RUNTIME_INTEGRATION_PASS`。
- `make RUNTIME_ARCH=arm64 release-aot-audit`: production AOT bundleの`capabilities=3` exact auditがpass。
- `make test`: format 372 files変更0、root/package analyze issue 0、Note store実filesystem、security stress、
  distribution/update/symbolを含む全回帰が`dart_terminal tests passed`。
- 最初のsandbox内Developer JIT buildはClang module cacheへの書込み拒否で停止した。権限付き同一commandで再実行し、
  build/audit/integrationがpassしたため製品codeの失敗ではない。
- 隣接`dart_appkit`の差分は着手前から存在する3 fileだけで、本サブタスクによる追加差分は0。

### 次への引き継ぎ

- Native-to-nativeの`dtn_surface_attach_to_host`は既にあるが、productのpane host view handleとNote surfaceを接続する
  composition/lifecycleは未実装であり、第2サブタスクで行う。
- 第1サブタスクではsurfaceをapplicationへ生成していない。したがってdefault-off/on双方でNote surface/store ownerはまだ0で、
  entry action、mutation、Detached/exportも後続サブタスクの範囲である。

## 2026-09-21: 第2サブタスク着手と分割

- ROADMAPを再確認し、先頭未完了がCM-10第2サブタスク
  「application compositionとpane/Quick Terminal surface lifecycleを接続する」であることを確認した。
- Implementation plan、CM-04〜CM-09のauthority/restoration/input/native契約、`TerminalApplication`のinteractive hierarchy、
  `TerminalNativeHierarchyAdapter`、`TerminalQuickTerminalController`、product configuration reload/teardownを再確認した。
- このサブタスクはnative host composition、durable authority/topology、application wiringの独立した3境界にまたがり、
  一commitではfailure isolationが不十分になるため、次の順に分割した。
  1. Product-owned rendererのopaque identityを用い、Note native surfaceをterminal native viewへ
     native-to-nativeでcompositionする。
  2. Production Note subsystemでlazy store/authority、pane/Quick Terminal bind/attach/update/detachを所有する。
  3. Application composition root、window interaction、live font、ordered teardownへ接続しdisabled resource 0を固定する。
- `View`の非公開native handleをDartへ公開する案、generic `dart_appkit`へNote型やNote operationを追加する案、
  AppKit object pointerをDart FFIへ渡す案はすべて不採用とした。
- 既存の`register_custom_view_provider`／`register_custom_view_operation`は、operationを呼んだcustom View自身にのみ
  dispatchする。Note側custom Viewから別providerがterminal Viewを安全に解決できず、仲介のAppKit
  object pointerをDartへ露出するため、host compositionに利用する案は追加調査後に不採用とした。
- 採用案は、rendererが自身のopaque `handle`/`generation`に紐づくbound native viewを
  native-to-native限定で解決するexportを持ち、Notes capabilityがそのexportをprocess-localに解決して
  既存の`dtn_surface_attach_to_host`を呼ぶ境界とする。DartはAppKit object pointerではなく、
  rendererにもともと必要なvolatile opaque identityのみを注入する。
- Renderer identityをpersistent Note/Context identityに使わず、renderer generationの生存期間に限定する。
  Unknown/stale/unbound identity、wrong thread、多重hostはfail closedにし、rendererにはNote body、ID、timestamp、
  card geometryを渡さない。

## 2026-09-21: Note overlay composition seam完了

### 実装と判断

- Renderer capabilityに`dtr_metal_renderer_native_view(handle, generation)`を追加した。Main thread上で
  live registry、exact generation、bound/admitting viewを検証し、条件が揃ったときだけunretained
  native viewを返す。Dart FFIはこの関数を呼ばない。
- Dart renderer facadeに`TerminalMetalRendererCompositionIdentity`を追加し、live rendererのopaque
  handle/generationだけを取得可能にした。`TerminalLiveMetalSurface.compositionIdentity`は常に
  recovery coordinatorのcurrent domainから取得するため、renderer復旧後の新generationに追従できる。
  Dispose後はidentityを公開しない。
- Notes capabilityに`dtn_surface_attach_to_renderer`を追加した。通常のprocess-global lookupに加え、
  manifest/native-assets loaderがrenderer dylibをlocal scopeで読み込んだ場合も、読み込み済みimageのexact
  leaf nameから`RTLD_NOLOAD`でresolverを取得する。Notes側から新たにdylibをloadしない。
- `TerminalNotesNativeSurface.attachToRenderer`はAppKit pointerではなくopaque identityだけを受け、
  `attached` / `rendererUnavailable` / `busy`の型付き結果を返す。DetachもDart facadeへ追加した。
  Zero/out-of-rangeはFFI前に拒否し、stale/unbound/releasedはfail soft、off-main-threadは拒否、異なる
  2つのhostへの同時attachは`busy`とした。Same-host attachはidempotentである。
- Native integration testは実renderer dylibを`RTLD_LOCAL`でloadし、登録されたcustom View factory/operationを使って
  rendererをbindする。その上でNotes surfaceがterminal Metal viewの最前面childになることを検証した。
  これによりDartやtestがnative pointerを仲介して成功したように見せない。
- `dart_appkit`には一切変更を加えていない。隣接repositoryで検出した3 fileの変更はすべて
  着手前からのuser変更である。

### 検証

- `make terminal-renderer-native-test terminal-renderer-dart-test terminal-notes-native-test terminal-notes-dart-test
  terminal-notes-capability-audit`: 権限付き最終実行で全成功。Notes export allowlistは17、
  `dart_appkit=generic`を維持した。Rendererのunbound/exact/stale/released identity、Notesのactual overlay、
  same-host idempotence、second-host busy、wrong-thread、detachを含む。
- 最初のsandbox内renderer native testはMetal device/shaderを利用できず後続失敗したため中断した。
  Host framework/GPUへアクセスできる権限付き同一gateは成功し、製品codeの失敗ではない。
- 最初の`make test`はrenderer source hashを参照するGhostty gap inventoryのfreshnessだけで停止した。
  `make ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`を正規generatorで実行し、
  classification/count/blockerを変えずsource hash chainだけを更新した。
- 再生成後の`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。372 filesのformat変更0、
  root/package analyze issue 0、native capability、Note store実filesystem、security stress、distributionを含む全回帰が
  `dart_terminal tests passed`で完了した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`: 両方で成功。どちらも
  `capabilities=3`、Notes/rendererを含むexact native asset bundleとarchitecture/code inventoryを受け入れた。
- `git diff --check`: 成功。

### 次への引き継ぎ

- 現時点でapplicationはNote surfaceを生成せず、overlay seamも呼び出さない。次はproduction
  Note subsystemがlazy store/authorityとpane/Quick Terminalごとのsurfaceを所有し、bind/attach/update/detachの
  topologyを実装する。
- Renderer recoveryでcomposition identityが変わる場合は、topology ownerが旧hostからdetachし、新identityへ
  reattachする。Native surfaceやrendererにpersistent Note/Context identityを持たせない。
