# Contextual terminal memory architecture, verification, and rollout

- 状態: Gate 7 完了（implementation plan登録済み、製品コード未着手）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- Product判断: [`contextual-terminal-memory-product-slices.md`](contextual-terminal-memory-product-slices.md)
- Scope/trigger仕様: [`contextual-terminal-memory-scope-trigger-semantics.md`](contextual-terminal-memory-scope-trigger-semantics.md)
- Data/privacy仕様: [`contextual-terminal-memory-data-persistence-privacy.md`](contextual-terminal-memory-data-persistence-privacy.md)
- Overlay/input仕様: [`contextual-terminal-memory-overlay-editor-accessibility.md`](contextual-terminal-memory-overlay-editor-accessibility.md)
- Checkpoint採否: [`contextual-terminal-memory-checkpoint-feasibility.md`](contextual-terminal-memory-checkpoint-feasibility.md)
- 実装計画: [`contextual-terminal-memory-implementation-plan.md`](contextual-terminal-memory-implementation-plan.md)

## 目的

採用済みのS1 Basic memory、S2 On Return、S3 At Next Promptを、既存terminal architectureを壊さず
実装できるspecificationへ凍結する。Application、store、pane/session worker、terminal core、native main
threadのownerとmessage boundary、設定/capability、schema evolution、verification budget、previewから
default-onまでのrollout／rollbackを定義し、次taskで安全にimplementation subtaskへ分割できる状態にする。

## 背景

Gate 1〜6で製品slice、scope/identity、trigger、data/privacy、GUI/input/accessibilityを確定し、S5/S6は
不採用とした。しかし、modelとnative overlayを誰が所有するか、live projectionをどうboundedに保つか、
設定変更やstore version mismatchをどう扱うか、どのtestとperformance budgetをrelease gateにするかは
まだ統合仕様になっていない。この境界を決めずに実装taskを作ると、application owner、native handle、
restoration、shell capability、rollbackの責任が重複する。

## 対象範囲

- D-43〜D-48
- S1/S2 initial sliceと、S1/S2 acceptance後のS3 increment
- Model/store/context binding、trigger/delivery、native note surfaceの所有権とmessage schema
- Queue、generation、revision、backpressure、teardown、failure/recovery invariant
- Typed config、runtime capability、kill switch、live reload／new-session behavior
- Store/projection ABIのversioning、forward/backward compatibility、rollback-safe behavior
- Unit/property/fault/real PTY/native UI/accessibility/performance/privacy/release acceptance
- Internal preview、opt-in preview、default-on、S3 opt-inのstageとrollback runbook

## 対象外

- 製品code、test code、native API、config option、store file、assetの実装
- S4 Invocation receipt、S5 checkpoint、S6 simulation
- Workspace scope、command content/digest、notification、sync、collaboration、import
- 旧roadmapの低優先follow-up、既存terminal featureの設計変更

## 依存関係

- `TerminalNoteContextId`、separate Note/Trigger/Delivery/Context records、bounded canonical store
- On ReturnとAt Next Promptのstate machine、FIFO due delivery、prompt capability state
- Interactive AppKit child surface、unified window interaction owner、native editor/accessibility contract
- Application/window/pane/session generation、runtime worker、terminal core OSC 133 snapshot、native main-thread handle
- Typed configuration、safe reload、restoration、diagnostics/privacy、Developer JIT／Release AOT gateの既存precedent

## 完了条件

- D-43〜D-47を採用、延期、不採用で閉じ、D-48のspec freezeと次taskでのtask化手順を確定する。
- Owner table、message schema、queue/backpressure、teardown順、stale/revision rejectionを定義する。
- Config/capability transition、store/projection version matrix、rollback-safe behaviorを定義する。
- Slice別test pyramid、environment matrix、latency/memory/file/queue budgetを定義する。
- Rollout stage、exit/kill criteria、kill switch、data-preserving rollback runbookを定義する。
- S1〜S3間とGate 1〜6間に未解決の矛盾がなく、S4〜S6のfield/taskが混入していないことをreviewする。
- 親文書、提案、roadmapを更新し、次の未完了taskをimplementation subdivisionにする。
- Markdown/link/order/diff scopeを検証し、このtaskだけをcommitする。

## 検証方針

- Existing application/pane/session/native/config/restoration ownershipをsourceとtask recordで照合する。
- 全messageのproducer/consumer、bound、generation/revision、body exposure、failure fallbackをtableで検査する。
- Slice×environment×rollout matrixと、必須automated/manual evidenceを静的にcross-checkする。
- Gate 1〜6のadopted/deferred/rejected fieldをallowlistとdenylistで照合する。
- Changed Markdown link、whitespace、roadmap ordering、product-code差分なしを検査する。

## 調査記録

### 2026-09-20: 着手

- Gate 6はcommit `7a896d0`で完了し、着手時のworktreeはcleanだった。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、Gate 1〜6の仕様、repository構成を再確認し、
  Gate 7が最初の未完了taskであることを確認した。
- S5/S6は不採用のため、Gate 7へcheckpoint owner、command matcher/digest、bidirectional shell
  protocol、simulation、adapter version negotiationを含めない。S4も延期のためreceipt identityを含めない。

