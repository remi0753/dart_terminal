# Contextual terminal memory 設計判断一覧

- 状態: Gate 1/2/4 完了、Gate 3/5/6/7は未決定（実装未承認）
- 作成日: 2026-09-20
- 対象提案: [`contextual-terminal-memory-and-input-checkpoints.md`](contextual-terminal-memory-and-input-checkpoints.md)

## 目的

既存のターミナルエミュレーターと配布版を基盤として、contextual terminal memory と
input checkpoint のうち何を製品仕様として採用するかを、実装着手前に判断できる状態へ
する。提案に含まれる前提を既存実装と照合し、依存関係の順に設計論点、選択肢、判断基準、
検証方法を明文化する。

## 背景

従来の `ROADMAP.md` が対象とした主要な terminal emulator 機能と配布基盤は完了した。
一方、提案文書は製品像、MVP、実装順を一つの案として示しているものの、scope、identity、
persistence、trigger、input authority、shell adapter、privacy、UX などに未決定事項がある。
この段階で提案の全項目を実装 backlog とみなすと、後から不要と判断する機能の基盤まで
先行して固定してしまうため、先に decision gate を設ける。

## 対象範囲

- 現行 roadmap の完了済み計画としてのアーカイブ方法
- 提案と既存の application state、terminal core、renderer、input、shell integration、
  persistence、privacy 境界の照合
- 実装前に必要な product、UX、data、protocol、security、compatibility の判断事項
- 各判断の依存順、成果物、完了条件
- 機能または slice ごとの採用、延期、不採用の記録方法

## 対象外

- contextual terminal memory の製品コード実装
- UI mockup、schema、protocol、migration の最終仕様確定
- 提案にある MVP 項目を暗黙にすべて採用すること
- 旧 roadmap に残る主要ゴール後の低優先 follow-up の実装

## 依存関係

- `README.md`、`FEATURE_MATRIX.md`、アーカイブ前の `ROADMAP.md`
- 対象提案と、関連する既存の task memo／ADR
- application state、pane/session identity、semantic prompt range、render overlay、input routing、
  shell integration、restoration、configuration、localization、accessibility の現行 contract

## 完了条件

- 従来 roadmap が履歴と未完了 follow-up を失わず `docs/` に保存される。
- ルート `ROADMAP.md` が設計判断を最初の未完了作業として示し、実装項目を先行承認しない。
- 設計判断が依存順に並び、各項目に判断対象、主な選択肢、判断基準、必要な証拠、
  downstream 影響がある。
- 各機能を採用、延期、不採用のいずれかで閉じられる。
- 既存実装との照合結果、検証結果、残る不確実性が本書から辿れる。

## 検証方針

- Markdown link、見出し、checkbox、参照先の存在を静的に検査する。
- `ROADMAP.md` の最初の未完了項目が設計 intake であることを確認する。
- アーカイブ本文と未完了 follow-up が保持され、差分が archive 注記、相対 link の
  rebasing、表示を変えない whitespace 正規化に限られることを Git diff で確認する。
- 実装コード、生成物、既存の利用者変更が差分へ混入していないことを確認する。

## 調査記録

### 2026-09-20: 初期確認

- 作業開始時の tracked worktree は clean で、`docs/proposals/` だけが untracked だった。
- 旧 roadmap の Phase 0〜11、回帰修正、追加機能、配布基盤は完了済みだった。
- 未完了なのは「主要ゴール後の低優先 follow-up」5件であり、主要ゴールの完了定義から
  明示的に除外されている。アーカイブしても未達の履歴として保持する必要がある。
- 提案文書の status は `Proposal, not scheduled` であり、提案内の `MVP` や
  `Implementation order` はまだ承認済み backlog ではない。
- 最初の archive patch では、同じ patch 内で `ROADMAP.md` を move してから同名 file を
  add しようとしたため `apply_patch` が target 重複として拒否した。move と新規作成を
  別 patch に分離して解消し、拒否された patch による file 変更はなかった。

### 2026-09-20: 既存 contract との照合

