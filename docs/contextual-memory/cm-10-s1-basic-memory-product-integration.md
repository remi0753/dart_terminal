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

## 2026-09-21: Production authority/topology lifecycle着手

- ROADMAPを再確認し、先頭未完了がCM-10第2サブタスク内の
  「production Note subsystemのauthority/topology lifecycleを実装する」であることを確認した。
- `TerminalNoteCompositionRoot`、`TerminalNoteAuthority`、store worker、restoration binding、native adapter、renderer
  composition identityを再確認し、この段階ではapplication hierarchyへ接続せず、production factoryとtopology ownerを
  完結させる。
- Application自身がstore worker、authority、native surfaceを個別に所有する案は、close/renderer recovery/quitの順序を
  複数箇所へ分散させるため不採用とした。`TerminalNoteProductSubsystem`を唯一のproduct topology ownerとし、storeと
  authorityはadmission後に一度だけ起動、native surfaceはpane rendererのattach時まで生成しない。
- Native surfaceを全pane分eager生成する案はdefault-off/hidden surfaceのresource 0とlazy owner条件に反するため不採用とした。
  Pane bindingとnative surface ownershipを分離し、pane/Quick Terminal topologyだけを先にauthorityへ登録する。
- Renderer recoveryでsurfaceを破棄して新規生成する案は、surface generationとdraft/selectionのvolatile continuityを失うため
  不採用とした。同じadapterを旧hostからdetachして新しいopaque renderer identityへreattachし、失敗時はauthority projectionを
  collapsed/non-eligibleへfail-closeした上で再試行可能なownerを保持する。
- Store/native failureの詳細をapplication capabilityへ漏らす案は不採用とした。起動結果は既存の固定分類だけへ写像し、
  topology resultもbody、ID、path、timestampを含まない。
- Topology操作は単一のserial tailへ投入し、pane bind/close、surface attach/update/detach、shutdownの所有権変更を順序付ける。
  Shutdown要求後の未着手操作は受理せず、authority stopとnative owner解放をsingle-flightで行う。
- Direct injectionでもschema外のNote font、authority generation、timestampを受理しない。Native reattach failure後にauthority側も
  surfaceを拒否した場合はlocal mapから除外してadapterを破棄し、authority/nativeの片側だけにownerを残さない。
- Focused format/analyze/adapter/product topology testは成功した。最初のfull `make test`は既存の正規freshness gateにより
  `compatibility/release_candidate_daily_use_matrix.json`のsource hashがstaleとして停止した。Acceptance内容を変更せず、
  正規generatorでhash chainを更新してから全回帰を再実行する。

## 2026-09-21: Production authority/topology lifecycle完了

### 実装

- `TerminalNoteProductSubsystem.start`をproduction factoryとして追加した。Enabled admission後にnative capabilityを初期化し、
  environmentからstore locationを解決してreal worker/authorityを一度だけ起動する。Disabled branchは既存composition rootの
  手前でfactory自体を呼ばない。Recovery、upgrade、lock contention、その他の起動失敗は固定application capabilityへ分類する。
- Initial standard paneとQuick Terminal singletonをauthorityへbindし、pane topologyとnative surface ownershipを分離した。
  Native channelはrenderer surface attach時だけ生成するため、store/authorityのeager ownerとsurfaceのlazy ownerを混同しない。
- Bind/close/attach/update/detach/shutdownを一つのserial topology tailへ集約した。Surface attachはrenderer host、layout、authorityの
  順で行い、closeはsurface detach後にcontextをretireする。Shutdownはsingle-flightでauthority/store/native ownerを全解放する。
- Renderer identity/generationが変わった場合は同じadapterとauthority surface generationをdetach/reattachする。Native failureは
  authority projectionをcollapsed/non-eligibleにして再試行可能にし、authority側も拒否した場合はadapterを破棄して片側ownerを
  残さない。Layout failure、duplicate/stale、invalid timestampもtyped resultでfail closedにした。
- Live configurationは12..24ptのNote fontだけを再projectionし、terminal grid、drawable、PTY geometryを変更しない。
  Launch-fixed flagの直接変更とschema外入力はnative/store ownershipを得る前、またはprojection変更前に拒否する。
- Existing native adapterへrenderer attach/detach seamを追加し、disposeはdetach failure後も必ずnative destroyを行う。
  `dart_appkit`へDart Terminal固有型・operation・codeは追加していない。

### 検証

- Focused format: 6 file、変更0。Focused analyze: product subsystem/native adapter/test、issue 0。
- Focused tests: projection adapter teardownとreal filesystem workerを使うproduction subsystem lifecycleが成功。2 initial pane、
  Quick Terminal、concurrent bind、lazy surface、renderer recovery/retry、live font、invalid launch-fixed change、failed attach、
  detach/close、single-flight shutdown、product/authority/worker/native owner baseline復帰を検証した。