### 2026-09-20: existing owner／version boundaryの照合

- 主な照合先は
  [`terminal_application_state.dart`](../../lib/src/terminal_application_state.dart)、
  [`terminal_pane.dart`](../../lib/src/terminal_pane.dart)、
  [`terminal_window_event_coordinator.dart`](../../lib/src/terminal_window_event_coordinator.dart)、
  [`terminal_native_hierarchy.dart`](../../lib/src/terminal_native_hierarchy.dart)、
  [`terminal_config.dart`](../../lib/src/terminal_config.dart)、
  [`terminal_config_reload.dart`](../../lib/src/terminal_config_reload.dart)、
  [`terminal_restoration.dart`](../../lib/src/terminal_restoration.dart)、
  [`terminal_restoration_lifecycle.dart`](../../lib/src/terminal_restoration_lifecycle.dart)、
  [`terminal_shell_integration.dart`](../../lib/src/terminal_shell_integration.dart)である。
- `TerminalApplicationState`はwindow/tab/split/pane hierarchyのsole ownerで、mutationを一件ずつ直列化し、
  `PaneId`からwindow/tabへのreverse indexを持つ。Note modelをpane/session objectへ分散させず、同じ
  application rootから参照する独立authorityに置くのが既存境界と一致する。
- `TerminalPaneOwner`は一paneにつき一つの`TerminalSessionId(paneId, generation)`を作り、native hierarchyは
  adapterをviewより先にdisposeする。Note surfaceもpane native adapterとしてこのteardown順へ参加できる。
- Current Context Dockはwindowごとのinput ownerとgeneration-bound native focus confirmationを持つ。
  Gate 5で決めた共通ownerは、このprecedentを一般化し、DockとNoteが別々のowner booleanを持たない形で
  実装する必要がある。
- `TerminalWindowEventCoordinator`はhierarchy mutation中のraw inputをdropし、notificationだけをtypeごとに
  bounded coalesceする。Note lifecycleもinput replayを行わず、focus edgeとprompt eventを明示boundで保持する。
- Restoration codecはstrict version 1で、unknown field/versionを拒否する。Pane leafはcwdだけを持つ。直接
  version 2へ上げるとpre-Notes binary rollbackでlayout全体が読めなくなるため、restoration v1を維持し、
  Note store内のhash-bound sidecar metadataでcontextを対応付ける。
- Config reloadは現状`live`と`newSession`だけを区別する。Application-wide Note authorityを途中で半分だけ
  create/disposeしないため、Gate 7では`nextLaunch` policyを追加し、Note enablementを明示restart境界にする。
- Gate 6文書の「shell integration version bumpを予約しない」はcheckpoint-specificな双方向protocolを
  意図していたが、S3は既にone-way instance-correlated lifecycle versionを要求する。Gate 7ではこの表現を
  狭め、S3用version 3を明示する。

## Decisions

### Decision summary

| ID | 結果 | 決定 |
| --- | --- | --- |
| D-43 | 採用 | Application rootの`TerminalNoteAuthority`を唯一のlogical ownerとし、store worker、session observer、native surfaceをbounded generation/revision messageで従属させる。 |
| D-44 | 採用 | `notes`、`notes-on-return`、`notes-next-prompt`は`nextLaunch`、`notes-font-size`はlive設定とする。Initial codeはdefault-off、slice別local kill switchを持つ。 |
| D-45 | 採用 | Note store v1、restoration binding v1、native surface ABI v1、S3 shell integration v3を独立versionにする。Restoration本体はv1を維持し、exact-byte hash bindingで旧版rollbackを可能にする。 |
| D-46 | 採用 | Pure model／codec／fault／native UI／real PTY／Developer JIT・Release AOT／manual accessibilityを必須test pyramidとし、queue、latency、memory、file budgetをhard gateにする。 |
| D-47 | 採用 | Hidden test→internal opt-in→user opt-in→S1/S2 default-on→S3 opt-in→S3 default-onの順とし、local restart kill switchとdata-preserving rollbackを各stageに要求する。 |
| D-48 | 採用 | S1/S2 initialとS3 next incrementのspecificationを凍結する。S4は延期、S5/S6は不採用のまま、採用sliceだけをlinked implementation planのCM-01〜CM-19へ分割した。 |

## Ownership and concurrency

### Owner table