| 領域 | 確認した事実 | 新機能設計への影響 |
| --- | --- | --- |
| Workspace | 製品 model に workspace entity や durable workspace ID はない。既存の `workspace` という語は主に build/test 用である。 | `workspace` scope は既存概念を利用できない。新しい製品概念を定義するか、最初の slice から外す必要がある。 |
| Pane / session | `PaneId` と `TerminalSessionId(paneId, generation)` は process lifetime 内の logical ID である。restoration は cwd と layout だけを保存し、新しい ID と shell を作る。 | 「この session」の寿命を app 再起動までにするか、restored pane へ継承するかを決めないと保存 key を定義できない。 |
| Invocation | OSC 133 から生成する semantic range の `commandId` は live session 内で単調増加するが、bounded retention で eviction され、再起動を跨がない。command bytes は保持しない。 | command receipt はまず live-session object として設計できる。durable receipt には別の ID、retention、missing-anchor 表示が要る。 |
| Shell integration | 現行 adapter は OSC 133/7/2 など content-free な一方向 signal を出す。shell history、command text、environment は収集しない。 | exact-command matching は現在の privacy boundary と protocol の拡張であり、単なる trigger 追加ではない。 |
| Input | keyboard、IME、paste、mouse、scroll、menu action は複数 route を持つ。Context Dock の input owner は keyboard focus の限定的な precedent である。 | `Checkpoint` mode が「全入力」を止めるには、全 route を覆う authority と atomic transition を新たに定義する必要がある。 |
| Rendering | grid overlay と IME preedit overlay はあるが、一般的な interactive pane overlay はない。既存 `ViewBadge` は bounded text の非 interactive 表示である。Context Dock は layout を変える。 | terminal geometry と `SIGWINCH` を変えない trusted overlay primitive、badge の優先順位、interaction surface が必要になる。 |
| Persistence / secrets | restoration store はあるが note/rule store はない。Keychain、暗号化、keyed digest の product capability もない。 | schema だけでなく file permission、atomicity、locking、corruption recovery、key lifecycle、export/delete 境界まで決める必要がある。 |
| Privacy / diagnostics | diagnostics は terminal content、command、cwd などを既定で export しない。shell integration も content-minimal である。 | note body、rule label、digest、match event を log、diagnostic、crash metadata、analytics に含めない原則を明記する必要がある。 |

主な参照箇所:

- application identity: `lib/src/terminal_application_state.dart`、`lib/src/terminal_pane.dart`
- restoration: `lib/src/terminal_restoration.dart`、
  [`full-screen / restoration record`](../phase7/fullscreen-screen-migration-restoration-reopen.md)
- prompt / invocation: `lib/src/terminal_core/terminal_semantic_prompt.dart`、
  `lib/src/terminal_core/terminal_semantic_ranges.dart`
- shell privacy boundary: [`shell integration record`](../phase8/shell-integration.md)、
  [`cwd/title/prompt record`](../phase8/cwd-title-prompt-mark-close-hint.md)
- input ownership: [`exclusive key routing`](../phase2/exclusive-key-event-routing.md)、
  [`text input / preedit`](../phase5/text-input-client-preedit.md)、
  [`Context Dock terminal mode`](../phase7/context-dock-terminal-mode.md)
- diagnostics boundary: [`terminal diagnostics`](../reference/terminal-diagnostics.md)

### 2026-09-20: Gate 1 product slice decision

- 利用者の指示に従い、`main` の `87c9a70` から
  `codex/contextual-memory-design` branch を作成した。
- 利用者は terminal note の mental model として Miro の付箋を示し、pixel-level な外観は
  必須ではないが GUI ならではの見せ方を求めた。添付 screenshot 内の文言や toolbar は
  instruction とせず、card、color、surface hierarchy の visual reference としてだけ扱った。
- D-01〜D-06を
  [`product slice decisions`](contextual-terminal-memory-product-slices.md) で閉じた。中心価値は
  GUI-native contextual note と return cue、最小 slice は non-blocking な S1+S2 とした。
- S3は S1/S2 acceptance 後の next increment として採用した。S4は receipt identity と
  user value の確認まで延期、S5/S6は Gate 6の独立再評価まで延期した。
- infinite canvas、自由座標、arrow、collaboration UI、Miro互換、cell-relative sticky noteは
  明示的に不採用とした。visual note は pane chrome に anchor した badge／rail／card とする。
- Product validation は production telemetry ではなく、scripted acceptance、5人以上の
  moderated usability、明示的 opt-in feedback で行う。Note内容や利用時刻は収集しない。

### 2026-09-20: Gate 2/4 scope and trigger decision

