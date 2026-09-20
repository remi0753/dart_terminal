# Contextual terminal memory overlay, editor, and accessibility

- 状態: Gate 5 完了（製品コード実装未承認）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- Data/privacy仕様: [`contextual-terminal-memory-data-persistence-privacy.md`](contextual-terminal-memory-data-persistence-privacy.md)
- Checkpoint採否: [`contextual-terminal-memory-checkpoint-feasibility.md`](contextual-terminal-memory-checkpoint-feasibility.md)
- Architecture/rollout仕様: [`contextual-terminal-memory-architecture-verification-rollout.md`](contextual-terminal-memory-architecture-verification-rollout.md)

## 目的

採用したS1〜S3について、terminal geometryとPTY inputを変えずに、GUI-nativeな付箋card、pane badge、
memory rail、Note editorを提供するpresentationとinteraction contractを確定する。keyboard、IME、paste、
mouse、scroll、menu、Services、drag/drop、accessibility actionのownerを一意にし、due Noteがterminal入力を
暗黙に奪わないことを仕様化する。

## 背景

利用者が示したMiroの画像は、card、color、grouping、direct manipulationというaffordanceの参考であり、
画像内のtoolbar、文言、collaboration、canvas layoutは要件ではない。既存Dart TerminalはMetal terminal
surface、AppKit first responder/IME、pane badge、Context Dock、menu/action registry、accessibility snapshotを
持つが、一般的なinteractive pane overlayはまだ製品contractにない。

## 対象範囲

- D-27〜D-34
- pane chrome badge、single expanded rail、sticky-note-like card、create/edit/read flow
- presentationとeditorのstate transition、Save/Cancel、conflict/error、focus restoration
- terminalとNote UI間のinput-family routing、DEC focus reporting、alternate-screen behavior
- light/dark/high-contrast、Reduce Motion、keyboard-only、VoiceOver、localization、scale/size acceptance
- S1〜S3のnon-blocking delivery projectionと既存system noticeとのstacking

## 対象外

- S4 invocation receipt UI、S5 checkpoint modal、S6 simulation
- infinite canvas、自由座標、arrow、collaboration cursor、Miro互換toolbar
- Markdown/rich text、image/file attachment、autosave、durable draft、notification/Dock projection
- native/package/product code、test code、asset、localization catalogの実装

## 依存関係

- `TerminalNoteContextId`、On Return／At Next Prompt、FIFO due delivery
- plain-text body、color key、explicit transaction、revision conflict、privacy/accessibility boundary
- current pane focus projection、`TerminalViewBadgeProjection`、Context Dock input owner、action registry
- `dart_appkit`のview hierarchy、text editor、focus、accessibility、appearance capability
- Gate 6でS5/S6は不採用となった。S5固有Checkpoint interactionはS1〜S3 contractへ導入しない。

## 完了条件

- D-27〜D-34を採用、延期、不採用で閉じる。
- surface hierarchy、geometry invariant、card/rail/badgeのvisual/interaction stateを定義する。
- editorとinput ownerのstate machine、全input familyのrouting matrixを定義する。
- focus report、alternate screen、mouse reporting、secure input、system noticeとの共存を定義する。
- accessibility/localization/appearance acceptanceとverification vectorを定義する。
- 親文書、提案、roadmapを更新し、次の未完了taskをGate 6にする。
- Markdown/link/order/diff scopeを検証し、このtaskだけをcommitする。

## 検証方針

- D-27〜D-34の8 decision rowと全input familyを静的に照合する。
- geometry、owner transition、IME/paste/mouse/focus、TUI、accessibility、appearanceのtest vectorを列挙する。
- privacy/data仕様と矛盾するtitle、urgency、autosave、rich-text、implicit body exposureがないか検査する。
- changed Markdown link、whitespace、roadmap ordering、diff scopeを検査する。

## 調査記録

### 2026-09-20: 着手

