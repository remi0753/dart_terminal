# CM-05 application-root Note authority

## 目的

Application root Dart isolateに唯一の`TerminalNoteAuthority`を置き、committed Note document、runtime pane/context binding、
mutation admission、focus/prompt ingress、projection generation、presentation acknowledgement、store lifecycleを一か所で直列化する。
Workerのdurable success後だけ新snapshotとUI-visible resultを公開し、failure、timeout、duplicate、stale eventではcandidateを破棄する。

## 背景

- CM-01はpure Note/trigger/delivery state machine、CM-02はstrict store v1、CM-03はapplication-wide isolate worker、CM-04は
  exact restoration bindingとordered shutdown persistenceを実装済みである。
- `TerminalApplicationState`はtopologyのsole owner、`TerminalPaneOwner`はsession generationのownerである。Note authorityをこれらの
  classへ埋め込まず、composition rootが並列に所有するのが凍結owner boundaryである。
- Native Note surfaceはCM-08、product action/editor統合はCM-09〜CM-11、typed enablementはCM-06である。CM-05ではfake portとpure
  projection contractだけを使用する。

## 範囲

- Store load/reconciliation、ready/recovery/unavailable capability、commit/stopを所有するapplication-root authority。
- One in-flight、pending 32 intent、pending body 128 KiB、arrival-order、revision conflict、duplicate、structural supersedeを扱うserial queue。
- Pane/context topology、eligible focus、session generation、prompt ringをcontent-free bounded ingressへ変換するadapter。
- Paneごとのsurface/projection generation、ephemeral card token、collapsed/expanded projection、visible acknowledgement validation。
- Pane/session/application teardown、最大3秒drain、最大1秒store stop、reopen generation、late event reject。
- O-01〜O-05、R-01、64 pane、worker unavailable、full close/reopenのfake/real-worker focused acceptance。

## 対象外

- `notes`等のtyped config、default、Settings、product composition root activation（CM-06）。
- Exactly-one window input ownerの既存owner統合（CM-07）。
- AppKit view、native ABI decode、sticky-note card drawing/editor/IME/accessibility（CM-08〜CM-09）。
- User-facing action/menuとS1/S2 product integration（CM-10〜CM-11）。
- Shell integration version 3 parser/resource（CM-16）。CM-05のprompt adapterはpure event fixtureだけを受ける。
- `dart_appkit`または他の汎用packageへのDart Terminal固有code追加。

## 依存関係

- CM-01〜CM-04。
- Gate 7 owner table、startup/teardown sequence、transaction/ingress bounds、message schema、review vectors。
- Existing `TerminalApplicationState`、`TerminalSessionId`、restoration lifecycle、CM-03 worker client。

## 分割と実施順

1. **Store lifecycle and serial durable mutation authority**
   - Store port/worker adapter、startup load/reconciliation、capability state、authority generationを実装する。
   - One in-flight＋32 intent/128 KiB FIFO、duplicate/revision handling、commit-success-only publishを実装する。
   - O-01、O-02、R-01、worker unavailable、load/reconciliation failureを検証する。
2. **Bounded topology, focus, and prompt ingress**
   - 最大64 live contextのpane bind/create/closeとfocus edge coalescing、session generation lifecycleを実装する。
   - Sessionごと32 prompt event ring、最大64 session、overflow sessionだけ`suspended(eventOverflow)`、structural supersedeを実装する。
   - O-04、O-05、duplicate/out-of-order/stale session、pane close中eventを検証する。
3. **Projection acknowledgement, teardown, and reopen acceptance**
   - Per-pane latest projection、surface/projection generation、ephemeral card token、collapsed/expanded boundを実装する。
   - Visible current ackだけをdurable mutationへ変換し、duplicate/stale/occluded/late ackをrejectする。
   - Pane close、application freeze/drain/ordered persistence/store stop、reopen generation、O-03、64 pane/full cleanupを検証する。

各サブタスクは個別に検証、記録、ROADMAP更新、commitする。後続サブタスクやCM-06を先行実装しない。

## 完了条件

- Authority以外からstore workerをcommitせず、application rootにcommitted documentとruntime stateのsole ownerが一つだけある。
- Persistent candidateはworkerのmatching success後だけpublishされ、failure/stale/timeoutでは旧document/revision/projectionを保持する。
- Queue、focus、prompt、projection、intent、ackのhard boundとstale/duplicate/supersede semanticsを満たす。
- Pane/session/app teardown順とdeadlineを守り、late eventが新generationへ適用されず、worker/store handleが0になる。
- Diagnostics/resultは本文、persistent ID、path、cwd、title、time、color、hashを含まない。
- Focused test、format、analyze、`make test`、必要なAOT/real-worker test、compatibility freshness、diff/source auditがpassする。

## 検証方針

- Deterministic fake store/surface/sessionでqueue順、fault、duplicate、stale、overflow、ack、teardownを全分岐検査する。
- CM-03 real isolate workerでload→multiple commit→failure/stop/reopenを検査し、authority/client live countが0になることを確認する。
- Native surface実装前なのでAppKit objectを作らず、projection/intentはpure immutable objectで検証する。
- 各サブタスクで隣接`dart_appkit`差分0、root外のproduct-specific code追加0を監査する。

## 2026-09-21: 着手前調査

