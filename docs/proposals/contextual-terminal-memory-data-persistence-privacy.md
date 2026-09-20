# Contextual terminal memory data, persistence, and privacy

- 状態: Gate 3 完了（採用sliceはimplementation planへ登録済み）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- Scope/trigger仕様: [`contextual-terminal-memory-scope-trigger-semantics.md`](contextual-terminal-memory-scope-trigger-semantics.md)
- Checkpoint採否: [`contextual-terminal-memory-checkpoint-feasibility.md`](contextual-terminal-memory-checkpoint-feasibility.md)
- Architecture/rollout仕様: [`contextual-terminal-memory-architecture-verification-rollout.md`](contextual-terminal-memory-architecture-verification-rollout.md)
- 実装計画: [`contextual-terminal-memory-implementation-plan.md`](contextual-terminal-memory-implementation-plan.md)

## 目的

採用したS1〜S3について、Note、trigger、delivery、attachmentのdata invariant、本文format、
lifecycle、永続store、quota、privacy、export/delete、schema migrationを確定する。延期中の
S4とGate 6で不採用になったS5/S6のcommand data、digest、rule、receiptをschemaへ導入しない。

## 背景

Noteはuser-authored contentであり、既存restorationやdiagnosticsより機微なdataを持つ。
現行restoration storeはcwd/layoutだけをbounded JSONへ保存し、same-directory pending renameを
行うが、Note storeに必要なpermission、backup、corruption recovery、transaction、lock、
retentionは持たない。既存diagnosticsはterminal text、command、cwd、stable ID、timestampを
defaultで除外しているため、Note本文やcontext identityを暗黙に追加してはならない。

## 対象範囲

- D-12〜D-20
- S1〜S3のentity分離、field invariant、plain-text policy、state transition
- local store path、canonical format、atomic commit、backup/recovery、single writer
- bounded quota、capacity failure、detached Note retention
- export/delete、diagnostics/logging/analytics exclusion、migration/rollback

## 対象外

- S4 receipt、S5 rule/digest/raw command、S6 simulation data
- encrypted command storage、Keychain、team sync、cloud sync、shared templates
- card layout、editor control、native overlay、accessibility implementation
- production code、test code、existing restoration/schemaの変更

## 依存関係

- `TerminalNoteContextId`、detached lifecycle、S2/S3 trigger state machine
- `FileTerminalRestorationStore`、settings atomic writer、diagnostics privacy reference
- macOS Application Support directoryとsingle-application process model
- Gate 5のeditor/visual projection、Gate 7のownership/rollout/migration verification

## 完了条件

- D-12〜D-20を採用、延期、不採用で閉じる。
- field table、valid combination、state transition、canonical serializationを定義する。
- size/count/storage boundsとcapacity failureを定義する。
- crash/corruption/locking/restoration reconciliation/migration/rollbackを定義する。
- privacy data-flow matrix、export/import/delete、diagnostics/log boundaryを定義する。
- 親文書、提案、roadmapを更新し、次の未完了taskをGate 5にする。
- Markdown/link/order/diff scopeを検証し、このtaskだけをcommitする。

## 検証方針

- D-12〜D-20の9 decision rowと全schema fieldを静的に照合する。
- valid/invalid entity例、state transition、crash recovery、quota、migration test vectorを列挙する。
- privacy matrixで本文、ID、時刻、色、trigger eventがimplicit outputへ流れないことを確認する。
- changed Markdown link、whitespace、roadmap ordering、diff scopeを検査する。

## 調査記録

### 2026-09-20: 着手

- Gate 2/4はcommit `38fbd40`で完了し、worktreeはcleanだった。
- `ROADMAP.md`を再確認し、Gate 3が最初の未完了taskであることを確認した。
- 現行restoration storeは最大512 KiB、UTF-8 strict decode、`path.pending`へのflushとrenameを
  行うが、backup、checksum、file permission、multi-process lockはNote用途のcontractにない。
- Settings writerはexclusive sibling temp、flush、既存permission維持、symlink/non-regular拒否の
  precedentを持つ。Note storeでは新規fileの0600、directory 0700、backup/recoveryも必要になる。
