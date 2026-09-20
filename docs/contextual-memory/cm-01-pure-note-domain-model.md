# CM-01 Pure Note domain model と trigger state machine

## 目的

S1 Basic memory、S2 On Return、S3 At Next Promptの永続状態と状態遷移を、I/OやUIから独立した
Pure Dart modelとして実装する。後続のcodec、store worker、application authority、native UIが同じ
immutable snapshotと検証済みmutationを共有できる境界を作る。

## 背景

Gate 2/3/4/7で、This Terminal scope、opaque identity、分離したNote/Context/Trigger/Delivery record、
bounded plain text、optimistic revision、S2/S3 state machine、delivery FIFOが凍結済みである。
`ROADMAP.md`の先頭未完了項目はCM-01であり、CM-02以降へ進む前に本taskを単独で検証・commitする。

## 範囲

- opaque 128-bit `NoteId`、`TerminalNoteContextId`、runtime binding identity
- `NoteRecord`、`NoteContextRecord`、`NoteTriggerRecord`、`NoteDeliveryRecord`
- immutable `TerminalNoteSnapshot`とcopy-on-write mutation result
- create、edit、reorder、resolve、reopen、delete、detach、reattach、arm、cancel、ack
- store revision、Note revision、trigger generation、`DeliverySequence`
- Note body、record count、per-context count、aggregate body、counterのhard limit
- S2 On ReturnとS3 At Next Promptのpure event transition
- due FIFO、stable Note ID tie-break、user orderによるdeterministic projection

## 対象外

- JSON、checksum、canonical codec、filesystem、store worker、restoration reconciliation
- application authority、native Note surface、AppKit、PTY、実shell event接続
- S4、S5、S6、Markdown、attachment、notification、workspace scope
- `dart_appkit`の変更。Noteの製品概念は`dart_terminal`にだけ置く

## 依存関係

- `docs/proposals/contextual-terminal-memory-scope-trigger-semantics.md`
- `docs/proposals/contextual-terminal-memory-data-persistence-privacy.md`
- `docs/proposals/contextual-terminal-memory-architecture-verification-rollout.md`
- `docs/proposals/contextual-terminal-memory-implementation-plan.md`

## 完了条件

- create/edit/reorder/resolve/reopen/delete/detach/reattachとrevision conflictを無変更失敗として表現する
- 全quota境界、counter overflow、duplicate/reset/out-of-order eventをatomicに扱う
- focus F1〜F4、prompt P1〜P7、coalescing C1をpure testへ変換する
- fixed-seed 10,000 state sequenceで毎stepのsnapshot invariantを検証する
- exception/resultの文字列表現へNote bodyとpersistent IDを含めないsentinel testを通す
- format、analyze、focused test、aggregate testを通し、本記録とroadmapを更新して一つのcommitにする

## 検証方針

- standalone focused testをaggregate runnerにも登録する
- limitの`-1 / exact / +1`と、revision/generation/sequence最大値を明示fixtureで試す
- accepted mutation後は常にpublic invariant validatorを呼び、失敗mutationでは元snapshotのidentityと
  内容が変わらないことを確認する
- model sourceのimportを静的検査し、`dart:io`、AppKit、PTY依存が0であることを確認する

## 調査・判断記録

### 2026-09-20: 着手

- branchは`codex/contextual-memory-design`、着手時worktreeはcleanだった。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、Gate 2/3/4/7文書、既存model/test runnerを確認した。
- Empty snapshotの`storeRevision`は0とし、最初のaccepted transactionで1にする。Record revision、trigger
  generation、delivery sequenceは仕様どおりpositiveとする。
- ID生成はCM-04のCSPRNG ownerへ残す。CM-01はlowercase 32-hexのcanonical opaque valueを検証して保持し、
  `toString`はraw valueを返さない。Codec向けraw accessは明示getterに限定する。
- Pure modelは`dart_terminal` product-owned sourceへ置く。`dart_appkit`にNote型やDart Terminal固有policyを
  追加しない。後続native capabilityも既定計画どおりproduct-owned packageで実装する。
- File-sizeとdeletion journal quotaはcodec/storeの責務なのでCM-02/CM-03へ残す。CM-01ではrecord/body/counter
  quotaとcross-record invariantを扱う。
- Presentationの`presented`は長期recordにせず、ack transactionでdeliveryとtriggerを同時削除する。
- S3 runtime session/instance bindingはpersistent trigger recordと分離したimmutable memory-only valueにする。
- Dart nativeの`int`ではpositive unsigned 64-bit全域を表せず、`0xffffffffffffffff`は`-1`として扱われる。
  Revision、generation、delivery/event sequenceは`BigInt`で保持し、`2^64-1`までexactに検証する。
  Timestampとcollection orderは非負のnative `int`であり、counter authorityには使用しない。
