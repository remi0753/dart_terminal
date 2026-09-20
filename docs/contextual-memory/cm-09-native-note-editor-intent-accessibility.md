# CM-09 native Note editor、intent、accessibility interaction

日付: 2026-09-21
状態: 完了

## 目的

CM-08のproduct-owned native Note surfaceへ、versioned semantic intent/result、標準multiline editor、volatile
draft/selection/IME/Undo、explicit Save/Cancelとcard action、keyboard/VoiceOver interactionを追加する。Native Noteが
ownerの間はterminal PTY/input pathへraw key、IME、paste、mouse、automationを一切流さず、generation/revision conflictを
fail closedにする。

## 背景

- CM-08はmanifest-independentなbadge/rail/card presentationとread-only accessibilityを実装済みである。Application manifestと
  production authority wiringはCM-10まで行わない。
- CM-07のwindow interaction authorityは`noteRail`/`noteEditor` owner identity、request/confirm/cancel、consumed gestureを既に
  持つ。CM-09は別のowner storeを作らず、そのadapterが使うnative interaction contractだけを提供する。
- Native semantic intentはsurfaceごとに最大1件outstandingで、navigation/selection/scrollはnative localである。Persistent
  Note/Context IDをnativeへ渡さず、ephemeral card token、surface/projection/event/draft generation、expected store revisionだけで
  application authorityへ要求する。
- `dart_appkit`は汎用libraryである。Dart Terminal固有のNote editor、intent kind、card action、input policyを追加しない。

## 範囲

- ABI v1 `NoteSurfaceIntent`/`NoteSurfaceResult`のfixed struct、bounded body payload、strict version/reserved/generation検証。
- Save、Cancel、color、move earlier/later、resolve/reopen、delete、reattach、export/copyのfixed intent kindと一件outstanding状態機械。
- Rail内の標準`NSTextView` editor、volatile baseline/draft/selection/marked text/Undo、Save/Cancel、dirty discard confirmation。
- 4,096 UTF-8 bytes、64 lines、non-whitespace、control/bidi/unpaired surrogateの全文admission。Paste/drop/Servicesも同じatomic policy。
- Keyboard/Full Keyboard Access/VoiceOver順、focus ring、outside click no replay、native-local navigationとcard action controls。
- E1〜E5、I1〜I3、F1〜F2、A1/A3相当、adapter-before-view teardown、retained owner 0のmanifest-independent acceptance。

## 対象外

- Root `TerminalNoteAuthority`へのmutation接続、store commit、application manifest登録、menu/palette/action公開（CM-10）。
- Autosave、durable draft、crash recovery、rich text、Markdown、attachment、title/tag、checkpoint control。
- S2/S3 trigger deliveryやshell integration、rollout stage。
- `dart_appkit`へのDart Terminal固有code。

## 依存関係

- CM-08 `dart_terminal_notes_macos` ABI v1、native child surface、projection generation/token。
- CM-07 `TerminalWindowInteractionAuthority`のgeneration-bound owner/gesture contract。
- CM-01〜CM-05のNote body policy、revision conflict、application authority queue。CM-09ではfake result adapterだけを使う。
- AppKit `NSTextView`/`NSInputContext`/Undo/accessibility、code-assets build hook。

## サブタスクと実施順

1. **Semantic intent/result ABIとone-outstanding state**
   - Projectionへdraft generationを追加し、fixed intent/result struct、bounded payload、Dart typed facadeを実装する。
   - Surface/projection/event/draft/token/revision/version/reserved mismatch、duplicate take/result、busy、disposeをatomic rejectする。
   - 完了条件: C/C++ header compile、Dart/native canonical/limit/fuzz、one outstanding、last-good、live owner 0。
2. **Native multiline editor、draft admission、actions**
   - Rail内editor、IME/selection/Undo、Save/Cancel/dirty confirmation、six-colorと全semantic action controlを実装する。
   - Paste/drop/Servicesを同一admissionへ通し、invalid/4,097-byte/65-line operationはdraft全体不変とする。
   - 完了条件: Japanese marked→commit→Save、boundary ±1、store failure/conflict時draft/selection/Undo保持、actual AX controls。
