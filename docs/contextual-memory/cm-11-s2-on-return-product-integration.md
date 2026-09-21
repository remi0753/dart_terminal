# CM-11 S2 On Return product integration

日付: 2026-09-21
状態: 実装中

## 目的

CM-01〜CM-10で固定・実装したNote domain、durable authority、native sticky-note surface、application
compositionへ、S2 On Returnを接続する。ユーザーが明示的にNoteをOn Returnへ設定し、そのNoteが属する
This Terminalからeligibleな意味で離れて戻ったときだけ、既存terminalの入力・focus・geometryを変えずに
一つのnative railを表示する。Deliveryはdurable dueとして保持し、実際に表示できたcardのacknowledgementが
commitされた後だけ消費する。

## 背景と確認済みの事実

- Pure modelは`armOnReturn`、`cancelTrigger`、`observeEligibleFocus`、`observeLifecycleBatch`、
  `acknowledgePresentation`、durable `DeliverySequence`を既に持つ。Due projectionはdelivery sequence FIFO、
  同一transaction内はNote ID tie-breakである。
- Authorityはfocus edgeを最大64件までcoalesceし、surface/projection/card token、foreground、occlusion、
  visible layoutを照合するacknowledgement境界を持つ。Collapsed/background/occluded/stale/duplicate ackは
  deliveryを消費しない。
- Product surface configurationの`foreground`はapp active、owning window visible/key、selected tab、focused paneを
  既に合成している。`occluded`との論理積をS2 eligible focusとして利用でき、Note rail/editorへfirst responderが
  移ってもeligibleのままである。
- Native surfaceはMiroの付箋に近いopaque colored card、trigger chip、rail/editorを既に描画する。
  `visibleAcknowledgementEligibleGeneration`はrailが実際に表示され、due cardが存在するときだけ現在の
  projection generationを返す。First card geometryも取得できる。
- Native intent enumは0〜19を使用中でappend-only、`DtnSurfaceIntentV1`のreserved fieldは全て0を要求する。
  予約領域をShow timingへ転用すると既存ABIのcanonical validationを壊すため使用しない。
- Shutdown candidateはcontextをrestorableにするが、現在は`onReturnArmedHere`をawayへ遷移しない。
  App terminationはS2のawayとしてdurableに記録する必要がある。
- `notes-on-return`はlaunch-fixedで、effective enablementは`notes && notesOnReturn`である。S1 passive Note操作は
  このflagがfalseでも維持する。
- `dart_appkit`は汎用libraryである。Note、On Return、Dart Terminal action/store/contextを追加せず、既存の
  generic Window/View/native-extension注入境界だけを利用する。

## 採用設計

### Explicit timing UIとmutation

- EditorにGUIの`Show: Always / On Return` segmented controlを追加する。選択はbody/colorと同じSave操作で
  authorityへ渡し、create/editとtrigger replacementを一つのcandidate・一つのstore commitで確定する。
- Selected cardのaction areaにも同じShow controlを置く。Due On Returnには明示的なRe-arm controlを表示し、
  次のaway→returnまで再待機できるようにする。
- Native ABIは既存intentの意味やreserved fieldを変更しない。`save always available`、`save on return`、
  `arm on return`、`make always available`をappend-only intent kindとして追加する。
- Projection flagへ`onReturnEnabled`をappendし、disabled時はtiming controlを表示しない。Legacy `save`は
  triggerを保持するS1 semanticsのままにする。
- Re-arm/Show変更はexisting trigger/deliveryを同じcandidate内でcancelしてからarmする。Model上の
  store revisionが複数進む場合もphysical store commitとpublicationは一回だけとする。

### Eligible focusとsingle rail

- Productが`foreground && !occluded`をpaneごとのeligible値としてauthorityへ渡す。Attach時の初期値と、
  app/window/tab/pane/minimize/hide/Quick Terminalの実edgeだけを観測し、重複updateはdeliveryを作らない。
