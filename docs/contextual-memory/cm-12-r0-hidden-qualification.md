# CM-12 R0 hidden qualification

日付: 2026-09-21
状態: 実施中

## 目的

CM-01〜CM-11で実装したS1 Basic memoryとS2 On Returnを、公開・internal previewへ昇格させずに
R0 hidden testとしてqualificationする。通常releaseは`notes=false`、user-visible entryなし、Note store access／worker／
surface／timer 0のまま維持し、test harnessだけが明示的なdependency injectionとtemporary storeで機能を起動する。
Frozen privacy、resource、latency、rollback、input/focus、bundle境界を一つのstage decisionとして再現可能にする。

## 背景と確認した現状

- `ROADMAP.md`の先頭未完了はCM-12であり、CM-11はcommit `40738fd`で完了した。着手時worktreeはcleanである。
- Typed configは`notes=false`、`notes-on-return=true`、`notes-next-prompt=false`で、4つのNote optionは
  `internalPreview` exposureである。Normal action catalogはNote action 3件を含めず、composition disabled pathはfactoryを
  評価しない。
- S1/S2 focused harnessと両runtime suiteは`Directory.systemTemp`配下または明示されたabsolute temporary directoryだけを使い、
  runtime-only CLIはcontent-free environment gateを要求する。通常起動のconfig authorityとしてhidden environment flagを
  使っていない。
- Pure model、codec limit/property、store operation fault、worker crash/contention、native ABI/UI、product S1/S2、64-pane、
  privacy、sanitizer、Developer JIT/Release AOTの証拠は個別に存在する。
- `terminal_note_store_acceptance_test.dart`はisolated local filesystemで20回の1 MiB worker commit p95 250 ms以下と
  16 MiB durable primitive p95 1.5 s以下をhard gateにする。`terminal_note_disabled_input_benchmark.dart`はRelease AOTで
  key→PTY p95 2 ms未満、pre-Notes相当baseline比+5%以下、factory/store/surface owner 0を測る。
- Queue、64 live pane/session/surface、64 card/256 KiB projection、2,048 Note、8 MiB body、4,096 context、16 MiB fileの
  structural hard limitはmodel/codec/authority testで固定済みである。
- 不足しているR0固有証拠は、temporary-storeとrollbackをまとめたstage harness、enabled collapsed idle／model transition／
  rail projection／native apply／hard-cap memoryの実測、全証拠と全architecture bundleを束ねるnamed aggregate、manual checklistと
  明示的stage decisionである。

## 範囲

- R0専用temporary-store harness、normal default-off/user-entry 0、disabled no-access、soft rollback、pre-Notes rollback、
  exact/mismatch re-upgradeのcontent-free acceptance。
- Fixed M1/arm64 Release AOTをauthorityとするNote resource/latency benchmarkとversioned/content-free evidence。
- Existing pure/codec/fault/native/product/privacy/source/resource/bundle/distribution gate、Developer JIT/Release AOT、
  arm64/x86_64/Universal resource equalityを束ねるnamed aggregate。
- Japanese IME、keyboard-only、VoiceOver accessibility tree、12/15/24 pt、light/dark/contrast/differentiate without color/
  Reduce Motion、Retina/non-Retina、小pane、alternate-screen/Vim/Codex/mouse TUIのmanual checklistとR0 exit decision。

## 対象外

- Internal/user opt-in、public Settings/reference、default-on、S3 shell integration v3。
- Production telemetry、remote flag、background upload、実データstore、同期/import/rich text/attachment。
- Hard budget、quota、privacy sentinel、acceptance条件を測定結果に合わせて緩和すること。
- `dart_appkit`へのDart Terminal固有Note、benchmark、rollout code追加。

## 依存関係

- CM-01〜CM-11のmodel、codec、worker、identity/restoration、authority、configuration、input owner、native UI、S1/S2 product contract。
- Gate 7のtest pyramid、hard resource/latency budget、environment matrix、R0 stage、kill/rollback rule、review vector。
- Existing process resource sampler、runtime builder/audit、Universal assembler、native sanitizer、distribution verification。

## サブタスクと実施順

1. **R0 temporary-store harness、hidden/default-off、rollback contract**
   - Normal config/action/compositionのentry、factory、file access、worker、surface、timerが0であることを固定する。
   - Temporary store内でS1/S2を起動し、soft off restart、pre-Notes restoration-only launch、exact/mismatch re-upgrade、
     incompatible/corrupt/native-missing時のstore非破壊とterminal継続をcontent-free summaryへまとめる。
2. **Hard resource/latency budget benchmarkとevidence**
   - Enabled collapsed 64-pane idle RSS/timer/frame、model transition p95/max、128-note first projection、native apply p95/stall、
     hard-cap steady/peak RSS、teardown owner 0をRelease AOTで測る。
   - Existing disabled input、1/16 MiB durable commit、queue/persistent boundと合わせ、hard thresholdを固定したevidenceにする。
3. **Named aggregateとcross-architecture audit**
   - Pure/codec/fault/native/product/sanitizer/privacy/source/shell/restoration/bundle/budget/runtime gateを一つのR0 targetへ接続する。
   - Developer JIT/Release AOTとarm64/x86_64/Universal bundleのNote capability/resource equality、body/path leak 0を検査する。
4. **Manual checklistとR0 stage decision**
   - Frozen manual matrixを実AppKit candidateで実施し、pass/fail、環境、未検証事項を本文を含まない形で記録する。
   - Automated/manual evidenceをreviewし、hard invariant violation 0の場合だけR0をpassとしてROADMAPを完了する。

各サブタスクを個別に検証、文書更新、ROADMAP更新、commitする。前の項目を完了するまで次へ進まない。Budget違反や
hard invariant violationを発見した場合は、閾値を緩めず修正taskを現在位置へ追加する。

## 完了条件

- Normal release default off、user-visible Note entry 0、store read/write/lock、worker、native surface、timer 0。
- Test harnessはtemporary storeとexplicit injectionだけを使い、本文、ID、time、color、trigger、pathをevidenceへ出さない。
- Gate 7の全hard resource/latency budget、queue/persistent bounds、complete teardown 0 leakをM1/arm64 Release AOTで満たす。
- Pure/codec/fault/native/product、disabled zero-cost、privacy/source/resource/bundle、runtime/distribution gateがpassする。
- Soft rollbackとpre-Notes binary相当のrestoration-only launchでstore bytesを変更せず、re-upgrade exact matchだけreattachし、
  mismatchはDetached、wrong-pane attach 0となる。
- Manual IME/keyboard/VoiceOver/appearance/font/scale/small-pane/TUI checklistがpassし、hard invariant violation、body/privacy leak 0。
- `dart_appkit`のgeneric auditがpassし、Dart Terminal固有code追加0。

## 検証方針

- Focused R0 harness、configuration/action/composition/restoration/store/native fault test。
- Release AOT budget executableを20回以上のlatency sampleとcontent-free RSS deltaで実行し、native applyはactual AppKit viewで測る。
- `make test`、native sanitizer、disabled benchmark、S1/S2 aggregate、runtime verify、release distribution audit/integration。
- arm64/x86_64 thinとUniversal manifest/resource hash、Note capability declaration、source/privacy/shell/diagnostics audit。
- 実AppKit manual checklist、`git diff --check`、最終差分review、隣接`dart_appkit` full test/generic audit。

## サブタスク1: temporary-store、hidden/default-off、rollback contract

### 実装と固定した判断

- `test/terminal_note_r0_hidden_qualification_test.dart`を追加し、通常の`--no-config`解決結果が`notes=false`、
  `notes-on-return=true`、`notes-next-prompt=false`、font 15であることを固定した。Normal action catalogにはNote action 0、
  public option/referenceには4つのNote option 0であり、R0にuser-visible entryを追加していない。
- Disabled compositionへ、評価された場合にdirectoryを作って例外を投げるfactoryを注入した。Factory call 0、probe path 0、
  runtime ownership 0を確認し、通常起動がstore path、worker、authority、surface、timerへ到達しない境界とした。
