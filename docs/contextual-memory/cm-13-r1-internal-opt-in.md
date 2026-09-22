# CM-13 R1 internal S1/S2 opt-in

日付: 2026-09-22<br>
状態: R1 automated subtask完了。次はpersistent store manual checklistとR1 stage decision。manual／stageへは未着手。

## 目的

R0 hidden qualificationを通過したS1 Basic memoryとS2 On Returnを、明示的に
`notes=true`へ設定したinternal buildだけで実データstoreへ接続できるR1候補として受け入れる。
S3は無効のまま維持し、問題時にはstoreを変更せずlocal configとrestartだけでNotes全体を停止できることを
実利用環境で再確認する。

## 背景

CM-12ではtemporary storeを使うhidden/default-off候補について、pure/codec/fault/native/product、
resource/latency、architecture、privacy、manual IME/keyboard/VoiceOver/appearance/TUIの各gateを完了した。
R1では機能仕様を増やさず、internal audienceだけがtyped configを通じて実データstoreを使う運用境界と、
data-preserving rollback/recoveryを成立させる。

## 対象範囲

- internal buildでtyped `notes=true`を明示してS1/S2を起動する経路
- `notes-next-prompt=false`を固定したR1 candidateと実データstore preview
- Developer JIT / Release AOTのfresh internal candidate
- store/restore、64 pane、IME/TUI、manual checklist、kill switch、全resource回収
- on→off restart、store lock/corrupt/newer、native capability missing、pre-Notes binary rollback/re-upgrade
- internal runbook、data recovery/export手順、本文を含まない結果記録、明示的なR1 stage decision

## 対象外

- public configuration reference、public Settings、一般利用者向けpreview文書
- `notes`のdefault-on、S3 At Next Prompt、shell integration version 3
- telemetry、background upload、remote feature flag
- storeの自動reset、rollbackを利用したdata migration、本文を含む診断・証跡

## 依存関係

- CM-12 R0 hidden qualification（commit `55b842f`）
- Gate 7のtyped option、disabled lifecycle、store/restoration/native ABI、rollout/rollback凍結仕様
- CM-10 S1、CM-11 S2のDeveloper JIT / Release AOT product acceptance

## 完了条件

- internal buildだけでtyped `notes=true`を使用でき、通常releaseはdefault-offかつuser-visible entryなしを維持する。
- R1候補は実データstoreを使い、S1/S2だけを有効化し、S3 launch/event/resourceを開始しない。
- Gate 7 R1のJIT/AOT end-to-end、store/restore、64 pane、IME/TUI/manual、kill switch、全resource回収が通る。
- 指定rollback/recovery vectorでwrong-context、data loss/corruption、body/privacy leak、unintended PTY byte、
  geometry change、false/lost/duplicate delivery、hard invariant violationが0である。
- internal runbook、recovery/export手順、content-free evidence、明示的なstage decisionを残す。
- 必要な検証、文書、ROADMAP更新を完了し、このtaskまたは分割した各subtaskを個別にcommitする。

## 検証方針

- 既存R0 aggregateを基準にし、R1専用fixtureはtyped configと実store/rollback境界だけを追加する。
- pure/config/store/restoration/native/productのfocused testを先に実行し、fresh JIT/AOT candidateで統合確認する。
- 64 pane、実IME/TUI、native capability missing、lock/corrupt/newer、on→off、pre-Notes rollback/re-upgradeを
  内容非保持のcount/state/hashだけで記録する。
- disabled/off runではstore read/write/lock/delete、Note native surface、context bindingが0であることを確認する。
- 最後にfull gate、format/analyze、diff/privacy/source/resource auditを実行する。

## サブタスクと実施順

1. **typed internal launch profileと実データstore preview境界を固定する**
   - 通常と同じfresh Developer JIT / Release AOT bundleへ、通常のtyped resolverを通る
     `notes=true`、`notes-on-return=true`、`notes-next-prompt=false`を最高優先度で与えるinternal profileを固定する。
   - Default-off、internal-only exposure、通常catalog entry 0を変えず、profileのS1/S2 enabled、S3 disabled、
     `nextLaunch` policy、実データstore locationを自動検証する。
   - 完了条件: 別schema、compile-time flag、environment feature authorityを作らず、fresh candidateの構成を
     content-freeに再現でき、focused test、format/analyze、既存config/R0 gateがpassする。
