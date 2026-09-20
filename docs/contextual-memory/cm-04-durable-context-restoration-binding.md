# CM-04 durable context identity and restoration binding

## 目的

既存restoration JSON version 1のbyte表現を変えず、standard paneのlogical traversalとopaqueな
`TerminalNoteContextId`をNote store側のexact-byte SHA-256 bindingで安全に対応付ける。Bindingが完全一致する場合だけ
保存contextを復元し、欠落、不一致、rollback中のlayout変更ではfresh contextとDetached Noteへfail closedする。

## 背景

- CM-01はNote専用の128-bit context ID、active/restorable/detached lifecycle、context detachを実装済みである。
- CM-02はNote store v1に`restorationBinding`を実装済みで、lowercase SHA-256、最大64 unique known standard contextを
  strict validationする。
- CM-03は一件in-flightのdurable store workerを実装済みである。
- 既存`TerminalRestorationCodec`はversion 1のwindow→tab→split first/second DFSをcanonical encodeし、
  `TerminalApplicationRestorer`はfresh runtime `PaneId`で同じtopologyを復元する。Quick Terminalはrestorationから除外される。

## 範囲

- Production defaultでcryptographically secure random 16 bytesからcontext IDを発行し、既存IDとの衝突をboundedに拒否する。
- Restoration snapshot、exact encoded UTF-8 bytes、SHA-256、standard pane traversalを一つのimmutable artifactとして扱う。
- Restore後のfresh `PaneId` traversalを明示して、runtime IDやcwd/title/pathをdurable identityに混ぜない。
- Binding全体がhash/count/known-kind/uniqueの全条件を満たす場合だけordered attachするpure startup reconciliation。
- Mismatch/legacy時の全standard context detach、全live pane fresh ID、wrong-pane partial attach 0。
- Quick Terminal contextをrestoration list外の一つのactive singletonとしてhide/show/restartで再利用する。
- Shutdownでrestorationを先にcommitし、そのexact bytesのbindingを含むNote candidateを次にcommitする注入可能なcoordinator。
- B-01〜B-05、two-transaction failure order、pre-Notes v1 fixture、64-pane/count/duplicate、generation/reopen、
  Quick Terminal lifecycleのfocused test。

## 対象外

- CM-05のapplication-root authority、mutation ingress queue、product composition root接続。
- Note card/native surface、focus/prompt delivery、typed config/default変更。
- Restoration v2、restoration JSONへのcontext ID追加、cwd/title/path/indexによる推測attach。
- `dart_appkit`または汎用packageへのDart Terminal固有code追加。

## 依存関係

- CM-01〜CM-03。
- Existing restoration v1、`TerminalApplicationState`のdeterministic insertion/traversal、Quick Terminal singleton role。
- Frozen Gate 2/4/7 contractとimplementation plan CM-04。

## 分割と実施順

1. **Exact restoration artifact and secure context identity**
   - Secure ID generator、exact UTF-8 artifact/hash、capture/restore traversal projectionを実装する。
   - Pre-Notes literal fixtureのdecode→encode bytes、window/tab/DFS順、64-pane bound、ID collision/format/privacyを検証する。
2. **Startup reconciliation and Quick Terminal singleton binding**
   - Pure reconciliation resultとimmutable pane bindingを実装する。
   - B-01〜B-05、missing/hash/count/unknown/duplicateのall-or-nothing、Detached reason、fresh ID、singleton reuseを検証する。
3. **Ordered persistence, rollback, and crash acceptance**
   - Shutdown candidate作成とrestoration-first/Note-second coordinatorを注入可能なportで実装する。
   - 各transaction failure、reopen generation、rollback no-change/change、real existing restoration storeとのexact-byte証拠、
     full aggregate/source/diff gateを完了する。

各サブタスクは個別に検証、記録、ROADMAP更新、commitする。後続サブタスクやCM-05を先行実装しない。

## 完了条件