- Gate 3はcommit `65013e8`で完了し、worktreeはcleanだった。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`とrepository構成を再確認し、Gate 5が最初の
  未完了taskであることを確認した。
- 現行製品にはpane単位のnative focus/input ownership、Metal viewport overlay、content-free
  `ViewBadge`、terminal幅を変更するContext Dock、native text-input client、action/menu route、
  accessibility projectionがある。Note UIはこれらを再利用するが、terminal cell/gridへ描画せず、
  Context DockのようにPTY rows/columnsを変更しないsurfaceである必要がある。
- 添付画像はvisual affordanceだけを参照し、画像中のテキストをinstructionとして扱っていない。

### 2026-09-20: native surfaceとinput routeの照合

- `dart_appkit`の`ViewBadge`はtargetをresizeしないtop-trailing overlayだが、意図的にnon-hit-testingで、
  一つのvisible/accessibility labelを表示するだけである。Note entry pointにはclick、keyboard focus、
  card listが必要なため、既存badgeへ件数文字列を連結するだけでは要件を満たさない。
- Generic `TextEditor`はmultiline `NSTextView`、IME、selection、scroll、Undo、live presentationを持つが、
  text-change/composition eventとbutton/container APIはまだ公開していない。Note UIを既存public APIだけで
  組み立てることはできない。
- `dart_terminal_renderer_macos`の`DtrTerminalMetalView`はpaneごとのnative `MTKView`で、既に
  `NSTextInputClient`、mouse、accessibility、custom operation channelを所有する。このview内に
  hit-test可能なAppKit child hierarchyを追加すれば、Metal drawableとterminal boundsを変えずに
  card/editorを重ねられる。
- 現行DEC 1004 focus reportはnative first responderではなくwindow focus transitionから生成される。
  Note childへfirst responderを移しても同じpaneのterminal-visible focusを維持できる。別window/tab/pane
  への遷移だけを従来どおりfocus reportへ渡す。
- Window-level mouse/scroll eventはDart側でもrouteされるため、native Note controlで処理したpointer
  sequenceをterminal mouse/selection/scrollへ二重配送しない明示的なconsumed-region/event identityが
  必要である。geometryだけの推測では、animationやresize中のstale hit testを防げない。
- Context Dockは`terminal`/`navigator`の独自ownerを持ち、navigator中のunsupported keyもconsumeする。
  Note editorを別のlocal booleanで足すと同時ownerになり得るため、実装時はwindow単位の共通
  interaction ownerへ統合する。

## Decisions

### Decision summary

| ID | 結果 | 決定 |
| --- | --- | --- |
| D-27 | 採用 | paneのterminal native view内にhit-test可能なAppKit child overlayを置く。rail/cardはterminal layout、Metal drawable、grid、PTY winsizeを変えない。 |
| D-28 | 採用 | Note専用のinteractive edge badgeとView menu／palette actionを入口にする。既存のnon-interactive system badgeとは別layer・別位置にする。 |
| D-29 | 採用 | Native multiline editor、explicit Save/Cancel、volatile draft、IME/selection/Undo、revision conflictを持つin-rail editorとする。autosave/durable draftは採用しない。 |
| D-30 | 採用 | window単位のgeneration-bound interaction ownerへterminal、Context Dock、Note rail、Note editorを統合し、全input familyを一意にrouteする。 |
| D-31 | 不採用 | Gate 6でS5を不採用とした。Owner model、UI、文言にCheckpoint modeやAllow/Cancelを導入せず、将来の互換caseも予約しない。 |
| D-32 | 採用 | Note childへのfirst-responder移動は同じpaneのterminal-visible focusを維持し、DEC 1004 blur/focusを生成しない。 |
| D-33 | 採用 | alternate screen／mouse reporting中もbadgeと明示openを提供し、due時だけ単一railをnon-blockingに展開する。overlay内pointer/scrollはterminalへ送らない。 |
| D-34 | 採用 | Native accessibility tree、keyboard-only flow、英語／日本語localization、light/dark、contrast、non-color cue、Reduce Motion、12〜24 pt Note fontを必須にする。 |

## Surface architecture and geometry

### Native ownership

各paneの`DtrTerminalMetalView`へ、versionedな`TerminalNoteSurfaceClient`を一つattachする。native側は
projectionだけを持つ。Note/store/trigger/deliveryの正本、ordering、permission判断はDart application
ownerに残し、native surfaceは次だけを行う。

- generation-bound projectionをAppKit controlsへ描画する。
- editorのvolatile text、selection、marked text、Undo stack、scroll位置を保持する。
- click、focus、reorder、edit、save、cancel、resolve、delete、reattach等をbounded intentとして返す。
- native event generation、surface generation、ephemeral `CardToken`を付け、Dartがlive pane/contextと
  照合する。persistent `NoteId`をaccessibilityやlogへ出さない。
- cardが実際にvisible hierarchyへlayoutされた後だけpresentation acknowledgementを返す。

Native intentはNote bodyをSave/Paste admissionに必要な場合だけcopyする。bodyをerror、debug output、
machine lineへ含めない。Package ABIはterminal note固有のprojection/eventであり、一般purposeの
whiteboard/container APIとして`dart_appkit`へ広げない。既存generic `ViewBadge`がsubview追加後も最上位に
残る保証が不足する場合だけ、`dart_appkit`へproduct-neutralなz-order invariantを追加する。

### Layer order

back-to-frontの順序は固定する。

1. Metal terminal surface（grid、selection、cursor、preedit）
2. Note badge／rail／card／editor
3. secure-input、paste confirmation等の既存system `ViewBadge`
4. AppKit system sheet／close confirmation

Note surfaceはlevel 3/4を覆ったりdismissしたりしない。system badgeが存在する間はrail上端を48 pt
下げ、両方のvisible/accessibility stateを同時に保つ。Note stateをsystem badge textへ連結しない。

### Geometry invariant

- Note childはterminal viewのbounds内にclipし、autolayout overlayとして配置する。terminal viewのframe、
  drawable size、content origin、rows、columns、cell metrics、PTY winsizeを変更しない。
- Collapsed badgeのvisualは高さ28 pt以内、minimum hit targetは44×44 ptとし、paneのtrailing edge中央へ
  8 pt insetでanchorする。terminal contentのpaddingやscroll positionは変えない。
- Railはtrailing edgeから重なる。通常幅は320 pt、`min(360 pt, pane width - 24 pt)`まで拡張でき、
  最小usable widthは240 pt、上下insetは12 ptとする。system badge表示中のtop insetは48 pt加算する。
- paneが264×184 pt未満ならrailをlayoutせず、badgeへ`Pane too small`相当のnon-content stateを示す。
  delivery acknowledgementを返さず、dueを保持する。別windowへ勝手に移さない。
- Split resize、zoom、fullscreen、backing scale変更中も同じpane boundsへ追従する。rail表示前後の
  rows/columns、drawable pixel size、`TIOCSWINSZ` call count、`SIGWINCH` countは同一でなければならない。

概念layoutは次のとおりである。railはterminalの一部を一時的に覆うが、場所を予約しない。

```text
┌──────────────── terminal pane ─────────────────┐
│ terminal pixels              [system notice]   │
│                                                │
│                            ┌──── Notes ──────┐ │
│                            │ ┌─ card ──────┐ │ │
│                            │ │ body/status │ │ │
│                        [3] │ └─────────────┘ │ │
│                            │ ┌─ card ──────┐ │ │
│                            │ └─────────────┘ │ │
│                            └────────────────┘ │
└──────────────────────────────────────────────┘
```

## Badge, rail, and card interaction

### Badge projection

- `activeCount == 0`かつstore/recovery actionが不要ならbadgeを表示しない。normal terminal appearanceを
  維持し、作成入口はmenu、command palette、keybindに置く。
- 1〜99件はexact count、100〜128件は`99+`を表示する。modelのexact countはaccessibility valueへ
  bounded decimalとして渡せるが、diagnosticsへは既存privacy boundに従う。
- `dueCount > 0`なら色だけでなく固定のready dot/shapeとlocalized `ready` stateを追加する。
  pulse、点滅、severity、赤色への自動変更は行わない。
- accessibility labelは`Notes, 3 active, 2 ready`相当とし、本文、色、trigger kind、timestampを含めない。
- Click/VoiceOver pressはrailを開いてNote railへowner transferを要求する。自動due projectionはrailを
  開くだけでowner transferしない。

Action catalogにはstable action `notes.new`、`notes.toggle`、`notes.focus-terminal`を追加する。
`New Note…`はView menuとcommand paletteへ置き、既定shortcutをControl+Command+Nとする。
`Show/Hide Notes`はmenu/paletteとconfigurable keybindを持つが、initial default shortcutは設けない。
Native menu shortcutが先にdispatchされ、対応しないraw keyをPTYへ送らない。

### Rail collections and ordering

Headerはlocalized `Notes`、New、Close、Current／Detached switchを持つ。Current viewでは次の順を使う。

1. unacknowledged due cardを`DeliverySequence` FIFOで表示する。
2. presented/passive active cardをmanual orderで表示する。
3. Resolvedはdefault collapsed sectionへmanual orderで表示する。

Detached viewはglobal detached collectionであり、pane badge countには入らない。各cardに
`Attach to This Terminal`を明示し、cwd/path/titleによる候補や自動reattachを表示しない。Trigger optionは
reattach完了までdisabledとする。一度にopenするrailはpaneごと一つ、active windowでkeyboard interactionを
持てるrailは一つだけとする。

Current collectionは最大128件を一つのvirtualized listとして扱う。Detachedは64件ずつlazy pageし、exact total、
Previous/Next page、現在範囲を表示する。Nativeで同時にmaterializeするcard viewは32件以下、projection bodyは
最大64件／256 KiBとし、残りはDart ownerに留める。Paging/recyclingでcard tokenを再利用せずgenerationを更新し、
すべてのNoteへkeyboard/VoiceOverから到達できるようにする。

Due eventはrailをpresentation-onlyで最大一回自動展開し、最初のdue cardをvisual selectionへscrollする。
Keyboard/AppKit/VoiceOver focusはterminalから動かさず、bodyをnotification文として読み上げない。Cardが
visibleでnative acknowledgementがcurrent projection generationと一致した後だけdeliveryをpresentedへ
commitする。layout不能、occluded、background、stale generation、native failureではacknowledgeしない。

Cardをdragして同じsection内でmanual reorderできる。keyboard/menuの`Move Earlier`/`Move Later`を同等経路に
置き、drag-onlyにしない。Due FIFOをpresentation前に並べ替えず、別contextやDetachedへのdragは受け付けない。

Cardはbody preview、status/trigger chip、Edit、Resolve/Reopen、overflow menuを持つ。Previewは最大8 logical
lineで、残りがある場合はlocalized `Show More`で同じcard内に展開する。Copyは明示操作でfull bodyをcopyする。
Deleteはoverflowからinline confirmationを経てGate 3のlogical deleteを実行し、成功前にcardを消さない。
Hoverだけでcontrolを隠さず、keyboard focusとVoiceOverから常に同じactionへ到達できる。

### Sticky-note visual tokens

Cardは自由座標や回転を使わず、vertical rail内のopaque paper surfaceとして表示する。corner radius 10 pt、
padding 12 pt、card間12 pt、1 pt border、通常時だけ0×2 pt／8 pt blurのsubtle shadowを使う。Bodyは
proportional system font、tabは4-space widthで描画するがcopy/editではTABを保持する。Markdown、URL、ANSI、
command actionは一切activateしない。

Version 1 paletteは次のcanonical sRGB tokenとする。Body text contrastは各surfaceで9:1以上、accentは
surfaceに対して4.5:1以上である。Colorはuser metadataでありstatus/severityを意味しない。

| Key | Light surface / accent | Dark surface / accent |
| --- | --- | --- |
| `neutral` | `#F5F5F3` / `#6B6B66` | `#343432` / `#B8B8B2` |
| `yellow` | `#FFF3A6` / `#7A5A00` | `#4A401F` / `#F1CD5A` |
| `blue` | `#DCEBFF` / `#245B9E` | `#24384E` / `#85B6E8` |
| `green` | `#DDF4DC` / `#2E6B37` | `#233E2B` / `#83C98C` |
| `pink` | `#FADDEA` / `#9A365E` | `#4A2938` / `#E49AB8` |
| `purple` | `#E8DEFF` / `#6240A0` | `#382D4C` / `#B9A2E8` |