3. **Input isolation、focus/accessibility、teardown acceptance**
   - All input familyのexactly-one consumer、outside click/gesture no replay、automation busy、focus report delta 0、keyboard/VoiceOver順を固定する。
   - ASan/UBSan、Developer JIT/Release AOT host、privacy/source/resource audit、adapter-before-view teardownをaggregateへ接続する。
   - 完了条件: E/I/F/A vector、terminal byte 0、native retained owner 0、package/full gate、`dart_appkit`変更0。

## 完了条件

- Implementation planのCM-09成果物、完了条件、必須検証を満たす。
- Semantic intent/resultはpersistent ID/body echo/free-form errorを持たず、body payloadはSave/explicit copyだけに限定する。
- Dirty closeはSave/Discard/Cancel、outside event replay 0。Native interaction中のterminal raw/IME/paste/mouse/automation byte 0。
- Production wiringを先行せずmanifest-independentに検証できる。`dart_appkit`変更0。

## 検証方針

- Dart canonical codec/property/fuzz、C/C++ header layout、native strict decode/result state machine。
- Actual AppKit editorのmarked text、Undo、selection、paste/drop/Services、button/keyboard/AX action。
- Input/geometry/focus/PTY byte sentinel、stale/duplicate/busy/dispose、ASan/UBSan、JIT/AOT host。
- Package format/analyze/test、root analyze/test、generated freshness、privacy/export/resource audit、隣接repository audit。

## 2026-09-21: 第1サブタスク着手

- ROADMAPを再確認し、先頭未完了がCM-09であることを確認した。README、FEATURE_MATRIX、implementation plan、
  overlay/editor/accessibility、architecture/rollout、data/privacy、CM-07/CM-08実装を照合した。
- IntentをJSON/dictionaryにする案はunknown field、payload種別、allocation boundをfail closedにできないため不採用とした。
  Fixed-size LE structとseparate bounded body bufferを採用する。
- Nativeからpersistent IDを返す案、Dartへper-keystroke draftをmirrorする案、`dart_appkit.TextEditor`へproduct callbackを追加する案は
  ownership/privacy/汎用library境界に反するため不採用とした。
- Application authority結果をnativeが直接storeへ反映する案も不採用とした。CM-09はfixed resultだけを受け、accepted projectionは
  後続のCM-10 adapterが別generationとしてapplyする。
- `dart_appkit`は読み取り監査だけとし、着手前からの3変更へ触れない。

### 第1サブタスクの実装と判断

- Projection headerの予約領域へ64-bit `draftGeneration`を追加した。Editor inactiveは0、creating/editingは正数、creatingは
  selectionなし、editingは既存ephemeral token selectionありをDart/native双方でstrict検証する。
- `DtnSurfaceIntentV1`は112 bytes、`DtnSurfaceResultV1`は88 bytesのfixed C ABIとした。Intentはsurface/projection/event/
  draft generation、ephemeral token、expected 64-bit store revision、fixed kind、payload byte count、palette keyだけを持つ。
  Resultは同じgeneration tuple、fixed disposition、新store revision/projection generationだけを持つ。
- Fixed kindはSave/Cancel/Change Color/Move Earlier/Move Later/Resolve/Reopen/Delete/Reattach/Export/Copyとした。
  Body payloadはSave/Copyだけ、palette keyはSave/Change Colorだけに許可し、それ以外の組み合わせ、unknown enum、reserved bit、
  4,096 bytes超過、invalid bodyをpacket全体rejectする。
- Surfaceごとにone outstanding intentとone-shot takeを実装した。Pending中は新intentを`busy`、undersized takeはpending保持、
  duplicate takeはnot-found、mismatched/duplicate resultはstaleとする。Accepted mutationはstore revisionとprojection generationの
  両方の前進を必須にし、conflict/rejected/busy/unavailableはcurrent revision/generation以外を拒否する。
- New projectionが先に来た場合はpendingをgeneration-boundにinvalidateする。Resultだけでlast-good projectionを変更せず、
  application authorityがcommit後に次projectionをapplyする境界を維持した。