- 正規generatorで`release_candidate_daily_use_matrix.json`の`test/run_tests.dart` source hashだけを更新した。
  再実行した`CI=true DART_SUPPRESS_ANALYTICS=true make test`はnative packages、actual Notes capability、store real filesystem、
  security stress、compatibility、distributionを含めて`dart_terminal tests passed`。Full runで検出したbarrel export ordering infoを
  修正後、root `dart analyze`はissue 0。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`: 両runtimeで成功し、`capabilities=3`のexact bundleを維持した。
- `git diff --check`: 成功。隣接`dart_appkit`の差分は着手前から存在する3 fileだけで、本作業による変更は0。

### 次への引き継ぎ

- Product subsystemはまだ`TerminalApplication`から生成・駆動されていない。次はcomposition rootをapplication startupへ接続し、
  pane/Quick Terminal renderer lifecycle、window interaction adapter、live font reload、ordered teardownをproduction eventへ結ぶ。
- Mutation/action/exportは後続サブタスクの範囲であり、この段階ではnative intentをpollせず、S2/S3 trigger deliveryも開始しない。

## 2026-09-21: Application composition/interaction lifecycle着手

- ROADMAPを再確認し、先頭未完了がCM-10第2サブタスク内の
  「application composition、interaction、live font、disabled lifecycleを接続する」であることを確認した。
- `TerminalApplication`のinteractive hierarchy startup、pane resource factory、Quick Terminal、configuration reload、
  accessibility/theme projection、window interaction authority、pane/window close、quit teardownの順序を再確認した。
- Pane/window/tabを生成する全action implementationへNote処理を個別追加する案は、AppleScript、Quick Terminal、close/recoveryなどで
  漏れや順序差を作るため不採用とする。Application stateのsettled topologyを一箇所で比較するproduct coordinatorを追加し、
  logical bind/closeをnative hierarchy reconciliationより前にqueueする。
- Generic `TerminalNativeHierarchyAdapter`や`dart_appkit`へNote型を追加する案は不採用とする。既存のpane resource callbackから
  Dart Terminal側coordinatorへrenderer identity、layout、window identity、presentationだけを注入する。
- Native hierarchyのadapter teardown callbackは同期でview destroyより先に呼ばれる。Authority detach完了を待つだけでは順序を保証
  できないため、product subsystemへ同期のhost-detach preparationを追加し、interaction ownerを返してNote childをhostから外した後に
  非同期authority closeをqueueする。Application全体のshutdownではNote subsystem shutdown完了後にterminal renderer viewを破棄する。
- Disabled branchはcomposition factoryを呼ばず、store path解決、native Notes initialization、authority/worker、surface、interaction adapterを
  すべて0に保つ。有効時もnative surfaceは最初のlive layoutまで生成しない。
- Note fontだけをconfiguration reloadからlive projectionし、renderer recovery、pane resize、backing scale、window focus/occlusion、
  accessibility/theme/system badgeはpane-local presentation updateへ変換する。Terminal grid/drawable/PTY resizeは既存経路だけが所有する。
- Native semantic intentのmutation、Note action catalog、Detached/exportは次サブタスクで接続し、本サブタスクでは先行実装しない。

## 2026-09-21: Application composition/interaction lifecycle実装

### 実装と判断

- `TerminalNoteApplicationCoordinator`をDart Terminalのapplication-owned composition境界として追加した。
  Launch admission、logical pane/Quick Terminal binding、native surface、window interaction adapterを一か所で直列化し、
  generic AppKit hierarchyや`dart_appkit`へNote型を追加しない。
- `TerminalApplication`は既存hierarchyを走査してstandard/Quick Terminalのpane bindingを注入し、実rendererの
  composition identity、pane-local layout/backing scale/foreground/occlusion/theme/accessibility/system badge/localeを
  product subsystemへ投影する。Note overlayはrenderer child compositionであり、grid/PTY resize入力には加えない。
- Default-offでもapplication coordinator自体はcontent-freeなdisabled shellとして存在するが、composition rootは
  production factoryを呼ばない。したがってstore location解決、worker、authority、native initializer、surface、timerは0のままにする。
- Note editorのdirty/pending transferはsole window interaction authorityからpane/window closeとapplication Quitを
  `busy`にする。View teardown時はterminal first responderへの二段階transfer、native host detach、terminal view destroyの順に固定した。
- Renderer recoveryでは、host detach時に破棄したinteraction adapterだけを新しいrenderer hostへ再生成する。
  Durable contextとauthority surface generationは維持し、renderer generationの変更だけを再attachする。
- Live reloadはlaunch-fixedな`notes*` flagを変更せず、`notes-font-size`だけをcomposition root経由で全live surfaceへ反映する。
- 端末screen更新ごとの無用なNote presentation再送を避けるため、system badge projectionが実際に変わった時だけ
  Note surface reconciliationを要求する。Terminal session notice由来のbadgeもsecure-input badgeと同じくsystem badgeとして扱う。
- S1 create/open/edit等のsemantic intentとexpanded rail visibilityは次のsubtaskへ残し、この段階ではsurfaceをcollapsedで接続した。

### 検証途中の判明事項

- Focused analyzeは対象9 fileでissue 0。
- 最初のfocused testはMetal build hookがsandbox外の`~/.cache/clang/ModuleCache`へ書き込めず失敗した。
  `CLANG_MODULE_CACHE_PATH`は`xcrun metal`に反映されなかったため、同じ検証を許可済みの通常cache経路で再実行した。
- 再実行したcoordinator、product subsystem、application state、window interaction、product configurationのfocused testはpassした。
  Disabled factory 0、standard/Quick binding、dirty close/quit admission、live font、adapter-before-view、renderer reattach、single-flight shutdownを確認した。
- 実AppKit JIT/AOT、restart/fault、多window topologyのaggregateはCM-10最後のacceptance subtaskで実施する。

## 2026-09-21: Application composition/interaction lifecycle完了

### 検証

- Focused format/analyzeは成功。Coordinator、product subsystem、application state、window interaction、product
  configurationのfocused testを許可済みcache経路で再実行し、すべてpassした。
- 最初のfull `make test`は変更した`terminal_application.dart`を追跡するPhase 7 AppKit acceptanceのfreshnessだけで停止した。
  正規generatorでPhase 7、compatibility regression、Ghostty gap、release-candidate daily-use証跡を再生成した。
  差分はapplication/test runnerと連鎖artifactのSHA-256だけで、criterion、count、classification、release blockerは変えていない。
- 再実行した`CI=true DART_SUPPRESS_ANALYTICS=true make test`は376 fileのformat変更0、root/package analyze issue 0、
  native Notes host/capability、real Note store、security stress、compatibility、distributionを含めて
  `dart_terminal tests passed`で完了した。Notes host acceptanceは両modeで`geometry_delta=0`、capability auditは
  `dart_appkit=generic`を報告した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`は両方成功。Developer JIT/Release AOTとも
  `capabilities=3`のexact bundle、5 build assets、Note dylibを受け入れた。