- `Directory.systemTemp`配下のcanonical absolute pathだけを使い、実`TerminalNoteStoreWorkerClient`でrestoration bindingと
  private Note 1件をcommitした。本文、Note ID、temporary pathはmachine evidenceへ含めない。
- 両copy corruptでは`recoveryRequired`、currentがnewer versionかつbackupがv1では`upgradeRequired`となり、明示的な
  recovery／upgradeなしにcurrent、backup、deletion journalのpayloadを変更しないことを実workerで確認した。Advisory lockの
  `store.lock`はworker ownershipに従って生成され得るため、非破壊比較の対象はdurable payload 3種とし、lock lifecycleは
  worker owner countと停止完了で別に検証する。
- Soft off restartとnative capability unavailableはいずれも既存store bytesを変更しない。Pre-Notes binary相当はrestoration v1を
  exact bytesでread/publishするだけでNote storeを開かない。再upgrade時、同一layout hashは元contextへ再接続してcommit不要、
  changed layout hashはfresh contextを作り旧NoteをDetachedにし、新paneへの誤接続0とした。
- Composition、authority、worker、product subsystemのlive ownerはharness前後で同数、temporary treeは`finally`で削除する。
  `test/run_tests.dart`へ登録し、登録ファイルのhash変更だけを
  `compatibility/release_candidate_daily_use_matrix.json`へ再生成した。

Content-freeな合格行は次で固定した。

```text
TERMINAL_NOTE_R0_HARNESS_PASS temporary_store=1 default_off=1 user_entries=0 disabled_resources=0 soft_rollback=1 corrupt=1 incompatible=1 native_missing=1 exact_reattach=1 mismatch_detached=1 wrong_attach=0 store_changes=0 privacy=1 owners=0
```

### 判明した失敗と再発防止

- Sandbox内のnative asset buildはMetal clang module cacheへ書けず失敗した。権限付きの同一commandでは成功しており、
  product failureではない。
- Sandbox内の`dart format`は対象を整形した後、ユーザーtelemetry sessionのmtime更新だけに失敗した。権限付きformatと
  `--set-exit-if-changed`で0 changesを確認した。なお`--output=none`は差分を表示するだけで保存しないため、実適用には通常の
  `dart format`を使う必要がある。
- 複数の`dart run`を並行実行するとnative asset bundler同士が同じ`.dart_tool/lib`を更新し、composition testが一度だけ
  library不在になった。Dart native assetを使うfocused testは直列実行し、単独再実行でpassした。
- Corrupt fixtureでdirectory全ファイルを比較すると、workerが正当に生成する`store.lock`をpayload変更と誤認した。
  Current／backup／deletion journalだけをbyte比較し、lockとworkerはstopおよびowner countで検証するよう分離した。
- 最終全体回帰中、既存PTY testの終了直前process sampling raceが一度再発し、空listへの`firstWhere`で停止した。
  `make dpty-dart-test`の単独再実行と、その後の同一`make test`はpassした。Note差分にPTY code変更はない。

### 検証結果

- Focused R0 harness: pass。上記machine lineをexact出力した。
- `dart analyze test/terminal_note_r0_hidden_qualification_test.dart`: `No issues found!`。
- Configuration、action registry、restoration、store worker、composition focused regressions: pass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。全385 Dart fileはformat済み、root analyzeは
  `No issues found!`、R0 harnessとstore acceptance
  （20 runs、1 MiB commit p95 152,831 us、16 MiB primitive p95 18,323 us）を含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`であり、Dart Terminal固有code追加0。
- `dart_appkit`の既存未commit変更3件
  （`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、`scripts/build_dart_engine.sh`）は変更もstageもしていない。

サブタスク1の完了条件を満たした。CM-12全体はhard budget、cross-architecture aggregate、manual stage decisionが未完了のため
引き続き実施中とする。

## サブタスク2: hard resource/latency budget benchmarkとevidence

### 着手時の目的、範囲、完了条件

- 目的: Gate 7で凍結した閾値を変更せず、固定M1/arm64 Release AOTとactual AppKit main threadでfreshに測定し、
  raw sample、本文、ID、time、color、trigger、pathを保持しないversion 1 evidenceへ集約する。
- 対象: 64-pane enabled/collapsed idle、application-root model/event transition、128-note rail first-visible、native apply、
  2,048 Note／8 MiB body／4,096 context hard-cap RSSと実worker commit、既存disabled inputと1/16 MiB durable commit、
  queue/projection/persistent structural bounds、完全teardown。
- 対象外: Developer JITのperformance authority、他hardwareへの閾値転用、public/internal opt-in、cross-architecture bundle aggregate、
  manual usability/accessibility判定、`dart_appkit`への製品固有benchmark追加。
- 依存: `TerminalCurrentProcessResourceSampler`、product subsystem／authority／worker、native Notes capability、既存disabled inputと
  store acceptance、固定baseline `MacBookPro17,1`／arm64／16 GiB／Dart 3.13.2。
- 完了条件: 全hard budget、content-free line inventory、static no-idle-timer audit、structural bound、owner 0がpassし、
  versioned JSON evidenceをfresh runから生成できる。違反時は閾値を緩めず現在位置にfix taskを追加する。
- 検証: evidence parserのpositive/negative unit test、Release AOT benchmark、actual AppKit native benchmark、既存2 benchmark、
  focused format/analyze、`make test`、隣接`dart_appkit` generic audit、差分review。

### 計測設計

- RSS計測を相互に汚染しないよう、単一Release AOT executableがidle、model、projection、hard-capの4 child processを直列起動する。
  Parentはexactなcontent-free summaryだけを受理し、child stderrやtemporary pathをevidenceへ転送しない。
- Idle fixtureはtemporary store上の実worker、64 live pane、64 collapsed fake-native channelを持つproduct subsystemとする。
  Settled window中のprojection／notification／store payload delta 0、RSS増分16 MiB以下を確認し、shutdown後全ownerを基準線へ戻す。
  Native channelはframe schedulingを実装しない。加えてproduct/authority/native sourceのperiodic timer／display-link不在と、
  store timerがrequest timeoutだけであることをstatic auditする。
- Model/event transitionはbody encode/fsyncを行わないopen/close runtime transitionを64 sample測り、p95 1 ms以下、max 4 ms以下、
  store commit delta 0とする。
- Rail fixtureは同一contextの128 Note、1件4,096 byte、先頭page 64 card／256 KiBを使い、collapsedから最初のexpanded projectionまでを
  20 sample以上測る。Native fixtureも同じ64 card／256 KiB packetをactual AppKit viewへ適用し、layout/display完了までを
  first-visibleとして測る。Root projectionとnative first-visibleのp95和を100 ms以下、native apply p95を8 ms以下、
  16.67 ms超main-thread sampleを0とする。
- Hard-cap fixtureは4,096 context、2,048 Note、各4,096 byte、2,048 trigger/deliveryを使う。実worker commit中もRSSをsampleし、
  steady増分64 MiB以下、lifetime peak増分96 MiB以下、canonical file 16 MiB以下、stop後owner 0を要求する。
- Evidence builderはDart／native／disabled／durableのlogをexact line inventoryとしてparseし、余分なlineをprivacy failureにする。
  Raw sampleは保存せずp95/max/count/deltaとinput/source SHA-256だけをJSONへ置く。

実装は依存順に、(1) isolated Release AOT Dart fixture、(2) actual AppKit native fixture、(3) versioned evidenceと全hard gateへ
分割する。各項目を個別に検証、ROADMAP更新、commitし、前の項目が完了するまで次を実装しない。

### Dart fixture実装中に判明したhard-cap違反と追加分割

- Dart 3.13.2の`dart compile exe`はbuild hook由来のdynamic native assetをbundleしない。最初のAOT executableでは
  model／projectionは動作した一方、durable-fileを使うidle／hard-capがcontent-freeなnative resolution failureになった。
  Supportedな`dart build cli`は`bundle/bin`と`bundle/lib`を生成し、5 native assetを同梱するため、この経路をRelease AOT
  fixtureの正本にする。単一executableを成功扱いにしたり、JITへfallbackしたりしない。