| Component | Owns | Must not own |
| --- | --- | --- |
| `TerminalNoteAuthority`（application root Dart isolate） | committed Note/Trigger/Delivery/Context snapshot、store revision、`PaneId -> TerminalNoteContextId` runtime binding、S2/S3 state、due FIFO、projection generation、mutation admission | PTY bytes、terminal grid、native view、volatile editor text、filesystem handle |
| `TerminalNoteStoreWorker`（application-wide long-lived Dart isolate） | lock、directory/file descriptor、strict codec、checksum、backup/journal、atomic filesystem operation | product transition、pane binding、UI success、diagnostics content。Commit完了後にcandidate objectをretainしない |
| `TerminalApplicationState` / restoration lifecycle | window/tab/split/pane topology、selection/focus、restoration v1 capture | Note record、body、trigger logic。Note authorityへcontent-free topology eventだけを渡す |
| `TerminalSession` / terminal core | PTY、OSC parse、semantic range、current session/integration generation | Note ID/body、delivery、rail。S3へbounded content-free lifecycle eventだけを出す |
| `TerminalWindowInteractionAuthority` | window内のexactly-one owner、native focus request/confirm、owner generation | Note/store mutation、terminal-visible DEC focus。Context Dockの既存ownerをこのauthorityへ移行する |
| `TerminalNoteSurfaceClient`（AppKit main thread、paneごと） | badge/rail/card view、layout、hit testing、volatile draft/selection/IME/Undo、accessibility object、surface/event generation | durable Note truth、trigger、attachment、filesystem、PTY write |
| Metal renderer / PTY backend | existing terminal rendering/input/process contract | Note body、card、note hit region。Note projectionのためにgrid/drawable/winsizeを変えない |

`TerminalNoteAuthority`は`TerminalApplicationState`へfieldを追加して同一classに埋め込まず、application
composition rootが両者を所有する。これによりNotes disabled／recovery-requiredでもterminal hierarchyを
通常どおり起動できる。Logical mutationはapplication root isolateでserialに決定し、native callback、window
notification、session eventがstore workerを直接呼ばない。

Store workerはcontent-bearing boundaryだが、log、uncaught error text、machine lineへsnapshot/body/path/IDを
出さない。Authorityはimmutable candidateをworkerへ一件だけ渡し、workerのdurable success後だけcurrent
snapshotとUI successをpublishする。Worker failure、timeout、generation mismatchではcandidateを破棄し、
committed snapshotを不変にする。

### Startup sequence

1. Typed configをresolveし、`notes=false`ならworker、store read、directory creation、native Note surfaceを
   一切開始しない。Terminalは既存pathで起動する。
2. `notes=true`ならstore workerを起動してexclusive lockを取得し、current/backup/journalをstrict loadする。
   Loadはterminal window作成をblockせず、完了までNotes actionは`Starting`とする。
3. Restoration v1のexact encoded bytesとlogical pane traversalをcaptureし、後述bindingが一致したpaneだけへ
   context IDを復元する。Legacy/mismatchはfresh IDを割り当て、store-only contextをDetachedへ移す。
4. Reconciliation candidateをdurable commitしてからsnapshotをpublishする。Failure時はNotesだけを
   unavailable/recovery-requiredにし、terminal paneとPTYは継続する。
5. Live paneごとにsurface generationを発行してnative child surfaceをattachする。Collapsed projectionから
   開始し、bodyはrailが明示またはdueで開くまでnativeへ送らない。
6. S3 enabled sessionだけにfresh `ShellIntegrationInstanceId`をlaunch時にbindし、matching version 3 markerを
   観測するまでcapabilityを`probing`とする。

Store loadが3秒以内に完了しない場合、UI rootはそのauthority generationを`unavailable(timeout)`として
terminal起動を続ける。遅いworker resultはstale generationとして破棄してstopし、同process内で暗黙retryしない。
利用者が明示的に`Retry Notes`を選ぶ場合だけ新generationで再開する。

### Transaction and ingress bounds

| Channel | Bound | Backpressure / stale behavior |
| --- | --- | --- |
| Durable mutation | 1 in flight、pending user intent最大32、pending body合計128 KiB | full時はfixed `Notes are busy`で新intentを無変更拒否。last-write-wins/implicit retryなし |
| Focus lifecycle | live context最大64件、それぞれ`awayObserved`と`returnObserved`を一つずつcoalesce | edge順を失わず一回のdue candidateへ畳む。close/detachがpending edgeをsupersede |
| S3 prompt lifecycle | sessionごと32 event、全live session最大64 | overflowしたsessionを`suspended(eventOverflow)`にし、deliveryを推測しない。別sessionへ影響なし |
| Native projection | paneごとlatest 1件、collapsedはcontent-free、expandedは最大64 card／256 KiB | old projectionをreplace。nativeはprotocol/surface/store generationがstaleならatomic reject |
| Native semantic intent | surfaceごと1 outstanding mutation。navigation/scroll/selectionはnative-local | Save/reorder/resolve中は対応controlをdisable。duplicate event sequenceは結果を再適用せずdrop |
| Presentation acknowledgement | `(surfaceGeneration, projectionGeneration, cardToken)`ごと1 | visible layout後だけ受理。duplicate/stale/occluded ackはdeliveryを変更しない |

すべてのauthority ingressへprocess-local単調増加`AuthoritySequence`を付ける。Pending intentは到着順に処理し、
structural detach/deleteだけが同じcontext/noteの後続trigger intentを明示的にsupersedeする。Priorityで古いdueを
追い越さない。Store commitが遅くてもterminal output、render、keyboard/PTY pathを待たせない。

### Teardown sequence

#### Pane / session

- Dirty Note editorがあるpane close/moveはGate 5のSave/Discardを先に完了する。確認前にpane mutationを
  開始しない。
- Pane close admission後はsurface generationをinvalidateし、新native intent/ackを拒否する。Runtime bindingを
  removeし、context detach candidateをcommitする。Commit失敗でもterminal closeを永久にblockせず、次startupの
  intersection ruleでDetachedにする。