2. **data recovery/export、kill switch、rollback rehearsalとinternal runbookを完了する**
   - 実filesystem/workerでon→off restart、lock contention、corrupt/newer store、native missing、portable export、
     pre-Notes exact/mismatch re-upgradeを一つのcontent-free R1 rehearsalへ固定する。
   - Storeの標準location、backup/raw-file保全、consented portable export、soft/binary rollback、再有効化をinternal runbookにする。
   - 完了条件: Off/newer/corrupt/native-missing/pre-Notes経路によるstore mutation 0、exactだけreattach、
     mismatchはDetached、wrong attach/data loss/privacy leak/owner leak 0を自動検証する。
3. **R1両runtime、64-pane、manual aggregateとstage decisionを完了する**
   - Fresh internal profileでDeveloper JIT / Release AOTのS1/S2 end-to-endを実行し、R0の64-pane hard gateと
     architecture/resource/privacy/bundle/fault gateをR1 named aggregateへ接続する。
   - 実IME、keyboard-only、VoiceOver、appearance、alternate-screen/Vim/Codex/mouse TUIをinternal store候補で再確認する。
   - 完了条件: aggregateとmanual checklistがpassし、hard invariant violation 0、全resource回収、content-free evidence、
     明示的なR1 stage decisionを記録してCM-13を完了する。

## 着手時の確認事項

- `ROADMAP.md`の先頭未完了はCM-13であり、CM-14以降へ先行しない。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、Gate 7 rollout仕様、implementation planのCM-13を確認した。
- 作業branchは`codex/contextual-memory-design`、着手時のroot worktreeはcleanである。
- sibling `dart_appkit`には利用者の既存変更があるため触れない。新規汎用capabilityが必要な場合も、
  Dart Terminal固有codeを`dart_appkit`へ入れず、application側からparameterを注入する。

## 調査ログ

### 2026-09-22 — 仕様境界

- R1は機能追加stageではなく、既存S1/S2をinternal audienceで実データstoreへ接続するopt-in stageである。
- stage promotionはcode mergeだけでは成立せず、本memoにevidenceと明示decisionを残す必要がある。
- soft rollbackはlocal configをoffにしてrestartし、off pathはstoreへ一切触れない。
- pre-Notes binaryはrestoration v1を通常どおり読みNote storeを無視する。再upgradeではexact hash matchだけを
  reattachし、rollback中にlayoutが変わった場合はDetachedへ送る。
- newer/unknown storeはread/write/downgrade/resetせず、compatible appへ戻るまでunavailableとする。

### 2026-09-22 — 既存実装と分割判断

- 4つのNote optionは既に通常のfile/CLI resolverに含まれ、`notes` default false、`notes-on-return` default true、
  `notes-next-prompt` default false、`notes-font-size` default 15である。全て`internalPreview` exposureで、generated public
  configuration catalogだけが除外する。`--show-config`を含むtyped resolution自体は通常pathを使う。
- Production compositionは`notes=true`の場合だけnative capability、store location、runtime worker、authorityを起動し、
  `XDG_STATE_HOME/dart-terminal/notes`を優先して、未設定時は
  `HOME/Library/Application Support/Dart Terminal/Notes`を使う。Disabled branchはfactoryを呼ばない。
- Interactive applicationはproduct runtime processへstore operationを委譲する`TerminalNoteProcessStoreFactory`を使い、
  Note/context IDは同じ汎用runtime lifecycleへ注入したentropy sourceから生成する。
- R0 aggregateは64 pane/64 surface idle、real filesystem、native AppKit、JIT/AOT、arm64/x86_64/Universal、privacy、
  sanitizer/fuzz/faultを既にnamed gate化している。R1はこれを緩めず、typed internal profileとpersistent rehearsalを追加する。