- Dart facadeはtyped intent/body/colorとtyped resultを公開する。Machine snapshotへはdraft generation、outstanding bit、bounded
  emitted/result countだけを追加し、body/color/tokenを追加していない。Privacy auditのproduction export allowlistは14 symbolsとなった。

### 第1サブタスクの現時点の検証

- `make terminal-notes-contract-check terminal-notes-native-test`: pass。C11/C++20 struct size、editor projection、Save payload、
  one outstanding、undersized/duplicate take、stale/conflict/accepted result、4,096/+1、content-free counts、owner 0を確認。
- `make terminal-notes-dart-test`: package format 9 files 0 changed、analyze issue 0、draft generation codec/invariant、typed
  intent/result facade、native assetをpass。
- `make terminal-notes-capability-audit`: pass。manifest 0、snapshot content-free、exports 14、generic `dart_appkit`を確認。
- 初回package gateはformatterが2 edited filesを要formatとして停止し、通常のwrite modeでformatした。次の実行は0 changes。
  続くanalyzeでtest fakeがinternal status constantを参照した1 errorを検出したためliteral ABI success 0へ修正し、再実行でpassした。

### 第1サブタスク完了

- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。370 root files format 0 changed、root/package analyze issue 0、
  全native/package/generated/freshness/compatibility/application/distribution/security testと`dart_terminal tests passed`を確認。
- `make product-native-sanitizer`: pass。5 suites/11 ASan artifacts/9 UBSan artifacts。Notes library/harnessは
  intent/result state machineを含めASan/UBSan instrumentation下でpassした。
- `git diff --check`: pass。Root application manifest/dependency登録0、`dart_appkit`変更0。
- Editor view、IME/Undo、buttons/dirty confirmationはまだ実装しておらず、第2サブタスクの対象である。

## 2026-09-21: 第2サブタスク着手

- ROADMAPを再確認し、CM-09の先頭未完了が「native multiline editor、draft admission、actions」であることを確認した。
- EditorはCM-08 rail内のselected card/list領域を置換するproduct-owned `NSTextView` compositionとする。別window/sheetや
  `dart_appkit`変更は行わない。
- Draft bodyをDartへchange eventとして送る案はper-keystroke mirrorとprivacy境界に反するため不採用とする。Text、selection、
  marked text、scroll、Undoはnativeに保持し、Save時だけbounded snapshotをsemantic intentへ載せる。
- Six-color選択はdraft-localとし、Save intentのpalette keyへ含める。既存cardのread-mode color changeは独立semantic intentとする。
- Paste/drop/Servicesごとに別validationを作らず、candidate全文を一つのadmission関数へ通す。Invalid operationはtext storage、
  selection、Undo、baselineを全て変更しない。

### 第2サブタスクの実装と判断

- CM-08のrail内へstandard `NSTextView`を持つeditor cardを追加した。本文、selection、marked text、scroll、Undo、baseline、
  draft colorはnativeだけが保持し、同じ`draftGeneration`のprojectionでは再初期化しない。新しいdraft、accepted Save/Cancel、
  teardownだけがUndoを破棄する。
- Editor cardは6色のsurface/accent、multiline body、fixed local error、Save/Cancel、dirty時のDiscard/Keep Editingを持つ。
  Command+ReturnはSave buttonのnative key equivalentとし、Save前にmarked textをcommitしてから全文をsnapshotする。
- `DtnPlainTextView`のreadable/acceptable pasteboard typeをplain text一種へ限定した。Typing、IME commit、paste、plain-text
  drop、Services returned textは全て`NSTextViewDelegate`の同じcandidate全文admissionを通る。Rich/custom/file URLはreaderへ
  入れずrejectする。
- Draft admissionはUTF-8 4,096 bytes以下、64 lines以下、control/bidi/unpaired surrogateなしを毎operationで判定する。
  空またはwhitespace-onlyは編集途中だけ許し、Saveではnon-whitespaceを必須とする。Reject時はtext、selection、Undo action、
  baselineを変更せずfixed local errorだけを表示する。