- Initial/restored dueまたはaway→eligible returnでdueがあるとき、authority-owned runtime actionがCurrent sectionの
  railを一回だけexpandする。TerminalやNoteへfirst responderを移さず、PTY input、DEC focus report、mouse/TUI、
  grid/drawable/winsizeを変更しない。
- 同じeligible visitでユーザーがrailを閉じても重複surface updateでは再openしない。Native/renderer replacementで
  unacknowledged dueが残る場合はat-least-once recoveryとして再projectionを許す。

### Visible acknowledgementと終了境界

- Nativeが新しいvisible-eligible projectionをlayoutしたときだけ既存scalar wake-upを発行する。Productは先に
  pending user intentを処理し、intentがない場合にexact projection generation、rail visibility、small-pane否定、
  first-card geometry、first due tokenを照合して一件だけacknowledgeする。
- Ack commitによる次projectionで次のFIFO dueがfirst cardになった場合は別wake-upで処理し、main-thread上の
  同期loopで複数disk commitを行わない。
- Shutdown candidate作成時、retained/restorable contextの`onReturnArmedHere`だけを`onReturnArmedAway`へ
  durable transitionする。Already-away/due/passiveは保持する。Restart後の最初のeligible observationでdueになる。
- Ack commit前のcrashはdueを保持して再表示し、ack commit後のcrashは消費済みを再表示しない。

## 不採用案

- Intentの`reserved0`へtimingを格納する案: ABI v1のreserved-zero canonical contractを破るため不採用。
- Save後に別commitでarmする案: create/editだけcommitされtriggerが失われるcrash windowを作るため不採用。
- Focus return時にnotification、urgency、timeout、input holdを使う案: S2の範囲外であり不採用。
- Terminal output、shell marker、foreground process、alternate-screen stateからreturnを推測する案: shell-independent
  S2とterminal transparencyに反するため不採用。
- Rail表示時に全dueを一括ackする案: viewport外cardをfalse-consumeし得るため不採用。実際にfirst cardとして
  layoutされた一件ずつをFIFOでackする。
- `dart_appkit`へNote固有control/model/intentを追加する案: generic library境界に反するため不採用。

## 範囲

- On Return enablement projection、native editor/action controls、append-only intent/result validation。
- Create/edit + Show timingのatomic authority transition、standalone arm/re-arm/cancel。
- App/window/tab/pane/minimize/hide/Quick Terminalを含むeligible focus observationとedge coalescing。
- Due時のsingle non-blocking native rail、visible-card acknowledgement、FIFO delivery。
- Termination-away、restart、commit/ack crash behavior、S2 product acceptance。

## 対象外

- S3 At Next Prompt、shell integration v3、command/prompt inference。
- Notification、Dock urgency、timeout、input hold、terminal output decoration。
- Public Settings/documentation、rollout stage promotion、default-on decision。
- Rich text、Markdown、attachment、workspace scope、sync/import。
- `dart_appkit`の製品固有変更。

## 依存関係

- CM-01〜CM-06のdomain/store/authority/configuration contract。
- CM-07のsole input/focus authority、CM-08/09のnative surface/editor ABI、CM-10のproduct subsystemと両runtime harness。
- Existing application hierarchyが生成するforeground/occluded値と、native renderer composition identity。

## サブタスクと実施順

1. **Explicit arm/re-arm native UIとatomic product mutation**
   - Projection enablement、editor/action Show controls、append-only intentを追加する。
   - Create/edit/arm/re-arm/make-alwaysを一回のcandidate/store commitへ接続する。
   - Disabled時entry 0、legacy S1 Save semantics維持、conflict/fault時draft保持を検証する。
2. **Eligible focus lifecycleとsingle non-blocking rail**
   - Product surface configからexact eligibility edgeをauthorityへ渡す。
   - Initial/restored dueとaway→returnでCurrent railをvisitあたり一回だけ自動表示する。
   - App/window/tab/pane/minimize/hide/Quick Terminal、64 edge pressure、focus/input/geometry不変を検証する。