- Native-assets CLI bundleへ切り替えたfresh childで、idleはRSS増分3,899,392 bytes、modelはp95 2 us／max 6 us、
  projectionはp95 4,193 usで合格した。Hard-capはsteady増分44,908,544 bytesとcanonical 9,698,603 bytesは上限内だが、
  commit peak増分451,624,960 bytesで96 MiB上限に違反した。本文、ID、path、raw sampleは出力していない。
- `terminalSha256`は入力全体をgrowable boxed `List<int>`へ複製し、さらに64-byte blockごとに8要素listを生成する。
  Hard-cap commitではcanonical payload／envelope／decode検証の複数回hashと重なり、入力8 MiBに対して無視できない一時heapを
  作る。まずpadding byteをindex計算し、64-word scheduleと8-word stateだけを保持するconstant-working-memory実装へ変更する。
- この修正はNote固有仕様を汎用packageへ入れるものではなく、既存のroot-local SHA-256 primitiveの同値な資源修正である。
  Known vector、padding境界、iteratorを禁止したindexed virtual inputで互換性と入力materialize 0を固定し、AOT hard-capを再測定する。
  それでも96 MiBを超える場合は次の最大retainerを特定し、閾値を緩めず現在位置で追加修正する。

このためisolated Dart fixtureを、(1) SHA-256 working memoryのbounded化、(2) 残るcommit peak retainerの除去、
(3) native-assets CLI bundleと4-phase gate完了へ追加分割した。各項目を個別に検証、commitし、前の項目を完了するまで
後続を完了扱いにしない。

### Bounded SHA-256 working memoryの完了結果

- `terminalSha256`は入力を複製せず、padding byteを元入力length、block offset、64-bit bit lengthから合成する。
  64-word scheduleと8-word hash stateを再利用し、従来blockごとに生成していた8要素listも除去した。Digest、lowercase hex、
  Dart-only／native-process dependency 0という公開挙動は変更していない。
- 新規`terminal_sha256_test.dart`はempty／abc oracle、55／56／57／63／64／65-byte padding境界、1,000-byte vectorを固定した。
  さらにiteratorを例外にする1 MiB indexed zero inputをexactly 1 read/byteでhashし、入力materializeを回帰検出する。
- Native-assets CLI bundleの同一hard-cap childでは、変更前のpeak増分451,624,960 bytesから変更後148,357,120 bytesへ
  303,267,840 bytes減少した。Steady 44,924,928 bytes、canonical 9,698,603 bytesは引き続き各上限内である。
- Peakはなお96 MiBを47,693,824 bytes超過するため閾値は緩めず、workerがdurable write後に同じcanonical bytesをfull decodeし、
  strict JSON tree、canonical string、decoded documentを同時所有する箇所を次の現在taskとして追加した。Encode時にcandidateは既に
  model validation済みで、worker codecも`encode`冒頭で再検証する。次項ではsuccessful write後にimmutable worker-side candidateを
  retainできるかをfault／round-trip／restart semanticsとともに検証する。

検証結果:

- `dart run test/terminal_sha256_test.dart`: pass。
- Note store codecとshell integration resourceのfocused test: pass。Existing `abc` oracleとcanonical envelope checksumも維持した。
- Focusedおよびroot `dart analyze`: `No issues found!`。Aggregate中に新規importのdirective ordering infoを1件確認し、修正後の
  format checkとroot analyzeで0件を再確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。387 Dart filesのformat、root suite、R0 hidden harness、20-run store
  acceptanceを含む。Matrixは新規aggregate test登録とMake targetのhashへ再生成した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`で、Dart Terminal固有code追加0。既存未commit変更3件は変更もstageもしていない。

SHA-256 working memoryの個別完了条件を満たした。Isolated Dart fixture全体はhard-cap peak違反が残るため未完了とする。

### Duplicate canonical decode除去の着手条件

- 目的: Successful commit後だけ実行される`decode(candidateBytes)`によるstrict JSON tree、canonical再encode、2個目の
  `TerminalNoteStoreDocument`の一時所有をなくし、96 MiB peak上限を満たす。
- 範囲: `TerminalNoteStoreTransactionEngine.commitCandidate`のpublish後state更新、ordinary／deletion／fault／restart test、
  fixed M1 Release AOT hard-cap再測定。Durable write前のcandidate validation、canonical encode、checksum、atomic replace、
  deletion coverage read-backは維持する。
- 対象外: Store format/version、checksum algorithm、isolate full-snapshot protocol、file/body/count上限、threshold、native UI、
  `dart_appkit`変更。
- 安全性前提: `TerminalNoteStoreDocument` constructorと`TerminalNoteSnapshot.fromRecords`はrecordsをcopyしてunmodifiable viewにし、
  model invariantを検証する。Worker-side `encode(candidate)`もwrite前に`snapshot.validate()`し、canonical bytes生成失敗時はpublishしない。
  Candidateはisolate messageでworker heapへcopy済みで、commit後に外部producerから変更できない。
- 完了条件: 成功応答のrevision/count/bytes、連続commit、disk reload、backup rotation、deletion resurrection protection、全fault後の
  old-or-new recoveryが不変であり、hard-cap steady 64 MiB／peak 96 MiB／file 16 MiBとowner 0を満たす。
- 検証: store worker／isolate／acceptance focused test、AOT hard-cap child、format/analyze、root `make test`、隣接
  `dart_appkit` generic audit、差分review。違反が残れば次retainerを現在位置へ追加し、閾値は変更しない。

### Duplicate canonical decode除去の完了結果

- Durable replace成功後は、同じ`candidateBytes`をstrict parse／canonical再encodeして第二documentを作らず、write前の
  `encode(candidate)`で再検証済みかつworker heap所有のimmutable candidateを`_loaded`へ保持する。Failure、recovery、load、
  deletion coverageのdisk decodeは変更していない。
- Store worker／isolate／real filesystem acceptanceは全てpassした。Ordinary連続commit、backup rotation、全filesystem fault後の
  old-or-new read、On Return commit/ack crash、deletion resurrection、two-process contention、restart reloadが既存vectorのまま通る。
- Fixed M1 Release AOT hard-capは、SHA修正後148,357,120 bytesだったpeak増分が108,740,608 bytesへ39,616,512 bytes減少した。
  Steady 44,941,312 bytes、canonical 9,698,603 bytesは上限内だが、peakは96 MiB上限を8,077,312 bytes超える。
- 残る主要な入力比例allocationはpayload checksum用の`utf8.encode(payloadSource)`で、canonical約9.7 MiBを丸ごと複製する。
  Thresholdは変更せず、UTF-8 code pointをincremental SHA-256へ直接渡すbounded checksumを次の現在taskとして追加した。
- 最初のroot aggregateは、前subtaskでimport orderingを直した後にmatrixを再生成していなかったためstale判定で停止した。
  Matrixをfresh生成し直し、同じaggregateを再実行してpassした。履歴のamendは行っていない。

検証結果:

- `dart analyze lib/src/terminal_note_store_worker.dart`: `No issues found!`。
- Store worker、store isolate、20-run real filesystem acceptance: pass。Commit p95 48,908 us、primitive p95 13,425 us。
- Hard-cap AOT child: gate failureは上記peakのみ。Commit、steady、file、privacy-safe classificationはpass相当。
- Regenerated release-candidate matrix check後の`CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。387 Dart files、root analyze
  `No issues found!`、R0 hidden harness、store acceptanceを含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、Dart Terminal固有code追加0。既存未commit変更3件は非接触。

Duplicate decode除去の個別完了条件を満たした。Isolated Dart fixture全体は残る8,077,312-byte peak違反のため未完了とする。

### UTF-8 checksum allocation bounded化の着手条件

- 目的: Canonical payload `String`をchecksumのためだけに同サイズの`Uint8List`へ変換する一括allocationを除き、digest bytesと
  store formatを変えずhard-cap peakを96 MiB以下にする。
- 範囲: Root-local SHA-256 primitiveのincremental block state、Dart UTF-16からstandard UTF-8への直接feed、store payload／
  deletion journal／decode checksum call site、Unicode／surrogate／padding regression、AOT hard-cap再測定。