- S1/S2 runtime vectorは実product composition、store worker、exact restoration、TUI/focus、resource cleanupを既に両runtimeで通す。
  R1では同じbundleを明示profileで起動し、stage固有のconfig/store/rollback証跡を追加する。
- 既存build systemにinternal binary variantはない。Gate 7はinternal preview、test CLI、normal releaseの全てが同じtyped
  resolutionを使い、hidden environment variableを別authorityにしないと定めている。このため、別bundleやcompile-time
  feature flagを作る案は不採用とした。Fresh通常bundleとexact typed launch profileの組をinternal candidateとする。
- `notes=true`をschema defaultへ変更する案はR3を先行するため不採用。Notes optionをpublic reference/Settingsへ出す案も
  R2を先行するため不採用。R1 runbookは`docs/contextual-memory/`内のinternal資料に限定する。
- CM-13はconfig/build profile、durable recovery/operation、runtime/manual promotionという独立したfailure boundaryを持つため、
  上記3サブタスクへ分割し、ROADMAPへ依存順で登録した。個別bug修正項目はROADMAPへ追加しない。

### 2026-09-22 — typed internal launch profileとcandidate境界完了

#### 実装と判断

- `TERMINAL_NOTE_R1_INTERNAL_ARGUMENTS`をMakefileのsingle sourceとして追加し、引数順を
  `--notes=true`、`--notes-on-return=true`、`--notes-next-prompt=false`へ固定した。通常のfile/CLI resolverを
  そのまま使用し、compile-time flag、environment feature flag、別schema、別bundle identityは追加していない。
- `tool/terminal_note_r1_internal_profile.dart`は、profile引数とMake targetのexact inventory、CLIがconflicting file値へ
  勝つこと、3 flagの`nextLaunch`/`internalPreview`、Note fontの`live`/`internalPreview`、S1/S2 enabled、S3 disabledを
  fail closedで検証する。
- 同checkerはnormal defaultがoff、generated public config option 0、normal action catalogのNote entry 0であり、
  enabled catalogにだけ3 actionが存在することも検証する。R2/R3のpublic exposure/default変更は行っていない。
- 実データstore previewのlocation contractとして、安全な`XDG_STATE_HOME`を優先し、未設定時はmacOS Application Supportを
  使う既存product resolverを検証した。Machine lineにはpath、本文、ID、時刻を出さず、location classだけを記録する。
- `contextual-memory-r1-internal-candidate-build`はprofile checkerの後にfresh sourceからDeveloper JITとRelease AOTを
  build/auditする。Candidateは「通常と同じaudited bundle + exact typed profile」であり、build時やchecker実行時に
  Note storeを開かない。
- Positive/negative unit testはmissing/reordered argument、S3 enable、runtime build order driftを拒否する。
  Root aggregate runnerへ追加し、release-candidate matrixは正規generatorでMakefileとrunnerのSHA-256だけを更新した。
- 新規codeは`dart_terminal`のtool/test/build orchestrationだけである。Sibling `dart_appkit`へDart Terminal固有code、
  profile、store path、feature stateを追加していない。

#### 検証と試行記録

- Focused profile test: pass。Exact machine lineは
  `TERMINAL_NOTE_R1_INTERNAL_PROFILE_PASS version=1 ... content_free=true`。
- Focused analyzer: 更新tool/testともissue 0。
- `make contextual-memory-r1-internal-profile-check`: pass。
- `make contextual-memory-r1-internal-candidate-build`: Developer JIT / Release AOTのbuildとbundle auditがpass。
  両modeともhelper 1、application native asset 1、helper asset 5、native capability 3、localization 8を維持した。
- `make test`: 395 Dart fileのformat変更0、root/packages analyze issue 0、native Notes、store実filesystem、R0 hidden
  harness、privacy、compatibility、distributionを含む全回帰が`dart_terminal tests passed`で完了した。
- 最初のsandbox内focused runとMake runは、通常のMetal module cacheおよびDart telemetry session fileへ書けず、
  test本体前に停止した。許可済みの通常cache環境で同一commandを再実行してpassしたため、product failureではない。
