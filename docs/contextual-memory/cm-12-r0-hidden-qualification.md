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