- S1〜S3のattach identityとして、restorationを跨ぐopaque 128-bit
  `TerminalNoteContextId`を採用した。live `PaneId`／`TerminalSessionId`とは一対一mappingを持つが、
  shell restartでNote identityを変えない。
- initial user-facing scopeは`This Terminal`だけとし、workspace、invocation receipt、
  exact-command rule scopeはそれぞれ対応sliceとともに延期した。
- pane closeやrestoration不一致時にNoteをpath/cwdで推測reattachせず、Detached collectionへ
  保持する。split/new tab/cloneへの自動copyも行わない。
- `On Return`はapp/window/tab/paneのeligible focusが一度awayになった後のfalse→trueだけを
  qualifying eventとし、Note UI内部のfirst-responder移動はawayに数えない。
- `At Next Prompt`はruntime sessionとnon-secret integration instanceにbindし、arm後の
  C→D→A/N→Bだけをqualifying cycleにした。standard OSC 133 rangeとNote delivery channelを
  分離し、remote/TUIの偶発markerをNote triggerに使わない。
- 複数due Noteは単一railへFIFO coalesceし、capabilityはavailable/probing/suspended/unavailableを
  明示する。available以外をno-matchやsafeと表示しない。

## 判断方法

各項目は次のいずれかで閉じる。`採用` だけが後続の仕様化と実装候補になる。

- **採用**: user value、contract、必要な証拠、対象 version を確定する。
- **延期**: 再検討条件と依存先を記録し、今回の schema/API が不用意に固定しない。
- **不採用**: 理由と、代替する user experience または明示的に許容する欠落を記録する。

判断を閉じるには、少なくとも「選択結果」「理由」「既存 contract への影響」「privacy / failure
behavior」「検証可能な acceptance」「後続 task」を本書または直接 link した decision recordへ
追記する。Gate 1 の D-01〜D-06 は
[`product slice decisions`](contextual-terminal-memory-product-slices.md) で完了した。
Gate 2/4 のD-07〜D-11、D-21〜D-26は
[`scope and trigger semantics`](contextual-terminal-memory-scope-trigger-semantics.md) で完了した。
Gate 3/5/6/7は**未決定**であり、表に挙げた選択肢は採用を意味しない。

## 機能 slice

提案を一括採否せず、依存と risk が異なる単位に分ける。

| Slice | 利用者に提供する結果 | 主な依存 | 現在の状態 |
| --- | --- | --- | --- |
| S1 Basic memory | terminal を離れず note を作成・閲覧・編集し、必要時だけ badge/overlay で示す | note model、store、overlay、editor、privacy | **採用: initial release** |
| S2 Park / next focus | pane へ戻ったとき一度だけ user-authored note を提示する | S1、session scope、focus event、exactly-once lifecycle | **採用: initial release、input holdなし** |
| S3 Next prompt | command 完了後の次の prompt で note を提示する | S1、OSC 133 capability、prompt state machine | **採用: next increment** |
| S4 Invocation receipt | 既に実行した invocation の semantic range へ note を関連付ける | S1、receipt identity、anchor retention | **延期: S1〜S3検証とidentity判断後** |
| S5 Exact-command checkpoint | shell が受理する直前の完全一致 command を一時停止し user 判断を求める | global input authority、新 shell adapter、secret handling、fail-open | **延期: Gate 6の独立再評価まで** |
| S6 Simulation / observe | S5 を有効化する前に real PTY write なしで rule と protocol を検証する | S5 の matcher と protocol | **延期: S5採用時のみ** |

## 設計判断一覧

### Gate 1 — 製品境界と採否基準

この gate は最初に実施する。ここで slice を独立に扱うことを確定しない限り、後続の
大きな shell / input 基盤を「MVP」という名前だけで必須にしてしまう。