- Native Note editor/surface adapter、terminal input adapter、Metal adapterの順にadapterをdisposeし、既存
  hierarchy contractどおり最後にviewをdisposeする。Surface dispose後のeventはstale rejectする。
- PTY/shell generationだけが変わる場合、contextとS1/S2は保持し、S3 runtime bindingをinvalidateしてtriggerを
  `suspended(sessionChanged)`へcommitする。別sessionへeventをtransferしない。

#### Application shutdown / reopen

1. New Note mutationをfreezeし、dirty editorの既存quit confirmationを完了する。
2. Window/input/focus/session event ingressをfreezeし、in-flight durable mutationを最大3秒drainする。
3. 同一hierarchy snapshotからrestoration v1 bytesとordered context listをcaptureする。
4. Restoration v1を先にcommitし、そのexact SHA-256 bindingを含むNote candidateを次にcommitする。片方だけ成功
   したcrash/failureでは次startupにhash mismatchとなり、自動reattachしない。
5. Note surface/interaction adapterをdisposeし、store workerへstop（最大1秒）を送りlockを解放する。
6. Existing native hierarchy、pane/session、worker teardownを従来順で実行する。

Quick Terminal hideはteardownではなくaway transitionで、singleton contextとsurfaceを保持する。App/Dock reopenで
新しいapplication hierarchy generationを作る場合、古いsurface/session generationを破棄し、restoration bindingを
再照合してからNote projectionを再開する。

## Versioned message schemas

### Native note surface ABI version 1

`NoteSurfaceProjectionV1`は次だけを含む。

- protocol version、runtime `PaneId`、surface generation、projection generation、committed store revision
- collapsed badgeの`activeCount`、`dueCount`、ready cue、feature/surface state
- rail visibility、Current/Detached section、paging range、selection、editor mode、appearance/accessibility flags
- 最大64件のephemeral `CardToken`、body／preview、color key、active/resolved、trigger/status chip、order
- fixed localized control/error key。自由なdebug/error text、persistent Note/Context IDは含めない

Expanded projectionは256 KiB以下、one bodyは4,096 UTF-8 bytes以下で、native decodeはunknown field/version、
duplicate token、limit超過をprojection全体rejectする。Applyはatomicで、reject時にlast known-good surfaceを保持する。
Collapsed projectionへbodyを含めない。Native snapshot／machine lineはprotocol/generation/count/stateだけを返し、
body、color、ID、timestampを返さない。

`NoteSurfaceIntentV1`はprotocol/surface/projection/event/draft generation、ephemeral token、fixed intent kind、
bounded payloadを持つ。BodyはSaveまたはexplicit clipboard actionだけ、colorはpalette keyだけを許す。
`NoteSurfaceResultV1`はaccepted/conflict/rejected/busy/unavailableとnew revision/generationだけを返し、errorへbodyを
echoしない。Persistent IDはapplication root内でCardTokenから解決し、nativeへ渡さない。

### Store worker protocol version 1

Requestは`load`、`commitCandidate`、`exportToApprovedPath`、`retryRecovery`、`stop`だけとし、authority generation、
request sequence、strict boundを持つ。`commitCandidate`はimmutable full snapshotを一件だけ送り、workerがcanonical
encode、checksum、lock/permission、backup/journal、atomic replaceを行う。Responseはdisposition、store revision、
bounded count/byte metrics、fixed failure classだけを返す。Load successだけはvalidated snapshotをauthorityへ返す。

Isolate間payloadは最大16 MiB canonical fileと8 MiB aggregate bodyの既存hard capに従い、一件だけin flightにする。
Existing `RuntimeWorkerFrame`の1 MiB protocolへ詰め込まず、Note専用のbounded isolate protocolを作る。

### S3 one-way shell lifecycle version 3

S3はbidirectional checkpoint protocolを導入しない。Current version 2 shell integrationを次のone-way version 3へ
拡張する。

```text
OSC 133 ; <action> [ ; <existing printable fields> ] ; dtr-note-v3=<32 lowercase hex> ST
```

- `<action>`はS3では`C`、`D`、`A`、`N`、`B`だけを入力にする。`D`のexit status等existing fieldはNote
  authorityへ渡さず、terminal compatibility処理だけが従来どおり扱う。
- 128-bit `ShellIntegrationInstanceId`をsession launch時にCSPRNGで生成し、adapter bootstrapがshell-localへ
  取り込んだ直後にenvironmentから削除する。Secretではないがchildへexportせず、diagnosticsへ出さない。
- Parserはtrailing fieldがexact grammar、configured adapter version 3、current session bindingと一致した場合だけ
  `PromptLifecycleEventV1(sessionGeneration, instance, semanticGeneration, eventSequence, action)`を出す。
- Missing、duplicate conflicting、malformed、wrong instance、wrong version fieldはS3 eventとしてrejectするが、
  validなstandard OSC 133 actionはexisting semantic rangeへ引き続き適用できる。
- Version 2/missing integrationはS1/S2へ影響せずS3 `unavailable`、session/instance changeとhigher unknown versionは
  armed S3を`suspended`にする。No-matchやsafeとは表示しない。

