# Dart Terminal — contextual memory ロードマップ

最終更新: 2026-09-21<br>
状態: S1/S2の製品実装を完了。R0 hidden qualificationは未着手。

主要な terminal emulator 機能と配布版リリースまでの計画は達成済みであり、
[`docs/archive/terminal-emulator-release-roadmap.md`](docs/archive/terminal-emulator-release-roadmap.md)
へアーカイブした。そこに残る5件の低優先 follow-up は履歴として保持するが、
この roadmap の作業順序には含めない。再開する場合は本書の適切な位置へ明示的に追加する。

新機能の原案は
[`docs/proposals/contextual-terminal-memory-and-input-checkpoints.md`](docs/proposals/contextual-terminal-memory-and-input-checkpoints.md)、
既存実装との照合結果と判断項目は
[`docs/proposals/contextual-terminal-memory-design-decisions.md`](docs/proposals/contextual-terminal-memory-design-decisions.md)
を参照する。Gate 1の製品判断は
[`docs/proposals/contextual-terminal-memory-product-slices.md`](docs/proposals/contextual-terminal-memory-product-slices.md)
を正本とする。原案内の一括 MVP と実装順は superseded されている。Gate 1〜7の凍結仕様と
[`implementation plan`](docs/proposals/contextual-terminal-memory-implementation-plan.md)に従い、
S1/S2、次にS3だけを以下の順で実装する。S4は延期、S5/S6は不採用である。

## 完了した設計順序

- [x] 旧 roadmap を履歴と未完了 follow-up を保ったままアーカイブし、新機能の設計論点を洗い出す
  （実施記録は
  [`contextual-terminal-memory-design-decisions.md`](docs/proposals/contextual-terminal-memory-design-decisions.md)
  を参照する）
- [x] 製品 slice と成功条件を決め、memory、prompt連動、exact-command checkpointを個別に採用・延期・不採用へ分類する
  （判断結果は
  [`contextual-terminal-memory-product-slices.md`](docs/proposals/contextual-terminal-memory-product-slices.md)
  を参照する）
- [x] scope、identity、lifecycle と trigger delivery semantics を確定する
  （判断結果は
  [`contextual-terminal-memory-scope-trigger-semantics.md`](docs/proposals/contextual-terminal-memory-scope-trigger-semantics.md)
  を参照する）
- [x] data model、永続化、privacy、security、migration 方針を確定する
  （判断結果は
  [`contextual-terminal-memory-data-persistence-privacy.md`](docs/proposals/contextual-terminal-memory-data-persistence-privacy.md)
  を参照する）
- [x] overlay、編集体験、input authority、accessibility の仕様を確定する
  （判断結果は
  [`contextual-terminal-memory-overlay-editor-accessibility.md`](docs/proposals/contextual-terminal-memory-overlay-editor-accessibility.md)
  を参照する）
- [x] exact-command shell adapter の feasibility と trust boundary を検証し、checkpoint slice の採否を決める
  （判断結果は
  [`contextual-terminal-memory-checkpoint-feasibility.md`](docs/proposals/contextual-terminal-memory-checkpoint-feasibility.md)
  を参照する）
- [x] 採用した slice の仕様、互換性 matrix、検証条件、段階的 rollout を確定する
  （判断結果は
  [`contextual-terminal-memory-architecture-verification-rollout.md`](docs/proposals/contextual-terminal-memory-architecture-verification-rollout.md)
  を参照する）
- [x] 採用した slice だけを実装可能な work package へ分割し、依存順と個別の完了条件を登録する
  （判断結果は
  [`contextual-terminal-memory-implementation-plan.md`](docs/proposals/contextual-terminal-memory-implementation-plan.md)
  を参照する）

## 実装・rollout順序

各項目は、実施時に
[`contextual-terminal-memory-implementation-plan.md`](docs/proposals/contextual-terminal-memory-implementation-plan.md)
の同じIDを参照する。現在の先頭未完了taskをcommitする前に後続へ進まない。Stage taskはcode mergeだけで
完了にせず、指定された実測evidenceを満たすまで未完了とする。

- [x] archived release roadmapへcompatibility acceptanceのhistorical owner参照を移す
  （[`archived-roadmap-acceptance-ownership.md`](docs/contextual-memory/archived-roadmap-acceptance-ownership.md)
  を参照して実施する）