3. **Visible acknowledgement、shutdown-away、crash境界**
   - Actual native visible layout wake-upからfirst due tokenを一件ずつackする。
   - Background/occluded/small/stale/duplicate false-consume 0、simultaneous due FIFOを検証する。
   - Termination-away、restart、commit前後/ack前後crashのat-least-once境界を固定する。
4. **S2両runtime product acceptanceと全監査**
   - F1〜F4、multi-window/tab/pane/Quick Terminal、alternate screen/Vim/Codex/mouse TUI vectorを実装する。
   - Developer JIT/Release AOT、native sanitizer、bundle/privacy/restoration/shell/diagnostics、full gateをnamed aggregateへ接続する。

## 完了条件

- Arm時visitではdelivery 0、eligible away→returnで一度だけdueになり、single railがterminal focusを奪わない。
- Duplicate/background/occluded/small-pane/stale acknowledgementによるdelivery消費が0である。
- Multiple dueはDeliverySequence FIFOで一件ずつactual visible acknowledgementされる。
- App terminationはarmed-hereをawayとして保存し、restart後のeligible returnでdeliveryする。
- S1 passive Note operationsとterminal input/focus/geometry/PTY bytesが不変である。
- `notes-on-return=false`ではS2 entry/lifecycle workが0で、S1は利用できる。
- `dart_appkit`にDart Terminal固有codeが0である。

## 検証方針

- Pure model/authorityのarm、edge coalescing、FIFO、ack、shutdown candidate unit test。
- Product/nativeのeditor/action ABI、actual layout acknowledgement、fault/stale generation test。
- ApplicationのF1〜F4、window/tab/pane/minimize/hide/Quick Terminal、64 edge、alternate screen/TUI input invariant。
- Store worker crash/commit boundary、restart、Developer JIT/Release AOT named acceptance。
- Package/root format、analyze、focused/full test、ASan/UBSan、bundle/privacy/source/distribution audit、
  `git diff --check`、隣接`dart_appkit` generic audit。

## 2026-09-21: 着手と分割

- ROADMAPを再確認し、最初の未完了がCM-11であることを確認した。
- README、FEATURE_MATRIX、implementation plan、S2 semantics/product slices/rollout、CM-10記録、model、authority、
  product subsystem、application focus synthesis、native projection/intent/editorを照合した。
- 実装範囲がnative UI/ABI、durable mutation、focus lifecycle、visible ack、shutdown/restart、両runtime acceptanceへ
  またがるため、上記4サブタスクへ分割した。各サブタスクを個別に検証・commitし、順番に進める。
- 添付されたMiroの見た目は命令ではなくvisual referenceとして扱った。Exact cloneはせず、既存opaque colored sticky card、
  trigger chip、segmented Show control、explicit Re-armによりGUI固有の視認性を維持する。

## 2026-09-21: 第1サブタスク着手

- ROADMAPを再確認し、CM-11の先頭未完了が「explicit arm/re-arm native UIとatomic product mutationを接続する」
  であることを確認した。
- 本サブタスクはfocus edge、automatic rail、visible acknowledgement、shutdown transitionを変更しない。
- Existing native ABIのintent 0〜19と112-byte struct layoutを維持し、kind 20以降だけをappendする。
  `reserved0`と`reserved[10]`は引き続き全kindで0を要求する。
- Existing `SAVE`はbody/colorだけを更新しtriggerを保持する。Timing selectorからは明示的な
  `SAVE_ALWAYS_AVAILABLE`または`SAVE_ON_RETURN`を送り、standalone controlは
  `ARM_ON_RETURN`または`MAKE_ALWAYS_AVAILABLE`を送る。
