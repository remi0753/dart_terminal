# Context Dock Developer JIT runtime regression

- Status: complete
- Date: 2026-09-14
- Scope: `make RUNTIME_ARCH=arm64 developer-jit-run`の通常製品起動
- Related: UI-02、UI-05、IN-09、AX-01、SEC-05

## 目的と背景

通常のDeveloper JIT製品を起動してContext Dockを表示した時に、Directory Navigatorへworking directory、
file／folder tree、検索結果が投影されず、パネル表示中のterminal入力ごとにmacOSのビープが発生する回帰を
修正する。先行taskのnative-content acceptance専用scenarioではtree／searchとkeyboard routingが成功しているため、
acceptance flagに依存する初期化、通常shellのprocess/cwd authority、Dock表示後のnative first responder、window key
event routingの差を明らかにし、通常起動そのものを受け入れ対象へ追加する。

## 範囲

- `developer-jit-run`とnative-content acceptance起動のenvironment／argument／initialization差の調査
- 通常interactive zshにおけるtrusted cwd resolution、privacy admission、directory/search operationの状態確認
- Context Dockの表示／reparent／reconcile後もterminal viewがfirst responderであり続ける契約
- `Shift+Command+F`後だけNavigatorが入力を所有し、それ以外のterminal入力でビープやPTY write欠落がないrouting
- working directory treeとquery検索の通常起動回帰test、Developer JIT／Release AOT受け入れ、文書・証跡更新

## 対象外

- 新しいContext Dock module、file content検索、Finder代替、remote／SSH directory provider
- terminal processへhidden `pwd`／`find`／`ls`を送る回避策
- shortcut、search ranking、path handoff仕様の再設計

## 依存関係と前提

- `TerminalContextDockState`、`TerminalContextDockDirectoryController`、
  `TerminalContextDockDirectoryPresenter`のvisibility／input-owner／generation契約
- `TerminalNativeHierarchyAdapter`のtab root decoration、layout reconcile、terminal text-input client ownership
- `TerminalWorkingDirectoryResolver`と`TerminalSession.workingDirectorySnapshot()`のlocal cwd authority
- application action／window event／native first responder routing、および既存の両runtime native-content scenario
- user報告を再現条件の正本とし、terminal outputやpath内容を診断へ永続化しない

## 完了条件

- 通常Developer JIT起動でContext Dockを検索なしに表示すると、focused local paneのworking directoryとtreeが出る。
- `Shift+Command+F`から入力したqueryがcurrent subtree以降の検索を開始し、結果またはtyped coverageを表示する。
- Dock表示中でもterminal ownershipなら通常入力がexactly onceでPTYへ届き、macOSビープを発生させない。
- Navigator ownership中は検索／navigation keyだけがDockへ届きPTY writeは0、`Escape`でterminalへ戻る。
- focused test、format、analysis、generated freshness、full `make test`、Developer JIT／Release AOTの通常製品受け入れが成功する。

## 検証方針

- まず通常runとacceptance runの起動引数、shell state、Dock snapshot、native first responderをcontent-freeな状態で比較する。
- fake AppKit／state testでDock root decoration後のterminal responder保持、検索focus、Escape復帰、key eventのexact routingを固定する。
- runtime smokeにacceptance flagなしの通常起動経路を追加し、cwd/tree/search、terminal input、beepを生む未処理native key経路、cleanupを検証する。
- Developer JITで再現修正を確認後、Release AOT、privacy/localization/Phase 7 freshness、full gateを実行する。

## 調査記録

### 2026-09-14 着手

- user環境では`make RUNTIME_ARCH=arm64 developer-jit-run`で右Context Dockのdirectory情報が空になり、file検索も機能しない。
- 同じbranchの受け入れ専用`developer-jit-native-content`はtree、search、path handoff、privacy、cleanupに成功している。
  したがってfilesystem/search primitiveそのものより、通常起動だけに残るstate initializationまたはnative focus projectionを優先して調べる。

### 2026-09-14 通常起動の再現結果

- 指定どおり`CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 developer-jit-run`で通常製品を起動し、
  View menuの`Toggle Context Dock`を実行した。native accessibility treeと画面の双方で、Dockは
  `TERMINAL INPUT`、`Working directory: Unknown`、`Remote directory browsing is not available`を表示した。
- この状態で実physical相当の文字入力を送ってもterminalのaccessible valueと画面が更新されず、user報告のビープ／入力欠落を再現した。
  `Shift+Command+F`後は`NAVIGATOR INPUT`となりquery自体は更新されたが、cwdがremote-unavailableなので検索operationは開始されなかった。