- 一般diagnosticsはterminal text、command、path、stable pane/session ID、timestampを除外する。
  Note本文、Note/context ID、created/updated時刻、trigger historyも同じdefault-exclude境界に置く。

## Decisions

### Decision summary

| ID | 結果 | 決定 |
| --- | --- | --- |
| D-12 | 採用 | `NoteRecord`、`NoteTriggerRecord`、`NoteDeliveryRecord`、`NoteContextRecord`を分離し、巨大なoptional-field objectにしない。 |
| D-13 | 採用 | Initial bodyはbounded Unicode plain text。Markdown、link、command actionを解釈しない。 |
| D-14 | 採用 | Note lifecycleはactive/resolved、trigger/delivery lifecycleは別state machine。draft/snooze/expire/disabledはinitial schemaに入れない。 |
| D-15 | 採用 | Versioned canonical JSON snapshot、single writer、checksum、atomic same-directory replace、known-good backup、deletion journalを使う。 |
| D-16 | 採用 | count/body/fileにhard capを設け、user Noteを自動evictしない。capacity超過はmutationを無変更で拒否する。 |
| D-17 | 延期 | Note store自体のapp-level encryptionはinitial releaseでは提供せず将来判断とする。S5 command digest/raw command/key storageはGate 6の不採用によりschemaへ入れない。 |
| D-18 | 不採用 | Gate 6でS5を不採用としたためExact-command bytes/label fieldとUIを定義せず、互換予約も残さない。 |
| D-19 | 採用 | 明示exportとlogical deleteを採用し、importはinitial releaseで延期する。 |
| D-20 | 採用 | Note content/identity/time/color/trigger historyをdiagnostics、log、analytics、crash metadataからdefault-excludeする。 |

## Entity model

### `NoteRecord`

| Field | Type / bound | Invariant |
| --- | --- | --- |
| `id` | opaque random 128-bit `NoteId` | CSPRNGで生成し再利用しない。path/time/pane indexをencodeしない。 |
| `attachment` | `attached(contextId)` or `detached(previousContextId, reason)` | exactly one variant。cwd/path一致で自動reattachしない。 |
| `body` | `NoteBody` | 後述plain-text policyを満たし、空白だけではない。 |
| `color` | versioned `NoteColorKey` enum | theme-aware palette key。raw ARGBやseverityではない。 |
| `status` | `active` or `resolved` | deletedはstatusではなくrecord removal。 |
| `order` | non-negative integer | 同じattached/detached collection内で一意。transaction内で0始まりへ正規化可能。 |
| `createdAtUtcMicros` | finite non-negative 64-bit integer | 表示用。ordering/expiry/authorityに使わない。 |
| `updatedAtUtcMicros` | finite non-negative 64-bit integer | `createdAt`以上。wall-clock rollback時もrevisionを優先する。 |
| `revision` | positive 64-bit integer | Note mutationごとに増加。optimistic editor conflict検出に使う。 |

Initial `NoteColorKey`は`neutral`、`yellow`、`blue`、`green`、`pink`、`purple`の6値とする。
具体的なlight/dark/high-contrast color tokenはGate 5で決める。未知のcolor keyはfallback表示せず
strict decodeでmigration対象にする。色だけでstatusやdueを表さない。

`title`、`urgency`、`tags`、`workspace`、`provenance`、`expiresAt`、`rawCommand`、`digest`、
`receiptId`はinitial `NoteRecord`に存在しない。将来必要になったときschema versionを上げる。

### `NoteTriggerRecord`

一つのNoteは最大一つのtriggerを持つ。passive Noteはtrigger recordを持たない。