**状態: 完了。** D-01〜D-06の選択結果、visual direction、success/kill criteria、support
matrix、terminology は
[`contextual-terminal-memory-product-slices.md`](contextual-terminal-memory-product-slices.md)
を正本とする。中心価値は付箋として視覚化した contextual note と return cue、最小 slice は
S1+S2、S3は次 increment、S4〜S6は延期とした。

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-01 | 解くべき中心課題 | terminal context の記憶、再開 timing、誤操作前の注意のどれを first-class outcome とするか。 | 優先 user story と対象外を一文で説明し、S1〜S6を個別に採用・延期・不採用へ分類する。以後すべての scope に影響する。 |
| D-02 | 最小 slice と依存関係 | S1のみ、S1+S2、S1+S3/S4、S5/S6を別 release のどれにするか。 | 最小 end-to-end slice と、除外しても future compatibility を約束しない項目を確定する。 |
| D-03 | 成功・中止基準 | discoverability、再開成功、誤表示率、false positive、操作遅延をどう測るか。telemetry を使わず local/manual evidence にするか。 | metric、観察期間、kill criterion、privacy-safe な取得方法を定義する。rollout 判断に影響する。 |
| D-04 | safety claim | reminder / interruption であり security boundary ではない、という提案の表示と責任境界で十分か。 | UI 文言、fail-open 表示、脅威 model、保証しない事項を仕様化する。特に S5 の名称と onboarding に影響する。 |
| D-05 | 対象環境 | macOS version、local shell、zsh/bash/fish/nushell、alternate screen、tmux、SSH のどこまで各 slice を保証するか。 | slice × environment の support matrix と unsupported 表示を作る。後続検証量を決める。 |
| D-06 | 用語と概念 model | note、rule、receipt、checkpoint、memory rail、workspace、session を user-facing / internal でどう呼ぶか。 | glossary と object relation を確定し、同じ object を mode-dependent に使うか分離するか決める。 |

### Gate 2 — Scope、identity、lifecycle

**状態: 完了。** Initial attach targetはuser-facing `This Terminal`、durable identityは
opaque `TerminalNoteContextId`とした。workspace、invocation receipt、exact-command rule scopeは
延期した。runtime/restoration/orphan transitionの正本は
[`contextual-terminal-memory-scope-trigger-semantics.md`](contextual-terminal-memory-scope-trigger-semantics.md)
を参照する。

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-07 | Workspace identity | git root、自動検出 cwd tree、user-created workspace、profile、または初版対象外のどれか。rename、symlink、複数 window、remote cwd をどう扱うか。 | stable key と lifecycle を定義できなければ workspace scope は延期する。store key、UI、migration に影響する。 |
| D-08 | Session identity | live PTY generation、pane lifetime、restored pane slot、user-named session のどれを指すか。 | start/end/restart/restoration/split duplication 時の真理値表を作る。S2、S3、保存期間に影響する。 |
| D-09 | Invocation / receipt identity | 現行 live `commandId` を使うか、durable receipt ID を新設するか。semantic anchor eviction、RIS、session close 後をどう表示するか。 | uniqueness、retention、missing-anchor behavior を確定する。S4 と store size に影響する。 |
| D-10 | Exact-command rule scope | global、profile、workspace、session、shell-kind のどこへ属するか。複数 rule が一致した場合の precedence と merge をどうするか。 | scope lattice と conflict table を作る。matcher、editor、import に影響する。 |
| D-11 | Scope transition | cwd change、tab move、pane split/close、window restoration、app restart、shell re-exec で note/rule を retain、move、expire のどれにするか。 | event × scope の lifecycle table と orphan handling を作る。data integrity に影響する。 |

### Gate 3 — Data model、永続化、privacy

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-12 | Entity と invariant | note と checkpoint rule を単一 entity の optional fields で表すか分離するか。無効な field 組合せをどう防ぐか。 | schema、required/forbidden fields、stable ID、ordering、validation error を定義する。 |
| D-13 | 本文 format | plain text か Markdown-lite か。最大 bytes/lines、Unicode normalization、bidi/control、link/action、copy/paste をどう扱うか。 | grammar と renderer/editor round-trip test を定義する。本文から terminal command は実行しない。 |
| D-14 | State machine | draft、active、snoozed、resolved、expired、disabled の遷移主体と時刻 semantics。snooze と expiry、編集途中、undo をどう扱うか。 | transition table、invalid transition、clock change behavior を確定する。 |
| D-15 | Store contract | JSON/SQLite/他、schema version、atomic commit、fsync、permission、multi-window writer、crash/corruption recovery をどうするか。 | failure-injection 可能な storage contract と migration policy を作る。 |
| D-16 | Quota と retention | note数、本文量、receipt数、期限、eviction policy。persistent user note を自動削除してよいか。 | bounded resource budget と、容量超過時の user-visible failure を定義する。 |
| D-17 | Command secret handling | digestのみ、raw command の暗号化 opt-in、raw command を一切保存しない、のどれか。key を Keychain 等でどう生成・rotate・delete するか。 | data-flow / threat model と key loss 時 behavior を確定する。secure store 能力がなければ raw 保存は採用しない。 |
| D-18 | Exact bytes と label の可視性 | digestしかない rule を user が識別・編集・削除するため何を表示するか。label に command text を入れる危険をどう伝えるか。 | privacy UI、redaction、screen sharing / accessibility exposure を定義する。 |
| D-19 | Export / import / delete | backup、別 install への移行、key 非共有時の digest、import rule の既定 disabled、secure erase の保証範囲をどうするか。 | portable fields、non-portable fields、delete semantics、confirmation を定義する。 |
| D-20 | Observability boundary | note本文、scope、digest、match event を log、diagnostic bundle、crash metadata、analyticsへ含めるか。 | default-exclude matrix と opt-in redaction test を作る。既存 diagnostics privacy contract に影響する。 |