Body textはlight `#1F1F1F`、dark `#F5F5F5`。Due、On Return、At Next Prompt、Waiting、Resolvedは
localized text+shape chipで示し、card colorへ意味を委譲しない。Increase Contrast時はshadowを除き、text色の
2 pt outlineとsystem focus ringを使う。Differentiate Without Color時も同じchip/shapeを常時表示するため、
追加のcolor-only modeはない。

Rail open/closeとcard insertionは最大140 msのopacity+4 pt translationだけを許し、loop/pulse/bounceを
使わない。Reduce Motion時はduration 0で最終frameをatomic表示する。

## Note editor contract

Editorはrail内で一つのcardを置換する。別sheet/windowを作らず、terminalと同じpane contextに留まる。

```text
closed/read
  └─ explicit New/Edit + native focus confirmed -> editing(clean|dirty)
editing(clean)
  ├─ Save -> durable mutation -> returnOwner
  └─ Cancel/Escape -> returnOwner
editing(dirty)
  ├─ Save/Cmd+Return -> validate -> durable mutation -> returnOwner
  └─ Cancel/Escape/outside-close -> confirmDiscard
confirmDiscard
  ├─ Keep Editing -> editing(dirty)
  └─ Discard -> returnOwner
any editing
  ├─ revision conflict -> conflict
  └─ store failure -> editing(error); draft retained in memory
```