Markerはauthentication boundaryではなく、launchしたlocal root adapterとのcorrelationである。tmux/SSH/nested
shellへinstanceを継承せず、その内部markerでS3を発火しない。

## Configuration and capability

### Typed options

| Option | Type / default at first implementation | Application policy | Effect |
| --- | --- | --- | --- |
| `notes` | bool / `false` | `nextLaunch` | S1 surface/storeのmaster enable。falseならstore read/write/lock、native surface、context binding 0 |
| `notes-on-return` | bool / `true` | `nextLaunch` | `notes=true`時だけS2 create/arm/deliveryを許すlocal slice kill switch |
| `notes-next-prompt` | bool / `false` | `nextLaunch` | `notes=true`時だけS3 adapter v3 launchとUI optionを許す。S3 rolloutまでfalse |
| `notes-font-size` | finite double 12–24 / `15` | `live` | Note body/editorだけをreflowし、terminal font/grid/drawable/winsizeへ影響しない |

`TerminalConfigApplicationPolicy`へ`nextLaunch`を追加する。Reloadは値をlast-known-good configへacceptして
`pending restart`と表示するが、current `TerminalNoteAuthority`をcreate/disposeしたりlive sessionへv3 tokenを
注入したりしない。Theme/contrast/Reduce Motionは既存live OS/config projectionを使う。Invalid optionを含むreloadは
従来どおり全体rejectする。

Effective runtime flagsは次で固定する。

```text
surfaceEnabled    = notes
onReturnEnabled   = notes && notesOnReturn
nextPromptEnabled = notes && notesNextPrompt
```

Internal preview build、test CLI、release defaultはいずれも同じtyped resolutionを通り、hidden environment variableや
remote kill serviceを別authorityにしない。Emergency rollbackはlocal config default/explicit overrideとrestartで行う。

### Capability states

Application-level Notes stateは`disabled`、`starting`、`available`、`inUseByOtherProcess`、
`recoveryRequired`、`incompatibleStore`、`unavailable`を持つ。Disabled以外のfailureは本文を含まないfixed reasonと
Retry／Export Raw Files等の許可されたactionだけを示し、empty storeへ自動resetしない。

Pane surface stateは`attaching`、`ready`、`tooSmall`、`nativeUnavailable`、`disposed`。`tooSmall`と
`nativeUnavailable`はdelivery acknowledgementを返さない。S3 capabilityはGate 2/4の`probing`、`available`、
`suspended`、`unavailable`を維持し、global/pane stateと直積で判定する。S1/S2はshell stateに依存しない。

## Schema, restoration, and compatibility

### Note store version 1 restoration binding

Existing restoration JSONはversion 1のまま変更しない。Note store v1 payloadへ次のoptional objectを追加する。

```text
restorationBinding = null | {
  restorationFormat: 1,
  restorationSha256: <64 lowercase hex>,
  paneContextIds: [<TerminalNoteContextId> ...] // deterministic traversal, max 64
}
```

Traversalはwindow order→tab order→split tree first/second DFSで、existing restoration encode/captureと同じである。
Hashはdiskへcommitしたrestoration JSONのexact UTF-8 bytesへ計算する。Bindingはpane count一致、context ID unique、
全IDがknown contextである場合だけvalid。Cwd、title、index、pathをidentityとして保存しない。Quick Terminal singletonは
このlistへ含めない。

- Matching hash: ordered paneへcontextをbindし、store/restoration intersectionをcommitする。
- Bindingなし（pre-Notes/legacy）: 全paneへfresh ID、既存store contextは推測せずDetached。
- Hash/count/ID mismatch: binding全体を使わず全paneへfresh ID、store-onlyをDetached。部分位置合わせしない。
- Pre-Notes binary rollback: restoration v1を通常GUIで維持する版は同形式を読み書きし、Note storeを無視する。
- Rollback binaryがlayoutを変更した後の再upgrade: hash mismatchによりNoteはDetachedとなり、別paneへ誤接続しない。
  既存tag `0.1.0`の通常GUIはv1を維持しないため、rollback前にR1のtrust markerを無効化し、
  layout変化の有無によらず再upgradeをDetachedへ送る。旧binaryの手順外起動は現行binaryから検出できない。

このobjectもcanonical payload/checksumに含める。RestorationとNote storeは別transactionのままで、hash matchを
commit markerとして使う。SHA-256はcorruption/correlation用でauthentication claimを持たない。

### Compatibility matrix

| Consumer / artifact | Same version | Older / missing | Newer / unknown |
| --- | --- | --- | --- |
| App ↔ Note store v1 | strict read/write | no storeはempty。pre-Notes appはfileを無視する | current appはread/write/overwrite 0、`Upgrade required` |
| App ↔ restoration binding v1 | exact hashでattach | missing/mismatchはfresh+Detached | unknown binding/store versionはstore全体strict reject |
| Dart ↔ native Note ABI v1 | ready | missing capabilityはpane `nativeUnavailable`、terminal継続 | protocol mismatchはsurface reject、terminal継続 |
| App ↔ shell integration v3 | matching instance/versionでS3 | v2/none/unsupportedはS3 unavailable、S1/S2継続 | higher/mismatchはS3 suspended、standard OSC処理継続 |
| Config schema | known typed options | absentはstage default | unknown optionは既存diagnostic policyでreject/ignoreせず明示 |