| Field | Type / bound | Invariant |
| --- | --- | --- |
| `noteId` | existing `NoteId` | activeかつattached Noteだけを参照する。 |
| `generation` | positive 64-bit integer | 同じNoteをre-armするたび増加し、stale eventを拒否する。 |
| `kind` | `onReturn` or `atNextPrompt` | S1〜S3以外のkindをversion 1に入れない。 |
| `phase` | kind-specific enum | scope/trigger仕様のstate machineに一致する。 |
| `suspendReason` | bounded enum or null | `suspended`以外ではnull。raw error/textを持たない。 |
| `armedAtRevision` | store revision | wall clockではなくtransaction orderを示す。 |

Live `TerminalSessionId`、`ShellIntegrationInstanceId`、semantic generationは
`TriggerRuntimeBinding`としてmemory内だけに保持する。storeへ書かない。load時にwaiting中の
`atNextPrompt` triggerは必ず`suspended(sessionEnded)`へ変換する。既に`due`になったdeliveryは
runtime bindingを必要とせず保持する。

### `NoteDeliveryRecord`

| Field | Type / bound | Invariant |
| --- | --- | --- |
| `noteId` | existing `NoteId` | activeかつattached Noteを参照する。 |
| `triggerGeneration` | matching trigger generation | stale generationのdeliveryを拒否する。 |
| `sequence` | positive 64-bit `DeliverySequence` | store全体で単調増加し、FIFO orderを決める。 |
| `state` | `due` only | presented acknowledgementと同じtransactionでrecordを削除し、triggerをpassiveへ戻す。historyは残さない。 |

`presented`を長期保存しない。presentation transactionがcommitするまでは`due`を残すため、crash後に
一度再提示される可能性は許容するが、未提示のNoteを失わない。exactly-onceは一つのhealthy
process lifetime内で保証し、crash境界はat-least-once presentationと明記する。

### `NoteContextRecord`

| Field | Type / bound | Invariant |
| --- | --- | --- |
| `id` | `TerminalNoteContextId` | scope/identity仕様に従う。 |
| `kind` | `standard` or `quickTerminal` | unknown kindはreject。 |
| `state` | `active`、`restorable`、`detached` | live mappingとrestoration reconciliationでのみ遷移する。 |
| `revision` | positive 64-bit integer | context lifecycle mutation order。 |

Context recordはcwd、title、window/tab index、hostname、process identityを持たない。Quick Terminalの
singleton context IDもこのtableに保存する。

### Cross-record invariants

- `NoteId`、`TerminalNoteContextId`、active `(noteId, trigger generation)`、delivery sequenceは各domainで
  uniqueである。
- resolved/detached Noteはtriggerとdeliveryを持たない。
- deliveryはmatching triggerが`due` phaseのときだけ存在する。
- `restorationBinding`のcontext IDはuniqueなknown standard contextだけで、最大64件。Quick Terminal contextは
  含めない。
- Note deleteはNote、trigger、delivery、collection orderを一transactionで更新する。
- context detachは関連trigger/deliveryを解除し、Note attachmentをdetachedへ一transactionで変える。
- dangling reference、duplicate order、unknown enum/field、non-canonical ID、counter rollbackをdecode時に
  record単位でsalvageせずstore全体rejectにする。

## Note body policy

Initial Noteはplain textだけを保存・描画する。

- UTF-8 encoded sizeは1〜4,096 bytes、logical lineは最大64行。
- CRLF/CRはeditor admission時にLFへnormalizeする。それ以外のUnicode normalizationは行わず、
  valid Unicode scalar sequenceをcopy/exportまでround-tripする。
- 少なくとも一つのnon-whitespace scalarを必要とする。leading/trailing whitespace自体は保持する。
- LFとTABを許可する。NUL、その他のC0/C1 control、DEL、unpaired surrogateを拒否する。
- bidi embedding/override/isolate controls（U+202A〜U+202E、U+2066〜U+2069）とLRM/RLMを拒否する。
  Arabic/Hebrew等の通常textは許可し、paragraph isolationはrenderer側で行う。
- emoji ZWJ、variation selector、combining markは許可する。
- TABの表示幅はGate 5で固定するが、copy/exportではTABを保持する。
- Markdown、HTML、ANSI/OSC、URL autolink、mention、image、attachment、command interpolationを
  解釈しない。文字列`rm -rf`やURLも単なるtextである。