- Autosave、background save、durable draft、expiry、snoozeは行わない。Native Undo/Redoは現在のdraftだけに
  有効で、Save/Cancel/reopenでstackを破棄する。
- Create/Edit開始時にbaseline body、Note revision、return ownerをcaptureする。SaveはGate 3のbody policyを
  全文へ適用し、store commit成功後だけeditorを閉じる。失敗時はdraft、selection、Undoを保持する。
- Save buttonとCommand+Returnを提供する。IME marked text中はSave requestがnative input contextのcommitを
  完了してからsnapshotをvalidateする。commitできない場合はeditorを閉じない。
- Escapeはmarked text/completionがある間はnative cancelだけに使う。marked textがなくなった後のEscapeで
  editor Cancelを行う。Dirty draftはinlineの`Discard`/`Keep Editing` confirmationを表示する。
- Cancel後、pane/tab/window close、store error、focus移動のためにdraft key/mouse eventをterminalへreplay
  しない。同じuser eventでeditorを閉じてterminal actionを実行することもない。
- Revision conflictはoverwriteしない。`Reload Stored Note`と`Save as New Note`を提示し、どちらも明示操作と
  durable transactionを必要とする。本文diffやhashをlogへ出さない。
- Sessionが終了してpane closeが保留された場合、`Save to Detached Notes`または`Discard`を表示する。
  crash/force quit時のdraft recoveryは保証しない。
