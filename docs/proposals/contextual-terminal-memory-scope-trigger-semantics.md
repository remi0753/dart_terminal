# Contextual terminal memory scope and trigger semantics

- 状態: Gate 2/4 完了（製品コード実装未承認）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- 製品判断: [`contextual-terminal-memory-product-slices.md`](contextual-terminal-memory-product-slices.md)
- Checkpoint採否: [`contextual-terminal-memory-checkpoint-feasibility.md`](contextual-terminal-memory-checkpoint-feasibility.md)

## 目的

採用した S1 Basic memory、S2 On Return、S3 At Next Prompt に必要な scope、identity、
lifecycle、trigger delivery semantics を確定する。runtime の pane/session ID と、利用者が
期待する durable な「このterminal」を分離し、focus/prompt event が重複や推測なしに
一度だけ Note を due にする contract を作る。

## 背景

現行 `PaneId`、`TerminalSessionId`、semantic `commandId` は live application/session 内の
identity であり、restoration は fresh ID と fresh shell を生成する。一方、S1/S2の Note は
app restart後も同じ restored paneへ戻ることが期待される。S3は content-free OSC 133 lifecycle
を利用できるが、現在の prompt stateだけでは「arm後の次」を一意に表せず、integration欠落、
shell restart、tmux/SSHを推測してはならない。

## 対象範囲

- D-07〜D-11とD-21〜D-26
- S1〜S3のattach target、durable context identity、orphan semantics
- On Return と At Next Prompt のarming、due、consume、re-arm
- simultaneous delivery、badge projection、capability degradation
- restoration、pane/window/tab transition、shell restartとの関係

## 対象外

- S4 invocation receipt、S5 exact-command rule、S6 simulationのidentity/protocol
- Note schema、store format、transaction、migrationの実装詳細
- overlay/native view/input routingの実装
- workspace/repository/remote-hostの自動identity
- product code、test code、restoration formatの変更

## 依存関係

- Gate 1で採用したS1〜S3と付箋GUIのproduct boundary
- `TerminalApplicationState`、`PaneId`、`TerminalSessionId`
- `TerminalRestorablePane` と fresh-session restoration contract
- `TerminalSemanticPromptModel` の OSC 133 A/B/C/D/I/N/P lifecycle
- AppKit window/tab/pane focusとDEC focus reportingの既存contract

## 完了条件

- D-07〜D-11、D-21〜D-26を採用、延期、不採用で閉じる。
- durable Note attach identityとruntime identityのmappingを定義する。
- lifecycle transition tableとorphan recoveryを定義する。
- S2/S3のdeterministic state machine、dedupe、simultaneous deliveryを定義する。
- supported/probing/suspended/unavailableを安全状態と混同しない capability modelを定義する。
- 親文書、提案、roadmapを更新し、次の未完了taskをGate 3にする。
- Markdown/link/order/diff scopeを検証し、このtaskだけをcommitする。

## 検証方針

- decision ID 11件とstate/transition tableの網羅性を静的に検査する。
- identity uniqueness、focus sequence、prompt sequence、simultaneous deliveryのreview vectorを
  文書内でtraceし、期待結果が一意になることを確認する。
- changed Markdown link、whitespace、roadmap ordering、diff scopeを検査する。
- production codeを変更しないため既存testは実行せず、将来のmodel test vectorを仕様化する。

## 調査記録

### 2026-09-20: 着手

- Gate 1はcommit `0ffae5a`で完了し、worktreeはcleanだった。
- `ROADMAP.md`を再確認し、Gate 2/4が最初の未完了taskであることを確認した。
- 現行restoration format version 1のpane leafはcwdだけを保持し、restoreはfresh `PaneId`、
  `TerminalSessionId`、shellを作る。durable Note attach IDは存在しない。
- OSC 133 modelはA/N/Pをprompt、B/Iをinput、Cをcommand output、Dをunknownへ遷移する。
  zsh/fish/bash/nushell resourceは概ねcommand終了D、prompt A/B、実行前Cを出すが、optionsや
  command内容を保持しない。
- AppKit focus、window/tab/pane選択とterminal DEC focus reportは既存の別contractである。
  Note overlayへのfirst-responder移動をpane離脱として数える設計にはしない。

## Decisions

### Decision summary