- `git diff --check`は成功。隣接`dart_appkit`は着手前から存在する3 fileの変更だけで、本subtaskによる変更は0。

### 次への引き継ぎ

- Application、standard pane、Quick Terminal、renderer recovery、interaction/close admission、live font、ordered teardownの
  production接続は完了した。次の先頭未完了taskはS1 mutation、Detached、export、localized actionである。
- Native surfaceは意図的にcollapsedのままである。次のtaskでsemantic intentをdurable authorityへ接続し、create/open actionから
  railを展開する。Accepted resultはdurable commit後にだけnativeへ返し、content-free境界を維持する。
- 実AppKitのS1全flow、restart/fault、2 window/3 tab/5 pane、dirty confirmation、owner 0 aggregateはCM-10最後のtaskで実施する。

## 2026-09-21: Detached、reattach、copy/export task分割

- ROADMAPを再確認した。完了済みの「rail/editor navigationとdurable CRUD/reorder mutation bridge」は、3つの子taskがすべて
  検証・commit済みだったため親項目も完了へ補正した。次の先頭未完了は
  「Detached collection、reattach、explicit copy/exportを接続する」である。
- このtaskは、authority-owned global collection navigation、OS pasteboardへの本文egress、save panel承認後のportable file exportという
  異なる境界と失敗処理を含む。一つのcommitでは判断と残作業が曖昧になるため、次の順へ分割した。
  1. Current/Detached切替、64件単位paging、選択Noteのexplicit reattach
  2. authority検証後だけ実行する選択Note本文だけのexplicit pasteboard copy
  3. sensitive-content warningとsave panel承認後だけ実行するportable export
- 共通の範囲は、persistent Note IDをnative/productへ公開しないこと、native intentをauthorityのsurface generation/tokenで検証すること、
  Detachedを全context横断のglobal collectionとして表示すること、action resultより先にaccepted projectionまたは外部effectを確定すること
  である。Import、auto reattach、cwd/path/titleからの候補提示、Detached badge count、本文・pathを含む診断は対象外とする。
- Detached sectionをnativeだけのlocal stateにする案は、authority generationやtoken mapとずれるため不採用とする。
  Reattach先をcwd/path/titleから推測する案も、凍結仕様のexplicit actionとprivacy境界に反するため不採用とする。
- Detached pageは64件、exact total、Previous/Next/rangeをauthority projectionから決める。Native materialization上限32、projection上限64件または
  256 KiB、page切替時のcard token非再利用を維持する。
- Copyは選択Noteのfull bodyだけを明示操作でpasteboardへ出し、IDやmetadataを付けない。Exportは既存portable v1 codecを使い、
  body/color/status/order/passive trigger intentだけを含める。Save panel取消前のstore read/writeは行わず、path/contentを保持・記録しない。
- `dart_appkit`にはDart Terminal固有codeを一切追加しない。既存の汎用pasteboard/save panel APIをapplication compositionから注入して使う。
- 各子taskの完了条件はfocused native/Dart test、format/analyze、関連aggregate、`git diff --check`、隣接`dart_appkit`差分監査、
  task memo更新、個別commitである。

## 2026-09-21: Detached navigation、paging、reorder、explicit reattach着手

- ROADMAPを再確認し、先頭未完了が
  「authority-owned Detached navigation、64件paging、durable reorder、explicit reattachを接続する」であることを確認した。
- 目的は、Miroの付箋一覧に近いGUI上の見通しを維持しつつ、Currentとは別のglobal Detached collectionを明示的に閲覧し、
  選択したNoteだけを現在のterminal contextへ再接続できるようにすることである。
- 範囲はCurrent/Detached section intent、Detachedのexact totalと64件page、Previous/Next/range、pageごとのephemeral token、
  同じDetached section内のdurable reorder、selected detached Noteのauthority検証、現在pane contextへのdurable reattach、
  projection-before-result orderingである。凍結済みrail仕様との照合で、直前taskのreorderはCurrentだけを受け付け、Detached reorderが
  未追跡だと判明したため、実装前に現在taskへ追加した。
- 対象外はcopy/export、hidden create/open action、menu/palette localization、auto reattach、候補提示、Detached badge、import、trigger編集である。
- 依存関係はCM-05 authority/store queue、CM-08 projection codec/native surface、CM-09 semantic intent/result、直前taskのproduct intent pumpである。
  `dart_appkit`の変更は依存関係にも成果物にも含めない。
- 完了条件は、editor非active時だけのsection/page操作、64件境界に揃えたpage start、exact total、page遷移時token churn、
  Detached内だけのEarlier/Later、Detached選択Noteだけの明示reattach、commit後に全surfaceへ反映、失敗時のfixed content-free result、native control/accessibility、
  focused testとformat/analyze/関連aggregateの成功である。
- 検証方針は、pure authorityで65件以上のglobal Detached collectionと別contextへのreattachを確認し、product testでnative ABI/pump順序、
  native host acceptanceでsegmented control/pager/action状態、最後に関連aggregateと差分監査を行う。

## 2026-09-21: Detached navigation、paging、reorder、explicit reattach完了

### 実装と判断

- Authority surface intentへCurrent/Detached切替、Previous/Next、reattachを追加した。Section/page/selectionはnative local stateにせず、
  surface generation、projection generation、event generation、store revisionを照合したauthority transitionだけで更新する。
- Detached projectionはsnapshot全体からdetached attachmentだけを抽出し、orderとopaque IDによるdeterministic tie-breakで並べる。
  Badgeのactive/due countは従来どおり現在pane contextだけから算出し、Detached exact totalを混ぜない。
- Page startは64件境界に限定し、Previous/Nextで64件ずつ移動する。各projectionでcard tokenを新規発行し、64 card／256 KiBの
  projection上限と32 native viewのmaterialization上限を維持する。Reorderで選択Noteがpage境界を越えた場合は、そのNoteを含む64件pageへ
  authorityが移動する。