- 通常zshのpromptはlocal filesystem上にあり、PTYのowning processもlocalである。一方、user startup hookがbundled integrationより後に
  machine hostname付きOSC 7を送るため、`TerminalWorkingDirectoryResolver`がhostを`localhost`以外という理由だけでremoteと判定し、
  同じchild PIDについてkernelから得たlocal cwdを調べる前に終了していた。受け入れfixtureは最終的にplain `sh`へ移りOSC 7を持たないため、
  この通常startup競合を覆っていなかった。
- Dock表示時はnative windowのcontent rootがterminal viewからouter splitへ置き換わる。native hierarchyはlogical tab／pane focusが変わらない
  reconcileでは`makeFirstResponder`を再実行しないため、reparentされたterminal viewがfirst responderを失い、terminal ownershipのまま
  keyを受けられなかった。既存native testはDock visibleで初期windowを作る経路だけで、hiddenから表示する経路を検証していなかった。
- Navigatorはquery編集をDart-owned stateで行うread-only native editorなのに、window routingが`dartAndAppKit`だった。Dartで処理済みの
  printable keyをAppKitのread-only editorにも配送するため、検索queryは更新されてもAppKitが編集不可ビープを発生させる。command paletteと
  他のread-only presenterが使う`dartOnly`がこのownershipに対応する設定である。

### 採用する修正境界

- non-local host付きOSC 7を無条件でlocal authorityにはしない。owning shellとforeground process groupが一致し、同じchild PIDのkernel cwdが
  safe absolute pathとして取得できる場合だけ、そのOS cwdをlocal authorityとして採用する。別foreground processが所有する場合、PID mismatch、
  cwd取得不能時は従来どおり`remoteUnavailable`とし、local launch cwdへfallbackしない。
- Dock rootを新規表示または別tab／paneへreparentした時だけinput-owner projectionをpendingにし、hierarchy reconcile後にterminal ownerなら
  focused terminal view、Navigator ownerならread-only editorをfirst responderへ戻す。通常のoutput／layout reconcileごとにfocusを奪わない。
- Navigator ownershipのwindow key routingは`dartOnly`へ変更し、すべての編集／navigation keyを既存controllerで消費する。terminal ownershipへ
  戻す時は従来どおり`appKitOnly`とする。

### 実装中の失敗と修正

- source format時に誤って`ROADMAP.md`と本task memoも`dart format`の引数へ含めた。Dart sourceのformatは完了したが、Markdown 2件には
  想定どおりparse errorが出た。Markdownには変更が入っていないことを差分で確認した。以後は`.dart`だけを明示してformatする。
- 最初のformat／analysisでは、`_shouldShow`通過後のnullableなDock snapshotをそのまま参照した3箇所がstatic errorになった。
  通過直後にnon-nullな`visibleDock`へ束縛するよう修正し、再format後にfocused testとanalysisを再実行する。
- sandbox内の最初のfocused validationは、解析自体は`No issues found!`まで到達したものの、Dart telemetry session fileのmtimeを
  workspace外で更新できず終了コード1になった。`CI=true DART_SUPPRESS_ANALYTICS=true`を付けた再実行では全件成功した。
- 最初のDeveloper JIT native-content実行はMetal compilerのmodule cacheが`~/.cache/clang`にありsandboxから書けず失敗した。
  同じcommandを通常権限環境で再実行した。
- runtime scenarioへraw testing key eventを入れてDock表示後のPTY writeを数えようとしたが、このfixtureのevent injectionはnative AppKit
  `sendEvent:`ではなくDart event sinkへの直接注入である。`appKitOnly`中はDartへ届かないのが正しいため、当該assertionは不適切だった。
  これを削除し、fake native bindingsでfirst responder handleとroutingを自動検証し、通常起動の実AppKit入力はGUI操作で検証する。
- 通常起動を修正版でGUI再確認するとcwd/treeは復旧した一方、Dock表示後のaccessibility focusはterminalではなくwindowへ戻っていた。
  presenterは最初のreconcile後にterminalをfirst responderへ戻していたが、非同期directory snapshotの次のreconcileでも同一childを
  `TwoPaneSplitView.setChildren`へ再設定していた。実AppKitではこの冗長なremove/re-addがfirst responderを失わせ、projection pendingは
  既に消費済みなので再修復されなかった。child identityが変化した時だけ`setChildren`を実行し、その時はfocus projectionもpendingにする。