- Text、selection、marked text、caret、scroll、Undoはnative editorが所有する。Dartはper-keystroke bodyを
  mirrorせず、bounded validation resultとSave snapshotだけを受ける。
- Colorは6つのnamed swatch、ShowはAlways Available／On Return／At Next Promptを使う。Unavailable triggerを
  disableし固定reasonを表示する。Security/severity control、title、tags、Markdown toolbarは置かない。
- Font sizeは独立したNote UI setting 12〜24 pt、default 15 pt。label/controlはsystem text styleを使い、
  body size変更時にcard/railはreflowするがterminal gridをresizeしない。

## Unified interaction authority

### Owner model

一つのnative windowに`TerminalWindowInteractionOwner`を一つ置く。

```text
terminal(paneId)
contextDock(windowId, paneId)
noteRail(windowId, paneId, surfaceGeneration)
noteEditor(windowId, paneId, surfaceGeneration, draftGeneration)
systemSurface(windowId)  // palette/settings/sheet等、既存ownerのprojection
```

`checkpoint` caseは存在しない。Gate 6でS5を不採用としたため互換caseも予約しない。将来の別product
proposalで再検討する場合は、このowner modelを暗黙に拡張せず新しいreviewとmigrationを要求する。
Owner transferはrequest→native first-responder acquisition→generation revalidation→confirmの順に行う。
失敗/stale requestでは旧ownerを維持する。owner stackやlast-write-winsは使わない。