### Gate 4 — Trigger と delivery semantics

**状態: 完了。** S2はeligible focusのaway→return、S3は同一session/integration instanceの
arm後C→D→A/N→B cycleで一度だけdueになる。passive/due、FIFO coalescing、capability状態の
正本は
[`contextual-terminal-memory-scope-trigger-semantics.md`](contextual-terminal-memory-scope-trigger-semantics.md)
を参照する。

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-21 | Passive due / badge | 何を due と数えるか。urgency field、表示順、badge 上限、resolved/snoozed 表示、quiet default をどうするか。 | 同一 state から一意に UI projection が決まる pure model test を作る。 |
| D-22 | Next focus | app activation、window key、tab select、pane focus のどれを「戻る」とするか。作成直後、focus bounce、再起動で exactly-once をどう守るか。 | focus event sequence ごとの arm/deliver/consume table を作る。S2 に影響する。 |
| D-23 | Next prompt | OSC 133 A/B/C/D のどの transition を採用し、作成時すでに prompt の場合、shell restart、missing/out-of-order event、継続出力をどう扱うか。 | prompt automaton、arming point、dedupe、timeout、unsupported 表示を定義する。S3 に影響する。 |
| D-24 | Invocation receipt | prompt/command/output のどこへ attach し、range 消失後に本文をどう見せるか。command text を表示せず選択できるか。 | attach UI、stable reference、orphan projection と keyboard/accessibility flow を定義する。S4 に影響する。 |
| D-25 | 同時 delivery | passive、focus、prompt、invocation、checkpoint が同時に due の場合、優先、coalesce、queue、dismiss/snooze をどうするか。 | deterministic priority と starvation-free bounded queue を定義する。overlay stack に影響する。 |
| D-26 | Capability / degradation | shell adapter 未導入、OSC欠落、tmux/SSH、protocol timeout を supported/degraded/unavailable のどれで示すか。 | capability state machine を作り、未確認状態を「一致なし」「安全」と表示しない。全 trigger に影響する。 |

### Gate 5 — Overlay、編集、input authority、accessibility

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-27 | Overlay primitive | terminal view 内 child overlay、popover/sheet、別 window、Context Dock extension のどれか。pane 単位か window 単位か。 | overlay 表示前後で rows/columns、drawable、PTY winsize、`SIGWINCH` が不変である architecture と test を定義する。 |
| D-28 | Badge と entry point | 既存 secure-input/session/paste notice badge とどう共存するか。非 interactive `ViewBadge` からどう editor/rail を開くか。 | precedence、aggregation、hit target、menu/keybind entry を定義する。 |
| D-29 | Note editor | autosave/explicit save、cancel、IME marked text、selection、paste、undo、draft recovery、shortcut conflict をどうするか。 | editor state machine と IME/paste/accessibility acceptance を定義する。 |
| D-30 | Global input authority | `Terminal` / `NoteEdit` / `Checkpoint` を一つの owner model にするか。raw key、key-up/repeat、IME commit、paste/menu/services/drop/AppleScript、mouse/scroll、accessibility action の扱いを決める。 | input family × mode の routing matrix を作り、terminal へ漏れる path がないことを test する。 |
| D-31 | Checkpoint interaction | Allow/Cancel/Edit/Snooze/Escape、default focus、timeout、app inactive、window/pane close、shell exit、output継続、Secure Input 中をどう扱うか。 | atomic enter/leave、drop-not-queue、no replay、fail-open の state table を作る。S5 に影響する。 |
| D-32 | Focus reporting | overlay/editor focus 中に terminal の DEC focus report を維持するか blur を送るか。AppKit first responder と terminal-visible focus を分離するか。 | focus ownership contract と TUI regression test を定義する。 |
| D-33 | TUI / alternate screen / mouse | full-screen app、mouse reporting、bracketed paste、Kitty keyboard 中にどの slice を表示・操作できるか。 | environment matrix で layout不変、mouse leakなし、no terminal corruption を確認する。 |
| D-34 | Accessibility / localization | VoiceOver tree、focus order、live announcement、Reduce Motion、contrast、Dynamic Type相当、shortcut description、翻訳範囲をどうするか。 | note本文と app control の読み分け、localized UI、display-scale matrix の acceptance を定義する。 |