- 同じauthority drainでfocusとpromptが同時に進む場合のため、`observeLifecycleBatch`を一transactionとして
  用意した。同transactionで新たにdueになったNoteはfamily順ではなくstable `NoteId`順にsequenceを割り当てる。
- `FEATURE_MATRIX.md`はuser-visible product capabilityの現状表であり、本taskは未接続のpure foundationだけを
  追加するため更新しない。S1 product統合時にCurrent列へ反映する。

### 2026-09-20: 実装中の試行

- `dart format`へMarkdownも渡したためparser errorになった。Dart source 2件のformat自体は完了した。
  以後format対象を`.dart`だけに限定する。
- 同じcommand内の`dart analyze`はformatのnon-zero終了により未実行だった。またDart CLIがsandbox外の
  telemetry logを更新しようとしたため、以後`CI=true DART_SUPPRESS_ANALYTICS=true`を付けた許可済みの
  実行境界で検証する。
- 最初のfocused testはempty snapshot作成時に`invalidCounter`となった。原因はunsigned maxをhexのDart
  `int` literalにしたことで`-1`になったためで、counter型を`BigInt`へ変更してunsigned 64-bit境界を保持した。
- 次のfocused testはrevisionの期待値だけをDart `int`の`2`と比較して失敗した。Test期待値も`BigInt`へ
  揃え、opaque ID順のassertionはredacted `toString`ではなくtest内の明示的canonical valueで比較した。
- Aggregate body上限8 MiBは`2,048 Notes × 4,096 bytes`と数学的に同時到達する。Exact境界fixtureで両方を
  検証し、次のcreateがrecord/per-context/body capacityのどれにもevictionせずatomic rejectされることを確認した。

### 2026-09-20: 実装結果

- `lib/src/terminal_note_model.dart`へopaque ID、plain-text body policy、分離record、immutable snapshot、
  fixed-disposition mutation、cross-record validator、S2/S3 FSM、coalesced lifecycle batch、FIFO projectionを追加した。
- ID生成は行わず、CSPRNG ownerから注入されるlowercase 32-hexを受理する。これによりCM-04のidentity ownerと
  CM-01のdeterministic modelを分離した。
- Trigger generationはaccepted arm transactionのstore revisionを使う。Trigger record消費後もre-arm時に
  必ず増加し、追加のpersistent counter fieldをschemaへ持ち込まない。
- Runtime-only prompt dedupeはimmutable snapshotを更新するがstore revisionを増やさない。Persistent phase、
  suspend、due、ackだけがdurable transactionとなり、duplicate eventはexact no-opになる。
- `test/terminal_note_model_test.dart`へbody/ID、lifecycle、revision conflict、quota/counter、F1〜F4、P1〜P7、
  C1、duplicate/reset/overflow、privacy/dependency sentinel、fixed-seed 10,000-step sequenceを追加し、aggregate
  runnerへ登録した。
- `dart_appkit`、PTY、filesystem、JSONへのmodel依存は追加していない。変更は`dart_terminal` repository内の
  product-owned pure sourceに限定した。

### 2026-09-20: 検証結果とhandoff

- `CI=true DART_SUPPRESS_ANALYTICS=true dart format --output=none --set-exit-if-changed ...`:
  pass、対象Dart fileの変更0。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze lib/src/terminal_note_model.dart
  test/terminal_note_model_test.dart test/run_tests.dart`: pass、issues 0。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_note_model_test.dart`: pass。
  Exact body/line/record/context/trigger/delivery/aggregate/counter境界、F1〜F4、P1〜P7、C1、duplicate ack、
  stale revision、out-of-order reset、33-event overflow、10,000-step fixed-seedを含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: final pass。353 Dart files format変更0、root analyze
  issues 0、native contract、compatibility、distribution、aggregate Dart testsを含め`dart_terminal tests passed`。
- `compatibility/release_candidate_daily_use_matrix.json`はaggregate runner source hashを正規generatorで更新し、
  `release-candidate-daily-use-matrix-check`をaggregate内でpassした。
- `git diff --check`: pass。秘密情報、debug出力、生成cache、`dart_appkit`変更は0。
- CM-02は`TerminalNoteSnapshot.fromRecords`をstrict decodeの唯一の構築境界として使い、persistent recordだけを
  canonical encodeする。`runtimeBindings`はdiskへ書かず、loadしたwaiting S3 triggerは仕様どおり
  `suspended(sessionEnded)`へpure transformしてからsnapshotを構築する。
- 残riskはI/O、codec、restoration、native projection、実shellとの接続であり、すべてCM-02以降に明示済み。
  CM-01の未完了項目や追加blockerはない。
