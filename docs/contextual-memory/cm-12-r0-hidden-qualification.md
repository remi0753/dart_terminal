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