| ID | 結果 | 決定 |
| --- | --- | --- |
| D-07 | 延期 | Initial releaseにworkspace scopeを設けない。cwd、Git root、remote hostから自動identityを作らない。 |
| D-08 | 採用 | Note専用のdurable `TerminalNoteContextId`を導入し、runtimeの`PaneId`／`TerminalSessionId`から分離する。 |
| D-09 | 延期 | S4とともにinvocation/receipt identityを延期し、現行`commandId`を永続化しない。 |
| D-10 | 不採用 | Gate 6でS5を不採用としたためexact-command rule scopeとprecedenceを定義せず、型や互換予約も残さない。 |
| D-11 | 採用 | context、runtime session、triggerを別lifecycleとして扱い、transition tableを正本にする。 |
| D-21 | 採用 | passive Noteとdue deliveryを分離し、badgeはactive countとdue countだけを投影する。 |
| D-22 | 採用 | `On Return`をpane visibility/focusのfalse→true visitで一度だけdueにするstate machineとする。 |
| D-23 | 採用 | `At Next Prompt`は同一runtime session／integration instanceのarm後C→D→A/N→B cycleだけでdueにする。 |
| D-24 | 延期 | S4とともにcommand attachment UI、anchor loss、orphan receiptを延期する。 |
| D-25 | 採用 | 複数deliveryは単一railへFIFO coalesceし、同じeventから複数overlayを開かない。 |
| D-26 | 採用 | prompt capabilityを`available`、`probing`、`suspended`、`unavailable`で表し、available以外をno-match/safeとして扱わない。 |

## Scope and identity

### User-facing scope

Initial releaseのattach targetは **This Terminal / このterminal** 一つだけとする。これはcwd、
repository、shell process、window/tab indexではなく、一つのlogical pane contextを指す。
UIでは`session`という語を使わない。shellをrestartしてもNoteが残るため、runtime sessionと
呼ぶとlifetimeを誤解させるためである。

Workspace scopeは延期する。Git rootやcwdを自動workspaceにすると、symlink、rename、monorepo、
複数window、SSH/remote cwdでidentityが不安定になり、利用者が意図しないpaneへNoteが現れる。
将来再検討する場合も、暗黙のpath推論ではなくuser-created workspace identityを第一候補にする。

### `TerminalNoteContextId`

`TerminalNoteContextId`はNote attachment専用のopaque 128-bit random IDである。

- path、hostname、username、PID、pane index、creation timeをencodeしない。
- 一度発行した値を別contextへ再利用しない。
- standard paneを作るたびに新規発行し、restoration対象paneでは保存・復元する。
- runtimeでは`PaneId -> TerminalNoteContextId`をapplication ownerが一対一で保持する。
- `TerminalSessionId` generationが変わってもcontext IDは変えない。
- tab/window間のmove、split resize、zoom、title/cwd changeでも変えない。
- split、new tab、new window、将来のduplicate/cloneは新しいcontext IDを発行し、source Noteを
  自動copyしない。
- IDを利用者向け画面、diagnostics、logへ通常表示しない。

現行restoration version 1にはこのIDがない。実装時はversioned migrationで既存paneへ新規IDを
一度だけ割り当てる必要があるが、encodingとtransactionはGate 3で決める。

Quick Terminalはlayout restoration対象外だが、製品上は一つのlogical terminalとして再利用される。
そのためQuick Terminal専用のcontext IDをNote store metadataに一つ保持し、hide/showとapp restartで
再利用する。Quick Terminalを明示的にresetしてもNoteは削除せず、削除はNote操作に限定する。

### Runtime identities

| Identity | Lifetime | Noteでの用途 |
| --- | --- | --- |
| `TerminalNoteContextId` | logical terminal context。restorationを跨ぐ | S1/S2のattach key |
| `PaneId` | 一つのlive application state | UI/native eventからcontextを引くruntime key |
| `TerminalSessionId` | paneが所有する一つのPTY/process generation | S3 armingを別shellへ誤転用しないgeneration key |
| semantic generation / prompt cycle | 一つのlive terminal session内 | S3のdedupeとevent ordering |
| semantic `commandId` | bounded live semantic range | S4延期中のためNote storeへ保存しない |

## Lifecycle semantics

### Context transition table