- 対象外: Canonical JSON field order、escaping、envelope version、SHA-256 algorithm、body normalization、isolate protocol、threshold、
  `dart_appkit`および他packageへのproduct code追加。
- 完了条件: `terminalSha256Utf8(source) == terminalSha256(utf8.encode(source))`がASCII、multi-byte、valid surrogate pair、unpaired
  surrogate replacementで成立し、既存known vector／codec bytes／fuzzが不変、input比例byte copy 0、hard-cap全memory gate passとなる。
- 検証: SHA/codec/store focused test、format/analyze、fixed M1 AOT hard-cap、root `make test`、隣接`dart_appkit` generic audit。
  96 MiB違反が残る場合は次retainerを現在位置へ追加し、閾値やfixture sizeを変更しない。

### UTF-8 checksum allocation bounded化の完了結果

- SHA-256を64-byte block accumulatorへ整理し、`terminalSha256Utf8`はDart UTF-16 code unitからstandard UTF-8 byteを直接feedする。
  Valid surrogate pairは4 byte、unpaired surrogateはstandard encoderと同じU+FFFDとして処理し、input-sized byte listを作らない。
- Store payload、deletion journal、decode checksumはdirect UTF-8 digestを使用する。Envelopeもpayload objectを二度canonicalizeせず、
  checksum対象のcanonical payload sourceを再利用し、small prefix／payload／suffixのUTF-8 lengthを先に検証してexact `Uint8List`へ
  直接書く。16 MiB超過はallocation前にfailし、field order、one trailing LF、checksum、version 1 bytesは不変である。
- 最初にchecksum byte listだけを除いたrunはpeak 109,494,272 bytesで測定変動内に留まり、standard `utf8.encode`結果への
  redundant `Uint8List.fromList`だけを除いたrunも105,873,408 bytesで未達だった。原因はpayloadを含む約9.7 MiB envelope
  `String`の再構築も同時所有していたためであり、上記direct envelope writeまで実施した。失敗した2試行でthresholdやfixtureは変えていない。
- Final fixed M1 Release AOT hard-capはsteady増分44,892,160 bytes、peak増分89,997,312 bytes、canonical 9,698,603 bytes、
  owners 0で合格した。64／96 MiB、16 MiBの全閾値は凍結値のままである。

検証結果:

- SHA known vector、55／56／57／63／64／65-byte padding、1 MiB indexed input、ASCII／multi-byte／surrogate equivalence: pass。
- Note codec canonical exact bytes、Unicode round-trip、strict/fuzz/capacity/privacy tests: pass。
- Focused `dart analyze`: `No issues found!`。AOT hard-cap childは上記exact PASS lineを出力した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。387 Dart files、root analyze、R0 hidden harness、20-run real store
  acceptance（commit p95 45,280 us、primitive p95 15,798 us）を含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、Dart Terminal固有code追加0。既存未commit変更3件は非接触。

UTF-8 allocation bounded化の個別完了条件を満たした。次にnative-assets CLI bundleの全4 phaseをfresh aggregateで確定する。

### Native-assets CLI bundle／4-phase hard gateの着手条件

- 目的: Supportedな`dart build cli`で全native assetを同梱したRelease AOT bundleを正本とし、idle、model、projection、
  hard-capを相互に汚染しない4 child processでfresh実行して、全Dart-side hard gateを同時に満たす。
- 背景: 個別phaseはnative-assets bundle上で実行済みだが、hard-cap peak違反を解消する3件のresource修正後にparent aggregateを
  完走した証拠はまだない。`dart compile exe`やJITへのfallbackはnative assetを欠くため認めない。
- 範囲: CLI bundle build/run target、4 phaseのexact one-line受理、content-free failure code、success時stderr 0、固定authority環境、
  frozen threshold、全phase teardown owner 0、fresh aggregate実測。
- 対象外: Actual AppKit viewへのnative apply／layout／display、evidence JSON生成、disabled/store log統合、cross-architecture bundle、
  manual checklist、`dart_appkit`への製品固有code追加。
- 依存: 直前3サブタスクのbounded SHA-256、validated commit state保持、direct UTF-8 checksum/envelope encode、および
  `TerminalCurrentProcessResourceSampler`、product subsystem、実durable-file worker。
- 完了条件: 固定M1/arm64 Release AOT authorityでidle RSS 16 MiB以下、model p95 1 ms／max 4 ms以下、projection p95 100 ms以下、
  hard-cap steady 64 MiB／peak 96 MiB／file 16 MiB以下を満たし、4 phase各1行とversion 1 aggregate 1行以外を出力せず、
  commit delta 0／idle activity delta 0／全owner 0を確認する。
- 検証: Focused format/analyze、fresh native-assets aggregate、root `make test`、隣接`dart_appkit` full test/generic audit、
  `git diff --check`。違反時はthresholdやfixture sizeを変えず、原因を現在位置の追加taskとして追跡する。

### Native-assets CLI bundle／4-phase hard gateの完了結果

- `dart build cli`はbundleへdurable-file、PTY、AppleScript、Notes、rendererの5 native assetをcopyし、生成した
  `bundle/bin/terminal_note_r0_budget_benchmark`だけをRelease AOT authorityとして実行した。JITまたは単体
  `dart compile exe`へのfallbackはない。
- Parentは各childのstdoutをexactly one PASS lineとして受理し、success時のstderrもemptyでなければfail closedにした。
  Projection helperの実際のStateError文言とcontent-free failure code tableの不一致も修正した。Invalid phaseはexit 1と
  `phase=invalid reason=format_error content_free=true`だけを返す。
- Fresh aggregateは次の5行で合格した。Build logとtemporary pathはevidence lineに含めず、本文、Note/context ID、time、color、
  trigger、store path、raw latency/RSS sampleを出力していない。

```text
TERMINAL_NOTE_R0_IDLE_PASS panes=64 surfaces=64 worker=1 rss_delta_bytes=3293184 rss_budget_bytes=16777216 idle_window_ms=250 projection_delta=0 notification_delta=0 layout_delta=0 frame_delta=0 store_changes=0 owners=0
TERMINAL_NOTE_R0_MODEL_PASS samples=64 p95_us=4 max_us=11 p95_budget_us=1000 max_budget_us=4000 store_commit_delta=0 body_encode=0 fsync=0 owners=0
TERMINAL_NOTE_R0_PROJECTION_PASS samples=21 notes=128 cards=64 body_bytes=262144 p95_us=4553 budget_us=100000 store_commit_delta=0 owners=0
TERMINAL_NOTE_R0_HARD_CAP_PASS notes=2048 contexts=4096 triggers=2048 deliveries=2048 body_bytes=8388608 file_bytes=9698603 steady_delta_bytes=44892160 steady_budget_bytes=67108864 peak_delta_bytes=90144768 peak_budget_bytes=100663296 owners=0
TERMINAL_NOTE_R0_DART_BUDGET_PASS version=1 build=release-aot abi=macos_arm64 hardware=MacBookPro17,1 memory_bytes=17179869184 dart=3.13.2 phases=4 content_free=true
```

検証結果:

- Focused formatは0 changes、`dart analyze tool/terminal_note_r0_budget_benchmark.dart`は`No issues found!`。
- `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 terminal-note-r0-dart-budget`: pass。Frozen threshold、
  fixture count/body size、authority environmentを変更していない。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。387 Dart files、root analyze、R0 hidden harness、20-run real store
  acceptance（commit p95 47,729 us、primitive p95 18,342 us）を含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、Dart Terminal固有code追加0。既存未commit変更3件は非接触。

Native-assets CLI bundleと4-phase hard gate、および親のisolated Release AOT Dart fixtureの完了条件を満たした。次は順番どおり、
同じ64 card／256 KiB packetをactual AppKit main threadへ適用するnative apply／first-visible fixtureを実装する。

### Actual AppKit native apply／first-visible fixtureの着手条件