- Earlier/LaterはCurrentでは従来のattached reorder、Detachedではglobal detached reorderへ分岐する。同じsection内だけを対象にし、
  section間dragやimplicit attachmentは追加していない。
- ReattachはDetached projectionのephemeral tokenをauthority内部でpersistent IDへ解決し、選択Noteだけを操作したpane contextへdurable
  commitする。cwd/path/titleは参照せず、commit後の全surface refreshとtarget projection acceptanceより先にsuccessを返さない。
- Native ABIは既存0〜15を変更せず、show Current、show Detached、Previous、Nextを16〜19へappendした。Reattachは既存kind 8を使用する。
  Native validationもCurrent-only create/edit、Detached-only paging/reattach、one-outstanding、body-free navigationをfail closedにした。
- Railにはauthority-projected segmented control、localized Previous/Next、exact rangeを追加した。Detached cardのEdit位置は
  `Attach to This Terminal`／`このターミナルへ接続`へ置き換え、各cardから明示reattachできる。New、edit、color、resolve/reopen/deleteは
  Detachedで無効、Earlier/LaterはDetachedのcollection境界で無効になる。Cardのaccessibility positionはpage startを含むglobal位置を示す。
- `dart_appkit`は変更していない。Dart Terminal固有のprojection、intent、paging、reattach policyはproduct packageとapplication authorityに
  留めた。

### 検証

- Pure authority testは別contextから65件をDetached化し、exact total 65、64/1件page、往復時token非再利用、badge count 0、
  Detached durable reorder、選択Noteだけのreattach、Currentへの反映を確認してpassした。
- Product subsystem testは別pane closeからglobal Detached表示、native intent pump、reattach、Current復帰を実行し、各操作で
  `take → projection → result`の順を確認してpassした。
- Native capability testは実AppKit segmented control、Previous/Next、`1–64 of 65`／`65–65 of 65`、64 projected／32 materialized、
  per-card Attach action、content-free intentを確認してpassした。Dart package testはappend-only intent index 16〜19を固定した。
- `make terminal-notes-acceptance`はnative/Dart codec、Developer JIT/Release AOT host、capability audit、sanitizerを含めて成功し、
  `manifest=registered snapshot=content-free exports=20 dart_appkit=generic`を報告した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`は376 file format変更0、root/package analyze issue 0、Notes、store、security stress、
  compatibility、distributionを含めて`dart_terminal tests passed`で完了した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`は両modeで5 build assets、3 capabilities、Notes dylibを受け入れて成功した。
  `git diff --check`も成功した。
- 最後のoverflow防止式変更後に再実行したnative gateは、Notes assertionではなくrenderer identity/native host結合fixture 6件が一度だけ失敗した。
  同じbinaryをbuildし直さず即時再実行すると全件passし、直前のNotes acceptance、full suite、JIT/AOT auditでも同fixtureはpassしている。
  再現条件を固定できない単発のnative test environment failureとして記録し、再実行成功を確認した。
- 隣接`dart_appkit`は着手前から存在する`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、
  `scripts/build_dart_engine.sh`の3変更だけで、本taskによる変更は0である。

### 次への引き継ぎ

- 次の先頭未完了taskは「selected Noteのexplicit body-only pasteboard copyを接続する」である。
- Native Copy intentは既存どおりfull bodyを持つが、現時点のproduct pumpは固定rejectする。次taskではauthorityがtoken、generation、
  exact bodyを検証した後だけ、application compositionから注入した汎用pasteboard effectを一回実行する。IDやmetadataはcopyしない。

## 2026-09-21: explicit body-only pasteboard copy着手

- ROADMAPを再確認し、先頭未完了が「selected Noteのexplicit body-only pasteboard copyを接続する」であることを確認した。
- 目的は、Current/Detachedの明示Copy操作で選択または対象cardのfull plain-text bodyだけをsystem pasteboardへ一回書き、
  persistent ID、context、color、status、trigger、timestamp、revisionを一切egressしないことである。
- 範囲はauthorityのgeneration/token/exact-body検証、product subsystemの単発copy effect、application compositionからの汎用pasteboard
  callback注入、success/failureのcontent-free native resultである。Export、import、automatic copy、copy履歴、diagnosticsへの本文追加は対象外とする。
- Nativeだけでpasteboardへ直接書く案は、persistent authorityがstale token/bodyを検証できず、effect orderingをproduct testで固定できないため
  不採用とする。Authorityから本文をresultとして返す案もcontent-free result境界を破るため不採用とする。
- Native intentに既に含まれるbounded full bodyをauthorityの現在snapshot本文と完全一致で検証し、その検証成功後だけproductが注入callbackへ
  同じ本文を渡す。Callback成功後にだけaccepted resultを返し、失敗・例外は本文を保持または記録せずfixed unavailable resultへ畳む。
- `dart_appkit`は変更せず、既存`AppKitApplication.generalPasteboard.writeText`をproduction callback内で使う。Product/authorityは
  AppKit型をimportせず、汎用的な同期effect signatureだけを所有する。
- 完了条件はCurrent/Detached双方のexact body copy、stale token/mismatched body拒否、effect一回、metadata 0、projection/store mutation 0、
  pasteboard failureのfixed result、focused/aggregate test成功、task memoと個別commitである。

## 2026-09-21: explicit body-only pasteboard copy完了

### 実装と判断

- Authorityへcopy semantic intentを追加した。Expanded surface、inactive editor、current projectionのephemeral card token、draft/store/projection/event
  generationを照合し、intent bodyが現在snapshotのNote bodyと完全一致する場合だけcontent-free `runtimeApplied`を返す。
  Persistent IDや本文はresultへ返さず、projection generation、store revision、selectionも変更しない。
- Product subsystemへ同期`TerminalNoteBodyCopyEffect`を必須注入した。Authority検証成功後に限り同じbodyを一回だけeffectへ渡し、effectがtrueを
  返した後だけnative accepted resultを適用する。falseまたは例外は同じstore/projection generationのfixed unavailableへ畳み、再送用本文、
  pasteboard change count、例外内容を保持・診断しない。
- Application compositionは既存`AppKitApplication.generalPasteboard.writeText`をcallback内で呼ぶ。Product/authority層はAppKit型をimportせず、
  callbackはplain body以外のID、color、status、trigger、timestamp、revisionを受け取れない。
- Native ABIは既存Copy kind 10と4,096-byte/64-line plain-text payload validationをそのまま使う。Current/Detachedのどちらでも、現在projectionの
  cardだけをcopyできる。Copyはnon-projecting resultとして同じgeneration/revisionで完了する。
- `dart_appkit`は変更していない。汎用pasteboard APIの利用はDart Terminal production compositionだけに置いた。

### 検証

- Authority focused testはexact bodyを受理し、mismatched bodyを拒否し、store commit数、native projection数、revision/generationを変えず、
  result文字列表現へ本文を出さないことを確認してpassした。
- Product focused testはDetached bodyとCurrent bodyをそれぞれ一回だけcallbackへ渡し、projection/store mutation 0を確認した。
  注入effect例外はnative/productのfixed unavailableとなり、その後の明示retryは成功した。Copy resultにはbody/metadataを含めない。
- `dart analyze`はissue 0、両focused testはpassした。
- 最初のfull `make test`は`terminal_application.dart`のhash変更を検知したPhase 7 freshness gateだけで停止した。正規generatorでPhase 7、
  compatibility regression、Ghostty gap、release-candidate daily-use証跡を再生成した。実差分はapplicationと連鎖artifactのSHA-256だけで、
  criterion、count、classification、release blockerは変えていない。
- 再実行した`CI=true DART_SUPPRESS_ANALYTICS=true make test`は376 file format変更0、root/package analyze issue 0、native Notes、real store、
  security stress、compatibility、distributionを含めて`dart_terminal tests passed`で完了した。Capability auditは
  `manifest=registered snapshot=content-free exports=20 dart_appkit=generic`を報告した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`は両modeで5 build assets、3 capabilities、Notes dylibを受け入れて成功した。
  `git diff --check`も成功した。
