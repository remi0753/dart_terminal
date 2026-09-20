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

## 2026-09-21: bounded topology、focus、prompt ingress着手

### 目的と範囲の再確認

- ROADMAPの先頭未完了がCM-05第2サブタスクであることを再確認した。第1サブタスクのstore/serial authorityを拡張し、
  topology/focus/session/promptだけを扱う。Projection、native ack、application shutdown persistenceは第3サブタスクまで実装しない。
- `TerminalApplicationState`は最大64 paneのtopology sole owner、`TerminalPaneOwner`は`TerminalSessionId` sole ownerのまま維持する。
  既存classへNote fieldを埋め込まず、composition rootが内容を持たないeventをauthorityへ注入する。
- `dart_appkit`は変更しない。Terminal固有のcontext、pane、session、prompt semanticsはすべて`dart_terminal`側に置く。

### 採用する内部構造

- Authority startup時のCM-04 bindingsからlive pane/context表を初期化し、新規standard paneはsecure ID generatorを注入してcontextを作る。
  Quick Terminalは既存singleton contextを再利用し、hideをdetachとして扱わない。
- Focusはcontextごとにconsecutive duplicateをdropし、未処理のaway/return edgeを各1件、最大2 edgeまでcoalesceする。
  Modelのlifecycle batchを最大2 edge対応にして、away→returnを一つのdurable candidateへ畳みつつ順序を保持する。
- Promptはcurrent `TerminalSessionId`、instance、semantic generationへbindし、sessionごと32 event、全live session 64に制限する。
  Duplicate/out-of-order/wrong generationはmodelへ渡さず、33件目でそのsessionだけを`eventOverflow`へsuspendする。
- 最初のfocus/prompt event到着時にcontext単位の内部drain placeholderをserial queueへ一つだけ置く。後続eventはそのplaceholderへ
  coalesceし、transition開始後に到着したeventは完了後の新placeholderへ送る。これにより別user mutationとのarrival orderと
  一件in-flightを維持し、lifecycle ingressを32 user-intent上限へ誤算入しない。
- Pane close/session replacementは未実行placeholderのeventをstructurally supersedeする。Pane close後のeventはstale rejectし、
  session replacementではold bindingだけを`instanceChanged`へsuspendしてS1/S2と別sessionを保持する。

### 完了条件と検証方針

- 64 pane/context/session境界、focus away→return、duplicate focus、prompt 32/33、別session isolation、O-04、O-05、
  old generation/instance/out-of-order、pane close中late event、structural supersedeをdeterministic fake storeで検証する。
- focused format/analyze/test、compatibility freshness、`make test`、privacy/source/diff auditをpassしてからROADMAPを更新しcommitする。

### 実装結果

- Startup reconciliationのstandard pane bindingsからauthority-owned live pane表を初期化し、`bindPane`/`closePane`を追加した。
  Standard pane createは注入されたsecure context ID generatorで新contextを作ってdurable success後だけCM-04 bindingsへ公開する。
  Close admissionはruntime bindingとevent ingressを即時invalidateし、standard context detachをserial durable queueへ送る。
- Quick Terminal bindは既存singleton contextだけを再利用し、同時に二paneへbindしない。Close/hide相当ではcontextをdetachせず、
  standard restoration pane listへ混入させない。
- Live pane/contextとprompt sessionをそれぞれ64件へ制限した。Dynamic context create、session start/replacement/end、focus/prompt eventは
  すべてcallerが採番したauthority sequenceを消費し、old authority、old pane/session/instance/semantic generationをstore call前にrejectする。
- Focus ingressはconsecutive duplicateをdropし、未実行placeholder内にaway/return各1 edge、最大2件を保持する。
  away→return→awayの3件目は最初のcycleを失わず、drain後にfinal awayを次batchへ送る。Pure modelのlifecycle batchも最大2 edgeを
  一store revisionへcoalesceするよう拡張した。
- Prompt ingressはsessionごと最大32 eventを保持する。33件目はringを破棄してoverflow markerだけを残し、そのsessionのmatching
  at-next-prompt triggerを`eventOverflow`へdurable suspendする。False deliveryは作らず、別sessionのring/deliveryは継続する。
- Session/instance replacementはold ringをstructurally supersedeし、old runtime bindingだけを`instanceChanged`へsuspendする。
  Session endは`sessionEnded`、pane closeはcontext detachでtrigger/runtime bindingを閉じ、late eventをstale rejectする。
- Lifecycle placeholderは最初のeventのarrival位置でuser/structural mutationと共通queueへ入るが、32件のuser-intent上限には算入しない。
  Transition開始後に到着したeventは完了後の次placeholderへ送られ、常に一件in-flightとFIFOを維持する。
- Public lifecycle result、publication、mutation resultは固定enumと件数だけで、body、persistent ID、path、cwd、title、時刻、色、hashを含まない。