| Event | Context ID | S1 Note | Armed `On Return` | Armed `At Next Prompt` |
| --- | --- | --- | --- | --- |
| new window/tab/split pane | 新規 | なし | なし | なし |
| tab/window move、split resize/zoom | 保持 | 保持 | state保持 | state保持 |
| cwd/title/theme/font change | 保持 | 保持 | state保持 | state保持 |
| terminal first-responderがNote UIへ移動 | 保持 | 保持 | awayにしない | state保持 |
| app deactivate、別window/tab/pane、window minimize/hide | 保持 | 保持 | `armedAway`へ | output eventは追跡し、dueならbackgroundで保持 |
| Quick Terminal hide/show | 専用IDを保持 | 保持 | hideでaway、showでreturn | state保持 |
| PTY/shell generation restart | 保持 | 保持 | state保持 | `suspended`。新sessionへ自動transferしない |
| RIS / semantic reset | 保持 | 保持 | state保持 | candidate cycleを破棄して`suspended`。明示re-armが必要 |
| successful app restoration | 保存IDを復元 | 保持 | terminationをawayとし、最初のeligible visitでdue | fresh sessionのため`suspended` |
| restorationなし／decode失敗／対応pane欠落 | restoreしない | detachedとして保持 | trigger解除 | trigger解除 |
| userがpane/windowをclose | detachし、再利用しない | detachedとして保持 | trigger解除 | trigger解除 |
| future duplicate/clone | destinationは新規 | 自動copyしない | copyしない | copyしない |
| Note delete | 影響なし | 明示削除 | trigger削除 | trigger削除 |

App terminationは、restoration snapshotとNote storeの両方がcommitできたcontextだけを
restorableとして扱う。片方しか残らない場合は別paneへの推測reattachをせずdetachedにする。
atomicity、crash recovery、reconciliationはGate 3で決める。

Detached Noteは自動削除しない。`Notes`のapplication-level `Detached` collectionから閲覧、
reattach、resolve、deleteできることを後続UI contractへ要求する。cwdやpane順序が同じでも
自動reattachしない。

## Trigger model

Note lifecycleとdelivery lifecycleを分離する。Noteがactiveであり続けても、一回限りのtriggerは
consumeできる。trigger consumeはNoteのresolve/deleteを意味しない。

### Shared delivery states

```text
passive
  └─ explicit arm ─> armed
armed
  ├─ qualifying event ─> due
  ├─ explicit cancel ─> passive
  └─ scope loss ─> suspended or passive
due
  ├─ presenter acknowledgement ─> presented
  └─ scope loss before presentation ─> suspended or passive
presented
  └─ trigger consumed; Note remains active/passive until resolve or re-arm
```

Trigger engineはqualifying eventで`due`を永続化し、UIが実際にcardをprojectionしたという
acknowledgementを返すまで`presented`にしない。windowがbackground、overlay ownerがbusy、
render surfaceが一時 unavailableでもdeliveryを失わない。`presented`後のfocus bounceやprompt
duplicateは同じtrigger generationを再配信しない。

### S2 `On Return`

#### Eligible focus

一つのcontextがeligible focusを持つのは、次がすべてtrueの場合である。

- applicationがactiveである。
- owning windowがvisibleかつkey/active windowである。
- owning tabがselectedである。
- owning paneがtabのfocused paneで、zoom stateによって隠れていない。

Note rail、Note editor、popover、sheetへのfirst-responder移動は同じpane context内のUI操作であり、
eligible focusをfalseにしない。これによりNoteを開くこと自体でreturn triggerを発火させない。
別application、別window/tab/pane、window minimize/hide、Quick Terminal hideはfalseにする。

#### State machine

```text
passive
  └─ arm while eligible ─> armedHere
  └─ arm while not eligible ─> armedAway
armedHere
  └─ eligible true -> false ─> armedAway
armedAway
  └─ eligible false -> true ─> due
due
  └─ actual card projection ─> presented -> passive trigger
```

- `eligible=true`の重複native notificationはtransitionではなく無視する。
- arm直後の同じfocus visitでは発火しない。必ず一度awayを観測する。
- app quit前にarmedでrestoration成功した場合、terminationをawayとして記録し、restored contextの
  最初のeligible visitで一度だけdueにする。
- dueがbackgroundで発生することはない。return transitionそのものがforeground条件を含む。
- detached contextではreturn不能なのでtriggerを解除し、NoteをDetached collectionへ残す。
- presentation後に再度表示したい場合、利用者が明示的に`On Return`をre-armする。

### S3 `At Next Prompt`

#### Integration instance