- [x] CM-01 Pure Note domain model と trigger state machineを実装する
- [x] CM-02 Note store version 1 codecを実装する
- [x] CM-03 durable Note store workerを実装する
  - [x] 汎用macOS durable-file capabilityを実装する
  - [x] Note transaction/recovery engineを実装する
  - [x] 専用isolate clientとbounded admissionを実装する
  - [x] 実filesystem受け入れと性能gateを完了する
- [x] CM-04 durable context identityとrestoration bindingを実装する
  （[`cm-04-durable-context-restoration-binding.md`](docs/contextual-memory/cm-04-durable-context-restoration-binding.md)
  を参照して実施する）
  - [x] exact restoration artifactとsecure context identityを実装する
  - [x] startup reconciliationとQuick Terminal singleton bindingを実装する
  - [x] ordered persistence、rollback、crash acceptanceを完了する
- [x] CM-05 application-root Note authorityを実装する
  （[`cm-05-application-root-note-authority.md`](docs/contextual-memory/cm-05-application-root-note-authority.md)
  を参照して実施する）
  - [x] store lifecycleとserial durable mutation authorityを実装する
  - [x] bounded topology、focus、prompt ingressを実装する
  - [x] projection acknowledgement、teardown、reopen acceptanceを完了する
- [x] CM-06 typed configurationとdisabled lifecycleを実装する
  （[`cm-06-typed-configuration-disabled-lifecycle.md`](docs/contextual-memory/cm-06-typed-configuration-disabled-lifecycle.md)
  を参照して実施する）
  - [x] typed optionと露出制御を実装する
  - [x] `nextLaunch` reloadとlive Note projectionを実装する
  - [x] composition-root disabled lifecycleと受け入れを完了する
- [x] CM-07 unified window interaction authorityへ既存input ownerを統合する
  （[`cm-07-unified-window-interaction-authority.md`](docs/contextual-memory/cm-07-unified-window-interaction-authority.md)
  を参照して実施する）
  - [x] generation-bound pure authorityとfuture Note owner contractを実装する
  - [x] Context Dock、system surface、input family routingをauthorityへ統合する
  - [x] responder、focus report、両runtime受け入れを完了する
- [x] CM-08 native Note presentation capabilityを実装する
  （[`cm-08-native-note-presentation-capability.md`](docs/contextual-memory/cm-08-native-note-presentation-capability.md)
  を参照して実施する）
  - [x] package、ABI v1、strict projection codecを実装する
  - [x] badge、rail、card、appearance、read-only accessibilityを実装する
  - [x] manifest-independent native acceptanceとfallbackを完了する
- [x] CM-09 native Note editor、intent、accessibility interactionを実装する
  （[`cm-09-native-note-editor-intent-accessibility.md`](docs/contextual-memory/cm-09-native-note-editor-intent-accessibility.md)
  を参照して実施する）
  - [x] semantic intent/result ABIとone-outstanding stateを実装する
  - [x] native multiline editor、draft admission、actionsを実装する
  - [x] input isolation、focus/accessibility、teardown acceptanceを完了する
- [x] CM-10 S1 Basic memoryをproductへ統合する
  （[`cm-10-s1-basic-memory-product-integration.md`](docs/contextual-memory/cm-10-s1-basic-memory-product-integration.md)
  を参照して実施する）
  - [x] native capability manifestとproduct Note subsystem adapterを実装する
  - [x] application compositionとpane/Quick Terminal surface lifecycleを接続する
    - [x] product-owned native-to-native Note overlay composition seamを実装する
    - [x] production Note subsystemのauthority/topology lifecycleを実装する
    - [x] application composition、interaction、live font、disabled lifecycleを接続する
  - [x] S1 mutation、Detached、export、localized actionを接続する
    - [x] rail/editor navigationとdurable CRUD/reorder mutation bridgeを接続する
      - [x] authority-owned surface stateとsemantic mutation contractを実装する
      - [x] native navigation ABIとproduct intent pumpを実装する
      - [x] applicationのrail/editor interaction lifecycleへ接続する
    - [x] Detached collection、reattach、explicit copy/exportを接続する
      - [x] authority-owned Detached navigation、64件paging、durable reorder、explicit reattachを接続する
      - [x] selected Noteのexplicit body-only pasteboard copyを接続する
      - [x] sensitive warning、save panel、portable exportを接続する
    - [x] Notes native sanitizer harnessをcurrent composition contractへ追随させる
    - [x] hidden create/open actionとlocalized menu/palette projectionを接続する
  - [x] restart、fault、close/quit、両runtime product acceptanceを完了する
    - [x] ordered Note shutdownとexact restoration commit境界をproductへ接続する
    - [x] S1 restart/fault/close/quit product vectorを実装する
    - [x] Developer JIT/Release AOT named acceptanceと全監査を完了する