- oversized/invalid pasteはsilent truncateせず、mutation全体を拒否してlocal errorを表示する。

この範囲は付箋として十分な短文と複数行checklistを許しつつ、renderer/parserをNote本文へ
持ち込まない。rich textの必要性はproduct validation後に別schemaとして再評価する。

## State and mutation semantics

### Note lifecycle

```text
create -> active
active -> resolved
resolved -> active       (explicit reopen)
active/resolved -> deleted (explicit delete; terminal state)
attached -> detached     (scope loss; statusは維持)
detached -> attached     (explicit user reattach only)
```

Draftはeditor ownerのvolatile stateでありstoreへ書かない。Initial releaseはdraft recovery、autosave、
snooze、expiry、disabled、undo historyを永続化しない。Gate 5でSave/Cancel UXを決める。

Resolveはtrigger/deliveryを同じtransactionで削除する。Reopenしても過去triggerを復元せずpassiveに
戻す。Deleteは確認後にlogical deletion transactionを完了し、undoを提供しない。wall clockは
state transitionを起こさない。

### Mutation transaction

すべてのmutationはimmutable snapshotに対するcopy-on-write transactionとして実行する。

1. current store revisionと対象Note revisionを検証する。
2. candidate snapshotへmutationとcascadeを適用する。
3. cross-record invariant、quota、canonical encodeを検証する。
4. candidateをdurable commitする。
5. commit成功後だけin-memory published snapshotとUI successを更新する。

失敗時はcurrent snapshotを変更しない。Editor Saveはdurable commit前に成功表示やcloseをしない。
Trigger eventは`due`とdelivery sequenceをcommitしてからpresenterへ通知する。Presentation ackは
delivery削除をcommitできなければcardを閉じても次回起動で再提示し得る。

## Store contract

### Location and permissions

Store directoryは次の固定product locationとし、initial releaseで任意path設定を設けない。

- `XDG_STATE_HOME`がabsolute safe pathとして設定済みなら
  `$XDG_STATE_HOME/dart-terminal/notes/`
- それ以外は `~/Library/Application Support/Dart Terminal/Notes/`

製品が作る`notes`/`Notes` directoryは0700、`store.json`、`store.backup.json`、
`deletions.json`、`store.lock`は0600とする。target fileは`lstat`でregular fileまたはnot-foundだけを
受理し、symlink、hard-link count >1、directory/device/socketを拒否する。temporary fileは同一directoryへ
exclusive createし、0600を設定してからcontentを書く。既存permissionが広い場合はread/write前に
0600へ狭め、失敗時はfeatureをunavailableにしてcontentを読まない。

Storeはapp-level encryptionを提供しない。macOS account/file-system encryptionやbackup policyの
範囲を越える保護を主張せず、初回作成UIで「local fileに保存され、Dart Terminal独自の暗号化は
されない」と説明する。Noteへsecretを書かないよう案内する。

### Canonical format

`store.json`はUTF-8 JSON、一つのtrailing LF、最大16 MiBとする。Envelopeは次を持つ。

```text
format = "dart-terminal-notes"
version = 1
payloadSha256 = lowercase 64-hex SHA-256
payload = {
  storeRevision,
  nextDeliverySequence,
  contexts[],
  notes[],
  triggers[],
  deliveries[],
  restorationBinding
}
```

Gate 7で、pre-Notes binary rollbackのためexisting restoration format version 1を変更せず、payloadへ
`restorationBinding`を追加した。値はnull、またはrestoration format 1、diskへcommitしたrestoration JSONの
exact UTF-8 bytesに対するlowercase SHA-256、deterministic pane traversal順の最大64 context IDを持つobjectである。
Bindingはcontext IDがunique/knownでpane countと一致する場合だけvalidとし、cwd、title、path、pane indexを
identityとして保存しない。Exact contractとrollback matrixは
[`architecture/rollout仕様`](contextual-terminal-memory-architecture-verification-rollout.md)を正本とする。