### 失敗した試行と修正

- 最初のO-05 testでは33件目を`overflowed`へ固定してringを消去したが、durable drain用の`overflowPending` markerを立てていなかった。
  そのためtriggerは`atNextPromptWaitingCommand`のまま変化しなかった。Sessionの恒久的overflow状態と一回だけ消費するpending markerを
  分離し、33件目で両方を設定するよう修正した。修正後はoverflow sessionだけがsuspendedとなり、別sessionは同じqueue内でdueへ進んだ。
- Queue内でfocus edgeが2件に達した後のthird edgeを単純dropすると最終eligible stateを失うため、`lastObservedEligibility`と
  `lastDrainedEligibility`を比較して次batchへ一件だけ補う方式を採用した。これによりhard boundを増やさずedge orderと最終状態を保つ。

### 検証結果

- `dart format`（model、authority、authority test）: 変更後format済み。
- `dart analyze`: repository全体 issue 0。Focused source/test解析もissue 0。
- `dart test/terminal_note_model_test.dart`、`dart test/terminal_note_authority_test.dart`、`dart test/run_tests.dart`: pass。
  Focus away/return/third-edge、dynamic bind/detach、late focus、prompt 32/33、duplicate/out-of-order、O-04、O-05、別session isolation、
  old instance、64 pane/session exact boundと65件目拒否を検証した。
- `make phase7-appkit-acceptance release-candidate-daily-use-matrix`: pass。生成差分0。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。363 files format変更0、全analyze/test/privacy/security/
  compatibility/release gate pass。Note store 20 runsはcommit p95 137,532 us、primitive p95 14,640 us、
  contention/recovery/privacyすべてpass。
- `git diff --check`: pass。隣接`dart_appkit`は開始前からの3ファイル以外に差分0で、Note authority/lifecycle symbol追加0。

### 第3サブタスクへの引き継ぎ

- Pane closeのsurface invalidation、projection/ack、application freeze/drain/ordered persistence/store stopは未実装であり、次サブタスクで
  既存live pane/session registryとserial queueへ接続する。
- `contextForPane`と`promptBindingForSession`はapplication-root integration用であり、persistent context IDやshell instance IDを
  native projectionへ渡してはならない。

## 2026-09-21: projection acknowledgement、teardown、reopen acceptance着手

### 目的と境界の再確認

- ROADMAPの先頭未完了がCM-05第3サブタスクであることを確認した。CM-05を閉じるため、pure/fake surface contract、ack、
  application shutdown、real worker reopen acceptanceを実装する。AppKit view/ABI decoder/editor/input owner/product actionはCM-07〜CM-10の範囲である。
- Projection型とfake portは`dart_terminal` product packageに置く。Terminal固有card、trigger、pane、ack protocolを汎用
  `dart_appkit`へ追加しない。CM-08のnative packageはこのcontractを実装する従属capabilityになる。

### 採用する設計

- Paneごとにsurface generationとlatest accepted projectionを一件だけ保持する。Projection version 1はruntime pane、surface/projection
  generation、committed store revision、content-free badge count/stateを持つ。Collapsedはcard/body 0、expandedはCurrent contextの
  ordered card最大64件、aggregate body最大256 KiBとする。
- `CardToken`はauthority process内の単調opaque tokenで、current projectionからpersistent `NoteId`へだけ解決する。
  `toString`、projection diagnostics、native-visible objectへNote/context IDを出さず、projection replace時にtoken mapを全交換する。
- Surface portはcandidate projectionをatomic applyできたかだけを返す。Reject/exception時はlast accepted projection/token mapを保持し、
  ack対象を進めない。Native implementationやAppKit objectをCM-05では作らない。
- Ackはcurrent `(surfaceGeneration, projectionGeneration, cardToken)`、expanded、foreground、not occluded、visible layoutをすべて満たし、
  current deliveryのtrigger generationと一致する場合だけserial durable mutationへ変換する。Pending duplicate、stale、occluded、late close ackはdropする。
- Pane closeはsurface/session/event generationを同期的にinvalidateしてからdetach mutationをqueueへ置き、surface dispose完了もclose Futureへ含める。
- Application shutdown APIは新規user/topology/focus/prompt/surface ingressをfreezeし、既存queueを最大3秒drainする。Drain成功後に
  CM-04 candidate builderとordered coordinatorでrestoration exact bytesを先、Note bindingを後にcommitする。その後surfaceをdisposeし、
  storeをstopする。Timeout/preparation/persistence/stop failureは固定結果に分類し、contentを含めない。
- Reopenは新authority generationでworker loadとexact restoration reconciliationをやり直し、旧surface/session/token/ackを受理しない。

### 完了条件と検証方針