- 最初のfull testは新しいMakefile/runner hashによりdaily-use matrix freshnessだけで停止した。正規generatorは
  `Makefile`と`test/run_tests.dart`のhashだけを更新し、program/workflow/gate count、既知差分、release blockerを変えていない。
  Regenerate後のfull testはpassした。
- `git diff --check`: pass。Sibling `dart_appkit`の着手前3変更はそのままで、本サブタスクによる差分0。

#### 次への引き継ぎ

- 次の先頭未完了はdata recovery/export、kill switch、rollback rehearsalとinternal runbookである。
- Candidate profileは`terminalNoteR1InternalArguments`とMake変数で共有できる。次のrehearsalはこれを再定義せず、
  real filesystem/workerへ接続し、off/native-missing/corrupt/newer/pre-Notes経路のstore byte不変を固定する。
- Candidate buildは個人のApplication Support storeを開いていない。実storeを使う手動previewの開始・停止・backup/exportは
  次のinternal runbookで明示し、automationは隔離したabsolute state rootを使用する。

## 着手時の論点（解決済み）

- Internal profileをMake target、versioned descriptor、checkerのどの最小構成で固定すると、手動previewと自動gateの双方が
  同じ引数列を再利用できるか。
- Recovery-required状態のraw-file保全は既存UIに専用actionがないため、R1 runbookでは安全なmanual copyを正本とするか、
  product actionがR1の必須成果物か。Gate 3とCM-13文言を照合して第2サブタスク着手時に決定する。

### 2026-09-22 — runtime／manualサブタスク着手

- **目的:** Exact typed internal profileをfresh Developer JIT／Release AOTのordinary product compositionへ通し、S1／S2、実store、
  64-pane hard bound、IME／TUI／accessibility、全resource回収を一つのR1 stage evidenceとして確定する。
- **背景:** 既存S1／S2 runtime suiteは両modeのproduct vectorを実行するが、integration-only flagだけで起動するためordinary applicationの
  Note coordinatorはdefault-offである。R1では同じsuiteへexact typed profileと隔離したproduction store locationを注入し、actual coordinatorが
  available、surface attached、shutdown後owner 0であることを追加確認する必要がある。
- **対象範囲:** R1専用runtime suite、Developer JIT／Release AOT、S1／S2、shared production store boundary、R0 64-pane budget evidence、
  architecture／privacy／sanitizer／fault／distribution回帰、persistent store manual checklist、stage decision。
- **対象外:** Public option／Settings／guide、default-on、S3、telemetry、別binary variant、`dart_appkit`変更、performance thresholdの再調整。
- **依存関係:** 第1サブタスクのexact profile、第2サブタスクのrehearsal／runbook、fresh R0 8-gate aggregate、既存S1／S2 runtime suite。
- **完了条件:** 両runtimeでexact profileがS1／S2 enabled・S3 disabledのactual product coordinatorを起動し、native surface 1以上、isolated
  production store、clean teardown／owner 0を証明する。Fresh automated aggregateはR0 64 pane／64 surface evidenceを含み、manual claimを
  偽らない。両runtimeのpersistent-store manual matrixがpassし、hard invariant violation 0でR1 pass／failを明示する。
- **検証方針:** まずR1 runtime suiteとfail-closed aggregate checkerをfocused testし、fresh serial aggregateを完走する。次に同じmanual storeを
  Developer JITからRelease AOTへ引き継ぎ、create／persist／On Return／IME／keyboard／VoiceOver／appearance／TUI／kill switchを実AppKitで確認する。
  System settingを変更する場合は開始値を記録し、各case後に復元する。結果は本文、identity、path、timestampを含めない。
- **分割:** 独立したautomated evidenceとmanual／stage decisionを上記2 subtaskへ分けた。前者を検証・commitするまで後者へ進まず、
  個別bug修正項目はROADMAPへ追加しない。

### 2026-09-22 — recovery／rollbackサブタスク着手