Field order、array order、integer/string encodingをcanonical codecで固定し、checksumはcanonical
payload UTF-8 bytesへ計算する。SHA-256はaccidental corruption検出であり、改ざん防止や署名ではない。
Unknown root/payload/entity field、duplicate key、unknown version、checksum mismatch、trailing data、
limit超過をstrict rejectする。一般JSON decoderがduplicate keyを上書きする前にduplicate検出できる
codecを使う。

### Single writer and atomic commit

- UI application ownerだけがmutable snapshotとserial transaction queueを所有する。
- 複数windowはownerへmessageを送り、fileを直接read/writeしない。
- `store.lock`へOS advisory exclusive lockを取得できないsecond processはread-onlyにもfallbackせず、
  Notes featureを`in use by another process`としてunavailableにする。stale lock fileの存在だけで拒否せず、
  kernel lock ownershipを判定する。
- candidateをexclusive sibling tempへwrite、flush/fsync後、current known-goodをbackupへrenameし、tempを
  currentへrenameしてdirectoryをfsyncする。どのrename失敗でも既知のcurrent/backupを破壊しない
  recovery sequenceを実装する。
- 一度にwriteは1件だけ。mutationは順序付きで、last-write-wins mergeを行わない。

### Recovery

Startupはcurrent、backupの順にsize、permission、type、strict schema、checksum、invariantを検証する。

- current validなら使用し、より古いbackupを自動mergeしない。
- current missing/invalidでbackup validなら、deletion journalを適用したread-only recovery previewを
  表示する。利用者が`Restore Backup`を明示するまでcurrentへ書き戻さない。
- 両方invalidならfileを上書き/resetせずNotesをrecovery-requiredにする。`Export Raw Files`は
  warning付き明示操作だけで提供し、一般diagnosticsへ含めない。
- orphan tempはcontentをdecodeせずowned naming pattern、regular file、directory ownershipを確認して
  best-effort削除する。
- record単位のbest-effort salvageは行わない。誤ったattachmentや本文混同より全体rejectを選ぶ。

### Restoration reconciliation

Restoration v1 exact-byte hashとNote storeの`restorationBinding`を照合し、matching binding内のcontext IDを
restoration leafのdeterministic traversalへ対応させた後、context ID集合を比較する。

- 両方にあるIDだけをlive paneへattachする。
- bindingなし、hash/count/ID mismatch、legacy restorationでは全restored paneへfresh IDを発行する。
- Note storeだけにあるactive/restorable IDはdetachedへ移し、cwd/title/orderで推測reattachしない。
- legacy restorationにIDがないpaneは新しいcontext IDを発行する。既存Noteを推測移行しない。
- Quick Terminalはstore内singleton contextを再利用する。

Reconciliation結果はNote storeの一transactionとしてcommitしてからUIへ公開する。二file間のatomic
commitは要求せず、intersection-only ruleによりcrashで別paneへNoteが誤接続されないことを優先する。

## Quotas and capacity failure

| Resource | Hard limit |
| --- | --- |
| total Note records | 2,048 |
| Note records per attached context | 128 |
| context records | 4,096 |
| trigger records | 2,048、かつNoteごと1 |
| delivery records | 2,048、かつtriggerごと1 |
| one body | 4,096 UTF-8 bytes / 64 lines |
| aggregate body bytes | 8 MiB |
| canonical store file | 16 MiB |
| deletion journal pending IDs | 8,192 |
| ID/revision/sequence counter | unsigned 64-bit positive range |

active、resolved、detachedはすべてquotaに数える。memory pressure、age、resolved状態、context closeで
user Noteを自動evictしない。上限到達時は新規作成またはサイズ増加mutationを無変更で拒否し、
`Delete notes to free space`と現在値/上限だけを表示する。本文やpathをerror/logへ含めない。
Resolveは容量を解放せず、Deleteだけが解放する。counter exhaustionはfeatureをread-onlyにし、wrapや
ID再利用を行わない。

## Delete, export, and import

### Logical delete

APFS snapshot、Time Machine、SSD behaviorによりsecure physical eraseは保証しない。製品が保証するのは、
成功応答後にcurrent/backup/recovery pathからNoteを再表示しないlogical deletionである。