- 目的: Dart projection生成時間と分離して、最大page packetをactual AppKit main thread上の実native Note viewへ適用し、
  projection apply単体とlayout/displayまでのfirst-visible latencyをfrozen Gate 7 thresholdで測定する。
- 背景: 既存native acceptanceは64 card／256 KiBのatomic apply、32 card materialization、geometry、bitmap、accessibility、owner回収を
  機能検証するが、warmup後のp95とmain-thread stall countを独立したhard gateにはしていない。
- 範囲: Product-owned Notes native test source、実`NSWindow`／host／Note view、64 card×4,096 bytes、context total 128、
  5 warmup＋21 measured sample、apply p95、apply+layout+display first-visible p95、16.67 ms超sample count、snapshot／owner境界、
  content-free one-line result、host-architecture Make target。
- 対象外: Dart model/projection timing、durable store、renderer/PTY、raw sample永続化、evidence JSON、cross-architecture実行、manual UX、
  production telemetry、`dart_appkit`へのDart Terminal固有code追加。
- 依存: `TerminalNotesPlugin` ABI v1、maximum packet contract、AppKit main-thread surface lifecycle、直前のDart projection p95 output。
- 完了条件: 固定M1/arm64／16 GiBでapply p95 8 ms以下、first-visible p95 100 ms以下、16.67 ms超のmain-thread sample 0、
  projected 64／materialized 32／aggregate body 256 KiB、actual layout/display、live surface owner 0を満たす。Root projection p95との
  合計100 ms gateは次のversioned evidence subtaskでexactに結合する。
- 検証: Warnings-as-errors native build、fresh benchmark、既存Notes native capability test、root `make test`、隣接`dart_appkit`
  full test/generic audit、content-free output review、`git diff --check`。違反時はthreshold、sample count、body/card sizeを変えず、
  native hot pathを現在位置で修正する。

### Actual AppKit native apply／first-visible fixtureの完了結果

- Product-owned `TerminalNotesBudgetBenchmark.mm`を追加し、offscreenだがordered-visibleな実`NSWindow`、host view、
  `DtnNoteSurfaceView`をAppKit main thread上で構成した。Collapsedをdisplayしてから、事前生成した64 card×4,096-byte packetを
  applyし、同期layout/display完了までを同一monotonic sampleに含める。5 warmup後に21 sampleを取り、raw sampleは保持／出力しない。
- Packetはcontext total 128、projected 64、aggregate body 262,144 bytes、materialized 32を毎sample snapshotで検査する。
  Apply p95 8 ms、first-visible p95 100 ms、16.67 ms超sample 0、surface owner 0をhard failとし、固定M1/arm64／16 GiB以外は
  content-free `environment_authority`でfail closedにする。Make targetはhost architectureだけを実行可能にする。
- 初回はapply p95 130,363 us、first-visible p95 200,478 us、stall 21で違反した。32 card viewを毎回破棄／再生成し、
  4,096-character bodyを全件同期measureしていたことが主因だった。Threshold、64/32 card、256 KiB、sample countは変更していない。
- Native hot pathは最大32個のcontent-free view shellを再利用し、collapsed時にmodel、body/chip text、intent callbackを消去してhiddenにする。
  再展開ではhierarchy remove/addを行わない。Card bodyはfull modelをmutation用に保ちながら、visible previewだけをsurrogate-safeな
  256 UTF-16 code unit／最大8 logical line／ellipsisへboundし、安価で保守的な1〜8 line heightを使う。Appearance/font/titleは
  実値が変わった時だけAppKit propertyへ反映する。既存card identity、collapsed body 0、accessibility active body countは維持した。
- 中間runは順に101,847/116,798 us、20,428/35,129 us、8,683/22,424 usまで改善した。Hierarchy shell再利用後の最初の
  fresh replayはp95 5,256/14,837 usでも1 sampleだけ16.67 msを超えたため未完了とし、unchanged appearance propertyの再設定を
  除いた。`MIN` macroのGNU extensionとObjective-C `.m`内`nullptr`はwarnings-as-errorsで検出され、portable ternary／`NULL`へ修正した。
- 最終fresh targetは次のexact content-free lineで合格した。直前の独立fresh process 2回も4,749/13,715 us、
  4,791/13,850 us、stall 0で合格し、閾値違反を再現しなかった。

```text
TERMINAL_NOTE_R0_NATIVE_BUDGET_PASS version=1 abi=macos_arm64 hardware=MacBookPro17,1 memory_bytes=17179869184 warmups=5 samples=21 cards=64 materialized=32 body_bytes=262144 apply_p95_us=4570 apply_budget_us=8000 first_visible_p95_us=12812 first_visible_budget_us=100000 stalls=0 stall_threshold_us=16670 owners=0 content_free=true
```

検証結果:

- Warnings-as-errors build、actual AppKit benchmark、既存Notes native codec/capability suite: pass。Maximum preview bound、view shell
  identity reuse、collapsed body preview消去、再展開FIFO、bitmap、geometry、accessibility、editor/intentを含む。
- 最初のroot `make test`はMakefile evidence hashのstale matrixだけで停止した。正規generatorで
  `compatibility/release_candidate_daily_use_matrix.json`のMakefile SHA-256だけを更新し、再実行はpass。387 Dart files、
  root analyze、R0 hidden harness、20-run real store acceptance（commit p95 54,346 us、primitive p95 26,475 us）を含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、Dart Terminal固有code追加0。既存未commit変更3件は非接触。

Actual AppKit native apply／first-visible fixtureの完了条件を満たした。次はversioned content-free evidenceでDart／native／disabled／
storeのexact line inventory、root projection＋native first-visible合計100 ms、static timer/source、structural boundを一つに結合する。

### Versioned content-free evidence／全hard gateの着手条件

- 目的: FreshなDart、actual AppKit native、disabled input、durable storeの4 benchmark logを一つのversion 1 evidenceへ結合し、
  Gate 7のresource／latency／structural／privacy条件をmachine-checkableな一成果物として固定する。
- 背景: 各benchmarkは独立してhard failするが、root projection p95＋native first-visible p95の合計、4 logのexact inventory、
  Note sourceのidle timer/display-link不在、全bound/provenanceを同時に判定するownerがまだない。
- 範囲: 4 input log（Dartはexact 5行、他は各1行）のstrict parser、combined 100 ms gate、全frozen threshold、structural constants、
  Note関連source全体のperiodic timer/display-link audit、store request timeoutだけのone-shot timer allowlist、input/source SHA-256、
  deterministic JSON schema、positive/negative parser tests、fresh generation Make target。
- 対象外: Raw latency/RSS sample、本文、Note/context ID、timestamp、color、trigger instance、absolute/temporary path、telemetry、
  cross-architecture/runtime aggregate、manual checklist、`dart_appkit`への製品固有code追加。
- 依存: 直前のisolated Dart 4-phase fixture、actual AppKit fixture、Release AOT disabled benchmark、real filesystem store acceptance、
  frozen model/authority/store/projection/native limit constants。
- 完了条件: Extra/missing/reordered/malformed line、unknown key、threshold/bound/environment mismatchをすべてfail closedにし、fresh 4 inputで
  combined first-visible 100 ms以下を含む全gateがpassする。Evidenceはaggregate値とSHA-256だけを保持し、同じinputからdeterministicに
  生成される。Static auditはperiodic timer/display-link 0、store request-timeout one-shot 1だけを許可する。
- 検証: Parser/schema positive/negative unit test、fresh evidence target、checked JSON validation、focused format/analyze、root `make test`、
  隣接`dart_appkit` full test/generic audit、privacy/source review、`git diff --check`。違反時はparserやthresholdを緩めず原因を修正する。

### Versioned content-free evidence／全hard gateの実装結果

- `terminal_note_r0_evidence.dart`を追加し、Dart budgetはexact 5行、actual AppKit／disabled input／real storeは各exact 1行として、
  行順、key順、single trailing LF、CR／空行／追加行0までstrictにparseする。各summaryが`PASS`を名乗るだけでは受理せず、固定M1／
  arm64／16 GiB／Dart 3.13.2／Release AOT、sample／fixture数、frozen threshold、owner 0、content-free claimを再評価する。