Standard OSC 133 markerは任意のchild outputが生成できる。S3はsecurity boundaryではないが、
remote/TUI outputの偶発markerでNoteを配信しないため、configured shell adapterごとに
non-secretな128-bit `ShellIntegrationInstanceId`を発行する。

- IDは`TerminalSessionId`にbindし、adapterへlaunch environmentで一度だけ渡す。
- root adapterは値をshell-local stateへ取り込み、childへ継承しないようenvironmentから消す。
- adapterが出すlifecycle eventはinstance IDとprotocol versionを含む。
- terminal compatibility用の一般OSC 133 semantic rangeは従来どおり処理できるが、S3 triggerは
  matching instance/versionのeventだけを受ける。
- このIDはauthentication secretではない。悪意あるlocal processを防ぐ保証はせず、diagnosticsや
  exportへ出さないcorrelation valueとして扱う。
- exact wire encoding、version negotiation、resource更新はGate 7と実装taskで固定する。

#### Prompt-cycle state machine

S3のqualifying cycleは、同じ`TerminalSessionId`と`ShellIntegrationInstanceId`でarm後に観測した
次のsequenceである。

```text
C (command output begins)
  -> D (command ends)
  -> A or N (new primary prompt begins)
  -> B (primary input becomes ready) -> due
```

`P` secondary promptはcommand continuationであり、delivery対象にしない。`I`はline-endで
command outputへ遷移する拡張input markerであり、primary prompt-readyの証拠に使わない。
現行zsh/bash/fish/nushell adapterはいずれもprimary input-readyにBを出す。

Stateは次のとおりである。

```text
passive
  └─ arm with capability available ─> waitingCommand
waitingCommand
  ├─ current state is commandOutput at arm ─> waitingEnd
  └─ matching C after arm ─> waitingEnd
waitingEnd
  └─ matching D ─> waitingPromptStart
waitingPromptStart
  └─ matching A or N ─> waitingInput
waitingInput
  └─ matching B ─> due
any armed state
  ├─ session/instance change or semantic reset ─> suspended
  └─ explicit cancel ─> passive
```

- arm時に既に`commandOutput`なら、そのstateへ入ったCがarm前でも現在実行中commandの終了を待つ
  意図として`waitingEnd`から始める。
- arm時にprompt/input/unknownなら現在のpromptへ即時deliveryせず、arm後のmatching Cを待つ。
- D/A/Bのduplicateはstateを進めず、順序外eventはcandidateだけをresetして次のmatching Cを待つ。
  Noteをdelete、resolve、safe扱いにはしない。
- long-running commandにwall-clock timeoutを設けない。時間経過だけでunavailableやdeliveredにしない。
- promptがbackgroundでreadyになった場合は`due`を保持し、paneをactivateしたときrailへprojectionする。
- session/instance change、RIS、adapter disableで`suspended`になったtriggerは新sessionへ自動移送せず、
  UIでreasonを示して明示re-armを求める。
- capabilityがavailableでないとき、新しい`At Next Prompt`はarmできない。Note自体はpassiveに作成、
  閲覧、編集できる。

## Capability model

| State | 意味 | UI / trigger behavior |
| --- | --- | --- |
| `available` | configured adapterとmatching instance/versionのprimary A/N→B lifecycleをcurrent sessionで確認済み | `At Next Prompt`を選択可能。full qualifying cycleだけをdeliveryに使う。 |
| `probing` | adapterをlaunchしたがcurrent sessionで有効なprimary prompt cycleをまだ確認していない | optionはdisabledで`Checking shell integration`相当を表示。既存armed triggerは進めない。 |
| `suspended` | session/instance change、semantic reset、adapter disable、version mismatchで以前のauthorityを失った | armed triggerを保留しreasonと`Re-arm`を表示。no-match/safeにしない。 |
| `unavailable` | integrationがdisabled、shell未対応、adapterなし | optionはdisabled。Noteはpassiveのまま利用可能。 |

`available`はcommand safetyやevent送信者のauthenticationを意味しない。「このlocal shell adapterの
versioned lifecycleと相関できる」という意味だけである。tmux/SSH/nested shellへinstance IDを
継承しないため、その内側のpromptにはdeliveryしない。外側のroot shellへ戻り、root adapterが
full cycleを完了した場合は、そのlocal promptをnext promptとして扱える。

## Passive, due, and simultaneous delivery

### Badge projection