- Collapsed body 0、expanded 64/256 KiB、latest-one replacement、surface reject last-good、ephemeral token、visible ack一回、O-03をfake surfaceで検証する。
- 64 surface attach/dispose、freeze/drain deadline、restoration-first順、persistence failure、full cleanupをfake storeで検証する。
- 実temporary filesystemのCM-03 isolate workerでcreate→shutdown→stop/lock release→reopen/reconcile→cleanupを検証し、
  `TerminalNoteStoreWorkerClient.debugLiveClientCount`がbaselineへ戻ることを確認する。
- Format/analyze/focused/aggregate/AOT、compatibility freshness、`make test`、privacy/source/diff auditをpassしてからCM-05 parentを完了する。

### 実装結果

- `TerminalNoteSurfaceProjection`と`TerminalNoteSurfacePort`をproduct側のpure Dart contractとして追加した。Projectionはprotocol version、
  runtime pane ID、surface/projection generation、committed store revision、表示状態、件数、bounded cardだけを持つ。Collapsed projectionは
  card/bodyを含まず、expanded projectionは最大64 cardsかつaggregate body 256 KiBで打ち切る。
- Cardはprocess-local opaque tokenで識別し、persistent Note/context IDをsurfaceへ公開しない。Accepted projectionを置換した時だけtoken mapを
  全交換し、portがcandidateを拒否または例外にした場合はlast-good projectionとack対象を保持した。
- Surface attach/update/detachをapplication-root authorityのserial ingressへ統合した。Foregroundかつunoccluded expanded surfaceで、current
  surface/projection/tokenとvisible layoutを満たすackだけを一回のdurable presentation ackへ変換した。Pane closeはregistryとsurfaceを先に
  invalidateするため、durable detach待ちのlate ackもstaleとなる。
- Application shutdownはcapabilityを`draining`へ遷移して全ingressをfreezeし、admitted queueを最大3秒drainする。成功時はexact restorationを
  Note bindingより先にcommitし、surface dispose、store stop、registry clearの順で解放する。Drain timeout時はlate worker resultを破棄し、
  restoration failure時はNote commitを開始せず、どちらもstore stopまで実行する。
- Reopenは新authority generationからfresh surface generationを割り当て、CM-03 workerを停止してlock/clientを解放後、同じdirectoryから
  committed snapshotとexact context bindingを再構築する。Authority/client live countは終了後baselineへ戻る。
- `dart_appkit`には変更を加えていない。Terminal固有のNote projection、pane lifecycle、trigger、ack、shutdown policyはすべて
  `dart_terminal`側に留め、後続のnative実装はこのproduct-owned portを満たす形に限定した。

### 失敗した試行と制約

- `dart compile exe test/terminal_note_authority_test.dart`で作ったraw executableは、CM-03 workerが使用するdynamic libraryのNative Assetsを
  同梱しないためreal-worker testで起動できなかった。これはsource/testの不具合ではなくbuild hookを迂回した生成方法の制約である。
  正規の`dart build cli --target=...`で4 native assetsを含むbundleを生成し、そのAOT executableで同じtestを完走させた。
- Projectionの256 KiB上限はcard body UTF-8 byte合計に対する契約である。CM-08のwire decoderは固定headerなどを含む自身のencoded input上限も
  別途fail-closedで検証する必要がある。

### 検証結果

- `dart format`（projection、authority、authority test）: format済み。
- `dart analyze`: repository全体 issue 0。
- `dart test test/terminal_note_authority_test.dart`: pass。Collapsed body 0、expanded exact 64 cards/256 KiB、latest-one、reject時last-good、
  opaque token、visible ack一回、O-03、64 surfaces、freeze/drain、ordered persistence、failure/timeout、fake reopenを検証した。
- `dart test test/run_tests.dart`: pass。Note store acceptanceはcommit p95 130,046 us、primitive p95 14,149 us、
  contention/recovery/privacyすべてpass。
- `make phase7-appkit-acceptance release-candidate-daily-use-matrix`: pass、生成差分0。
- `dart build cli --target=test/terminal_note_authority_test.dart --target-os=macos --target-arch=arm64`: pass、4 native assetsを同梱。
  生成したAOT executableのauthority testもpassし、実filesystem create→shutdown→reopen→cleanupを完走した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。363 filesのformat変更0、全analyze/test/privacy/security/
  compatibility/release gate pass。Note store 20 runsはcommit p95 132,086 us、primitive p95 14,018 us、
  contention/recovery/privacyすべてpass。
- `git diff --check`: pass。隣接`dart_appkit`の差分は着手前から存在する3ファイルだけで、本タスクによる変更は0。

### 後続タスクへの引き継ぎ

- CM-06はauthority生成前のtyped configuration、disabled時のstore/surface/shell非生成、enable/disable/re-enableの完全teardownを実装する。
- CM-08はこのpure Dart surface portに従う汎用native transport/view capabilityを構成するが、Terminal固有projection decoderやproduct actionは
  `dart_appkit`へ入れず、product側からbounded bytes/callbackを注入する境界を維持する。