Store v1以降のmigrationはGate 3のstrict pure transform、backup、no downgradeを維持する。Native ABIとshell
integration versionはstore versionから独立して上げ、partial migrationでpersistent recordへunknown fieldを残さない。

## Verification specification

### Required test pyramid

| Layer | 必須証拠 |
| --- | --- |
| Pure model | 全Gate 2/3 vector、create/edit/resolve/delete/reattach/reorder、focus/prompt FSM、queue/overflow、revision conflict、deterministic FIFO。Fixed-seed state sequence最低10,000件 |
| Codec/property/fuzz | Canonical round-trip、duplicate/unknown key、UTF-8/control/bidi、全limit±1、checksum、ID/revision/counter、restoration binding。Fixed-seed mutation最低10,000 case、任意byte input最低1 MiB |
| Store fault | lock/permission/symlink/hard-link、read/write/flush/fsync/rename/directory-fsync各step、backup/current/journal、timeout/worker crash、two-process contention。Partial publish/body log 0 |
| Native unit/UI | projection/intent decode、stale generation、layout/geometry、hit region、IME/paste/Undo、input family、focus/DEC report、mouse reporting、accessibility tree、light/dark/contrast/Reduce Motion |
| Real PTY / shell | zshとApple bashのv3 full cycle／mismatch/reset/restart、fish/nu resource fixtureとinstalled時conditional run、integration none、tmux/SSH/nested/TUIでS1/S2継続・S3 no false delivery |
| Product runtime | M1 Developer JITとRelease AOTでcreate/edit/persist/restore/detach/due/ack/close/reopen、64-pane bound、worker/native/session fault、complete teardown 0 leak |
| Aggregate/distribution | format、analyze、focused tests、`make test`、source/privacy/resource/bundle audit、`runtime-verify`、arm64/x86_64/Universal resource equality |
| Manual | VoiceOver、Japanese IME、keyboard-only、12/15/24 pt、light/dark/increase contrast/differentiate without color/Reduce Motion、Retina/non-Retina、small pane、Vim/Codex/mouse TUI checklist |

Body/ID/time/color/trigger history sentinelをdiagnostics、Unified Logging、crash metadata、machine line、restoration、
shell markerへ混ぜ、全export/auditで0件を要求する。Explicit Note exportだけはreviewed user-selected destinationへ
portable body/color/statusを出せる。

### Hard resource and latency budgets

| Resource / path | Budget |
| --- | --- |
| Disabled path | worker/store directory/native Note surface/timer 0。Existing key→PTY p95 <2 msを維持し、notes patch前baseline比+5%以下 |
| Enabled collapsed idle | polling/timer/continuous frame 0。64 pane empty stateのsettled RSS増分16 MiB以下 |
| Model/event transition | application root p95 1 ms以下、単発最大4 ms。Body encode/fsyncをrootで実行しない |
| Rail open/projection | 128-note contextでfirst visible p95 100 ms以下。Native apply p95 8 ms以下、main-thread stall 33.34 ms超0 |
| Durable commit | 1 MiB store p95 250 ms以下、16 MiB hard-cap store p95 1.5 s以下。UIは非同期Saving stateで応答しPTYをblockしない |
| Memory at hard-cap fixture | steady RSS増分64 MiB以下、commit中peak増分96 MiB以下、close後worker/native/card retained 0 |
| Queue / projection | pending mutation 32/128 KiB body、prompt 32/session、live pane 64、expanded projection 64 cards/256 KiB、materialized card 32 |
| Persistent data | Gate 3の2,048 Note、8 MiB body、16 MiB file、4,096 context、file/directory permissionを超えない |

Performance gateは固定M1/arm64 Release AOTをhard baselineにし、Developer JITはfunctional/leak evidenceに使う。
Disk latencyはisolated local APFS fixtureで20回以上測り、external/network volumeをsupport claimに含めない。Budget違反、
main-thread stall、unbounded retryはstage exit failure。単発測定揺れによる足止めを避けるため、ユーザー方針に従いstall判定閾値のみ旧16.67 msの2倍である33.34 msへ変更する。p95、owner、unbounded retryなど他の条件は緩めない。

### Environment acceptance matrix

| Environment | S1 | S2 | S3 | Required behavior |
| --- | --- | --- | --- | --- |
| local zsh/bash v3 | full | full | full after verified cycle | instance mismatch/out-of-orderでdelivery 0 |
| fish/nushell v3 | full | full | resource + conditional real-shell | shell未導入をbuild dependencyにしない |
| integration v2/none/unsupported shell | full | full | unavailable | Note本文/triggerを失わずpassive利用可能 |
| alternate screen / Vim / Codex / mouse TUI | full badge/manual rail | non-blocking due | eventなしならwaiting | geometry/input/mouse/DEC focus変化0 |
| tmux/SSH/mosh/nested shell | local pane Note | local focus | inner lifecycle unavailable | terminal textから推測せずouter verified rootへ戻ったcycleだけ候補 |
| Quick Terminal hide/show | full singleton context | hide→return | matching local root only | hideでdetachせず、app restartでもsingleton維持 |
| store corrupt/locked/newer | recovery UI only | inactive | inactive | terminal/PTY正常、automatic overwrite/reset 0 |
| pane too small/native surface failure | badge/fixed unavailable cue | due保持 | due保持 | presentation ack 0、rows/columns不変 |
| app restore/binary rollback/re-upgrade | hash matchだけattach | first eligible visit | fresh session suspended | mismatchはDetached、wrong-pane attach 0 |