- `activeCount`: contextにattachされ、resolved/deletedでないNote総数。
- `dueCount`: delivery stateが`due`で未presentationのNote数。
- passive Noteはrailから常に開けるが、`dueCount`には含めない。
- resolved、deleted、detached Noteはpane badgeへ含めない。
- colorはuser metadataであり、badge priorityやurgencyを自動決定しない。
- count表示上限、color stackの描画、animationはGate 5で決めるが、modelは正確なbounded countを渡す。

### Coalescing and order

一つのcontextで複数Noteがdueになってもoverlayを複数開かない。trigger engineはdue時に単調増加する
`DeliverySequence`を割り当て、単一note railで次の順に並べる。

1. 未presentationのdue Noteを`DeliverySequence`昇順（FIFO）で並べる。
2. 同一transactionでdueになった場合はstable `NoteId`順をtie-breakにする。
3. 既にpresentedされたactive Noteとpassive Noteは、その後にuser orderで並べる。

一つのfocus visitで自動展開するrailは最大1つである。S2とS3が同時にdueなら一つのrailに両方を
表示し、最初のdue cardへscroll/focusするがterminal input focusを奪わない。railが既に開いている
場合はcardを同じlistへ追加し、別popoverを生成しない。古いdueを追い越すpriority/urgencyは
initial releaseに設けず、starvationを防ぐ。

## Review vectors

| Vector | Initial state / events | Expected result |
| --- | --- | --- |
| F1 | active paneでOn Return arm、同じpane内でNote editor open/close | `armedHere`のまま、delivery 0 |
| F2 | F1後、別paneへ移動、元paneへ戻る、duplicate focus通知 | 元paneでdue 1、projection 1、duplicate 0 |
| F3 | armed paneを含むappを正常終了・restore | first eligible visitでdue 1 |
| F4 | armed paneをuser close | trigger解除、NoteはDetached、delivery 0 |
| P1 | promptでarm、C D A B | Bでdue 1 |
| P2 | commandOutput中にarm、D A B | Bでdue 1 |
| P3 | promptでarm、A Bだけ、後でC D A B | 最初のA/Bは0、後のBでdue 1 |
| P4 | arm後C、session generation変更、D A B | suspended、delivery 0 |
| P5 | arm後C D A P B | Pでは0、primary Bでdue 1 |
| P6 | arm後C D A Bをbackgroundで受信 | due保持、foregroundでprojection 1 |
| P7 | missing/mismatched integration instanceのC D A B | compatibility semanticsのみ、S3 delivery 0 |
| C1 | 同じtransactionでOn Return Note 2件とPrompt Note 1件がdue | rail 1、FIFO card 3、terminal focus不変 |

これらは実装時にpure model testへ変換し、全event split、duplicate、reset、close/disposeを追加する。

## 検証記録

2026-09-20 に次を実行した。

- `git diff --check`: pass。
- changed/new Markdown 5件の相対 link target検査: pass。
- D-07〜D-11、D-21〜D-26の11 decision rowを期待順で抽出し、全項目が`採用`、`延期`、
  `不採用`のいずれかで閉じていることを確認: pass。D-10はGate 6で延期から不採用へ更新した。
- focus 4件、prompt 7件、coalescing 1件の計12 review vectorを確認: pass。
- prompt-ready markerをBだけに限定したことを検査: pass。最初のscriptは現行modelの事実を
  説明する「B/Iをinput」という調査記録まで拾いfalse failureになったため、qualifying arrowの
  `→B/I`／`B or I`だけを拒否する検査へ修正した。検証記録自身にそのliteralを記載した後も
  一度false failureになったため、最終検査は本書先頭から`## 検証記録`直前までのspec本文だけを
  対象にした。最初は`lastIndexOf`が検証文中のheading名を拾ったため、line-anchoredな
  `^## 検証記録$`の位置で切るよう修正した。
- 最初のreview-vector検査はF4件+P7件+C1件を11件と誤計算してfalse failureになった。
  期待値を12件へ修正し、table rowを再検査した。
- roadmap ordering検査: pass。最初の3 taskが完了し、次の未完了taskはGate 3の
  data model、永続化、privacy、security、migration方針になった。
- diff scope review: `ROADMAP.md`と`docs/proposals/`のMarkdownだけを変更し、production code、
  test code、restoration format、shell resource、generated artifactは変更していない。
- 文書仕様taskのためDart/native testは対象外とした。Review vectorsは実装taskでpure modelと
  integration testへ変換する。