### 2026-09-14 通常起動の修正後GUI確認

- user指定と同じ`CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 developer-jit-run`で再ビルド／起動し、View menuの
  `Toggle Context Dock`だけを実行した。Dockは`Working directory: /Users/remi/dart/dart_terminal`とfolder-first treeを表示し、
  accessibility focusはwindowではなくterminal text-inputへ残った。
- Dock表示中に実AppKit経由でprintable inputを送るとterminal promptへ反映され、入力欠落は再現しなかった。次にView menuの
  `Search Files and Folders`でNavigatorへ移るとaccessibility focusもDirectory Navigatorへ移り、`ROADMAP`入力直後にcurrent subtreeの
  `/Users/remi/dart/dart_terminal/ROADMAP.md`とsystem index結果が表示された。
- `Escape`後は表示とqueryを保持したまま`TERMINAL INPUT`へ戻り、accessibility focusもterminal text-inputへ戻った。検証用入力はsubmitせず、
  app processを停止して破棄した。聴覚出力そのものは自動取得しないが、terminal時はAppKit terminal responder、Navigator時はDart-only
  routingでread-only AppKit editorへkeyを二重配送しない状態をnative focusとstateの双方で確認した。

### Release AOT検証で判明したcleanup race

- 最終の両runtime native-content検証ではDeveloper JITが成功した後、Release AOTが60秒timeoutになった。終了処理自体はsession／workerまで
  cleanに完了していたが、fixture root削除と同時にcancelしたdirectory streamの`StreamIterator.cancel()`がENOENTを返し、そのFutureを
  `unawaited`のままにしていたためunhandled errorになっていた。
- directory snapshotのdeadlineはcancel完了待ちに依存させず、cancel Futureへsuccess／error handlerを付けてlate errorをcleanup-only stateとして
  消費する。onCancelが`FileSystemException`を返すfake streamを追加し、cancelled snapshot、0 retained entry、unhandled errorなしを固定する。

## 実装結果

- working directory resolverは、local owning shellがforegroundを保持し、同じchild PIDのsafe kernel cwdを返す時に限り、machine hostname付き
  OSC 7をlocal host aliasとして扱う。別foreground process、PID mismatch、cwd取得不能では従来どおりremote boundaryを維持し、launch cwdへ
  fallbackしない。
- Dock表示／tab／pane／root attachmentが変わったreconcileだけをinput-owner projectionとして追跡し、terminal ownershipならfocused terminal view、
  Navigator ownershipならread-only editorをfirst responderへ戻す。同一split childは再接続せず、非同期directory更新でfocusを失わない。
- Navigatorのwindow key routingを`dartOnly`へ変更した。query、上下移動、path actionはDart controllerだけが処理し、read-only AppKit editorへ
  同じkeyを配送しない。terminalへ戻ると`appKitOnly`になる。
- directory stream cancelのlate filesystem errorをcleanup-only stateとして回収し、終了時のunhandled errorを防いだ。deadlineとgeneration cancellationの
  bounded contractは変更していない。
- native-content scenarioは検索shortcutを使う前にDockだけを表示し、real plain-sh cwd/tree、terminal ownership、0 PTY writeを確認する。
  focused testsはhostname alias／remote foreground分離、hide→showのfirst responder、同一child再接続なし、cancel error回収を固定する。

## 最終検証

- `dart format`対象346 files: 変更0。`CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: `No issues found!`。
- focused `terminal_directory_snapshot_test.dart`、`terminal_context_dock_test.dart`、`terminal_native_hierarchy_test.dart`: 全件成功。
- 通常Developer JIT: user指定の`make RUNTIME_ARCH=arm64 developer-jit-run`相当を実行し、local cwd/tree、terminal実入力、`ROADMAP`の
  current-subtree／system-index検索、Navigator focus、`Escape`復帰を実AppKit accessibility stateで確認した。
- runtime integration: Developer JITは
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true exact_pty=true sessions=4 elapsed_ms=5094`、Release AOTは
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true exact_pty=true sessions=4 elapsed_ms=4126`で成功した。
- Phase 7 acceptance、Ghostty P0/P1 gap inventory、release-candidate daily-use matrixを正規generatorで更新した。最終
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`はgenerated freshness、native／Dart、privacy、compatibility、distributionをすべて通過し、
  `dart_terminal tests passed`で終了した。

## 残課題

- 本回帰に関する未完了項目はない。remote／SSH directory providerは依頼どおり対象外のままで、実remote foregroundへlocal cwdを混ぜない。