### Gate 6 — Exact-command shell adapter feasibility

S5/S6 を Gate 1 で採用候補に残した場合だけ実施する。ここで feasibility が成立しなければ、
S1〜S4を巻き込まず S5/S6 を延期または不採用にする。

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-35 | Pre-submit hook の採否 | command 受理直前に shell line editor を hook することを product が要求するか。既存 content-free boundary を拡張する価値があるか。 | zsh を使った disposable prototype と threat/compatibility review により S5 を採用・延期・不採用へ閉じる。 |
| D-36 | Transport / authentication | PTY内 custom OSC/DCS request-reply、local Unix socket/helper、shell-specific widget の組合せ。偽 terminal output、別 process、stale response をどう拒否するか。 | trust boundary、nonce/session binding、permission、lifecycle、cleanup を含む protocol ADR を作る。 |
| D-37 | 「exact bytes」の定義 | line editor の character buffer、UTF-8 encoded bytes、shell locale bytes のどれか。末尾 Enter、leading/trailing whitespace、multiline、NUL、Unicode normalization、history expansion前後をどうするか。 | test vector と cross-language encoding contract を作る。matcher互換性に影響する。 |
| D-38 | zsh / line editor integration | ZLE widget wrapping、既存 user widget、plugin order、custom accept-line、vi/emacs mode、multiline、nested shell とどう共存するか。 | clean/user-customized zsh matrix で command を欠落・二重実行・並べ替えしない証拠を得る。 |
| D-39 | Request state machine | request ID、buffer revision、timeout、cancel、duplicate、late response、shell/app crash、re-entry をどう扱うか。 | state/sequence diagram と fault-injection test を作り、timeout が bounded fail-open であることを示す。 |
| D-40 | Remote / multiplexer boundary | tmux、SSH、mosh、container、nested local shell のどこで adapter が動き、どの app instance が authority を持つか。 | support matrix と capability indicator を確定する。曖昧な path では checkpoint を作動させない。 |
| D-41 | Matcher / conflict | per-install keyed digest の algorithm/version/domain separation、constant-time compare、key rotation、複数一致、disabled/snoozed rule をどう扱うか。 | known-answer、collision/conflict、rotation/migration test を定義する。 |
| D-42 | Simulation / observe-only | real PTY write を絶対に行わず、同じ matcher/protocol path をどう exercise するか。observe-only が secret を log しないか。 | write spy と integration harness で zero real command execution を証明する。S6 に影響する。 |

### Gate 7 — Architecture、検証、rollout、仕様凍結

| ID | 決めること | 主な選択肢・問い | 完了証拠と影響 |
| --- | --- | --- | --- |
| D-43 | Ownership / concurrency | app model、pane/session worker、renderer、native main thread のどこが store、trigger、overlay、protocol state を所有するか。queue上限と teardown 順は何か。 | ownership table、message schema、backpressure、stale generation rejection をADR化する。 |
| D-44 | Config と capability enablement | default off/on、live reload/new session only、per-slice kill switch、shell snippet version mismatch をどうするか。 | effective config と runtime transition matrix を作る。zero-default-policy と rollout に影響する。 |
| D-45 | Schema / protocol evolution | store version、shell adapter version negotiation、older app/shell、downgrade、partial migration をどう扱うか。 | forward/backward compatibility と rollback-safe migration test を定義する。 |
| D-46 | Verification budget | model/property/fuzz/fault injection、real PTY、native UI、IME/VoiceOver、TUI/tmux/SSH、performance/resource の必須 gate をどこまで課すか。 | slice ごとの test pyramid、platform matrix、latency/memory/file-size budget を定義する。 |
| D-47 | Release / rollback | internal preview、opt-in、default-on の段階、store backup、protocol disable、rollback後の data をどうするか。 | stage exit criteria、kill switch、recovery runbook を作る。 |
| D-48 | 仕様凍結と実装化 | 採用項目間の矛盾、未決定 dependency、acceptance 不足をどう検査し、どの粒度で実装 task にするか。 | slice ごとの specification と decision record を review し、採用分だけを `ROADMAP.md` に順序付きで追加する。 |