- 隣接`dart_appkit`は着手前から存在する3 fileの変更だけで、本taskによる変更は0である。

### 次への引き継ぎ

- 次の先頭未完了taskは「sensitive warning、save panel、portable exportを接続する」である。
- Exportはcopyと異なり全Note snapshotをworkerでportable v1へserializeする。Save panel承認前にstoreを読まず、path/contentをproduct statusや
  diagnosticsへ残さず、mutation queueと排他的に実行する必要がある。

## 2026-09-21: S1 mutation/Detached/export/action task分割

- ROADMAPを再確認し、先頭未完了がCM-10の「S1 mutation、Detached、export、localized actionを接続する」であることを確認した。
  Data/privacy、overlay/editor、architecture/rolloutの凍結仕様、CM-05 authority、CM-09 native intent/result、既存action/menu/paletteと
  save panel/export workerを再照合した。
- このtaskはnative navigation ABI、durable mutation、Detached global collection、copy/export egress、application action/localizationの
  独立成果物を含むため、一つの変更・検証・commitで扱うとowner境界と残作業が曖昧になる。次の順へ分割してROADMAPに登録した。
  1. rail/editor navigationとdurable create/edit/color/reorder/resolve/reopen/delete bridge
  2. Detached collection、explicit reattach、body-only copy、warning/save-panel後だけのportable export
  3. hidden/internal create/open actionとEnglish/Japanese menu/palette projection
- Native intentをproduct subsystemでpersistent IDへ変換する案は不採用とする。Surface/card tokenからNote IDへのmapはauthorityだけが所有し、
  product/nativeへIDを返さないhigh-level semantic ingressを追加する。
- Per-keystroke draftやselectionをDartへmirrorする案は不採用とする。Dart authorityはeditor mode、draft generation、ephemeral selectionだけを
  projectionし、本文はSave intentのbounded payloadで一度だけ受ける。
- Current/Detached切替、card selection、New/Edit開始をlocal native stateだけで変更する案は、authority generation/tokenとの不一致を
  作るため不採用とする。Bounded semantic navigation intentとしてDart ownerへ返し、accepted projectionだけでUIを更新する。
- Store commit前にaccepted native resultを返す案は不採用とする。Durable mutationはauthority queueでcommitし、新projectionをnativeが
  acceptした後に同じoutstanding intentへsuccessを返す。Conflict/busy/failureはold revision/generationのfixed resultを返す。
- Exportは既存workerのwrite-only portable codecとexclusive temp/flush/atomic renameを再利用する。Save panel前のstore content readやwrite、
  path/contentのlog、general diagnosticsへのNote body追加は行わない。
- `dart_appkit`は引き続き汎用libraryとして読み取り監査だけにし、Dart Terminal固有のNote/action/export codeを追加しない。

## 2026-09-21: rail/editor navigationとdurable mutation bridge着手

- ROADMAPを再確認し、分割後の先頭未完了が
  「rail/editor navigationとdurable CRUD/reorder mutation bridgeを接続する」であることを確認した。
- 範囲はnative badge/rail navigation、card selection、create/edit/cancelのvolatile state、Save/color/reorder/resolve/reopen/deleteの
  durable authority ingress、lazy intent pump、result/projection orderingである。Detached projection/reattach、copy/export、application
  action catalog/localizationは後続subtaskまで実装しない。
- 完了条件はpersistent ID非公開、surface/projection/event/draft/store revisionのstrict照合、surfaceごとone outstanding、
  commit-before-projection-before-success、失敗時draft/selection/Undo保持、disabled timer/resource 0、teardown owner 0とする。
- このsubtaskもauthority、native ABI/pump、application interactionの3層へまたがるため、さらに次の順へ分割した。
  1. authority-owned surface stateとpersistent-ID-free semantic mutation contract
  2. native navigation ABIとlazy product intent pump
  3. applicationのrail/editor owner transfer、focus、close admission接続

## 2026-09-21: authority-owned surface stateとsemantic mutation contract着手