1. contentを含まない`NoteId` tombstoneを`deletions.json`へdurable commitする。
2. Note、trigger、delivery、orderをcandidate storeから除去してcurrentをcommitする。
3. backupもdeleted Noteを含まないrevisionへreplaceする。
4. current/backup双方のrevisionがtombstone以後と検証できた後だけjournal entryをcompactする。

Crashがどのstepで起きてもloaderはjournal tombstoneをcurrent/backupへ先に適用し、deleted recordを
UI/exportへ戻さない。journal limit到達時は新しいdeleteを成功扱いせずrecoveryを要求する。
利用者向け文言はsystem backup/snapshotにcopyが残り得ることを明示する。

### Explicit export

`Export Notes…`はsave panelとsensitive-content warningの後だけ実行する。Version 1 portable exportは
body、color、resolved status、manual orderを含み、internal Note/context ID、timestamps、revision、
detached reason、runtime binding、trigger phase、delivery historyを含めない。Triggerはportableな
intentとして`passive`、`onReturn`、`atNextPrompt`だけを含められるが、export先ではactive ruleとして
扱わない。

Exportはuser-selected destinationのexclusive sibling tempへwrite/flush/atomic renameし、destination
pathやcontentをstatus/logへ保持しない。Copyは選択Noteのbodyだけを明示操作でpasteboardへ置く。

### Import

Importはinitial releaseで延期する。将来導入する場合、untrusted bounded decode後に新しいNoteIdを
割り当て、すべてdetached/passiveでpreviewし、利用者がcontextとtriggerを明示選択するまでactivate
しない。Export formatが存在することはimport互換性の約束ではない。

## Privacy and observability boundary

| Sink / surface | Content | IDs / timestamps / color | Trigger/delivery event |
| --- | --- | --- | --- |
| Note card/editor/rail | 利用者が開いたcontextで表示 | UIに必要なcolor/statusだけ | due/suspended reasonを固定文言で表示 |
| VoiceOver/accessibility | visible/focused cardのbodyをapplication controlとして公開 | stable internal ID/timeは非公開 | fixed role/stateを公開 |
| local Note store | 保存 | 保存。restoration exact-byte SHA-256 bindingもlocal-only | current stateだけ保存、historyなし |
| terminal grid/PTY/scrollback/search/copy | 送らない | 送らない | 送らない |
| shell integration environment/event | 送らない | Note/context IDは送らない | non-secret integration instanceだけ。Note identityなし |
| restoration file | bodyなし | Note/context IDなし。existing cwd/layout format v1を維持 | なし |
| general diagnostics/inspector/export | bodyなし | ID/time/color/restoration binding hashなし | fixed availabilityとbounded countsだけ許可 |
| unified log/stderr/machine line/crash metadata | なし | なし | fixed error class/countだけ許可 |
| analytics/telemetry/network/cloud/indexer | なし | なし | なし |
| explicit `Export Notes…` | warning後に含む | portable fieldだけ | passive intentだけ |
| pasteboard | explicit Copy時にbodyだけ | なし | なし |

General diagnosticsに追加可能なのは`notes_feature_state`、bounded total/active/due/detached counts、
store format version、最後のoperationの固定dispositionだけである。Note/context ID、本文hash、長さ分布、
color、timestamp、trigger kind別usageも追加しない。Product validationもproduction telemetryを使わない。

Accessibility exposureは利用者がvisibleにしたcardに限定し、collapsed badgeからbodyを読み上げない。
App switcher、window title、notification、Dock badgeへbodyを投影しない。Note fileをSpotlight/Quick Lookへ
登録せず、background upload/syncを行わない。

## Schema migration and rollback

- Version 1 decoderはstrictであり、unknown newer versionをread-only `upgrade required`として拒否し、
  overwrite/downgradeしない。
- Upgrade migrationはbounded pure transformとしてold snapshotを完全validateしてからcandidate new
  snapshotを作り、quota/invariant/checksumを検証する。