- Read modeにはEarlier/Later、Resolve/Reopen、Delete、Reattach、Export、Copyと6色controlをactual AppKit controlとして追加した。
  Deleteは独立した二回目のconfirmation actionを必要とする。Saveとexplicit Copy以外はbody payloadを作らない。
- UI eventはsurfaceのlast event generationから単調増加させ、public `dtn_surface_request_intent`へ集約した。Outstanding中は全semantic
  controlをdisableし、failure/conflictではdraft/selection/Undoを維持して再enableする。Accepted mutation後はauthorityから次の
  projectionが来るまでdisableを維持し、resultだけでlast-good projectionを変更しない。
- English/Japanese label、system focus ring、explicit AX role/nameをeditor、buttons、color controlへ付与した。Editor表示中はcard bodyを
  AX treeから外してeditor body一件だけを数え、read modeではcard actionをhoverに依存せず常設する。
- `dart_appkit`へeditorやNote intentを追加する案は採用していない。実装は`dart_terminal_notes_macos`内に閉じ、隣接repositoryは
  着手前から存在する3変更を含め読み取り監査だけとした。

### 第2サブタスクの検証

- `make terminal-notes-native-test`: pass。実`NSWindow`/`NSTextView`でJapanese marked→commit→Save、Undo、selection、
  4,096/4,097 bytes、64/65 lines、whitespace Save、bidi/unpaired surrogate、plain-text paste/drop/Services admission、
  file URL reject、conflict保持、dirty confirmation、6色、Copy/Delete、actual AX control、owner 0を確認した。
- `make terminal-notes-contract-check terminal-notes-dart-test terminal-notes-capability-audit`: pass。Package format 9 files
  0 changed、analyze issue 0、native asset、manifest absent、content-free snapshot、14 exports、generic `dart_appkit`を確認した。
- `make product-native-sanitizer`: pass。5 suites、11 ASan artifacts、9 UBSan artifacts。Notes editor/intent harnessを含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。370 root files format 0 changed、root/package analyze issue 0、
  native/package/generated/freshness/compatibility/application/distribution/security、Developer JIT/Release AOT hostを含む。
- `git diff --check`: pass。Application manifest/dependency登録0、`dart_appkit`変更0。

### 第2サブタスク完了

- Rail内editor、atomic draft admission、Save/Cancel/dirty confirmation、six-colorと全fixed semantic actionの実装・受け入れを完了した。
- Window interaction authorityとのall-input routing、Escape/outside click、focus/VoiceOver順、adapter-before-view teardownのaggregate
  acceptanceは第3サブタスクで実施する。

## 2026-09-21: 第3サブタスク着手

- ROADMAPを再確認し、CM-09の先頭未完了が「input isolation、focus/accessibility、teardown acceptance」であることを確認した。
- CM-07のsole `TerminalWindowInteractionAuthority`、12 input family、generation-bound transfer、consumed Note gestureを再確認した。
  別authorityやnative owner stackは作らず、Note surfaceごとの薄いproduct adapterで既存authorityを使用する。
- Native draft本文をDartへmirrorしてdirty判定する案はprivacy/ownership境界に反するため不採用とする。既存snapshotの予約領域を
  content-freeなinteraction flagsとfocus targetへ割り当て、struct size/versionを変えずdirty/confirm/focusだけを同期する。
- Native focusを`dart_appkit`固有widget APIへ追加する案は不採用とする。Note capability自身がrail/editor内のfirst responderを選ぶ
  bounded focus callを公開し、root adapterはnative focus成功後だけauthority transferをconfirmする二段階を維持する。
- Outside clickをterminalへhit-test replayする案は不採用とする。Note owner中は既存routerがcurrent eventをconsumeし、cleanなら
  terminal focus transfer、dirtyならinline discard confirmationへ遷移する。どちらも同じmouse eventをterminalへ再配送しない。
- Production manifest/dependency、Note store mutation、menu/action公開はCM-10のままとする。第3サブタスクではmanifest-independentな
  native harness、pure product adapter test、既存window-interaction runtime gateへのtest-only exerciseだけを接続する。

