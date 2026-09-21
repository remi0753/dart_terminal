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