- 既存transaction engineは、current破損かつbackup正常時のpayload-preserving recovery preview、明示的な
  `retryRecovery()`、ready／recovery previewからのportable exportをすでに提供する。Store worker protocolにも同じ操作があり、
  public product UIや新しい永続形式を追加しなくてもR1の復旧手順を構成できる。
- Recovery-required（current／backup双方が不正）とupgrade-required（未知のnewer version）はdocumentを公開せず、load中に
  store payloadを変更しない。ここへ自動reset、古いbackupへのfallback、downgradeを足す案はdata lossとforward compatibilityを
  損なうため不採用とした。
- R1の運用面は、アプリを完全終了してlockを解放した後だけ使うinternal store admin toolへ限定する。Statusはdurable payloadを保持し、portable
  exportは本文を含むことへの明示acknowledgement、backup復元はraw-file保全後の明示acknowledgementを要求する。結果はpath、本文、
  Note／context identity、時刻を含まない固定machine lineとする。
- 公開UIへRestore actionを増やす案と、production process protocolにR1専用commandを足す案はCM-14以降のsurface変更を先行するため
  不採用とした。Internal toolは既存の汎用engineをofflineで呼ぶだけとし、`dart_appkit`にはcodeを追加しない。
- 自動rehearsalは個人のApplication Supportを使わず、隔離したabsolute state rootで実isolate workerと実filesystemを使う。
  on→off、native missing、lock、current-only corruption、explicit export／restore、corrupt-both、newer、pre-Notes exact／mismatchを
  同じfixtureで検証し、終了時にtemporary rootを削除する。

### 2026-09-22 — recovery／rollbackサブタスク完了

#### 実装と運用境界

- `tool/terminal_note_internal_store_admin.dart`を追加した。Actionはpayload-preserving status、consented portable export、acknowledged
  backup restoreの3つだけで、absolute path、exactly-one action、action固有acknowledgementをfail closedで検証する。結果は
  source state、outcome、durable payload mutation有無だけを持つ固定machine lineで、本文、identity、path、時刻を出さない。
- Statusはloaded／empty／recovery-preview／recovery-required／upgrade-requiredを分類する。Exportはloaded／empty／
  recovery-previewだけ、restoreはrecovery-previewだけを許可する。Locked、corrupt-both、newer、unsafeは上書き、reset、古いcopyへの
  fallbackを行わない。Portable fileだけは明示した外部destinationへ書き、内部ID、timestamp、revision、context bindingを除外する。
- `tool/terminal_note_r1_rehearsal.dart`はexact typed profileからS1／S2 enabled、S3 disabledを再確認し、隔離した実state rootへ
  dedicated isolate workerで2 revisionをcommitする。その同じstoreでlive lock拒否、worker stop完了、on→off kill switch、native capability missing、
  pre-Notes exact reattach／layout mismatch Detachedを検証した。
- Rehearsalは別fixtureでcurrent-only corruptionをpayload-preserving recovery previewとして開き、portable export、raw payloadのexact copy、
  acknowledged backup restore、実workerからの再読込を完走する。Corrupt-bothとnewer-current＋valid-old-backupは分類だけ行い、payload byteを
  変えない。全temporary artifactをfinallyで削除し、composition／authority／worker／product owner差分0を要求する。
- `contextual-memory-r1-rehearsal`を正式Make入口へ追加し、typed profile checkを依存にした。Root test runnerにもpositive rehearsalと、
  relative path、ack不足、multiple action、irrelevant acknowledgementを拒否するnegative testを接続した。
- Internal運用手順は
  [`cm-13-r1-internal-runbook.md`](cm-13-r1-internal-runbook.md)へ固定した。Standard store location、アプリ完全終了、raw backup先行、
  sensitive export、明示restore、soft kill switch、再有効化、pre-Notes rollback／re-upgrade、停止条件を含む。Public reference、Settings、
  telemetry、import、自動resetは追加していない。
- 新規codeと文書は`dart_terminal`内に限定した。Sibling `dart_appkit`の汎用境界へDart Terminal固有のfeature、path、tool、parameterを
  追加していない。

#### 検証と試行記録