### 第3サブタスクの実装と判断

- `TerminalWindowNoteInteractionAdapter`を既存のsole `TerminalWindowInteractionAuthority`の薄いproduct adapterとして追加した。
  Rail/editorへの移行はnative focus成功後にだけauthorityをconfirmする二段階とし、stale/busy/focus failureは
  current ownerを変更せずfail closedにする。
- Authorityの12 input familyをNote owner時は全てNoteへのみrouteし、terminal raw byteとfocus reportを0に保つ。
  AutomationはNote owner中busyとし、gestureはrelease時にconsumeする。Clean/dirtyのoutside clickはどちらも現在eventを
  terminalへreplayせず、dirtyはinline confirmation、cleanは別のexplicit focus resolutionまでterminal入力を再開しない。
- Native snapshot ABIの予約済み8 bytesを`interaction_flags`/`focus_target`に割り当てた。ABI v1は160 bytesのままで、
  dirty/confirm/focus以外のbody、selection、tokenをDartへ出さない。`dtn_surface_focus`はrail/editorの有界targetだけを受ける。
- Marked textはcomposition開始時のbaseline/selection/replacementを保存し、composition中の変更はUndo登録しない。
  Commit時はbaselineから1つのUndoable editにし、最初のEscapeはcompositionだけをcancel、次のEscapeはdirty confirmation/
  Cancelを実行する。Accepted Save/Cancel、inactive projection、teardownはtext/baseline/Undo/generationを破棄する。
- Editor/confirmation表示に応じてAX childrenとkeyboard traversalを確定し、rail/editorへのfocus targetもsnapshotで観測できる。
  Viewを破棄する前にadapter ownerとgestureをreleaseし、delegate、Undo、native ownerを残さない。
- A1のうちCM-09で確定済みのSave/Cancel/color/reorder/resolve/delete/reattach/export/copyのnative action controlsを受け入れた。
  S2/S3 trigger selectorはこのnative editor固定ABIへ先行追加せず、CM-11/CM-17でproduct trigger stateと共に実装する。

### 第3サブタスクの検証

- `make terminal-notes-native-test`: pass。Actual AppKitのAX tree/key order、rail/editor focus、content-free dirty/confirm/focus snapshot、
  marked text Escape、accepted action後のdraft/Undo消去、read-mode action順を確認した。
- `make terminal-notes-contract-check terminal-notes-native-test terminal-notes-dart-test terminal-notes-capability-audit`: pass。
  Package format 9 files 0 changed、analyze issue 0、ABI header C/C++ compile、exports 15、manifest absent、snapshot content-free、
  generic `dart_appkit`を確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_window_interaction_test.dart`: pass。12 input familyのexactly-one consumer、
  automation busy、stale request、gesture/outside no-replay、dirty confirmation、focus report/terminal byte sentinel 0、teardown順を確認した。
- `make RUNTIME_ARCH=arm64 terminal-notes-acceptance`: pass。Developer JIT/Release AOTの実AppKit integration、
  `geometry_delta=0 terminal_bytes=0 native_owners=0`、Notesを含む5 sanitizer suite/11 artifactを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。370 root files format 0 changed、root/package analyze issue 0、
  native/package/generated freshness/compatibility/application/distribution/securityと`dart_terminal tests passed`を確認した。
- `phase7_acceptance_v1.json`、`ghostty_p0_p1_gap_inventory.json`、`release_candidate_daily_use_matrix.json`は、
  変更したapplication/runtime smoke/Makefileのsource hashだけをgeneratorで更新し、各freshness checkをpassした。
- `git diff --check`: pass。`../dart_appkit`は着手前からの3変更のみで、Dart Terminal固有のNote code/referenceを0に保った。

### CM-09完了

- Intent/result、native editor/actions、input isolation、focus/accessibility、teardownをmanifest-independentに実装し、CM-09の全完了条件を満たした。
- Production manifest、durable authority/store mutation、menu/palette、Quick Terminal lifecycleはCM-10、On Return triggerはCM-11、
  At Next Prompt triggerはCM-17まで未実装である。
