# Contextual terminal memory implementation plan

- 状態: 実装task分割完了（製品コード未着手）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- 凍結仕様: [`contextual-terminal-memory-architecture-verification-rollout.md`](contextual-terminal-memory-architecture-verification-rollout.md)

## 目的

凍結したS1 Basic memory、S2 On Return、S3 At Next Promptだけを、一task一commitで実装・検証できる
順序付きwork packageへ分割する。各taskの成果物、対象外、依存関係、完了条件、必須検証、rollout上の
停止条件を明示し、最初の実装taskを一意にする。

## 背景

Gate 1〜7で製品scope、trigger、data/privacy、GUI/input、checkpoint不採用、ownership、version、budget、
rolloutを確定した。次に全層を一括実装すると、pure model、filesystem durability、restoration、native ABI、
product wiring、shell protocol、release evidenceが一commitへ混在し、failure isolationとrollbackが難しくなる。
依存方向に沿って小さく閉じ、各境界を前段のtest doubleとcontract testで固定してから統合する必要がある。

## 対象範囲

- S1/S2 initial release sliceと、acceptance後に着手するS3 increment
- Pure model、store worker、restoration binding、config/lifecycle、window input authority、native Note surface
- Product action/UI wiring、S2 focus delivery、S3 shell integration version 3とprompt delivery
- Privacy、performance、Developer JIT／Release AOT、distribution、manual accessibility、段階的rollout evidence
- Root `ROADMAP.md`への全subtaskの依存順、個別completion、参照linkの登録

## 対象外

- このtask内でのDart/native/test code、shell resource、config schema、store/restoration fileの変更
- S4 Invocation receipt、S5 Exact-command checkpoint、S6 Simulation / observe
- Workspace scope、sync/collaboration、notification、import、rich text、app-level encryption
- 実装中のstage promotionを先に承認すること。各promotionは対応taskの実測evidenceで判断する

## 依存関係

- Product/scope/data/overlay/checkpoint/architectureのGate 1〜7正本
- Existing application/pane/session/native/config/restoration/shell-integration ownerと通常quality gate
- 一task一commit、先頭未完了taskだけへ着手するrepository規約
- R0〜R5の順序と、S1/S2 acceptance後だけS3へ進む停止条件

## 完了条件

- 採用済みS1〜S3だけを、循環のない依存順でimplementation／integration／promotion taskへ分割する。
- 各taskにpurpose、成果物、対象外、依存、個別completion、必須verification、更新文書を定義する。
- Pure boundaryからproduct integration、opt-in evidence、default判断までを漏れなく追跡する。
- S4〜S6、command content/digest、checkpoint/bidirectional field/taskが混入していないことを確認する。
- `ROADMAP.md`の設計taskを完了し、分割した全taskを正しい順の未完了checkboxとして追加する。
- 親文書と原案のstatus／next taskを同期し、Markdown/link/order/diff scopeを検証してcommitする。

## 検証方針

- Gate 7のowner、version、test pyramid、budget、R0〜R5をtask coverage matrixへ写像する。
- 各taskの入力／出力contractと依存先を静的に照合し、前段未完了で後段へ進めない順序を確認する。
- Accepted S1〜S3とdeferred/rejected S4〜S6のallowlist/denylistをtask titleとscopeへ適用する。
- Changed Markdown link、trailing whitespace、roadmap checkbox順、product-code差分なしを検査する。

## 調査記録

### 2026-09-20: 着手