- Dart projection p95とnative first-visible p95は別processのまま合算し、100,000 us以下をhard gateにした。Disabled inputは両p95を
  strict 2 ms未満、median ratioを1.05以下、storeは20-run worker commit 250 ms以下／16 MiB primitive 1.5 s以下として再検証する。
- Model、authority、worker、codec、product projection、native projectionの実constantをfrozen literalと照合し、queue／body／file／
  context／Note／trigger／delivery boundの変更をevidence生成失敗にする。
- Rootの`terminal_note_*.dart`、Notes packageのDart、Objective-C／Objective-C++／header計21 sourceを自動inventoryし、
  `Timer.periodic` 0、CV/CADisplayLink 0、one-shot `Timer` 1、store request-timeout allowlist 1を要求する。Source追加時はaggregate
  hashへ自動的に含まれる。
- Version 1 JSONは集約metric、frozen bound、boolean gate、4 input SHA-256、5 benchmark/builder sourceとaudited source aggregateの
  SHA-256だけを保持する。Raw sample、本文、Note/context ID、timestamp、color、trigger instance、absolute/temporary pathは保持しない。
  Checked evidence validatorはexact schema、deterministic pretty JSON、current source hashを再検証する。
- `terminal-note-r0-evidence` targetはnative-assets CLI bundle、actual AppKit binary、disabled Release AOT、real filesystem storeをfreshに
  実行してprivate build logへ分離し、`benchmark/evidence/terminal-note-r0-budget-macos-arm64-m1.json`をatomicに生成する。
- Positive／negative testは、追加／欠落／順序変更／未知key／CR／末尾LF欠落、threshold／environment mismatch、combined budget超過、
  privacy-bearing field、raw sample、source hash偽装、noncanonical JSON、periodic timer／display-link追加、allowlisted timeout欠落を
  fail-closedとして固定した。

Fresh固定authority実測:

- Idle RSS delta 3,211,264 / 16,777,216 bytes、activity／store change／owner 0。
- Model p95 4 / 1,000 us、max 11 / 4,000 us。Dart projection p95 4,670 us。
- Native apply p95 5,394 / 8,000 us、first-visible p95 14,623 us、16.67 ms超stall 0。合算first-visibleは
  19,293 / 100,000 us。
- Hard-cap steady 44,892,160 / 67,108,864 bytes、peak 89,554,944 / 100,663,296 bytes、canonical file 9,698,603 /
  16,777,216 bytes、owner 0。
- Disabled input baseline p95 286 ns、disabled p95 261 ns、median ratio 0.991087 / 1.05、factory 0。Store commit p95
  44,067 / 250,000 us、primitive p95 15,382 / 1,500,000 us。

実装中、最初のfocused testはevidenceに許可されたpolicy key `raw_samples_retained=false`を、禁止するraw sample payload keyと
substringで誤認して停止した。Privacy条件は緩めず、禁止対象をexact JSON key `"raw_samples":`へ修正した。同じpositive／negative
suiteの再実行はpassした。

検証結果:

- `dart analyze tool/terminal_note_r0_evidence.dart test/terminal_note_r0_evidence_test.dart test/run_tests.dart`: `No issues found!`。
  Focused positive／negative suiteとchecked JSON replayはpassした。
- `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 terminal-note-r0-evidence`: pass。上記fresh値からversion 1 evidenceを
  atomic生成し、machine summaryは`combined_first_visible_us=19293`、periodic timer／display-link 0、request timeout 1を報告した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。389 Dart filesはformat済み、root analyzeは`No issues found!`、新しい
  evidence schema／negative test、R0 hidden harness、20-run real store acceptance（commit p95 48,495 us、primitive p95 21,012 us）、
  release-candidate daily-use matrixを含む。Matrix再生成差分はMakefileと`test/run_tests.dart`のSHA-256だけである。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: pass。
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、Dart Terminal固有code追加0。既存未commit変更3件
  （`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、`scripts/build_dart_engine.sh`）は変更もstageもしていない。
- `git diff --check`: pass。Build配下の4 raw logはcheck-inせず、versioned content-free aggregateだけを追跡する。

Versioned evidence／全hard gateの個別完了条件を満たした。これによりhard resource/latency budget親項目も完了し、次は順番どおり
named aggregateとarm64/x86_64/Universal auditを接続する。

## サブタスク3: named aggregateとcross-architecture audit

### 分割、目的、範囲、完了条件

この項目は、先にbundle間の等価性を独立して証明し、その証拠を後段のnamed aggregateが必須入力として束ねる依存関係があるため、
実装前に次の2項目へ分割する。各項目を個別に検証、ROADMAP更新、commitし、前項目を完了するまで後項目へ進まない。

1. **Versioned cross-architecture Note capability/resource equality audit**
   - 目的: Freshなhost Developer JIT、arm64／x86_64 thinとUniversal Release AOT bundleで、Notes capability ABI v1、neutral resource
     bytes、Universal architecture/code inventoryがexactに一致し、audited manifest／neutral resource／evidenceのbody／ID／time／absolute
     path sentinel 0であることをmachine-checkableにする。
   - 範囲: 4 bundleのstrict manifest、Notes capability宣言、thin manifest SHA-256 ownership、neutral resource path/bytes/SHA-256、
     framework/helper Notes dylib architecture、content-free version 1 JSON、positive／negative unit test、fresh cross-build/audit target。
   - 対象外: Intel host上のnative execution claim、M1 budgetのx86_64への転用、manual UX、R0 stage decision、署名／notarization、
     `dart_appkit`へのDart Terminal固有code追加。
   - 依存: Existing runtime builder、Universal assembler、`dart_only_bundle_audit.dart`、Notes manifest ABI v1、直前のbudget evidence。
   - 完了条件: Developer JIT／arm64／x86_64のneutral resource inventory/hashが同一、Universal `resourceFiles`がそのexact集合、
     Notes declarationが4 application contractで同一、thin Notes imageは各1 architecture、Universalは2 architecture、全sentinel 0。
     Mismatch、extra、missing、unknown key、unsafe path、hash driftはfail closedとする。
   - 検証: Parser/schema positive/negative、fresh thin/Universal build、existing 3 bundle audit、new audit/evidence、format/analyze、root
     `make test`、隣接`dart_appkit` full test/generic audit、`git diff --check`。
2. **R0 named aggregateへのfull gate inventory接続**
   - 目的: Pure/codec/fault/native/product/sanitizer/privacy/source/shell/restoration/budget/runtime/distribution/cross-architectureを
     一つの明示名targetからfail-fastで実行し、R0 automated qualificationの唯一のentry pointにする。
   - 範囲: Existing gateの依存接続、fresh checked evidence検証、Developer JIT／Release AOT S1/S2、runtime verify、distribution verify、
     content-free exact machine summary、aggregate contract test。
   - 対象外: Manual checklistのpass宣言、R0 promotion decision、R1 option/public surface、重複する実装test logicのコピー。
   - 完了条件: Named targetが必須gateを省略せず、成功時だけexact summaryを一行出し、既存target／evidenceの失敗を隠さない。
   - 検証: Aggregate inventory unit test、fresh named target、root `make test`、隣接generic audit、差分review。

### Cross-target helper native-assets mapping阻害と追加分割

最初のfresh 4 bundle targetは、Developer JITとarm64 Release AOTのbuild／既存bundle auditまではpassしたが、x86_64 Release AOTの
helper snapshot生成前に`Dart helper native asset mapping has no target architecture`で停止した。生成済みhelper bundle内の5 dylibは
すべて`x86_64`であり、失敗原因はbinary architectureではない。Dart SDKの`dart build cli --target-arch=x64`はtarget imageを正しく
生成する一方、project rootの`.dart_tool/native_assets.yaml`をhostの`macos_arm64` mappingのまま残す。汎用runtime builderは同fileに
`macos_x64`が存在することだけを受理していたため、target imageが揃っていてもasset IDからbundle leafへの対応を構成できなかった。

検討した選択肢:

- Root側でmappingを書き換える案は、runtime builder自身が内部で`dart run`と`dart build cli`を実行する間に挿入できるhookがなく、
  appごとのworkaroundにもなるため不採用。
- Staleな既存x86_64 bundleをauditする案は、freshnessとcross-build gateを偽るため不採用。
- Target ABI不在時に複数architecture mappingから推測する案は、asset IDの所有元が曖昧になるため不採用。
- Target ABI不在かつmappingがexactly one architectureだけの場合、そのmapをarchitecture-independentなasset ID／leaf templateとして
  読み、実際にtarget buildが生成した`nativeImages`全件とのexact coverageを確認した上で、出力をrequested target ABIに固定する案を
  採用する。Target dylib architectureの生成／bundle auditは従来どおり独立して検証する。

この阻害はNoteやDart Terminal固有ではなく、native assetを使う任意のDart helperのcross-target buildに生じる汎用runtime問題である。
したがって現在のequality auditを次の順に追加分割し、前項を完了・commitするまで後項へ進まない。

1. **汎用runtime builderのcross-target helper native-assets mapping修正**
   - 目的: Host ABIだけを残す現行Dart SDK出力からでも、requested target向けhelper native-assets configurationを安全かつ決定的に生成する。
   - 背景: Fresh x86_64 buildはtarget dylibを生成済みだが、root mappingにtarget ABI keyがないため停止する。
   - 範囲: `dart_macos_runtime` builderのgeneric fallback、single-map／exact coverage／canonical target ABI、positive／negative test。
   - 対象外: Note capability名、Dart Terminal manifest／resource、app固有path、複数mapping間の推測、binary architecture監査の緩和。
   - 依存: Existing helper native-assets bundling、target-specific Dart SDK、生成済みtarget `nativeImages`。
   - 完了条件: Exact target mappingは従来どおり優先し、target不在時はsingle source mapだけを受理してtarget imageのexact leaf集合をcoverし、
     emitted JSONはrequested ABIだけを持つ。Zero／multiple candidate、malformed／missing／extra coverageはfail closedを維持する。
   - 検証: Focused builder tests、full `dart_appkit` testとgeneric repository audit、app固有語0、既存user変更非接触、fresh x86_64 build。
2. **Fresh 4 bundle equality auditとversioned evidence完了**
   - 目的、範囲、対象外、依存、完了条件は直前のcross-architecture audit定義を継承する。
   - 追加完了条件: Developer JIT、arm64／x86_64 thin、Universalを修正後にすべてfresh生成し、stale bundleを入力にしない。
   - 検証: 4 bundle target、new evidence checked replay、focused/full root tests、隣接full generic audit、privacy/source/diff review。

### 汎用cross-target helper mapping修正の完了結果

- `dart_macos_runtime`はrequested ABIのmappingを従来どおり最優先する。Target ABI keyが存在しない場合だけ、mapping全体がexactly one
  entryで、そのkeyが`macos_arm64`または`macos_x64`、valueがasset mapである場合に限ってasset ID／bundle leaf templateとして使う。
  出力configurationはsource keyを引き継がず、requested ABI keyだけを持つ。
- Template内の各entryは従来のstrict two-string tuple検査を通し、実際のtarget buildが生成した`nativeImages`のleaf全件をcoverしなければ
  failする。Target keyのmalformed value、empty map、target不在のzero／multiple／unsupported source mapはfail closedである。
- Test fakeにsource ABI overrideと追加architectureを導入した。既存x86_64 cross-target testは、実環境と同じくroot mappingを
  `macos_arm64`だけに残した状態から、emitted configurationが`macos_x64`だけになることを検証する。別testはtarget不在で2 mapある
  ambiguous入力を`builderSoftwareExitCode`で拒否する。
- Product名、Note contract、app manifest／resource、app固有pathは`dart_appkit`変更へ追加していない。実装commitは隣接repositoryの
  `f8d7dfe21c2ed58cded4a7058027d573c9e872c7`（`Support cross-target helper native assets`）。

検証結果:

- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-dart-test` in `../dart_appkit`: analyze `No issues found!`、builder、Universal、
  distribution publisherの全test pass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make release-aot-x86_64-audit`: fresh target helper／application native-assets buildが各5 assetを生成し、
  `DART_ONLY_BUNDLE_AUDIT_PASS mode=release-aot architecture=x86_64 helpers=1 assets=1 helper_assets=5 capabilities=3`。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: full pass、
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`、generic source内のDart Terminal固有語0。
- `dart format`は0 changes、appkitのstaged diff checkもpass。既存未commit変更3件
  （`docs/BUILDING_DART_ENGINE.md`、`scripts/bootstrap_dart_engine.sh`、`scripts/build_dart_engine.sh`）は変更もstageもしていない。