- ROADMAPを再確認し、先頭未完了が
  「authority-owned surface stateとsemantic mutation contractを実装する」であることを確認した。
- Authorityのlive surfaceにvisibilityとは別のsection/page/selection/editor/draft generationを持たせる。Persistent Note IDは
  authority内部のtoken mapとselectionだけに保持し、projectionはephemeral card tokenだけを公開する。
- Product subsystemへ任意の`TerminalNoteAuthorityTransition`を渡す案はpersistent ID、revision、delete tombstoneの責務を漏らすため
  不採用とする。Pane/surface/projection/event/draft/store revisionとfixed semantic kindだけを受けるhigh-level authority APIを作る。
- Secure Note ID生成もauthorityが所有する。Testだけdeterministic entropyを注入し、product/nativeへcanonical IDを返さない。
- この段階ではnative ABIとpollingを変更しない。Pure authority testからopen/create/edit/color/reorder/resolve/reopen/delete/cancel、
  stale/duplicate/conflict、commit-before-publication、projection token rotationを固定する。

## 2026-09-21: authority-owned surface stateとsemantic mutation contract実装

### 実装と判断

- `TerminalNoteAuthority`へsurface generationごとのCurrent section、page start、選択中Note、editor mode、draft generationを追加した。
  Persistent Note IDは`_LiveNoteSurface`とprojectionごとに再生成するtoken mapだけに保持し、public projection/result/diagnosticsには
  ephemeral tokenしか出さない。
- High-level `submitSurfaceIntent`はpane/surface/projection/event/draft/store revision、fixed intent kind、bounded Save payloadだけを受ける。
  Product側が任意のdomain transition、Note ID/revision、delete tombstoneを組み立てる余地を持たない。
- Open/close/select/create/edit/cancelはprojection-only state transitionとし、native surfaceがprojectionをrejectした場合はvolatile stateを
  rollbackする。Editing中のclose、古いtoken、draft不一致、unexpected payloadはfail closedとする。
- Save/createではauthority-owned secure 128-bit Note IDを生成する。Testだけentropy sourceを注入でき、衝突時は最大32回まで再生成する。
  Edit/color/reorder/resolve/reopen/deleteはauthority内でtokenをIDへ解決し、request時のstore/note revisionをdomain mutationへ渡す。
- Durable intentは既存の単一直列queueへ投入し、store commit成功後の`onBeforePublication`でのみeditor/selectionを遷移させる。
  その後target surfaceが新store revisionのprojectionをacceptして初めてsurface intentを成功扱いにする。Projection reject時はdurable
  commitを巻き戻さず`unavailable`を返し、後続のprojection reconciliationで収束させる。
- Deleteはaccepted snapshotの新store revisionを持つexact tombstoneを同じcommitへ渡す。Reorderはattached collection全体の
  deterministic orderをauthority内で組み替える。
- Projectionへsection/page/total/selection/editor/draftを追加した。最大64 card/256 KiBを維持し、選択Noteがpage外なら選択位置を
  page先頭へ移して必ずephemeral selected tokenを生成する。Collapsed projectionは本文とselected tokenを0に保つ。
- `dart_appkit`は変更していない。今回のAPI/state/mutationはすべて`dart_terminal`のproduct authority内に限定した。

### Focused検証

- `dart analyze lib/src/terminal_note_authority.dart lib/src/terminal_note_projection.dart test/terminal_note_authority_test.dart`:
  issue 0。Analytics session fileのmtime更新だけはsandboxに拒否されたが、解析自体は完了した。
- `dart run test/terminal_note_authority_test.dart`: pass。最初のsandbox実行はMetal/Clang module cache書込み拒否で停止し、
  host権限の同一commandで成功した。
- 新規vectorはopen/create/edit/color/reorder/resolve/reopen/delete/cancel、古いprojection/token、duplicate event、deterministic ID、
  durable revision conflict、delete tombstone、commit-before-projection、native projection reject後のreconciliationを確認する。

### 完了検証

- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。376 filesのformat変更0、root/package analyze issue 0、
  native capability/host acceptance、Note store実filesystem、privacy/security stress、distribution/update/symbolを含む全回帰が
  `dart_terminal tests passed`で完了した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`: 両runtimeともpass。Notesを含む`capabilities=3`、
  application asset/code inventory、localization、App Intents metadataをexactに受理した。
- `git diff --check`: pass。隣接`dart_appkit`の差分は着手前から存在する3 fileだけで、このsubtaskによる追加変更は0。

### 次への境界

- Native intent enumにはnavigation intentがまだなく、product adapterも新しいsection/selection/editor/draft projectionをまだ転送しない。
  次のROADMAP項目「native navigation ABIとproduct intent pump」で接続する。
- Detached collection/reattach、copy/exportは後続の専用subtaskまでauthority intentへ追加しない。

## 2026-09-21: native navigation ABIとproduct intent pump着手

- ROADMAPを再確認し、先頭未完了が「native navigation ABIとproduct intent pumpを実装する」であることを確認した。
- 目的はbadge/rail/card/New/Edit操作をgeneration-bound semantic intentとしてnativeから取り出し、product subsystemのlazy pumpで
  high-level authorityへ一度だけ渡し、projection/resultを正しい順序で同じnative surfaceへ返すことである。
- 範囲はproduct-owned Notes native ABI/facade、projection adapter、surfaceごとのbounded pump、clock injection、fault/teardownである。
  Applicationのwindow interaction owner transferとfocus policyは次のsubtask、Detached/export/action catalogは後続taskまで対象外とする。
- 完了条件はnavigationを含むone-outstanding、accepted durable intentのcommit→projection→result順、runtime intentのprojection/result整合、
  conflict/busy/faultでdraft/selection保持、polling ownerのlazy start/確実なstop、persistent ID/content-free diagnostics、
  native/product focused gateと`dart_appkit`変更0である。
- CM-09時点のnative-local navigation方針は、authority-owned selection/draft generationとの二重ownerになるためCM-10では採用しない。
  Native controlはfixed navigation intentだけを発行し、accepted authority projectionを唯一の状態更新にする。

## 2026-09-21: native navigation ABIとproduct intent pump完了

### 実装と判断

- ABI v1の既存値を変更せず、末尾へ`Open`、`Close`、`Select card`、`Begin create`、`Begin edit`を固定値11〜15で追加した。
  Intent/result struct、version、最大payloadは変更していない。Open/Close/Newはtoken 0、Select/Editは現在projectionに存在するephemeral
  card tokenだけを受理し、inactive editor・visibility・draft generationをnative入口でstrict検証する。
- Native railへNew/Close、各付箋cardへ選択領域とEditを追加した。選択中cardはaccent 3 px borderで示し、既存の色面、shadow、status chipを
  維持する。Card selectionはpointerだけでなくReturn/Space、VoiceOver pressに対応し、New/Close/card/Editを決定的なkeyboard/accessibility
  順へ含めた。Detached segmentとReattachは後続taskまで無効のままである。
- Nativeはnavigation、Cancel、durable mutationのaccepted resultを、先に適用済みのauthority projectionと完全一致する場合だけ受理する。
  Durable intentはstore revisionとprojection generationの双方が前進し、runtime navigationはstore revision同一でprojection generationだけが
  前進する。Copy/exportは非projection actionとして旧generationのまま完了できる。Projection適用中もone outstanding intentを保持し、
  resultまでsemantic controlを再有効化しない。
- Product adapterはauthority projectionのsection/page/total/selected token/editor/draft generationをnativeへ転送する。以前のCurrent/先頭page/
  selectionなし/inactive固定値は廃止したが、persistent Note/Context IDは追加していない。
- `TerminalNoteProductSubsystem.pumpSurfaceIntent`を追加した。Surface topologyと同じserial tailで一回につき最大1 intentだけ取り出し、fixed
  semantic kindを`submitSurfaceIntent`へ渡す。Clockはdurable mutationだけにinjectし、Open/Close/Select/Create/Edit/Cancelは時刻を持たない。
  Authorityがnative adapterへ新projectionを同期適用した後だけresultを返すため、commit→projection→result順が崩れない。
- Idle timer、periodic poll、continuous frame hookは作らなかった。Native interaction routing後にapplicationが明示的にpumpするevent-driven境界とし、
  disabled/collapsed idleのpolling ownerを0にした。Application event接続は次のROADMAP項目で実装する。
- Reattach/copy/exportは後続taskの責務なので、このpumpでは固定`rejected` resultを返し、projection/store revisionを進めない。Native result適用が
  reject/throwした場合はauthority surfaceをdetachしadapterをdisposeして、片側だけのownerや再送不可能なpending intentを残さない。
- `dart_appkit`は変更していない。Dart Terminal固有のNote ABI、GUI、pump、clock、fault処理はroot productと
  `dart_terminal_notes_macos`だけに置いた。

### 判明事項と失敗した試行

- 最初のnative回帰は旧testがaccepted resultをprojectionより先に適用していたため、先頭のSaveがpendingのまま残り後続actionが連鎖失敗した。
  Testをprojection-firstへ直し、result先行が`INVALID_ARGUMENT`になること自体も固定した。
- ProductのEdit後Cancel testで、Save時のcard tokenを再利用するとauthorityが拒否した。Ephemeral tokenはprojectionごとに再発行される設計どおりで、
  各操作は直前projectionのselected tokenを使うようにした。これによりpersistent identityをproductへ持ち出さずgeneration bindingを維持できる。
- Sandbox内の直接`dart analyze`は解析自体がissue 0でもuser telemetry session fileのmtime更新を拒否され終了code 1になった。権限付きの同一commandと
  `make test`内の正規analyzeでissue 0を確認した。製品codeの失敗ではない。

### 検証

- `make terminal-notes-dart-test terminal-notes-native-test terminal-notes-capability-audit`: pass。ABI値11〜15、実AppKit badge/New/card/Edit/
  Cancel/Close、pointer/keyboard/accessibility、one-outstanding、projection-first result、rejected action recovery、owner 0を確認した。
  Capability auditは`exports=17 dart_appkit=generic`。
- Focused product testはreal worker/filesystem上で、idle polling 0、Create/Save/Edit/Cancel、2 cardのEarlier/Later、色変更、Resolve/Reopen、Delete、
  未接続Copyのstate不変reject、native result fault時のsurface retirement、shutdown owner baselineを確認した。各accepted mutationは
  `take,projection,result`順である。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。376 filesのformat変更0、root/package analyze issue 0、native host/capability、
  Note store実filesystem、security stress、privacy/distribution/update/symbolを含む全回帰が`dart_terminal tests passed`で完了した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`: 両runtimeともpass。`capabilities=3`、5 build assets、Notes dylibを含む
  exact bundleを受理した。
- `git diff --check`: pass。隣接`dart_appkit`は着手前から存在する3 fileだけで、本subtaskによる追加変更は0。

### 次への境界

- 次の先頭未完了は「applicationのrail/editor interaction lifecycleへ接続する」。Native Note操作がwindow interaction authorityを経由した直後に
  対象paneのpumpを一度だけ呼び、rail/editor focusとterminal input suppression、dirty close admissionをapplication ownerへ接続する。
- Detached collection/reattach、copy/export、hidden create/open actionとmenu/palette localizationは順番どおり後続taskで行う。

## 2026-09-21: application rail/editor interaction lifecycle着手

- ROADMAPを再確認し、先頭未完了が「applicationのrail/editor interaction lifecycleへ接続する」であることを確認した。
- 目的は実native controlのeventをtimerなしでapplicationへ通知し、対象surfaceのintentを一回だけpumpした後、authority projectionに応じて
  sole window interaction ownerをterminal/Note rail/Note editorへ二段階transferすることである。Native dirty/confirm flagsもcontent-free snapshotから
  同期し、pane/window/quit close admissionへ反映する。