- Existing restoration v1のfield/version/encoded fixtureが不変で、pre-Notes binaryが通常どおり読める。
- Matching exact hashでだけ最大64 paneのordered contextが復元される。
- Bindingなし、hash/count/ID mismatch、rollback layout changeでold Noteのwrong-pane attachが0となる。
- Restoration commit成功前にNote binding commitを呼ばず、片方だけ成功した状態は次startupで必ずmismatchとなる。
- Quick Terminalはbinding listへ入らず、一つのcontextをhide/show/restartで再利用する。
- Context ID、path、cwd、title、Note本文をdiagnostics/error文字列へ出さない。
- Focused test、format、analyze、`make test`、必要なRelease AOT test、compatibility freshness、diff/source auditがpassする。

## 検証方針

- Pure deterministic fixtureで順序、境界、collision、B-01〜B-05を全分岐検査する。
- Failure injection portでrestoration write前後とNote commit failureを区別し、call traceとpersisted artifactを検査する。
- Existing restoration file storeへliteral v1 bytesをwrite/readし、digest対象がdiskへcommitしたexact bytesであることを確認する。
- `dart_appkit`差分0と、generic packageへproduct type/path/schema追加0を各サブタスクで確認する。

## 2026-09-20: 着手前調査

- ROADMAPを再読し、CM-03完了commit後の先頭未完了taskがCM-04であることを確認した。
- Existing restoration captureはstandard windowだけをwindow insertion order、tab insertion order、split first/second DFSでencodeし、
  Quick Terminalを除外する。Restorerも同じ構造順でfresh paneを作るが、ordered pane listはpublic resultに未投影である。
- Restoration persistenceはvalid UTF-8を`String`として保持し、save時にdeterministic codecを再encodeする。Hash対象のexact bytesを
  失わないため、decode済snapshotだけでなくread/capture時のencoded sourceをartifactへ保持する必要がある。
- Context modelにはcreate、active/restorable遷移、atomic detachがある。Reconciliationはこれらをpure candidateへ順次適用し、
  workerへは最終document一件だけを渡せる。Application-wide queue/lifecycle ownershipはCM-05まで導入しない。
- Quick Terminal contextのsingleton/always-active invariantは現modelで明示されていない。CM-04でidentity lifecycleとして固定し、
  standard restoration bindingへ混入させない。
- 一括実装ではv1 compatibility、reattach correctness、cross-file crash orderを独立にreview/rollbackできないため、上記3サブタスクへ
  分割した。

## 2026-09-21: exact restoration artifactとsecure context identity完了

- `TerminalNoteContextIdGenerator.secure()`を追加し、production constructorは`Random.secure()`から16 bytesを生成する経路だけにした。
  Deterministic sourceは明示的な`forTesting` constructorへ分離した。既存IDとのcollisionは最大32回だけretryし、entropy shape不正と
  exhaustionはIDを含まないfixed failureへ縮約する。
- `TerminalNoteRestorationArtifact`はdecoded restoration snapshotに加え、load/captureしたexact encoded string、immutable UTF-8 bytes、
  そのbytesのlowercase SHA-256を保持する。JSONを再encodeしてhashしないため、validなleading/trailing whitespaceを含むlegacy
  sourceでもdisk bytesとdigestが一致する。
- Existing `TerminalApplicationRestorationCapture`へsnapshotとstandard pane traversalを同時に返すAPIを追加した。Traversalは既存の
  window order→tab order→split first/second DFSをそのまま使用し、Quick Terminalを除外する。従来`capture`は新APIのsnapshotを返す
  wrapperとし、呼出側互換を維持した。
- `TerminalApplicationRestorer`はfresh runtime paneを作る過程でsaved leaf→new `PaneId`を対応させ、exact traversal listをresultへ追加した。
  Working-directory mapの挿入順には依存しない。Restoration JSONのfield、version、encode処理は変更していない。
