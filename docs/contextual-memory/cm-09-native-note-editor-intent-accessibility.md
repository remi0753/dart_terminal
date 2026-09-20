# CM-09 native Note editor、intent、accessibility interaction

日付: 2026-09-21
状態: 実装中

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