- Gate 7はcommit `eab6591`で完了し、着手時のworktreeはcleanだった。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`を再確認した。既存terminal emulatorとdistribution
  gateは完了済みで、root roadmapの最初の未完了taskはimplementation subdivisionである。
- このtaskでは製品codeを変更せず、Frozen specificationを実装可能なwork packageへ変換する。

## Work package設計

### 分割方針

- IDはtask memoとroadmap参照用であり、commit messageには含めない。
- CM-01からCM-19までstrict linearに進める。技術的に独立して見えるtaskも、前taskのcontractと
  verificationをcommitする前に先行しない。
- 各task着手時に`docs/contextual-memory/`へIDを含むtask memoを作り、本書の該当packageを具体化する。
  完了時は実測結果、失敗、残risk、変更file、次taskへのhandoffを同memoへ残す。
- 各taskはfocused/full verification、task memo、影響するreference／FEATURE_MATRIX、roadmap stateを更新し、
  そのtaskだけのsemantic commitを作ってから次へ進む。
- Frozen scope、owner、version、privacy、budget、rolloutを変える必要が生じた場合は、その実装を止め、
  decision再開taskを現在位置へ追加する。実装の都合だけで仕様をsilentに弱めない。
- CM-01〜CM-11はcodeを完成させてもrelease promotionではない。CM-12以降のstage exitはcode mergeだけで
  完了にせず、指定したautomated／manual／evaluation evidenceを満たすまで未完了のままにする。
- Native Note surfaceはgeneric `dart_appkit`へproduct UIを追加せず、このrepositoryのproduct-owned
  `packages/dart_terminal_notes_macos` capabilityとして実装する。既存generic handle APIで成立しない場合、
  sibling repositoryを暗黙に変更せず、境界再設計taskを先に登録する。
- R0ではnormal default-off pathにNote action/surface/storeがなく、test harnessだけがtemporary storeと
  explicit dependency injectionでfeatureを起動する。R1のinternal buildからtyped local optionを使い、
  hidden environment variable、remote flag、telemetryは使わない。

### CM-01 — Pure Note domain model and trigger state machines

- 依存: Gate 2/3/4のidentity、record、quota、focus/prompt semantics。
- 成果物: opaque ID、Note/Context/Trigger/Delivery、immutable snapshot、validated mutation、revision、
  `DeliverySequence`、S2/S3 pure FSM、deterministic projection ordering。`dart:io`、PTY、AppKit依存は0。
- 完了条件: create/edit/reorder/resolve/reopen/delete/detach/reattach、revision conflict、全quota境界、
  On ReturnとAt Next Promptの全review vector、duplicate/reset/overflowをatomic transitionとして表現する。
- 必須検証: focused unit、fixed-seed 10,000 state sequence、format/analyze、body/IDをerror stringへ出さない
  static sentinel。Dart-onlyで失敗を最小再現できること。
- 対象外: JSON、filesystem、restoration、native UI、実shell event。

### CM-02 — Note store version 1 codec

- 依存: CM-01。
- 成果物: canonical UTF-8 JSON envelope/payload codec、checksum、strict schema/invariant/limit validation、
  `restorationBinding` v1、deletion journal record、pure migration entrypoint。
- 完了条件: field/array ordering、one trailing LF、duplicate/unknown/trailing/noncanonical input rejection、
  16 MiB file／8 MiB body hard cap、newer version read/write 0を固定する。
- 必須検証: round-trip、all limit ±1、fixed-seed 10,000 mutation、任意byte最低1 MiB、checksum/counter/
  restoration binding fault。Codec exceptionへcontent/ID/timeを含めない。
- 対象外: file open、permission、lock、backup、isolate、product startup。

### CM-03 — Durable Note store worker

- 依存: CM-02。
- 成果物: application-wide isolate protocol v1、safe location、0700/0600、exclusive lock、lstat/link check、
  current/backup/journal、temp-write→flush→rename→directory-fsync、load/commit/export/recovery/stop。
- 完了条件: 一件in-flight、32 intent/128 KiB pending admission、3秒load timeout、1秒stop、two-process
  contention、crash/fault後known-good保持、empty auto-reset 0、worker log本文0を満たす。
- 必須検証: 全filesystem step fault、permission/symlink/hard-link、worker crash/timeout、contention、
  deletion resurrection、explicit export cancel/success、1/16 MiB performance fixture。
- 対象外: application Note semantics、pane binding、native success表示。

### CM-04 — Durable context identity and restoration binding

- 依存: CM-03、existing restoration v1/application topology。
- 成果物: cryptographically random `TerminalNoteContextId`、standard pane runtime binding、Quick Terminal
  singleton、deterministic pane traversal、exact restoration-byte SHA-256 binding、startup reconciliation。
- 完了条件: existing restoration JSON version/encoding fixtureを変えず、matching hashだけreattachし、
  missing/mismatch/rollback layout changeはfresh context + Detached、partial/index/path推測attach 0とする。
- 必須検証: B-01〜B-05、two-transaction crash order、pre-Notes binary fixture、64-pane/count/duplicate ID、
  restore/reopen generation、Quick Terminal hide/show/restart。
- 対象外: Note card、focus/prompt delivery、config default変更。

### CM-05 — Application-root Note authority

- 依存: CM-01〜CM-04。
- 成果物: sole `TerminalNoteAuthority`、store lifecycle、serial durable transaction、bounded ingress、
  topology/session event adapter、projection/card token generation、capability/failure state、shutdown drain。
- 完了条件: commit success後だけsnapshot/UI resultをpublishし、failure/stale/timeoutでcandidateを破棄する。
  Queue、focus、prompt、projection、ackのGate 7 boundとpane/session/application teardown順を満たす。
- 必須検証: O-01〜O-05、R-01、revision/duplicate/supersede、late event、64 pane、worker unavailable、
  full close/reopenでauthority/store handle 0。Fake surface/sessionだけを使用する。
- 対象外: public config option、AppKit surface、user-facing action。

### CM-06 — Typed configuration and disabled lifecycle

- 依存: CM-05、existing typed schema/reload/Settings/reference generation。
- 成果物: `nextLaunch` policy、`notes`、`notes-on-return`、`notes-next-prompt`、`notes-font-size`、
  internal-preview/public exposure metadata、composition-root admission、pending-restart projection。
- 完了条件: first implementation defaultはfalse/true/false/15、font 12〜24だけlive、invalid reloadは
  all-or-nothing。`notes=false`でworker、store access/directory、context binding、surface、timerが0になる。
- 必須検証: config priority/diagnostic/provenance/reference freshness、reload C-01〜C-03、Settings filter、
  `--show-config` privacy、disabled key→PTY baseline差+5%以下。
- 対象外: R2 public documentation、default-on変更、S3 protocol event。

### CM-07 — Unified window interaction authority

- 依存: CM-06、existing terminal/Context Dock/system notice routing。
- 成果物: generation-bound `TerminalWindowInteractionAuthority`へterminal、Context Dock、system modal、
  future Note rail/editor ownershipを統合し、分散boolean ownerを除く。
- 完了条件: exactly-one owner、request/confirm/cancel、hierarchy mutation時no replay、stale reject、terminal
  responder復帰を既存observable behavior不変で固定する。Note ownerはまだtest doubleだけ。
- 必須検証: raw key/IME/menu/clipboard/Services/drop/mouse/scroll/AX/automation、DEC 1004 report delta 0、
  Context Dock/Quick Terminal/secure input/close/reopenのDeveloper JIT・Release AOT focused acceptance。
- 対象外: Note surface、store mutation、Note body。

### CM-08 — Native Note presentation capability

- 依存: CM-07、native Note surface ABI v1。
- 成果物: product-owned `dart_terminal_notes_macos` package、manifest-independent test capability、strict
  projection decoder、pane child surface、badge、trailing rail、opaque colored cards、theme/contrast/motion、
  geometry/hit region、read-only accessibility tree。
- 完了条件: collapsed body 0、expanded 64 card/256 KiB、atomic projection apply、stale/version/limit reject、
  last-good保持、small-pane/alternate-screen/TUIでもrows/columns/drawable/winsize/SIGWINCH delta 0。
- 必須検証: native C/ObjC header compile、unit/sanitizer、1x/2x geometry、light/dark/contrast/non-color/
  reduced motion、G/B/P/T/A/L presentation vector、missing capability fallback。
- 対象外: editor、semantic mutation、durable acknowledgement、application manifest registration。

### CM-09 — Native Note editor, intent, and accessibility interaction

- 依存: CM-08。
- 成果物: ABI v1 intent/result、standard multiline editor、volatile draft/selection/IME/Undo、explicit
  Save/Cancel、color/reorder/resolve/delete/reattach/export controls、keyboard/VoiceOver flow、one outstanding intent。
- 完了条件: generation/token/revision conflictをfail closedし、dirty closeはSave/Discard/Cancel、outside
  click replay 0、Note interaction中のterminal raw/IME/paste/mouse/automation byte 0を満たす。
- 必須検証: Japanese IME、4,096-byte/64-line boundary、paste/drop/Services、E-01〜E-05、I/F/A vector、
  Full Keyboard Access、VoiceOver tree、adapter-before-view teardown、native retained owner 0。
- 対象外: production Note authority wiring、autosave/durable draft、rich text、checkpoint control。

### CM-10 — S1 Basic memory product integration

- 依存: CM-09。
- 成果物: package manifest registration、application composition、pane/Quick Terminal surface lifecycle、
  hidden create/open/edit/reorder/resolve/reopen/delete、Detached collection/reattach、explicit export、localized
  action/menu/palette projectionをS1 authorityへ接続する。
- 完了条件: test-only/internal `notes=true`でS1全flowがdurable、restart後exact contextへ復元され、
  default-offではentry/surface/store 0。Renderer/grid/PTYへNote body/geometryを渡さない。
- 必須検証: S1 product vector、store/native fault、2 window/3 tab/5 pane、Quick Terminal、close/quit dirty
  confirmation、Developer JIT/Release AOT実AppKit、diagnostics/restoration/shell sentinel 0。
- 対象外: focus/prompt trigger、自動通知、public preview。

### CM-11 — S2 On Return product integration

- 依存: CM-10。
- 成果物: explicit On Return arm、application/window/tab/pane/minimize/hide/Quick Terminal focus edges、
  durable due、single non-blocking rail、FIFO coalescing、visible presentation ack、re-arm UI。
- 完了条件: arm visitで0、away→eligible returnで一回、duplicate/background/occluded/small-pane/stale ackで
  false consume 0、S1 passive操作とterminal focus/inputを維持する。
- 必須検証: F-01〜F-04、simultaneous due、crash before/after commit/ack、64 context edge pressure、
  alternate screen/Vim/Codex/mouse TUI、Developer JIT/Release AOT。
- 対象外: S3 shell event、notification/urgency/timeout、input hold。

### CM-12 — R0 hidden qualification

- 依存: CM-11。
- 成果物: R0専用temporary-store harness、named aggregate gate、privacy/source/resource/bundle audit、budget
  evidence、manual checklist。Normal release defaultとuser-visible entryはoffのまま。
- 完了条件: pure/codec/fault/native/product tests、disabled zero-cost、all hard resource/latency budget、
  rollback rehearsalがpassし、hard invariant violationとbody/privacy leakが0。
- 必須検証: `make test`、focused native/sanitizer/fault、runtime verify、Developer JIT/Release AOT、arm64/
  x86_64/Universal resource equality、manual IME/keyboard/VoiceOver/appearance/TUI。
- 対象外: internal/user opt-in promotion。未達は個別fix taskを現在位置へ追加する。

### CM-13 — R1 internal S1/S2 opt-in

- 依存: CM-12。
- 成果物: internal buildでtyped `notes=true`を使用可能にし、S3 offで実データstoreを使うpreview、
  internal runbook、data recovery/export手順、content-free result記録。
- 完了条件: Gate 7 R1のJIT/AOT end-to-end、store/restore、64 pane、IME/TUI/manual checklist、kill switch、
  full resource recoveryを実利用環境で再確認しhard invariant violation 0。
- 必須検証: internal candidateをfresh buildし、on→off restart、store lock/corrupt/newer、native missing、
  pre-Notes rollback/re-upgradeをrehearseする。
- 対象外: public docs、default-on、telemetry。問題は修正taskをR1直前へ追加する。

### CM-14 — R2 public S1/S2 opt-in

- 依存: CM-13。
- 成果物: `notes`、`notes-on-return`、`notes-font-size`をpublic reference/Settingsへ公開し、default offの
  opt-in preview、privacy/recovery/manual guide、FEATURE_MATRIXの実stageを更新する。
- 完了条件: representative evaluator 5人以上がS1 comprehension基準を満たし、各20回のscripted focusで
  false/lost/duplicate 0、actionable data issue 0。匿名aggregate countと設計観察だけをtask memoへ残す。
- 必須検証: public candidateのfull R0/R1 gate、documentation freshness、fresh install/upgrade/rollback、
  evaluator evidence review。人数や結果が不足する間は未完了とする。
- 対象外: schema default変更、S3、production telemetry。

### CM-15 — R3 S1/S2 default-on promotion

- 依存: CM-14。
- 成果物: independent release candidateでR2を再現後、`notes` schema defaultをtrueへ変更し、release/
  rollback documentationとFEATURE_MATRIXをdefault-onへ更新する。
- 完了条件: startup/performance/privacy/distribution、wrong-context 0、data loss/corruption 0、rollback
  rehearsal pass。Failure時はdefault offを維持し、このtaskを完了にしない。
- 必須検証: fresh/upgrade/pre-Notes install、on→off→on、M1 JIT/AOT、thin/Universal、full aggregate gate。
- 対象外: S3。CM-16はこのacceptance完了前に開始しない。

### CM-16 — Shell integration version 3 lifecycle protocol

- 依存: CM-15、existing version 2 shell integration/parser/resource pipeline。
- 成果物: v3 resource/contract、per-launch 128-bit instance、trailing `dtr-note-v3` field、strict parser、
  bounded content-free lifecycle event、v2/none/higher/mismatch capability、既存S3 optionのlaunch activation。
- 完了条件: S3 enabled local rootだけv3をlaunchし、disabled S1/S2はv2/none compatibilityを維持する。
  Command body/status/Note IDをevent/environment/logへ入れず、tmux/SSH/nestedへinstanceを継承しない。
- 必須検証: all split/malformed/duplicate/wrong instance、zsh/Apple bash real PTY、fish/nu fixture+
  conditional runtime、none/v2/higher、tmux/SSH negative、resource hash/bundle equality。
- 対象外: Note due transition、bidirectional protocol、command matcher/digest、input hold。

### CM-17 — S3 At Next Prompt product integration

- 依存: CM-16。
- 成果物: available/probing/suspended/unavailable UI、explicit arm、post-arm C→D→A/N→B FSMへのsession
  event wiring、durable due/presentation、re-arm/degradation flow。Defaultは`notes-next-prompt=false`。
- 完了条件: matching full cycleで一回だけdue、pre-arm/partial/out-of-order/reset/session change/background/
  overflowでfalse delivery 0。S1/S2/storeはS3 unavailable/faultから独立して継続する。
- 必須検証: P-01〜P-03とGate 2 P1〜P7、S2同時due、32 event/session・64 session、worker/native/
  shell restart、real alternate-screen/TUI、Developer JIT/Release AOT。
- 対象外: S4 receipt、S5/S6、command status/body、remote prompt inference。

### CM-18 — R4 public S3 opt-in

- 依存: CM-17。
- 成果物: `notes-next-prompt=true`をpublic reference/Settingsへ公開し、S1/S2のdefaultを変えずS3
  opt-in preview、supported/degraded/unavailable説明とmanual guideを提供する。
- 完了条件: 各capability class 20 sequenceでfalse/lost/duplicate 0、zsh/bash両runtime、tmux/SSH negative、
  resource/privacy/distribution audit pass。S3-only kill rehearsalがS1/S2/storeを保持する。
- 必須検証: fresh R4 candidateのfull S1/S2 regression、real PTY/resource、JIT/AOT、manual comprehension。
- 対象外: S3 default変更、unsupported shellをsafe/availableと見せること。

### CM-19 — R5 S3 default-on decision

- 依存: CM-18。
- 成果物: independent release candidateでR4を再確認し、基準を満たす場合だけ
  `notes-next-prompt` defaultをtrueへ変更する。未達ならopt-inを維持しtaskは未完了とする。
- 完了条件: supported/degraded/unavailable説明を5/5 evaluatorが理解し、false/lost/duplicate 0、all
  privacy/performance/resource/rollback gate pass、FEATURE_MATRIX/reference/release noteがactual defaultと一致する。
- 必須検証: full aggregate/distribution/manual matrix、S3 off/full Notes off/binary rollback rehearsal、
  final staged diff/privacy/source audit。
- 対象外: S4〜S6の再検討。必要なら別proposalから新roadmapを開始する。

## Contract coverage matrix

| Frozen contract | Primary package | Release evidence |
| --- | --- | --- |
| Note/Context/Trigger/Delivery、S2/S3 FSM | CM-01 | CM-12、CM-18 |
| Store v1 codec、privacy、delete/export | CM-02〜CM-03 | CM-12〜CM-14 |
| Context identity、restoration binding v1、rollback | CM-04 | CM-12〜CM-15 |
| Root authority、queue/generation/revision/teardown | CM-05 | CM-12、CM-17〜CM-19 |
| Config、capability、disabled zero-cost、kill switch | CM-06 | CM-12〜CM-15、CM-18〜CM-19 |
| Exactly-one window input owner | CM-07 | CM-12 |
| Native ABI v1、Miro-inspired card rail、editor、AX | CM-08〜CM-09 | CM-12〜CM-14 |
| S1 Basic memory | CM-10 | CM-12〜CM-15 |
| S2 On Return | CM-11 | CM-12〜CM-15 |
| Shell integration v3、S3 At Next Prompt | CM-16〜CM-17 | CM-18〜CM-19 |
| R0〜R5 rollout／rollback | CM-12〜CM-15、CM-18〜CM-19 | 各stage task自身 |

全frozen contractが少なくとも一つのimplementation packageと一つのrelease evidence taskへ対応する。
S4、S5、S6、workspace、sync、notification、import、rich text、command matcher/digest、bidirectional reply、
simulationに対応するpackageは置かない。

## 検証記録

2026-09-20 に次を実行した。

- CM-01〜CM-19のheading、roadmap item、依存、成果物、完了条件、必須検証、対象外を静的に数え、
  それぞれ19件が同じ順で存在することを確認した。Roadmapは設計完了8件、実装未完了19件で、
  最初の未完了taskはCM-01である。
- 各packageの依存lineからCM IDを抽出し、current ID以降を参照するforward dependency 0件を確認した。
  Rollout taskはR0、R1、R2、R3、R4、R5の順で、CM-16 S3 protocolはCM-15完了後にだけ現れる。
- Work package titleのdenylistを検査し、S4〜S6、receipt、checkpoint、simulation、workspace、sync、
  notification、import、rich text、digest、bidirectional task 0件を確認した。これらの語は対象外／不採用の
  明記にだけ残る。
- Contract coverage 11行をGate 7のowner、store/restoration、config、input、native、S1/S2/S3、rolloutと
  読み合わせ、すべてにimplementation packageとrelease evidence taskがあることを確認した。最初の
  row countはtable headerもdataとして数えて12件と誤判定したため、Primary package列が`CM-`で始まる
  data rowへ限定して再検査し11件でpassした。
- Changed/new Markdown 10件のrelative link 103件を検査し、missing target 0件を確認した。
- `git diff --check`: pass。差分は`ROADMAP.md`と`docs/proposals/`のMarkdownだけで、product/test/native
  code、dependency、build、shell resource、generated artifactを変更していない。
- 最初の`ROADMAP.md`一括patchは、複数hunkのうちintro contextが一致せず適用前に失敗した。Partial editは
  なく、header/introとtask listを小さいpatchへ分け、現在内容を再読してから適用した。
- このtaskは計画文書だけを変更したため、Dart unit test、native build、real PTY、Developer JIT／Release AOT、
  distribution testは未実施である。各実装／stage taskの必須検証としてCM-01〜CM-19へ割り当てた。