- [x] CM-11 S2 On Returnをproductへ統合する
  （[`cm-11-s2-on-return-product-integration.md`](docs/contextual-memory/cm-11-s2-on-return-product-integration.md)
  を参照して実施する）
  - [x] explicit arm/re-arm native UIとatomic product mutationを接続する
  - [x] eligible focus lifecycleとsingle non-blocking railを接続する
  - [x] visible acknowledgement、shutdown-away、crash境界を接続する
    - [x] actual visible layout wake-upとsingle FIFO acknowledgementを接続する
    - [x] ordered shutdown-awayとrestart deliveryを接続する
    - [x] commit/ack crash境界とfalse-consume vectorを固定する
  - [x] S2両runtime product acceptanceと全監査を完了する
- [ ] CM-12 R0 hidden qualificationを完了する
  （[`cm-12-r0-hidden-qualification.md`](docs/contextual-memory/cm-12-r0-hidden-qualification.md)
  を参照して実施する）
  - [x] R0 temporary-store harness、hidden/default-off、rollback contractを固定する
  - [x] hard resource/latency budget benchmarkとcontent-free evidenceを実装する
    - [x] isolated Release AOT Dart budget fixtureを実装する
      - [x] hard-cap commitのSHA-256 working memoryをbounded化する
      - [x] hard-cap commit後のduplicate canonical decodeを除去する
      - [x] canonical payload checksumのUTF-8 allocationをbounded化する
      - [x] native-assets CLI bundleと4-phase hard gateを完了する
    - [x] actual AppKit native apply/first-visible budget fixtureを実装する
    - [x] versioned content-free evidenceと全hard gateを接続する
  - [ ] named aggregateとarm64/x86_64/Universal auditを接続する
    - [x] versioned cross-architecture Note capability/resource equality auditを実装する
      - [x] 汎用runtime builderのcross-target helper native-assets mappingを修正する
      - [x] fresh 4 bundle equality auditとversioned evidenceを完了する
    - [ ] R0 named aggregateへfull gate inventoryを接続する
      - [x] PTY sanitizerのlarge-pipeline readiness raceを除去する
      - [ ] serial 8-gate inventoryとfinal evidence checkerを完了する
        - [x] exact serial inventoryとfail-closed checker contractを実装する
        - [x] product-owned generic macOS entropy packageへdirect FFI boundaryを分離する
        - [ ] fresh 8-gate aggregateとfinal evidence checkerを完走する
          - [x] default-off Note action catalogのruntime smoke count driftを修正する
          - [ ] 修正後のfresh 8-gate aggregateを先頭から完走する
            - [x] display-testのcurrent prompt readiness raceを除去する
            - [ ] prompt readiness修正後のfresh 8-gate aggregateを先頭から完走する
              - [x] windowless状態のNew Window action admissionを修正する
              - [ ] New Window admission修正後のfresh 8-gate aggregateを先頭から完走する
  - [ ] manual IME/keyboard/VoiceOver/appearance/TUI checklistとR0 stage decisionを完了する
- [ ] CM-13 R1 internal S1/S2 opt-inを完了する
- [ ] CM-14 R2 public S1/S2 opt-inを完了する
- [ ] CM-15 R3 S1/S2 default-on promotionを完了する
- [ ] CM-16 shell integration version 3 lifecycle protocolを実装する
- [ ] CM-17 S3 At Next Promptをproductへ統合する
- [ ] CM-18 R4 public S3 opt-inを完了する
- [ ] CM-19 R5 S3 default-on decisionを完了する