汎用mapping修正の個別完了条件を満たした。次はROADMAPを再確認し、fresh 4 bundle equality auditとversioned evidenceを完了する。

### Fresh 4 bundle equality auditの実装・検証経過

- Product-local auditor、positive／negative suite、Make targetを追加した。AuditorはDeveloper JIT arm64、Release AOT arm64／x86_64／
  Universalの4 bundleを入力に、strict manifest、release application contract、Notes ABI v1 declaration、framework/helperの2 Notes image、
  thin manifest ownership、neutral resource path／byte／Universal evidence、content／ID／time／absolute-path sentinelをfail closedで照合する。
- Version 1 evidenceは4 manifest hash、auditor source hash、Notes capability、resource count／aggregate byte／aggregate hash、architecture count、
  boolean gateだけを保持し、resource path／raw content／build pathは保持しない。Checked validatorはexact schema、source hash、canonical JSONを
  再検証する。
- Fresh targetはDeveloper JIT、arm64 thin、x86_64 thin、Universalをすべて再生成し、既存bundle audit 4件とnew auditをpassした。
  New machine lineは`resources=21 resource_bytes=1388080 note_images=8`、sentinel／absolute path 0、content-free trueだった。
- 最初のroot `make test`は、変更したMakefileとaggregate test registryをまだ反映していない
  `compatibility/release_candidate_daily_use_matrix.json`をstaleとして検出して停止した。Product test failureではなく、正規generatorで
  source hash chainを更新してから同じaggregateを再実行する。Matrixを直接編集せず、受け入れ条件も変更しない。

### Fresh 4 bundle equality auditの完了結果

- `tool/terminal_note_r0_architecture_audit.dart`はthin schema version 1とUniversal schema version 2のtop-level keyをexactに固定し、
  Release contractはarchitecture固有App Intents target tripleとlibrary byte countだけを正規化してarm64／x86_64／Universalで照合する。
  Universal top-level contract、sorted code inventory、両thin manifest SHA-256 ownershipも同時に検査する。
- Notes capabilityは4 contractすべてでpackage／library／ABI version／ABI symbol／initializerをexact照合し、framework imageとhelper imageを
  各bundleで要求する。`lipo -archs`結果はDeveloper JIT／arm64 thinがarm64、x86_64 thinがx86_64、Universalが両sliceでなければ
  failする。
- Bundle全fileをsymlink非追従、case-fold duplicate拒否、file／aggregate size bound付きで列挙し、manifest-declared code imageと署名を除く
  neutral resource 21 file／1,388,080 bytesを4 bundleでpath・byte exact照合した。Universal `resourceFiles`のsorted path／size／SHA-256も
  同じinventoryへbindした。
- Positive／negative suiteはdeterminism、unknown manifest key、Notes capability欠落／ABI drift、Release contract drift、thin ownership、
  resource byte／extra file／Universal hash drift、thin／Universal image architecture、architecture order、body sentinel、absolute path、
  checked schema／source hash／gate／canonical JSONをfail closedとして固定した。
- Checked-in evidenceは
  `benchmark/evidence/terminal-note-r0-architecture-macos.json`。4 manifestとauditor sourceのSHA-256、Notes ABI、resource aggregate、
  architecture count、boolean gateだけを保持し、resource path、raw content、build path、timestampは保持しない。

Fresh実測／検証結果:

- `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 terminal-note-r0-architecture-audit`: Developer JIT、arm64／x86_64 thin、
  Universalをfresh生成し、既存4 bundle auditがすべてpass。New exact summaryは
  `TERMINAL_NOTE_R0_ARCHITECTURE_PASS version=1 bundles=4 resources=21 resource_bytes=1388080 note_images=8 architectures=arm64,x86_64,universal capability_abi=1 sentinels=0 absolute_paths=0 content_free=true`。
- Focused `dart analyze`は`No issues found!`。Formatterは3 files／0 changes。Focused positive／negative suiteとchecked evidence replayはpass。
- 正規`make release-candidate-daily-use-matrix`はMakefileと`test/run_tests.dart`のSHA-256だけを更新した。再実行した
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`はpass。391 Dart files／0 format changes、root analyze issue 0、new architecture suite、
  R0 hidden harness、store acceptance（commit p95 45,434 us、primitive p95 14,641 us）、security／distributionを含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` in `../dart_appkit`: full pass、
  `GENERIC_REPOSITORY_AUDIT_PASS paths=148 text_files=147`。Dart Terminal固有code追加0。既存user変更3件は非接触。
- `git diff --check`、checked evidenceのcontent／ID／time／absolute-path sentinel scan、debug/TODO scanはpass。Raw build outputは追跡せず、
  versioned content-free evidenceだけを追加した。

Fresh 4 bundle equality auditと親のversioned cross-architecture auditの完了条件を満たした。次はROADMAPを再確認し、R0 named aggregateへ
full gate inventoryを接続する。

### R0 named aggregateへのfull gate inventory接続の着手条件

- 目的: R0 automated qualificationの唯一のentry pointを設け、既存gateの一部だけを実行してR0 passと誤認できないようにする。
- 範囲: 次の8 gateをexact order／重複なしのinventoryとして一つのserial recursive Make graphへ接続する。
  1. Fresh budget evidence
  2. Fresh cross-architecture equality evidence
  3. Native Note acceptance
  4. S1 product acceptance
  5. S2 product acceptance
  6. Sanitizer／fuzz／fault aggregate
  7. Full Developer JIT／Release AOT runtime verify
  8. arm64／x86_64／Universal distribution verify
- Evidence checker: Aggregate終了時にversioned budget／architecture evidenceをcurrent sourceで再検証し、Makefileの8-gate inventory、`-j1`、
  final checker invocationをexact contractとして検証する。成功時だけcontent-freeな固定summaryを一行出す。
- 対象外: Manual IME／keyboard／VoiceOver／appearance／TUIのpass、R0 stage decision、R1 promotion、既存gate logicの複製、
  `dart_appkit`への製品固有code追加。
- 依存: 完了済みR0 harness、budget evidence、cross-architecture evidence、S1／S2 named acceptance、既存runtime／distribution graph。
- 完了条件: Missing／extra／duplicate／reordered gate、parallel execution、checker欠落、stale／malformed evidenceをfail closedとし、fresh named targetが
  全graph完了後にexactly one final R0 summaryを出す。Manual／promotion claimはfalseのままにする。
- 検証: Aggregate inventory positive／negative test、focused format/analyze、fresh named target、root `make test`、隣接`dart_appkit` full generic
  audit、content-free outputとstaged diff review。

検討した選択肢:

- `runtime-verify`だけを別名で公開する案は、R0固有budget、cross-architecture evidence、native Note aggregate、S1／S2 named summaryを
  必須化できないため不採用。
- 各testを新targetへ再列挙する案は、既存ownerと将来の追加を二重管理するため不採用。
- 既存named gateを単一recursive Make invocationへ列挙し、Make dependency graphで共有前提をdeduplicateする案を採用する。

最初のfocused negative testは、parallel mutationがR0 targetではなく同じ`make -j1`断片を持つ既存release-candidate targetの先頭一致を
書き換えたため、期待したrejectが発生せず停止した。Validatorのfail-closed条件は正しく、test fixtureのmutation scopeが原因である。
置換対象をR0 target headerとrecipeの組へ限定し、他targetを変更してもR0 contract testが誤ってpassしない形へ修正する。

最初のfresh named aggregateはbudget evidenceと4 bundle cross-architecture auditをpassした後、3番目の`terminal-notes-acceptance`が依存する
`product-native-sanitizer`のPTY suiteで停止した。Allocation fault recoveryはpassしたが、foreground snapshotが期待33 memberに対して25となり、
その後のsignal、UTF-8、high-watermark、burst、exit／reap／owner回収assertionが連鎖失敗した。Aggregateはfinal summaryを出さずexit 2で
fail closedした。Gateの省略、threshold変更、成功扱いは行わず、isolated sanitizer再実行、process fixture／resource cleanup、再現性を
現在task内で調査する。

Isolated再実行でもtotal 28／33で同じ失敗を再現した。失敗後のprocess tableにはsanitizer test、test-owned zsh、`sleep 30`の残留は0で、
前回runのleakやsystem process exhaustionではない。Fixtureはforeground process groupがchild groupと異なった時点だけでstartup完了とみなし、
33-process pipelineの全memberが`libproc`観測可能になる前に64回のsnapshot benchmarkを開始していた。ASan/UBSan buildではspawnと観測が
遅くなり、25〜28 memberの途中snapshotを最終値として検査した後、33-process jobへSIGINTを送る前提が崩れて後続操作が連鎖失敗した。

検討した選択肢:

- 33を25〜28へ緩和する案はhard capのomission境界を検証できなくなるため不採用。
- Sanitizer gateからPTY suiteを除く、またはretryで隠す案はnative ownership／fault gateを弱めるため不採用。
- Production snapshotを33になるまでblockさせる案はnon-blocking APIの契約を変えるため不採用。
- Test fixtureだけがbounded deadline内で`total_member_count >= 33`を観測してからlatency sampleへ進む案を採用する。Production APIは各時点の
  valid snapshotを返すままとし、readiness待ちはfixture ownerに限定する。

Named aggregateを次の順で追加分割し、前項を個別検証・commitするまで後項を完了にしない。

1. **PTY sanitizerのlarge-pipeline readiness race除去**
   - 範囲: Product-owned PTY native acceptance fixtureのbounded readiness waitとfocused sanitizer／通常test。
   - 対象外: Production PTY code、process cap、33-process fixture、5 ms threshold、retry、`dart_appkit`。
   - 完了条件: 33 total／32 retained／1以上omittedをsample前に確認し、通常／ASan+UBSanで後続signal・burst・exit・owner 0までpassする。
2. **Serial 8-gate inventoryとfinal evidence checker完了**
   - 元のnamed aggregate着手条件を継承し、修正後のfresh aggregateをretry wrapperなしで先頭から完走させる。

### PTY sanitizer large-pipeline readiness raceの修正・検証

- Product codeとsnapshot APIのnon-blocking契約には変更を加えず、`PtyCapabilityTests.cc`の33-process fixtureだけに3秒のbounded
  readiness waitを追加した。Benchmark sample前にsnapshotがAVAILABLE、retained member 32、total member 33、omitted memberが
  `total - retained`であることを要求する。
- 33-process fixture、32-process hard cap、64回のlatency sample、p95 5 ms threshold、後続のsignal／UTF-8／burst／exit／reap／owner
  検証は変更していない。Deadline内にreadyにならなければtestは従来どおりfail closedする。
- `CI=true DART_SUPPRESS_ANALYTICS=true make dpty-native-test`はpass。Large pipelineはtotal 33／retained 32、p50 272 us、
  p95 316 usで、全PTY capability testが完走した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make product-native-sanitizer`はpass。PTY、renderer、AppleScript、App Intents、Notesの
  5 suiteと11 artifactが完走し、exact final lineは
  `PRODUCT_NATIVE_SANITIZER_PASS suites=5 artifacts=11 asan_artifacts=11 ubsan_artifacts=9 architecture=arm64`だった。
- 同じ`product-native-sanitizer`をretry wrapperなしで独立してもう一度実行し、同じsuite／artifact countとexact final lineで再度passした。
  Readiness不足で25〜28 memberを観測していた失敗は2連続のsanitizer runで再発せず、後続検証も連鎖失敗しなかった。