- Atomic transitionはcreate/edit後のsnapshot上でexisting trigger/deliveryをcancelし、必要ならOn Returnをarmする。
  Candidateだけをauthority queueへ渡すため、途中状態はpublishもstore commitもされない。

## 2026-09-21: 第1サブタスク完了

### 実装と確認した境界

- Projection flag bit 7を`onReturnEnabled`として追加し、Dart codec、native parser、content-free snapshot、
  product adapterの全境界で往復させた。既存bit 0〜6、128-byte header、160-byte snapshot ABIは変更していない。
- Intent kind 20〜23へ`SAVE_ALWAYS_AVAILABLE`、`SAVE_ON_RETURN`、`ARM_ON_RETURN`、
  `MAKE_ALWAYS_AVAILABLE`をappendした。既存kind 0〜19、112-byte intent struct、reserved-zero contractは維持した。
- Native editorへ`Show: Always / On Return`、selected card action areaへ同じShow controlとdue時のRe-armを追加した。
  英語・日本語label、VoiceOver tree、keyboard order、pending intent中のsemantic ownershipをAppKit controlとして固定した。
- `notes-on-return=false`ではShow/Re-armをnative projectionへ露出せず、fake/injected intentがnative UIを迂回しても
  product bridgeでrejectする。S1のlegacy `SAVE`は従来どおりbody/colorだけを更新し、既存triggerを保持する。
- Create/editとShow timing変更は、一つのauthority transition内でcreate/edit、既存trigger/delivery cancel、必要なarmを
  合成した。Logical store revisionが複数進んでも、store commitとprojection publicationは各一回である。
- Standalone arm、due re-arm、make-alwaysも一つのcandidateとしてcommitする。Re-armはdue deliveryをcancelして
  `onReturnArmedHere`へ戻し、make-alwaysはtrigger/deliveryを同時に除去する。