## 依存順と停止条件

1. Gate 1 で slice と success/kill criteria を決める。
2. 採用候補 slice に必要な Gate 2〜5 だけを確定する。
3. S5/S6 が残った場合だけ Gate 6 の disposable feasibility を行う。
4. 採用 slice に対して Gate 7 を確定し、仕様を review する。
5. D-48 が完了してから初めて実装 task を `ROADMAP.md` へ追加する。

次の場合は実装へ進まず、該当 slice を延期または不採用として閉じる。

- stable identity または lifecycle を定義できない。
- unsupported / timeout を安全扱いする設計しか成立しない。
- terminal geometry、PTY bytes、focus report、IME state を無断で変える。
- sensitive command data の保管・削除・診断境界を説明できない。
- bounded resource、fail-open、rollback、検証可能な acceptance を定義できない。

## Gate 1 着手前の初期仮説

- S1 は shell adapter に依存しないため、他 slice から独立して価値検証できる。
- 現行製品に workspace identity はないため、D-07 が閉じるまでは session scope だけで
  代用せず、workspace scope を延期候補として扱うのが安全である。
- S4 を現行 `commandId` へ接続する場合、最初は live-session 限定と明記する方が、
  restoration を含む durable receipt を暗黙に約束しない。
- S5 は新しい bidirectional control channel、global input authority、secret handling を必要と
  するため、S1〜S4 と同時に MVP 承認せず独立採否にする。
- encrypted raw command は secure key storage と recovery/delete contract が決まるまで
  採用しない。digest-only も key lifecycle が未決定なら実装しない。

Gate 1で、S1/S2採用、S3を次 incrementとして採用、S4〜S6延期となり、これらの仮説と
矛盾しない。S5/S6の最終的な採否はGate 6まで確定しない。

## 次の検討で最初に閉じる事項

`ROADMAP.md` の次の未完了 task は Gate 3 のdata model、永続化、privacy、security、migration
方針である。S1〜S3だけを current scope とし、次の順に決める。

1. Note entity、trigger record、delivery recordを分離するかとfield invariantを決める。
2. 本文format、Unicode/control/link policy、bounded sizeを決める。
3. active/resolved、trigger/delivery、detachedのstate transitionをdata modelへ落とす。
4. store、atomic transaction、restoration reconciliation、quota、corruption recoveryを決める。
5. export/import/delete/diagnostics/privacy boundaryとschema migrationを決める。

## 検証記録

2026-09-20 に次を実行した。

- `git diff --check` / `git diff --cached --check`: pass。初回検査では新しい
  `ROADMAP.md` に1件、archive を stage 後の検査では旧文書から継承した2件の trailing
  whitespace を検出した。いずれも Markdown hard break を `<br>` 表記へ置換して再検査した。
- changed/new Markdown 7件の相対 link target 検査: pass。repository 内、archive からの
  rebased path、隣接 `dart_appkit` の参照先がすべて存在する。
- `HEAD:ROADMAP.md` と archive 本文の比較: pass。archive banner を除き、差は移動後に
  必要な相対 link rebasing と、上記2件の hard break 表記の正規化だけで、本文と task
  state は保持されている。
  最初の比較 script は replacement 順により `../dart_appkit` を誤って `docs/dart_appkit`
  と正規化して mismatch を報告した。期待する archive 形へ一方向変換する比較へ直し、
  file 側に差がないことを確認した。
- roadmap ordering 検査: pass。現在の8項目のうち archive/intake だけが完了し、最初の
  未完了項目は Gate 1。archive 側の低優先 follow-up は5件とも未完了のまま残る。
- 最初の `git add` は sandbox 内から `.git/index.lock` を作れず失敗した。変更 file は
  保持され、許可済みの repository-scoped escalation で同じ明示 path だけを stage した。
- production code、build file、generated artifact は変更していないため、Dart unit test、
  native build、実機 acceptance は対象外とした。