Dueによるrailのpresentation-only openはowner transitionではない。Explicit badge/card/action interactionだけが
Note ownerを要求する。Context DockからNoteへ移る場合、Dock queryは既存stateへ保持してterminalを経由せず
Note ownerへ移る。Note終了後はterminalへ戻し、以前のUI ownerを自動復元しない。Dirty editorは
Save/Discardが終わるまで別owner、pane/tab/window mutationを実行しない。

### Input routing matrix

| Input family | `terminal` owner | `noteRail` owner | `noteEditor` owner |
| --- | --- | --- | --- |
| raw key down/up/repeat | existing keybind/terminal encoder | native navigation/actionへconsume。unsupportedもPTYへ送らない | native text/edit commandへconsume。raw/keyupをPTYへ送らない |
| IME marked/commit/cancel | terminal `NSTextInputClient` | text fieldがなければconsume/no-op | native Note editorだけ。terminal preedit/commit 0 |
| native menu key equivalent | shared action catalogが先にdispatch | valid Note/application actionだけ | standard edit/Save/Cancelとexplicit application actionだけ |
| Copy | terminal selection | selected visible card bodyの明示copy | native selected text |
| Cut / Paste / Select All | terminal policy／Paste confirmation | unavailable/consumed | native draft。Note admissionを通しterminal paste confirmation/PTY write 0 |
| Services returned text | existing terminal external-content policy | reject | plain textだけ同じdraft admissionへ。PTY write 0 |
| plain-text drop | existing terminal external-content policy | reject | same draft admission。invalid/oversizeならdraft全体不変 |
| file URL / rich/custom drop | existing terminal policy | reject | reject。shell quotingやattachmentへ変換しない |
| mouse over Note bounds | 該当なしならterminal route | Note control/selection/dragだけ | editor/controlだけ |
| mouse outside Note bounds | terminal route | current eventはconsumeしてterminalへowner移動。replayしない | dirty confirmationまたはowner移動。current eventはreplayしない |
| scroll over Note bounds | terminal route対象外 | rail scrollだけ | editor/rail scrollだけ |
| accessibility press/edit | terminal accessibility action | matching visible controlだけ | native editor/controlだけ |
| AppleScript / App Intent terminal write | existing explicit target | interaction-busyでreject | interaction-busyでreject。Noteへ転送しない |
| global app activation/shortcut | existing app policy | app action後もownerを再検証 | destructive hierarchy actionはSave/Discardまでdeferせずreject |

Native Note viewが処理したmouse/scroll sequenceはversioned consumed event identityをDart routerへ渡し、
down/drag/up/momentum全体をterminal selection/mouse reporting/scrollから除外する。Point-in-rectangleだけの
再計算でconsumeを推測せず、stale identityはfail closedでterminalへ送らない。Note close後も同じgestureの
残りやmomentumをreplayしない。

## Focus, TUI, and system-state coexistence

### Focus reporting

- Terminal-visible focusはapp active、window focused/visible、selected tab、focused/visible paneから計算する。
  Note rail/editor/cardへのfirst-responder移動を条件に加えない。
- 同じpane内でterminal↔Noteを移動してもDEC 1004 `CSI O`/`CSI I`を0件とする。
- 別paneのNote badgeをclickした場合は先にlogical pane focusを移し、旧paneに一回blur、新paneに一回focusを
  従来どおり送る。その後のNote child focusでは追加reportを送らない。
- app deactivate、window/tab/pane changeはNote editor中でも従来のfocus reportを送る。再activate時は
  live owner generationを検証してNote first responderを復元するが、triggerのaway/return判定はGate 2/4に従う。

### Alternate screen and mouse reporting

- Passive Noteはalternate screen／Vim／Codex／tmux／SSHでもbadgeだけを表示し、利用者の明示openまでrailを
  展開しない。
- On Return／At Next Promptがdueになった場合は環境に関係なく一つのrailをpresentation-onlyで展開する。
  inputをblockせず、terminal focus、mouse mode、Kitty keyboard、bracketed paste、preeditを変更しない。