- ROADMAP、README、FEATURE_MATRIX、implementation plan、Gate 2/3/5/7の凍結仕様を再読し、CM-04完了後の先頭未完了taskが
  CM-05であることを確認した。
- Existing topology/session ownerは既に直列化とgenerationを持つ。Note stateをそこへfieldとして追加せず、content-free event adapterを介して
  application-root authorityへ渡す。
- CM-03 worker clientはauthority generationと一件in-flightを検証するが、pending user intentを保持しない。32 intent/128 KiB admission、
  duplicate/supersede、candidate publish ownershipはCM-05 authority側に必要である。
- CM-01 modelはpersistent accepted、runtime-only、no-change、rejectedを区別する。Persistent acceptedだけをworkerへ送り、runtime-onlyは
  application memoryへ適用し、no-change/rejectedではfilesystem callを行わない。
- Native surface ABIはCM-08で実装するため、CM-05はpersistent IDをnativeへ渡さないephemeral token/projectionとack validationまでを所有する。
- Store lifecycle、event ingestion、projection/teardownを一括するとfailure isolationと個別commitが困難なため、上記3サブタスクへ分割した。

## 2026-09-21: store lifecycleとserial durable mutation authority

### 実装と判断

- `TerminalNoteAuthority`をapplication rootが所有する唯一のNote authorityとして追加した。CM-03 workerを直接公開せず、
  `TerminalNoteAuthorityStorePort`と汎用worker adapterを介してload後のcommit/stopだけを所有する。
- Startupはstrict load resultを分類し、recovery preview/newer schemaを自動更新しない。Accepted loadだけをCM-04 reconcilerへ渡し、
  reconciliation candidateのmatching durable success後に初めてdocument、bindings、ready capability、content-free publicationを公開する。
- Mutation ingressへauthority generation、単調増加sequence、source generation/event sequenceを必須化した。Sourceごとのhigh-watermarkで
  duplicate/staleをstore call前にdropし、source数も64に制限した。Busyを含む一度観測したevent identityは再利用せず、仕様どおり
  implicit retryを行わない。
- Queueは常に1件だけをin-flightとし、その後ろに最大32 intent、in-flightを含むbody申告量合計128 KiBを保持する。
  Full時はcandidateを作らずfixed `busy` resultを返す。Transitionは実行時のlatest committed snapshotへFIFOで適用するため、
  同時到着した異なるmutationもrevision順にcommitされる。
- Persistent mutationはcandidateをworkerへ渡し、disposition、failure、store revisionがcandidateと完全一致した場合だけdocumentを
  差し替えてpublishする。Runtime-onlyはmemoryだけ、no-change/rejected/revision conflictはfilesystem call 0とした。
- Store exception/crash/mismatched successはauthorityをunavailableへ固定し、candidateを捨て、残queueをfailureで完了する。
  Published documentとrevisionは最後のknown-goodを保持し、terminal側の実行経路には例外を伝播しない。
- `stop()`は新規ingressを止め、pending intentを完了し、in-flight終了後にstoreを一度だけstopする。複数回stopは同じFuture/resultを共有する。
- Publicationとresultの文字列表現は本文、context/note ID、path、cwd、title、時刻、色、hashを含まず、件数とrevision/dispositionだけを出す。
- 実装は`dart_terminal`内に限定した。隣接`dart_appkit`にはDart Terminal固有code、API、testを追加していない。

### 失敗した試行と修正

- Queue上限testの最初の試行では、直前mutationのresult Future完了直後に次scenarioを開始したため、`whenComplete`内のin-flight cleanupと
  次のadmissionが同一microtask境界で競合し、期待したpending 32ではなく31を観測した。Authorityの公開resultとidleは別契約なので、
  scenario境界で`whenIdle()`を待つようtestを修正した。Production queue順序やboundを緩める変更は行っていない。

### 検証結果

- `dart format lib/dart_terminal.dart lib/src/terminal_note_authority.dart test/run_tests.dart test/terminal_note_authority_test.dart`:
  4 files、変更0。
- `dart analyze lib/src/terminal_note_authority.dart test/terminal_note_authority_test.dart`: issue 0。
- `dart test/terminal_note_authority_test.dart`: pass。Startup commit-before-publish、O-01、O-02、revision conflict、32 intent、
  128 KiB、R-01、worker unavailable/recovery/startup failure、stopを検証した。
- `make phase7-appkit-acceptance release-candidate-daily-use-matrix`: pass。Phase 7 criteria 5、source refs 20、
  unit tests 16、integration tests 5、UI assertions 11。Aggregate runner追加に伴うdaily-use matrix hashだけを更新した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。363 files format変更0、`dart analyze` issue 0、全aggregate test pass。
  Note store実filesystem 20 runsはcommit p95 160,617 us、primitive p95 21,951 us、contention/recovery/privacyすべてpass。
- `git diff --check`: pass。隣接`dart_appkit`の既存作業差分は変更せず、同packageへのNote固有symbol追加0を確認した。

### 後続への引き継ぎ

- 第2サブタスクは、このauthorityのFIFO mutation入口へcontent-free topology/focus/prompt adapterを接続する。Pane/context/sessionの
  structural lifecycleを先に検証し、projection/ackやnative objectは第3サブタスクまで追加しない。
- Source generationを終了したadapterは`releaseIntentSource`を呼び、64-source high-watermark boundを回収する。