- Focused formatter: 3 fileをformatし、その後変更0。Focused analyzer: issue 0。
- `dart run test/terminal_note_r1_rehearsal_test.dart`: pass。実filesystem／isolate worker、lock、recovery、export、restore、rollback、
  cleanupとCLI validationを完走した。
- `make contextual-memory-r1-rehearsal`: pass。Profile checkerに続いて
  `TERMINAL_NOTE_R1_REHEARSAL_PASS version=1 ... wrong_attach=0 unintended_payload_changes=0 privacy=1 owners=0 temp_cleanup=1 content_free=true`
  を出力した。
- `make test`: 398 Dart fileのformat変更0、root／package analyze issue 0、native Notes、real filesystem store、R0 harness、privacy、
  compatibility、distributionを含む全回帰が`dart_terminal tests passed`で完了した。Store acceptanceを含む既存performance checkも
  現行の許容範囲でpassしたため、性能follow-upを追加していない。
- 最終diff reviewで、status loadがlock取得とengine-owned pending cleanupを行い得ることを明記し、結果名をstore全体のread-onlyではなく
  `payload_mutation`へ限定した。Worker stop結果も明示検証へ加えた。この修正後にfocused format変更0、analyze issue 0、focused test、
  正式Make rehearsalを再実行して全てpassした。
- 最初のfocused Dart dev commandと最初のMake rehearsalは、sandboxから共有Dart telemetry session fileのmtimeを更新できずtest本体前に停止した。
  通常のcache環境で同じcommandを再実行してpassしており、product／test failureではない。
- 正規generatorでrelease-candidate daily-use matrixを更新した。差分は`Makefile`と`test/run_tests.dart`のSHA-256だけで、program、
  workflow、gate、known limitation、release blockerは変えていない。`git diff --check`もpassした。
- Sibling `dart_appkit`の着手前3変更はそのままで、本サブタスクによる差分0。

#### 次への引き継ぎ

- 次の先頭未完了はR1両runtime、64-pane、manual aggregateとstage decisionである。Fresh candidateへ今回のexact profileとrehearsalを
  接続し、R0 hard gateを再利用してから実internal storeでmanual matrixを実施する。
- `recovery-required`／`upgrade-required`はR1 stageを停止する運用条件のままである。自動resetやpublic recovery UIは次サブタスクへ
  持ち越さない。

### 2026-09-22 — R1 automated qualification実装・両runtime確認

- `runtime_integration_smoke.dart`へR1専用suiteを追加した。既存S1／S2 product vectorを順番どおり再利用し、各起動へexact
  `terminalNoteR1InternalArguments`と隔離した`XDG_STATE_HOME`を注入する。Application本体は通常のproduction coordinatorを起動し、
  S1／S2 enabled、S3 disabled、native surface 1、binding 1、interaction owner 1を確認後、shutdownで全て0へ戻す。
- `developer-jit-note-r1`、`release-aot-note-r1`、`runtime-note-r1-integration`を追加した。両modeともfresh buildを使い、R1 suiteは
  本文、identity、store pathを出力せず、typed profile、slice数、isolated store、owner 0だけを報告する。
- `contextual-memory-r1-automated-qualification`はprofile、rehearsal、R0 8-gate qualification、R1両runtimeをexact順序で直列実行する。
  Final checkerはMake inventory／recipe、profile、R0 budget／architecture evidenceをfail closedで再検証し、idleの64 pane、64 surface、
  worker 1、projection／notification／layout／frame／store change／owner 0を明示検証する。Manual passやstage promotionは主張しない。
- 最初のJIT試行ではtyped configは有効だったがproduction coordinatorが`unavailable`になった。原因はmacOSのsystem temporary pathが
  `/var` symlink表現のまま`XDG_STATE_HOME`へ渡され、durable storeのcanonical path境界を満たさなかったことである。既存acceptanceと同じく
  temporary rootを`resolveSymbolicLinks()`した後で注入するよう修正した。Store安全制約を緩める案は不採用とし、ROADMAPへ個別bug項目は
  追加していない。