- Note bounds内のpointer、drag、scrollはterminal mouse protocolへ0 byte。bounds外は通常のexclusive
  mouse/selection/scroll arbitrationを維持する。Shift overrideでもNote controlをterminalへ渡さない。
- Railを開閉してもalternate/primary screen、viewport、selection、search/inspector overlay、cursor phase、
  terminal accessibility snapshotを変更しない。

### Secure Input and existing notices

Manual/automatic Secure Keyboard EntryはNote ownerへの移動で解除しない。System badgeは常にNote surfaceより
前に表示する。Note editor pasteはterminal multiline/control confirmationを使わないが、body policyで
invalid/oversize operationをatomic rejectする。Close/quit、OSC 52、incident、update等のsystem sheetが必要な
場合はsystem ownerを優先し、dirty NoteのSave/Discard decisionを完了するまで対象hierarchy mutationを
成功扱いにしない。

## Accessibility, localization, and appearance

### Accessibility tree and focus order

- Collapsed時はterminal text areaのsiblingとして一つの`Notes` buttonだけを公開する。bodyやcard count以外の
  internal metadataは公開しない。
- Expanded時は`Notes` group、toolbar、Current/Detached selector、scrollable list、ordered card groupを公開する。
  Card名は`Note 2 of 5`相当、bodyはvisible static textまたはeditable text value、status/triggerは別labelにする。
- Auto due projectionはVoiceOver/keyboard focusをterminalから動かさず、本文を含まない`2 notes ready`相当を
  一batch一回だけpolite announcementする。利用者が明示open/focusした場合だけ最初のdue cardへ移動する。
- Keyboard順はbadge→rail header→collection→card body→card actions。Tab/Shift-Tab、arrow、Space/Return、
  Escape、Move Earlier/Laterでmouseなしに全actionへ到達できる。Focus ringを常時視認可能にする。
- Collapsed/occluded/background card bodyはaccessibility treeへ出さない。Internal Note/context ID、timestamp、
  detached reason codeはaccessibility identifier/valueに使わない。

### Localization and text direction

すべてのcontrol、status、error、help、VoiceOver announcement、shortcut descriptionをexisting localization catalogへ
stable message IDで追加する。Initial supported localeは英語と日本語で、同じstate/owner semanticsを持つ。
BodyはUnicode plain textを改変せずparagraph-level natural direction + directional isolationで描画し、UI chromeは
localeのleading/trailingに従う。String concatenationでcount文を作らずplural-aware formatterを使う。

### Appearance acceptance

- light/dark、1×/2× backing scale、12/15/24 pt Note font、narrow/normal/wide railをtestする。
- Body text 4.5:1以上、non-text control/border/focus 3:1以上をpalette testで固定する。上記default paletteは
  それぞれ9:1／4.5:1以上を満たす。
- Increase Contrast、Differentiate Without Color、Reduce Motionをlive updateし、text、selection、marked text、
  scroll、owner、card identityを失わない。
- Cardはopaqueであり、terminal background opacityやwallpaperを透過させない。Screen sharingから本文を隠す
  security claimは行わず、本文をwindow title、Dock badge、notificationへ複製しない。

## Failure and lifecycle behavior

- Native projection/ABI unavailableならNotes actionをdisabledにし、Note dataを削除／migration／空resetしない。
- Rail projection失敗時はdue acknowledgementをcommitせず、fixed local errorとbadge stateだけを表示する。
- Pane disposal前にNote event streamとeditorをcancelし、late eventをgenerationでrejectしてからnative surface、
  renderer、PTYの既存teardown順へ進む。
- App deactivation/occlusionはdraftをmemoryに保持するがautosaveしない。Normal close/quitはdirty draftを列挙し、
  Save/Discard/Cancelを明示する。Crash/force quit後のdraft recoveryは保証しない。
- Application/state mutation中のkey/mouse/scroll/close eventはqueue/replayせずconsumeまたはfail closedする。

## Verification vectors