- Literal pre-Notes version 1 fixtureはdecode後のcanonical encodeもbyte-for-byte同一だった。複雑な6-pane fixtureはcapture順
  `1,3,4,2,5,6`、seed後restore順`401,402,404,403,405,406`を確認し、64-pane上限でもunique traversalと全session cleanupを確認した。
- 最初のfocused analyzeは新sourceが`PaneId`の定義元を直接importしていない3件を報告した。`terminal_pane.dart`依存を明示して解消した。
  最初のaggregateは更新対象のrestoration source/test hashによりPhase 7 evidence freshnessで停止したため、正規generatorでhashだけを
  更新し、連鎖するrelease-candidate matrixも再生成した。次のaggregateでpublic export orderingのinfo 1件を検出したため実行を中断し、
  alphabetic orderへ修正して最初から再検証した。基準やcriteriaは変更していない。

### 検証

- Focused format: 変更0。Focused analyze: issue 0。`dart test/terminal_restoration_test.dart`: 成功。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。361 files format変更0、root/package analyze issue 0、
  `PHASE7_APPKIT_ACCEPTANCE_PASS`、release-candidate gate 31/release blocker 0、全native/security/integration testを通過し、
  `dart_terminal tests passed`で終了した。Aggregate内のdurable store gateもp95 137,788/14,234 usでpassした。
- `git diff --check`: pass。変更はroot packageのNote/restoration API、test/evidence、ROADMAP/task memoだけで、generic packageへの
  product-specific code追加0である。隣接`dart_appkit` worktreeには着手前からのmodified 3 filesがあることを最終確認時に検出したが、
  このtaskでは同repositoryを編集・stageしていない。

このサブタスクではstartup時のattach/detach判断、Quick Terminal context作成、cross-file commitを実装していない。次の
startup reconciliationサブタスクへ残す。

## 2026-09-21: startup reconciliation着手

- ROADMAPと本メモを再読し、先頭未完了項目がCM-04の第2サブタスクであることを確認した。今回の範囲はpureな起動時照合、
  runtime pane binding、Quick Terminal singleton invariantまでであり、store I/O、cross-file commit、application-root ownerは含めない。
- Hash、pane count、binding contextのkind/stateがすべて一致する場合だけordered attachする。どれか一つでも不一致ならpartial attachを
  行わず、既存standard contextをDetachedへ移し、全live paneへfresh IDを発行するfail-closed案を採用した。
- Context IDとpane IDの対応はimmutable runtime mapとして返す。cwd、title、path、indexは照合材料にせず、diagnosticsは件数だけを返す。
- Quick Terminalはstore内で最大一つ、常にactive、detach不可というdomain invariantに固定する。Standard restoration bindingには含めず、
  既存singletonがあればhide/showとrestartで再利用し、必要時だけfresh singletonを作る。
- Reconciliationはcandidate documentと`requiresCommit`を返すだけにし、durable commit成功前のUI publishを行わない。commit/publish ownershipは
  CM-04第3サブタスクとCM-05へ分離する。

## 2026-09-21: startup reconciliationとQuick Terminal singleton binding完了

- `TerminalNoteContextReconciler`を追加した。Exact restoration hash、pane count、binding内の全contextがknown standardかつ
  non-detachedである条件を順に検査し、完全一致時だけrestoration traversal順でattachする。一つでも不一致なら既存standard contextを
  全件detachし、全live paneへfresh IDを発行するためwrong-pane partial attachは0となる。
- Fresh理由はrestoration missing、binding missing、hash mismatch、count mismatch、binding state mismatchへ固定分類した。
  Missing restoration時はfresh runtime contextを返すが新bindingを推測せず、restorationがあるfresh caseだけそのexact hashに対する次回用bindingを
  candidateへ含める。
- Matched binding外に残るactive/restorable standard contextも`contextUnavailable`でdetachする。Mismatch時のNoteは
  `restorationMismatch`でDetachedへ移し、関連trigger/deliveryは既存domain transactionにより同時解除する。Timestampは要求値と既存Noteの
  最新updated timeの大きい方を使い、順序正規化を含むmutationを有効範囲に保つ。