- 範囲はNotes capabilityのprocess-lifetime scalar notification、product subsystemのsurface event/focus/interaction snapshot、application
  coordinatorのserialized pump/focus/dirty lifecycle、Note内外pointerのno-replay処理、expanded visibilityのtopology update保持である。
- 対象外はDetached/reattach、copy/export、menu/palette action、restart aggregateであり、後続ROADMAP項目まで実装しない。
- Native callbackへpane ID、Note ID、body、pathを渡す案は不採用とする。Dart側が発行するprocess-localなopaque notification IDだけを渡し、
  listenerは即時returnして既存のbounded take APIから状態を取得する。`dart_appkit`のservice ABIやevent型は変更しない。
- Accepted navigation後のfocus policyは、expanded+inactiveをrail、expanded+active editorをeditor、collapsedをterminalとする。Dirty/confirmはnative
  本文をmirrorせず2 bitだけ同期し、Save/Cancel projection後はphaseをcleanにしてからrailへ移す。
- Application layout更新が常にcollapsedを再注入するとOpen直後のrailを閉じるため、attach時のinitial visibilityとauthority-owned live
  visibilityを分離する。Resize/appearance/renderer recoveryはlast accepted authority visibilityを維持する。
- 完了条件は通知あたり最大1 intent、通知coalescing、native focus成功後だけowner confirm、inside/outside pointerのterminal replay 0、dirty
  close/quit block、failure/teardown owner 0、disabled callback/surface owner 0、両runtime/full gate passとする。

## 2026-09-21: application rail/editor interaction lifecycle完了

### 実装と判断

- Notes native capabilityへprocess-lifetime callbackとsurfaceごとのopaque notification IDを追加した。Callback payloadは正のscalar IDだけで、
  pane ID、Note/Card ID、本文、path、timestampを含まない。Dart listenerは同期処理を行わず、application coordinatorが同一paneの通知を
  microtask単位でcoalesceして、通知対象surfaceの既存bounded intent APIを最大1回だけdrainする。
- Badge、New、Close、card selection、Edit、Save、Cancel、color/action、editor text/IME、discard/Keep Editingの実native controlからwake-upする。
  Accepted mutationは従来どおりauthority projectionをnativeへ適用した後だけresultを返し、その後のcontent-free snapshotで
  rail/editor/terminal focusとdirty/confirm phaseを同期する。Idle polling timerは追加していない。
- Product subsystemはnative snapshotのsurface/projection generationをlast accepted authority projectionとexact照合し、visibility、editor mode、
  draft generation、dirty/confirmの必要最小状態だけをapplicationへ返す。Native focus、discard confirmation、badge/rail hit-testもproduct-owned
  portに閉じ、`dart_appkit`へNote型、event、Dart Terminal固有codeを追加していない。
- Application coordinatorはnative first responder取得成功後だけsole window interaction authorityのtransferをconfirmする。Collapsed badge clickは
  rail、expanded read modeはrail、create/editはeditor、user Close後はterminalがownerになる。Dirty editorはpane/window/application quitをblockし、
  outside clickはinline discard confirmationを出してterminalへ再送しない。
- Pointer ownershipはdownだけでなくdrag/up/cancelまで保持する。Note上で開始したsequenceは外へ出ても全eventをconsumeし、terminal上で開始した
  sequenceはNote上へ入っても横取りしない。Window内でpane境界をまたいでも開始surfaceを追跡する。
- Layout/appearance更新の初期`collapsed`値がlive Open/editor stateを上書きしないよう、authorityのlast accepted visibilityを再投影する。
  Renderer host teardownもuser Closeとは区別してauthority visibility/editor stateを保持し、replacement host接続後にfocus/dirty stateを再同期する。
- Callback、handler map、pointer gesture、interaction adapterはsurface dispose/shutdown前に解除する。Native/result faultでsurface ownerが失われた場合は
  application interaction ownerもretireし、disabled branchはcallback、surface、storeを生成しない。

### 検証

- Focused format/analyze: application coordinator/product subsystem/native adapter、Notes packageと全更新testでissue 0。
- Focused Dart tests: opaque wake-up forwarding、projection generation照合、live visibility保持、host replacement、通知coalescing、1通知1pump、
  badge→rail→editor→dirty→confirm→Keep Editing→rail→terminal、pane/window/quit block、Note/terminal開始pointer sequenceのno-replay、shutdown owner 0がpass。
- `make terminal-notes-native-test terminal-notes-dart-test terminal-notes-capability-audit`: actual AppKit control、scalar callback、dirty confirmation、
  callback immutability、Dart facade、header/export inventoryがpass。Capability auditは`exports=20`、`snapshot=content-free`、`dart_appkit=generic`。
- 最初のfull gateは`terminal_application.dart`変更によりPhase 7 acceptance source hashがstaleとして停止した。正規
  `make phase7-appkit-acceptance`で同sourceの2 hashだけを更新した。次のrunはその入力を持つGhostty gap inventoryで停止したため、
  `make ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`を依存順に再生成した。Classification、件数、release blockerは変更していない。
- 最終`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。376 Dart filesのformat変更0、root/package analyze issue 0、
  native capability、実filesystem store、security stress、privacy、application、distributionと全freshness gateを完走し、
  `dart_terminal tests passed`を確認した。
- `make RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit`: 両方成功。Notesを含む5 native assets、3 capabilitiesのexact bundleを受理した。
- `git diff --check`: 成功。隣接`dart_appkit`の差分は着手前から存在する3 fileだけで、本サブタスクによる追加差分は0。

### 次への引き継ぎ

- Current collectionのdurable create/edit/reorder/resolve/reopen/deleteとrail/editor navigationはapplication lifecycleまで接続済みである。
- 次のROADMAP項目はDetached collection、reattach、explicit copy/exportである。現時点のnative semantic intentは存在するが、Detached selectionや
  export destination/pasteboard effectをproductへ接続しておらず、先行実装していない。