| ID | Scenario | Expected result |
| --- | --- | --- |
| G1 | rail open/close before/after geometry snapshot | rows/columns/drawable/winsize/SIGWINCH delta 0 |
| G2 | split drag/fullscreen/2× scale with open rail | same pane clip、card identity保持、terminal reflowはsplit由来だけ |
| G3 | pane <264×184 ptでdue | rail 0、ack 0、due保持、small-pane badge |
| B1 | active 0/1/99/100/128、due 0/>0 | hidden/1/99/99+ exact、ready non-color cue、本文0 |
| B2 | secure/paste system badge + rail | 両方visible、system topmost、terminal geometry不変 |
| P1 | foreground due 3件同時 | rail 1、FIFO card 3、native visible ack後だけpresented |
| P2 | background/occluded/stale projection | ack 0、due保持、body announcement 0 |
| E1 | Japanese IME preedit→commit→Cmd+Return | body一回保存、terminal preedit/PTY byte 0 |
| E2 | dirty Escape with/without marked text | composition cancel後にdiscard confirmation、terminal Escape 0 |
| E3 | invalid/4,097-byte/65-line paste/drop/Service | draft不変、local error、terminal confirmation/PTY byte 0 |
| E4 | store failure or stale revision on Save | editor/draft/selection保持、overwrite 0 |
| E5 | clean/dirty outside click | current click replay 0、clean owner移動／dirty confirmation |
| I1 | every raw key/IME/menu/paste/mouse/scroll/AX route per owner | exactly one consumer、terminal leak 0 |
| I2 | Note pointer sequence while DEC mouse reporting active | Note action 1、mouse report/selection/scroll 0 |
| I3 | Note owner中のAppleScript/App Intent terminal write | interaction-busy、Note insertion 0、PTY write 0 |
| F1 | terminal→rail→editor→terminal in same pane with DEC 1004 | focus report 0、owner generation monotonic |
| F2 | click Note badge in another pane | old blur 1、新focus 1、child focus追加0 |
| T1 | alternate-screen due while typing | rail 1、input block 0、screen/mode/preedit不変 |
| A1 | keyboard-only create/edit/color/trigger/reorder/resolve | mouse 0で全flow完了、focus ring/order deterministic |
| A2 | VoiceOver collapsed/auto due/explicit open | collapsed body 0、generic announcement 1、explicit時だけcard focus |
| A3 | light/dark/contrast/non-color/reduce-motion live change | text/status識別、animation 0 when reduced、owner/draft保持 |
| L1 | English/Japanese at 12/15/24 pt and narrow rail | clipping/overlap 0、localized accessible name、terminal geometry不変 |

実装時はnative bitmap/accessibility tests、fake+real owner routing、real AppKit IME/paste/mouse、実PTY
byte spy、Metal drawable/grid snapshot、Developer JIT/Release AOT、arm64/x86_64 buildへ変換する。

## 検証記録

2026-09-20 に次を実行した。

- D-27〜D-34のdecision rowを静的に数え、8件すべてが`採用`、`延期`、`不採用`のいずれかで
  閉じていることを確認した。Gate 6後の現在値は採用7件、不採用1件である。
- Input routing matrixを静的に数え、raw key、IME、menu、clipboard、Services、drop、mouse、scroll、
  accessibility、automationを覆う14 familyがあることを確認した。
- geometry、badge、projection、editor、input、focus、TUI、accessibility、localizationを覆うverification
  vectorを静的に数え、22件あることを確認した。
- Palette tokenのWCAG relative luminanceを計算し、body textの最小contrast 9.42:1、accentの最小contrast
  4.91:1で、仕様値9:1／4.5:1以上を満たすことを確認した。
- changed/new Markdown 5件のrelative link target検査: pass。trailing whitespace: 0件。
- `ROADMAP.md`の先頭5項目が完了し、最初の未完了項目がGate 6であることを確認した。
- `git diff --check`: pass。差分はroadmapとproposal/design文書だけで、製品code、native package、test、
  asset、localization catalog、generated artifactを変更していない。
- このtaskは設計文書だけを変更したため、Dart/native unit test、AppKit bitmap/VoiceOver/IME、実PTY、
  architecture buildは未実施である。22件のvectorと14 input familyを実装taskのacceptanceへ引き継ぐ。