- Runtime bindingはfresh `PaneId`からopaque context IDへのimmutable mapとし、文字列表現はstandard件数とQuick有無だけに制限した。
  Cwd、title、path、context ID、restoration hash、Note本文は照合診断へ出さない。
- Domain modelへQuick Terminal contextの「最大一つ・常にactive・detach不可」を追加した。Strict decodeでも同じinvariantを検査し、reconcilerは
  既存singletonを再利用するか、要求された時だけ一つ作成する。Standard pane bindingへの混入は既存codec invariantで引き続き拒否する。
- B-01〜B-05相当のcurrent/restoration-only/binding-only/rollback unchanged/layout-changeに加え、legacy missing binding、count mismatch、
  detached binding、missing restoration、duplicate runtime pane/ID、Quick create/restart reuse、immutable/privacyをfocused testで確認した。
- 最初のformatはtest一件を整形した後、sandbox外のDart telemetry metadata更新を拒否されexit 1となった。Repository fileの整形自体は完了しており、
  host権限のfocused analyze/testと最終aggregateで再実行して解消した。Product code/test failureではない。

### 検証

- Focused analyze: `terminal_note_model.dart`、`terminal_note_context_restoration.dart`、`terminal_restoration_test.dart`でissue 0。
- Focused tests: `terminal_restoration_test.dart`、`terminal_note_model_test.dart`、`terminal_note_store_codec_test.dart`はすべて成功。
- `make phase7-appkit-acceptance release-candidate-daily-use-matrix`: 成功。正規生成差分は変更したrestoration testのSHA-256と、その
  acceptance artifactを参照するrelease-candidate SHA-256だけである。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。361 files format変更0、root/package analyze issue 0、
  `PHASE7_APPKIT_ACCEPTANCE_PASS`、release gate 31/release blocker 0、Note store p95 147,201/18,246 us、全native/security/
  integration testを通過し、`dart_terminal tests passed`で終了した。
- `git diff --check`: pass。Root packageのdomain/reconciliation/test/evidence/task memoだけを変更した。隣接`dart_appkit`には着手前からの
  modified 3 filesが残るが、本サブタスクで編集・stageしたfileは0である。

このサブタスクではrestoration-first shutdown commit、Note-second commit、transaction failure/crash recoveryの受け入れを実装していない。
次のordered persistenceサブタスクへ残す。

## 2026-09-21: ordered persistence、rollback、crash acceptance着手

- ROADMAPを再読し、先頭未完了項目がCM-04の第3サブタスクであることを確認した。CM-05のapplication authority、queue、product wiringへは
  進まず、shutdown candidate、注入可能な二段commit、既存storeでの受け入れだけを対象とする。
- 二ファイル間のatomic commitは提供しない。Restoration exact bytesを先にcommitし、成功応答後だけ同じbytesのSHA-256 bindingを持つNote
  candidateをcommitする。Restorationの公開後failure、Note commit failure/応答喪失、rollbackによる片側変更はいずれも次回startupで
  exact hash一致または全件Detachedのどちらかになることを検査する。
- Shutdown candidateはcapture traversalとruntime bindingの完全一致を要求し、live standard contextを`restorable`へ遷移する。余分な
  standard contextは`contextUnavailable`でdetachし、Quick Terminalはactive singletonのままbinding外に保持する。
- Existing restoration persistenceにはvalidなexact encoded stringを再encodeせず保存・再読できる境界を追加する。Coordinator自体は
  callback portだけへ依存させ、CM-05で既存restoration persistenceとCM-03 Note workerを注入できる形にする。

## 2026-09-21: ordered persistence、rollback、crash acceptance完了