- 修正後の`make runtime-note-r1-integration`はDeveloper JIT／Release AOTの各modeでS1とS2を完走し、各modeの
  `RUNTIME_NOTE_R1_PASS ... typed_profile=true s3=false isolated_store=true owners=0 content_free=true`を確認した。
- Focused formatter、変更5 fileのanalyzer、`terminal_note_r1_qualification_test.dart`はpassした。次はfresh named aggregateを完走し、
  evidence／full regressionを確認してautomated subtaskをcommitする。
- Fresh aggregateの最初の試行はPhase 7の生成済みsource hashが旧値で停止した。`phase7-appkit-acceptance`、
  `ghostty-p0-p1-gap-inventory`、`release-candidate-daily-use-matrix`をこの順で正規再生成し、再試行ではPhase 7、
  Ghostty gap、daily-useを含むroot全回帰までpassした。
- 次の停止はR0の既存`developer-jit-native-content`で、外部の個人用DartTerminalがSecure Keyboard Entryを所有していたため
  test appがmanual leaseを取得できなかった。個人用アプリのmanual toggleは開始時off、確認操作後offに戻し、個人config fileは
  一切変更していない。Finderを前面にして個人用アプリのautomatic leaseを解放後、同gateのSecure Keyboard Entry境界は通過した。
  同再試行ではProcess Inspectorのargv非表示assertionが一度停止したが、単独再実行で
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... process_inspector=true`を確認した。Privacy invariantを緩める変更はしていない。
  Fresh aggregateを最初から再実行して最終判定する。
- そのfresh aggregateはprofile／rehearsal／budget／architecture／sanitizer／fault／S1／S2／Phase 7／compatibility／daily-use／
  root全回帰、両runtimeのdisplay・hierarchy・reliability・actions・AppleScript・system automationまで通過したが、
  `developer-jit-native-content`のProcess Inspector manual Secure Keyboard Entry所有確認で停止した。失敗時の診断は
  `manual_requested=true`、`application_active=true`、`owned=false`、`system_enabled=true`であり、別プロセスのSecure Input
  所有が残っている。`ioreg`のread-only確認ではSecure Input PIDが65157で、Finderを前面にしても変化しない。これはNotes
  固有の失敗ではなく、他アプリと排他的なOS資源を使う既存gateの実行環境競合である。安全assertionを弱めず再試行する。
- `lsof -p 65157 -a -d cwd`はSecure Input所有PIDがCodexを実行する`ChatGPT`プロセスであることを確認した。
  Finder前面でもleaseは解放されず、`make developer-jit-native-content`を単独で再実行しても同じ`owned=false`で停止した。
  試した別経路の直接`dart run`はサンドボックス外のclang module cacheへ書けず、OS test本体には到達しなかった。
- 選択肢は(1)同じOS gateを再試行、(2)外部所有時に`system_enabled`だけで合格、(3)mock leaseへ置換、
  (4)ChatGPTがSecure Inputを所有しない別GUI sessionでfresh aggregateを実行すること。(1)は単独再試行でも失敗、
  (2)はleaseの排他的ownership保証を失い、(3)はこのOS統合gateの意味を弱めるため採用しない。
  (4)が安全な残経路である。今回のtaskは完了扱いにせず、ROADMAPの未完了状態と実装差分を維持し、
  fresh named aggregate／最終checker／commit／manual stageは次の実行環境で行う。
- 別GUI環境から共有されたfresh aggregateの停止位置は前回から進み、Secure Keyboard Entryはautomatic／manualとも
  `owned=true`で通過した。一方、同じ既存`developer-jit-native-content`の後段で、menu-open時にはenabledだったcontext Quick Lookが
  dispatch時に`unavailable`になった。ログ上、pressure Quick Look、選択保持、Secure Input、Process Inspectorまでは成立しており、
  crashやNote側の失敗ではない。
- 調査で、context menuのenabled確認後、routeは`onWillRoute`でpaneをfocus/reconcileしてからdispatcherのavailabilityを再評価する。
  availabilityは保存されたcellまたはcursor cellを現在viewportのwordで再検証する。既存fixtureは`NATIVECONTENTLOOKUP`が画面へ出た
  瞬間に進み、後続のshell promptが出終わることを待たずにcell座標を保存していた。行scrollがmenu-openとdispatch間に入ると
  保存cellがstaleになり`unavailable`は正しいfail-closed結果になる。
- 選択肢は、(1)stale cellでもactionを実行する、(2)menu dispatchでavailability再確認を外す、(3)fixtureをshell prompt完了まで
  安定させること。(1)(2)はQuick Lookのstale-cell安全契約を弱めるため不採用。まず(3)として出力末尾に短いready markerを置き、
  同じ行へ続く一意のpromptを観測してからcellを求める。実AppKit gateを再実行し、なお失敗すればmenu focus/reconcile前後の
  content-free cell／viewport診断で原因をさらに絞る。
- 最初の安定化試行は`ready marker + prompt`を同一行の連続文字列として待ったが、その連続文字列は観測されず
  5秒でtimeoutした。改行やprompt redrawを許容しない条件だった。Secure Inputはautomatic／manualとも`owned=true`で
  通過しており、失敗は待機条件の誤りである。
  既存display受け入れと同じく、ready markerを観測した後、現在cursor行のprompt末尾とcursor位置が一致する
  `idle prompt`条件へ修正した。再実行で検証する。
- 2回目もidle判定で停止した。Ready markerがecho／scrollで失われた可能性と、既存promptのcursor column比較がzshの
  prompt描画に合っていない可能性を、この時点のcontent-freeログだけでは区別できない。追加の時間待ちで隠す案は不採用。
  対象shellの`PS1`をfixture内だけ一意の文字列に変える。コマンドechoにはその文字列が連続して現れないようquoteを分割し、
  実行後の新しいpromptが描画された時だけ`_waitForAsciiMarker`が成立するようにした。これは既存productのQuick Look
  safety checkを変えず、初期pane fixture内だけの同期である。
- `make developer-jit-native-content`はこの変更でpassした。`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`は
  `process_inspector=true`、`exact_pty=true`、4 sessionのclean teardownを報告した。Quick Lookのmenu availability、
  shared action dispatch、definition提示を含む既存`TERMINAL_NATIVE_CONTENT_TEST`を変更せず完走している。
- 同じfixtureの`make release-aot-native-content`もpassした。Developer JITとRelease AOTの両方でQuick Lookから
  4 session shutdownまで通過し、実OS Secure Inputのmanual ownershipは維持している。

### 2026-09-22 — R1 automated qualification完了

- `make phase7-appkit-acceptance ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`で、変更したapplication／
  runtime fixture／testに依存するversioned source hashを正規再生成した。生成物はsource hashとfresh R0 budget実測のみ変更した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart format --output=none --set-exit-if-changed`（変更5 Dart file）、同じ環境での
  focused `dart analyze`、`git diff --check`はpassした。単独`dart run`の一試行はsandbox外のclang module cacheに書けず、
  test本体に到達しなかったが、後続の正式Make aggregate内ではroot全テスト、400 file formatter、全体analyzerがpassした。
- Fresh `make contextual-memory-r1-automated-qualification`は終了コード0で完走した。Profile、rehearsal、R0の8-gate
  aggregate、R1両runtimeが順にpassし、final markerは`TERMINAL_NOTE_R1_AUTOMATED_QUALIFICATION_PASS version=1`
  `gates=4 base_gates=8 runtime_modes=2 slices=2 panes=64 surfaces=64 worker=1 idle_changes=0 owners=0`
  `manual_claim=false stage_claim=false content_free=true`だった。JIT／AOTともS1/S2 enabled、S3 disabled、isolated store、
  owner 0を確認した。R0側のarchitecture／privacy／sanitizer／fault／distribution／全runtime matrixもpassした。
- Quick Lookの修正はtest fixtureのshell完了同期だけで、menu、dispatcher、stale-cell判定、OS Secure Inputの受け入れ条件を
  変更していない。`dart_appkit`には変更を加えていない。Manual store matrixは未実施であり、stage promotionは主張しない。