- Migration前currentをknown-good backupとして保持し、新version commit成功後も最初のhealthy launchが
  完了するまで削除しない。削除journalはversionを跨いで先に適用する。
- Migration失敗時はold fileを変更せず、feature unavailableとfixed error classだけを表示する。
- Older appがnewer storeを開いた場合はread/writeせず、userにnewer appを使うよう表示する。
- Rollback対応を約束するversionでは、writerがold-version互換exportを別途生成できる場合だけ明示する。
  unknown fieldのdropや自動downgradeは行わない。
- Initial specificationはrestoration formatをversion 1のまま維持し、Note store内bindingとの別transactionを
  exact hashとcontext ID集合のintersection ruleでreconcileする。将来restoration formatを上げる場合もNote
  store migrationとは別transactionとし、同じfail-closed ruleを維持する。

## Verification vectors

| ID | Scenario | Expected result |
| --- | --- | --- |
| M1 | active Noteをresolve | trigger/delivery削除、Noteはresolvedで保持 |
| M2 | resolved Noteをreopen | active/passiveへ戻り、古いtriggerは復元しない |
| M3 | attached contextをclose |全Note detached、trigger/delivery 0、本文保持 |
| M4 | stale editor revisionでSave | conflict、store/in-memory snapshot無変更 |
| B1 | 4,096-byte/64-line body | accept |
| B2 | 4,097-byte、65-line、NUL、bidi override | transaction全体reject、silent truncate 0 |
| Q1 | total 2,048件から新規create | capacity reject、既存Note不変、eviction 0 |
| Q2 | resolved/detachedだけでcap到達 | create reject。resolveではcapacityを解放しない |
| F1 | temp write/flush/renameの各fault | currentまたはbackup known-good、partial publish 0 |
| F2 | current checksum failure、backup valid | explicit recovery preview、automatic overwrite 0 |
| F3 | current/backup両方invalid | recovery-required、empty reset 0 |
| D1 | deleteの各stepでcrash | tombstone適用によりcurrent/backupからNote再表示 0 |
| R1 | exact restoration hashとordered bindingが一致 | binding内のknown contextだけattach、store-onlyはdetached |
| R2 | legacy restoration v1 | fresh context ID、既存Noteのpath推測reattach 0 |
| P1 | general diagnostics/export/log生成 | body/ID/time/color/trigger history sentinel 0、bounded countsのみ |
| E1 | explicit export cancel | file write/content read 0 |
| E2 | explicit export success | portable fieldsのみ、internal ID/runtime/delivery 0 |
| V1 | newer unknown store version | read/write 0、upgrade-required、file不変 |

実装時はcanonical codec round-trip、duplicate key、unknown key、all limit boundaries、fixed-seed mutation、
permission/symlink/hard-link、lock contention、deletion crash matrixをautomated testへ変換する。

## 検証記録

2026-09-20 に次を実行した。

- D-12〜D-20のdecision rowを静的に数え、9件すべてが`採用`、`延期`、`不採用`のいずれかで
  閉じていることを確認した。Gate 6後の現在値は採用7件、延期1件、不採用1件である。
- `NoteRecord`、`NoteTriggerRecord`、`NoteDeliveryRecord`、`NoteContextRecord`のfield tableと
  cross-record invariantを読み合わせ、延期したcommand/receipt fieldがinitial schemaへ混入して
  いないことを確認した。
- model/body/quota/fault/delete/restoration/privacy/export/versionを覆うverification vectorを静的に数え、
  18件あることを確認した。
- changed/new Markdown 4件のrelative link target検査: pass。trailing whitespace: 0件。
- `ROADMAP.md`の先頭4項目が完了し、最初の未完了項目がGate 5であることを確認した。
- `git diff --check`: pass。差分はroadmapとproposal/design文書だけで、製品code、build file、
  dependency、generated artifactを変更していない。
- このtaskは設計文書だけを変更したため、Dart unit test、native build、runtime storage fault testは
  未実施である。18件のverification vectorを実装taskのautomated acceptanceへ引き継ぐ。