- `TerminalNoteShutdownCandidateBuilder`を追加した。Capture traversalとruntime pane bindingは同数・同一pane集合・unique known standard
  contextを要求し、live contextを`restorable`へ遷移する。Capture外に残るstandard contextは`contextUnavailable`でdetachし、Quick
  Terminalはstore/runtimeのsingleton IDが一致する場合だけactiveのまま保持する。
- Candidateはcaptureしたexact restoration artifactと、そのSHA-256およびordered context IDsを持つNote documentを一体で返す。
  Bindingだけが変わるのにsnapshot revisionを前進できない不正入力はcommit不能candidateを作らずcontent-freeにrejectする。
- `TerminalNoteOrderedPersistenceCoordinator`は注入されたcallbackへrestoration、次にNoteの順でだけcommitする。Restoration失敗または
  exceptionではNote callbackを呼ばず、Note失敗はrestoration成功応答後だけ発生する。返却値は実disk状態を断定せず、commit
  acknowledgementとattemptだけをcontent-freeに表すため、公開後の応答喪失も正しく扱える。
- Existing `TerminalRestorationPersistence`はload時のexact encoded stringを保持し、`saveExactEncoded`でstrict decode後の同一文字列を
  再encodeせずstoreへ渡す。既存`save(snapshot)`は同じ境界をcanonical encode経由で利用し、version 1 schema/encodingは変更していない。
- Failure injectionではrestoration reject/throw、restoration公開後の応答喪失、Note reject/throw、Note公開後の応答喪失、両方成功、
  Note no-changeを検査した。いずれもcall順はrestoration→Noteで、次回startupはexact matchかhash mismatchによる全件fresh/Detachedとなった。
- Pre-Notes rollbackはlayout/bytes不変ならB-04 match、layout変更ならB-05 mismatchとなる。Real `FileTerminalRestorationStore`と
  `TerminalNoteStoreTransactionEngine`へpaddingを含むvalid v1 exact bytesとcandidateをcommitし、disk byte一致、lock release、process内
  reopen、ordered context reattachを確認した。
- 最初のfocused analyzeは`save()`の`try`内Future returnへ明示`await`を要求するlint 1件で停止した。最初のreal filesystem fixtureは
  macOSの`/var` symlink表記をdurable-file capabilityが正しく`unsafeFile`拒否した。`await`を追加し、CM-03 acceptanceと同じく
  `resolveSymbolicLinks()`済みの一時rootを使って両方を解消した。Policyやfilesystem validationを緩めていない。

### 検証

- Focused format: 変更0。Focused analyze: issue 0。
- Developer JIT: `terminal_restoration_test.dart`成功。実restoration/Note fileへのcommit/reopenを含む。
- Existing lifecycle regression: `terminal_native_hierarchy_test.dart`成功。
- Release AOT: `dart build cli --target=test/terminal_restoration_test.dart --target-os=macos --target-arch=arm64`で4 native assetsを
  含むbundleを生成し、生成binaryの実filesystem acceptanceが成功。検証後の一時bundleは削除した。
- `make phase7-appkit-acceptance release-candidate-daily-use-matrix`: 成功。正規生成差分はrestoration test hashと、そのartifactを参照する
  release-candidate hashだけである。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。361 files format変更0、root/package analyze issue 0、
  `PHASE7_APPKIT_ACCEPTANCE_PASS`、release gate 31/release blocker 0、Note store p95 136,676/16,668 us、全native/security/
  integration testを通過し、`dart_terminal tests passed`で終了した。
- `git diff --check`: pass。変更はroot packageのcontext/restoration API、test/evidence、ROADMAP/task memoだけである。隣接
  `dart_appkit`の着手前modified 3 filesには変更・stageしておらず、汎用libraryへDart Terminal固有codeを追加していない。

CM-04の3サブタスクと親完了条件をすべて満たした。CM-05でこのpure candidate/coordinatorへapplication-root authority、CM-03 worker、
existing restoration lifecycleを注入し、commit成功後だけsnapshot/UIへpublishする。