## Rollout and rollback

### Stages

| Stage | Defaults / audience | Exit criteria |
| --- | --- | --- |
| R0 hidden test | 全release default off、temporary storeだけ、user UI entryなし | pure/codec/fault/native protocol、privacy audit、disabled-path zero-cost、all product gates pass |
| R1 internal S1/S2 opt-in | `notes=true`を明示したinternal build。S3 off | Developer JIT/AOT end-to-end、store/restore/64-pane/IME/TUI/manual checklist、hard invariant violation 0 |
| R2 user S1/S2 opt-in | documented local setting、default off、no telemetry | representative evaluator 5人以上でGate 1 comprehension基準、scripted focus各20回でfalse/lost/duplicate 0、actionable data issue 0 |
| R3 S1/S2 default-on | schema defaultを`notes=true`へ変更。S3 off | R2基準を独立release candidateでも再確認、startup/perf/privacy/distribution gate、rollback rehearsal pass |
| R4 S3 opt-in | `notes-next-prompt=true`を明示、v3 resource。S1/S2 default状態は維持 | supported/degraded/unavailable各20 sequenceでfalse/lost/duplicate 0、zsh/bash両runtime、tmux/SSH negative、resource audit pass |
| R5 S3 default-on | `notes-next-prompt=true` defaultを検討 | R4を独立release candidateで再確認し、unsupported説明を5/5 evaluatorが理解。未達ならopt-in維持 |

Stage promotionはcode mergeだけで自動発生せず、対応task memoにevidenceと明示decisionを記録する。Production
telemetry、background upload、remote flagは導入しない。Moderated結果は匿名countと設計上の観察だけを記録する。

### Kill and rollback rules

- Wrong-context attachment、store corruption/overwrite、body/privacy leak、unintended PTY byte、geometry changeの
  いずれか1件でNotes全体のdefault-on promotionを停止し、次patchの`notes=false`を選ぶ。
- S3 false/duplicate delivery、instance mismatch受理、shell regressionは`notes-next-prompt=false`だけをkillし、
  S1/S2を巻き戻さない。
- Native surface failure、IME/accessibility regressionはsurface stageを止め、storeを削除/resetしない。
- Performance/memory budget違反は該当stageを維持し、quotaや既存terminal performance gateを緩めない。
  ただし2026-09-22の利用者指示でidle CPU proxyに限り従来上限の2倍（合計1.0%以下）を許容する。
  これを超えたAOT測定やidle frame／ownership違反はpass扱いにしない。
- Soft rollbackはlocal configをoffにしてrestartする。Off pathはstoreをread/write/deleteせず、restoration v1と
  terminal behaviorを維持する。
- Binary rollbackはpre-Notes appがNote storeを無視し、Store fileを残す。通常GUIでrestoration v1を維持する版では
  再upgrade時にexact hash matchだけreattachし、layoutが変わればDetachedへ送る。既存tag `0.1.0`のように
  通常GUIがv1を維持しない版では、rollback前のtrust marker無効化を必須にし、再upgradeは常にDetachedとする。
- Newer/unknown storeをolder Notes appで開いた場合、read/write/downgrade/reset 0。Compatible appへ戻すまで
  feature unavailableとする。
- Corrupt store recovery、backup restore、raw export、logical deleteはGate 3手順だけを使い、release rollbackを
  data migration shortcutにしない。

Rollback rehearsalはR2以降の各candidateで、on→off restart、pre-Notes binary launch、re-upgrade hash match/mismatch、
S3 v3→v2 resource mismatch、native ABI missingを自動/手動fixtureとして実施する。

## Specification freeze

### Accepted release units

| Unit | Frozen contract | Not included |
| --- | --- | --- |
| S1 Basic memory | This Terminal context、plain-text colored card、explicit durable transaction、badge/rail/editor、Detached/reattach、resolve/delete/export | workspace、receipt、sync/import、Markdown、attachment |
| S2 On Return | explicit arm、eligible away→return、single non-blocking rail、durable due/at-least-once crash behavior | input hold、notification、urgency、timeout |
| S3 At Next Prompt | S1/S2 acceptance後、v3 matching instanceのpost-arm C→D→A/N→B、capability/degradation、non-blocking due | command body/status、screen scraping、remote inference、checkpoint |

Initial implementation specification versionsはNote store v1、restoration binding v1、native Note surface ABI v1。
S3 incrementだけshell integration resource/protocol v3を追加する。S1/S2 codeはv3を前提にしない。

### Freeze audit