- `dart_appkit`へNote、On Return、product intent/modelを追加していない。既存のgeneric native-extension/view境界だけを使った。
  隣接repositoryに元から存在した`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、
  `scripts/build_dart_engine.sh`の変更は読み取り確認だけ行い、編集・stageしていない。

### 検討結果

- Existing `SAVE`自体を新しいAlways semanticsへ変更する案は、S1 callerが意図せずtriggerを消すため不採用とした。
- Timing値をreserved fieldへ格納する案はcanonical ABIを壊すため不採用とし、append-only intentを採用した。
- Save後に別intentでarmする案はcrash windowと二重publicationを生むため不採用とし、pure snapshot mutationを
  candidate内で合成した。
- AppKit segmented controlはMiroのexact cloneではないが、既存opaque colored sticky cardと組み合わせてtimingを
  常時視認・直接操作できるため、GUI固有の見せ方とnative accessibilityを両立できると判断した。

### 検証

- `make terminal-notes-native-test terminal-notes-dart-test`: pass。append-only ABI、projection round-trip、
  editor/action controls、localized accessibility、conflict時draft保持、Re-arm/Always intent、native asset hookを確認した。
- `dart run test/terminal_note_authority_test.dart`: pass。create/edit/arm/re-arm/make-alwaysのatomic commit、
  delivery cancel、legacy Save trigger保持を確認した。
- `dart run test/terminal_note_native_adapter_test.dart`: pass。product presentationからnative projection/snapshotへの
  enablement伝播を確認した。
- `dart run test/terminal_note_product_subsystem_test.dart`: pass。enabled時のnative intent round-tripと、disabled時の
  entry非露出・injected intent拒否を確認した。
- `make terminal-notes-capability-audit`: pass
  (`TERMINAL_NOTES_CAPABILITY_AUDIT_PASS ... dart_appkit=generic`)。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。383 Dart filesのformat、root analyze、全native/package/root、
  Developer JIT/Release AOT host acceptance、privacy/restoration/shell/distributionを含む全gateが通過した。
- 隣接`dart_appkit`で`CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`と全native/Dart/runtime/example testが通過した。
- `git diff --check`: pass。
- sandbox内の最初のnative testではMetal renderer composition fixtureがcache/device制約で連鎖失敗し、Dart format/analyzeは
  workspace外telemetry fileのmtime更新だけ失敗した。通常のmacOS cache accessで同じgateを再実行すると、native test、
  format、analyzeはいずれも通過したため、実装不具合ではなくsandbox制約と判定した。

第1サブタスクの未検証事項と阻害要因はない。Eligible focus、automatic single rail、visible acknowledgement、
shutdown-awayは後続サブタスクの順序どおり未実装である。

## 2026-09-21: 第2サブタスク着手

- ROADMAPを再確認し、CM-11の先頭未完了が「eligible focus lifecycleとsingle non-blocking railを接続する」
  であることを確認した。
- 本サブタスクはvisible-card acknowledgement、delivery consume、shutdown-away、crash boundaryを変更しない。
  Dueは表示しても保持し、次サブタスクでactual layout acknowledgementへ接続する。
- Applicationは既に`application active && window visible/focused && active window && selected tab && focused pane`を
  `foreground`へ、pane/zoom visibilityとwindow occlusionを`occluded`へ合成している。Note rail/editorへの
  first-responder移動はこれらを変えないため、productのexact eligibilityを`foreground && !occluded`とする。
- Eligibilityはnative Note hostのattach成功可否から独立したcontext lifecycleである。Productはpaneごとのlast valueを
  保持し、`notes-on-return=true`のときだけinitial valueと実edgeをauthorityへ渡す。Duplicate surface/layout/
  appearance updateではlifecycle ingressを発生させず、disabled時はlifecycle workを0にする。
- Authorityはmemory-only eligible visit generationを持ち、new/restored dueをeligible surfaceへvisitごとに一回だけ
  auto-presentする。Current section、先頭page、DeliverySequence FIFOのfirst due cardを選ぶが、editor active中は
  draftを侵害せずpresentationを延期する。User close後の同一visitではreopenせず、次visitまたは新surface generationの
  unacknowledged recoveryでは再表示を許す。
- Automatic expansionは通常のuser openと区別するcontent-free authority projection stateとしてproductまで伝える。
  Application coordinatorはこの状態でrail/editor focus APIを呼ばず、terminalのsole input owner、first responder、
  DEC focus report、PTY bytesを維持する。利用者が実際にrailをpointer操作した時だけ既存interaction authority経由で
  Note ownershipへ移る。
- `dart_appkit`は変更せず、既存generic window/view eventとrenderer identityだけを利用する。

### 第2サブタスクの実装

- Productにpane単位のlast eligible値を追加し、On Return有効時だけattach前の初期値と
  `foreground && !occluded`の変化をauthorityへ渡した。Native host attachが失敗してもcontext lifecycleは失われず、
  同じ値のlayout、appearance、Note first-responder updateはedgeを増やさない。Pane closeとsubsystem teardownで
  memory-only値を破棄する。
- Authorityにeligible visit generationとsurface単位のlast/pending automatic visitを追加した。Initial/restored dueまたは
  return commit後にdueがある場合、Current、先頭page、DeliverySequence FIFOのfirst dueを選び、visitあたり一度だけ
  expanded railとしてprojectionする。Native projection拒否時はpendingを保持し、replacement surfaceは同じvisitの
  unacknowledged dueを再projectionできる。
- Automatic railは通常のroot surface再同期が渡す既定`collapsed`では閉じず、明示的なuser intentが
  `automaticPresentation`を解除するまでauthority-owned visibilityを保持する。これによりresize/appearance updateで
  railが消えること、および`collapsed + automaticPresentation`という不正projectionを防いだ。User Close後は同一visitの
  duplicate updateで再openせず、次のeligible visitでは未ack dueを再表示する。
- Editor active中はautomatic selection/visibilityを書き換えず、draftとdeliveryを保持する。Cancel時は既にユーザーが
  開いたrailにdue cardが現れる通常のeditor→rail解決を使い、automatic扱いにして消えたeditorをinteraction ownerへ
  残さない。Durable Save後などにautomatic projectionと同じsurfaceのeditor ownerが重なる場合だけcoordinatorが
  editor→railを解決し、terminalまたは別surfaceのownerにはfocus要求を出さない。
- Application coordinatorはautomatic railの通常同期ではnative rail/editor focus APIもterminal focus callbackも呼ばない。
  Pointer downが実際にrailへ入った場合だけ既存two-phase interaction authorityでNote railへ所有権を移す。
- Quick Terminalは専用app codeを汎用libraryへ追加せず、既存のpersistent quick contextと同じproduct eligibility APIを
  使用する。Hide/occlude→returnでstandard paneと同じdue/automatic/focus契約になることをproduct testで固定した。
- 64 live contextそれぞれへ`true, false, true`をcommit待ち中に投入し、contextあたり2 edgeのhard boundと
  `lastObservedEligibility`によるfinal-state coalescingを確認した。

### 第2サブタスクで検討した選択肢

- Surfaceのattach成功後だけeligibilityを観測する案は、renderer fault中のaway/returnを失うため不採用とした。
  Context lifecycleをnative ownershipから独立させ、再attach時に最新のeligible visitとdueをprojectionする。
- Automatic returnで常にrail focusを要求する案は、terminal input owner、DEC focus report、mouse/TUI routingを変えるため
  不採用とした。Projectionへcontent-freeなautomatic bitだけを持たせ、pointer操作までは既存ownerを維持する。
- Automatic railを毎surface updateで再openする案は、ユーザーのCloseを無効化するため不採用とした。Visit markerは
  projection成功時だけcommitし、同一surface/visitでは一度、replacement surfaceではat-least-once recoveryを許す。
- Editor終了直後を無条件にautomatic扱いする試行は、projection上はinactiveでもinteraction authorityに旧editor ownerを
  残し得るため取り消した。既にNoteを操作中なら通常のeditor→rail解決、terminal ownerならnon-blocking automatic rail、
  というownership別の境界にした。

### 第2サブタスクの検証（focused）

- 変更7 Dart fileの`dart analyze`: pass、issue 0。
- `dart run test/terminal_note_authority_test.dart`: pass。Arm時delivery 0、away→return、FIFO selection、visit一回、
  duplicate layout保持、manual Close抑止、later visit再表示、replacement recovery、active draft保護、64-context pressureを確認した。
- `dart run test/terminal_note_product_subsystem_test.dart`: pass。Exact eligibility、duplicate coalescing、standard paneと
  Quick Terminalのhide/return、disabled entry 0、native focus request 0を確認した。
- `dart run test/terminal_note_application_coordinator_test.dart`: pass。Terminal ownerを維持するautomatic rail、明示pointerでの
  rail transfer、既存editor ownerだけをrailへ解決する境界、renderer refresh時focus callback 0を確認した。
- 最初に3本の`dart run`を並行実行した際、共有`.dart_tool/lib`のnative build hookが競合し、coordinator testだけが
  `libdart_durable_file_macos.dylib`を一時的に見つけられず失敗した。同じtestを単独実行するとpassしたため、以後の
  Dart/native asset testは同じworktree内で直列実行する。

- `make terminal-notes-capability-audit`: pass
  (`TERMINAL_NOTES_CAPABILITY_AUDIT_PASS ... dart_appkit=generic`)。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。383 Dart filesのformat、root analyze、全native/package/root、
  Developer JIT/Release AOT host acceptance、privacy/restoration/shell/distributionを含む全gateが通過した。
- 隣接`dart_appkit`で`CI=true DART_SUPPRESS_ANALYTICS=true make test`: exit 0。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`と全native/Dart/runtime/example testが通過した。
  実行前後とも既存の`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、
  `scripts/build_dart_engine.sh`だけが変更状態で、本サブタスクは一切変更していない。
- `git diff --check`: pass。変更は本メモ、4 source file、3 focused test fileだけで、秘密情報、生成物、
  debug用変更、無関係な差分はない。

第2サブタスクの未検証事項と阻害要因はない。Visible acknowledgement、shutdown-away、crash boundaryは
後続サブタスクの順序どおり変更していない。

## 2026-09-21: 第3サブタスク着手

- ROADMAPを再確認し、CM-11の先頭未完了が「visible acknowledgement、shutdown-away、crash境界を接続する」
  であることを確認した。
- 目的は、actual native layoutを唯一のdelivery consume境界にし、application終了時のarmed-hereをawayとして
  durable保存し、commit/ack前後のfaultでもat-least-once規則を崩さないことである。
- 対象はnativeのcontent-free visible eligibility、productのone-intent-or-one-ack pump、authorityの既存generation/token
  validation、ordered shutdown candidate、restart/fault testである。S2 runtime matrix、alternate-screen/TUI、配布版の
  named aggregateは次のROADMAP項目で扱う。
- 実装範囲がnative layout、product pump、durable shutdown、worker faultへまたがるため、次の順序へ分割した。
  1. Actual visible layout wake-upからfirst due一件だけをFIFO acknowledgementする。Background、occluded、small、
     stale、duplicateではconsume 0とする。
  2. Ordered shutdown candidateでretained/restorable contextのarmed-hereだけをawayへ遷移し、restart後の最初の
     eligible observationでdeliveryする。
  3. Commit前後、ack前後のworker fault/crash vectorを固定し、親項目のfocused/full validationを完了する。
- 各子項目を個別に検証・文書更新・ROADMAP更新・commitし、親項目は3件すべて完了するまで未完了とする。
- `dart_appkit`は変更せず、Dart Terminal固有のlayout/Note acknowledgementはproduct/native Note package側に閉じる。

## 2026-09-21: actual visible layout wake-upとsingle FIFO acknowledgement

### 実装と境界

- Native surfaceは、host viewへ合成済み、expanded Current rail、presentation eligible、editor inactive、small-paneではない、
  first cardがdueかつ実際のclip内へ正の面積で見えている、という条件を満たす新しいprojection generationだけを
  `visibleAcknowledgementEligibleGeneration`へ公開する。同じgenerationのlayout反復、background、occluded、collapsed、
  small-pane、editor、Detachedでは0を返し、既存scalar surface callbackも発行しない。
- Visible wakeはaccessibility用`readyCue` presentation flagへ依存させない。Applicationが注入する通常presentationでは
  `readyCue=false`が既定であり、durable `due`とactual layoutがack資格の正本である。Generation単位の
  `lastAnnouncedGeneration`をscalar wakeとVoiceOver announcementの共通dedup境界にした。
- Product pumpは必ずnative user intentを先に一件だけtakeする。Intentがない場合だけ、authority projection、adapterが保持する
  native projection、content-free native snapshot、presentation snapshotを照合する。Pane/surface/projection generation、store
  revision、expanded/Current/editor inactive、feature/surface ready、On Return enablement、first due token、materialized count、rail/small
  flags、first-card/rail/pane intersectionの全条件が一致した場合だけauthorityへ一件のackを渡す。不一致は`noChange`で
  deliveryを保持し、native intent resultは生成しない。
- `Copy`のように新projectionを作らないuser intentがvisible wakeと競合すると、同generationのnative wakeはdedup済みになる。
  そのためintent resultをnativeへ返した後、dueが残る場合だけproduct event handlerへ一回の後続checkをscheduleする。
  Coordinatorの既存pane単位microtask coalescingを使い、現在のpump内でackを連続実行しない。
- Authority acknowledgementはvisible projection内の任意cardではなく、Current sectionのfirst due card tokenだけを受理する。
  Commit成功後、同じsurface/projectionがまだforeground visibleなら、次のdurable FIFO dueをpublication前にCurrent先頭へ選択する。
  これにより一回のwake/commitで一件だけ消費し、次dueは新しいprojection generationと別wakeで処理する。Concurrent duplicate
  token、late surface、visibility/editor変化は既存stale/duplicate境界でconsumeしない。
- 変更は`dart_terminal`のauthority/productとproduct-owned Notes native packageに限定した。`dart_appkit`へNote、delivery、
  acknowledgement、product schedulerを追加していない。

### 検討結果と実装中の判明事項

- Rail表示時に全dueを一括ackする案はviewport外のfalse consumeと同期disk commit loopを生むため不採用とした。
  Native actual visibilityとproduct exact snapshotを二重に照合し、first card一件だけを受理する。
- `readyCue` bitをwake条件に流用する案はproduction既定値がfalseでdeliveryを永久に保持するため不採用とした。Ready表示の装飾値と
  durable delivery stateを分離し、native testも`readyCue=false`のvisible dueでwakeするfixtureへ変更した。
- User intent処理後に同じpumpでackまで行う案は、UI mutationとdelivery commitを一つのevent turnへ連結するため不採用とした。
  一回だけ後続eventをscheduleし、native projection wakeと同じcoalescing境界へ戻す。
- Product testの最初の試行では、同一return transactionでdueになった2件を作成順のbody labelで期待した。しかし同一transactionの
  tie-breakはopaque Note IDであり、作成順は契約ではない。Actual first projectionのDeliverySequence順を基準に、first ack後も
  その次のcardが先頭になることを検証する形へ修正した。
- Sandbox内のnative focused testはMetal device/cache accessを得られずrenderer composition fixtureが連鎖失敗した。同一binaryを
  通常のmacOS権限で実行するとpassし、`make -B`後のhashも同一だったため、Notes logicまたは増分artifactの不具合ではなく
  sandbox制約と確認した。Native sanitizerも同じcache拒否後に通常権限で再実行してpassした。

### 検証

- `dart run test/terminal_note_authority_test.dart`: pass。First due限定、2件dueの別commit、ack後の次FIFO先頭選択、delivery 0までの
  generation更新を確認した。
- `dart run test/terminal_note_product_subsystem_test.dart`: pass。Intent優先と後続check、background、occluded、small-pane、stale
  generation、zero/outside geometry、hidden rail、duplicate old wakeのconsume 0、2件dueのone-per-pump commitを確認した。
- `dart run test/terminal_note_native_adapter_test.dart`、
  `dart run test/terminal_note_application_coordinator_test.dart`: pass。Projection変換とscalar wake coalescing/focus ownershipに回帰なし。
- `make terminal-notes-native-test`: pass（通常macOS権限）。`readyCue=false`、small→visible layoutでwake 1、同generation relayout 0、
  hidden due 0、notification ID一致をactual AppKit viewで確認した。
- `make terminal-notes-dart-test`: pass。Package format/analyze、codec、native asset hookが通過した。
- `make product-native-sanitizer`: pass。
  `PRODUCT_NATIVE_SANITIZER_PASS suites=5 artifacts=11 asan_artifacts=11 ubsan_artifacts=9 architecture=arm64`。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。383 Dart filesのformat、root analyze、全native/package/root、
  Developer JIT/Release AOT host acceptance、privacy/restoration/shell/distributionを含む全gateが通過した。
- 隣接`dart_appkit`で`CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`。実行前から存在する
  `docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、`scripts/build_dart_engine.sh`の変更だけが残り、
  本サブタスクは編集していない。
- `dart analyze`: pass、issue 0。`git diff --check`: pass。

本子項目の未検証事項と阻害要因はない。Shutdown-awayとrestart delivery、commit/ack crash vectorは次のROADMAP子項目として
未実装のまま保持する。