- Gate 1: S1/S2 initial、S3 next increment、GUI-native sticky-note direction、no telemetryを維持。
- Gate 2/4: `This Terminal`、opaque durable context、detached lifecycle、On Return／At Next Prompt FSM、FIFOを維持。
- Gate 3: plain text、separate records、canonical atomic store、quota、privacy、export/delete、strict migrationを維持。
  Gate 7はrollbackのため`restorationBinding` objectだけをstore v1 payloadへ追加する。
- Gate 5: AppKit child overlay、explicit editor、unified input owner、geometry/focus/TUI/accessibility invariantを維持。
- Gate 6: S5/S6不採用。Checkpoint/Rule/digest/bidirectional reply/simulationのtype、field、UI、taskは0。
- Deferred: S4、workspace、import、app-level encryption、notification。Implementation中に必要と見つけても
  current taskへ混ぜず、roadmapの適切な後続位置へ新規decision taskとして追加する。

D-01〜D-47のcurrent release判断とD-48のfreeze／implementation task登録は閉じた。実装順と個別完了条件は
[`implementation plan`](contextual-terminal-memory-implementation-plan.md)を正本とする。`延期`は明示的に
scope外であり実装blockerではない。
Class/file分割等のmechanical detailはimplementation taskで調整できるが、scope、owner、message bound、version、
privacy、failure、acceptance、rolloutを変更する場合は本specを再度開いてdecision/roadmapを更新する。

## Review vectors

| ID | Scenario | Expected result |
| --- | --- | --- |
| O-01 | two windows mutate different Notes concurrently | one ordered durable queue、revision順publish、body cross-projection 0 |
| O-02 | Save中にsame editor duplicate event | one commit、duplicate result/drop、revision increment 1 |
| O-03 | pane close中のlate native ack | stale surface reject、delivery stateを誤消費しない |
| O-04 | shell restart中のqueued prompt events | old instance全部reject、S3 suspended、S1/S2保持 |
| O-05 | prompt ring 33 events before drain | session suspended(eventOverflow)、false delivery 0、other session正常 |
| B-01 | restoration and binding both current | exact ordered contexts attach |
| B-02 | restorationだけnew／binding old | hash mismatch、全old Note Detached、wrong attach 0 |
| B-03 | bindingだけnew／restoration old | hash mismatch、全old Note Detached、wrong attach 0 |
| B-04 | pre-Notes binary launch then no layout change | v1 layout正常、store不変、re-upgradeでhash一致ならattach |
| B-05 | pre-Notes binaryでlayout change後re-upgrade | hash mismatch、fresh contexts、old Note Detached |
| C-01 | notes=false startup | file access/worker/surface/timer 0、terminal baseline同一 |
| C-02 | nextLaunch option reload | current authority不変、pending restart表示、restart後だけ反映 |
| C-03 | live Note font 12→24 | card/editor reflow、grid/drawable/winsize/SIGWINCH不変 |
| P-01 | v3 matching C D A B | Bでdue一回 |
| P-02 | v2/missing/wrong instance/higher version | S3 delivery 0、unavailable/suspended、standard semantic継続 |
| P-03 | tmux/SSH outputがinstance-like markerを出す | inherited bindingなしでS3 delivery 0 |
| R-01 | store worker crash mid-commit | current/backup known-good、published snapshot不変、terminal継続 |
| R-02 | native projection decode failure | last good UIまたはpane unavailable、store/PTY不変 |
| R-03 | soft kill S3 only | armed trigger suspended、S1/S2/store保持 |
| R-04 | full soft rollback | Notes off、store untouched、restoration/terminal正常 |
| V-01 | diagnostics/crash/machine line sentinel | body/ID/time/color/trigger/instance 0、fixed count/stateだけ |
| V-02 | max store/64 pane/32 cards + close | budget内、all Note/native/worker handle回収 |

## 検証記録

2026-09-20 に次を実行した。

- Existing application、pane/session、window event、native hierarchy、config、restoration、OSC semantic
  ownershipをsourceと既存task recordで照合し、owner table、startup/teardown、message boundへ反映した。
- D-43〜D-48のdecision row 6件、typed option 4件、rollout stage 6件、review vector 22件を静的に
  数え、すべてが本文に存在することを確認した。
- Accepted release unitを該当section内に限定して抽出し、S1、S2、S3の3件だけで、S4〜S6がないことを
  確認した。最初の抽出は文書全体の`S1`〜`S3` table rowを数えたため、transaction boundsの
  `S3 prompt lifecycle`も拾って4件と誤判定した。Heading境界で対象sectionを限定して再検査しpassした。
- Changed/new Markdown 9件のrelative link 85件を検査し、missing target 0件を確認した。
- `git diff --check`: pass。新規Gate 7文書も別途trailing whitespaceを検索し0件だった。
- Roadmap orderingは完了7件、未完了1件で、最初の未完了がimplementation subdivisionであることを
  確認した。差分は`ROADMAP.md`と`docs/proposals/`のMarkdownだけで、product/test/native code、build、
  shell resource、store/restoration file、generated artifactを変更していない。
- このtaskは設計文書だけを変更したため、Dart/native unit test、real PTY、AppKit UI、performance、
  distribution buildは未実施である。Frozen test pyramid、budget、22 vectorをimplementation taskへ引き継ぐ。
