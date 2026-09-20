# Contextual terminal memory checkpoint feasibility

- 状態: Gate 6 完了（製品コード実装未承認）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- Product判断: [`contextual-terminal-memory-product-slices.md`](contextual-terminal-memory-product-slices.md)
- Overlay/input仕様: [`contextual-terminal-memory-overlay-editor-accessibility.md`](contextual-terminal-memory-overlay-editor-accessibility.md)

## 目的

Exact-command checkpoint（S5）を実現するには、shellがcommandを受理する直前のbufferを取得し、
terminal appの判断が返るまで実行を保留する新しい双方向経路が必要になる。本書ではzshのdisposable
prototype、既存4-shell integrationとの互換性、transportとcommand secretのtrust boundaryを検証し、
S5と従属するsimulation（S6）を採用、延期、不採用のいずれかへ閉じる。

## 背景

Gate 1で採用した中心価値は、GUI-nativeな付箋としてterminalの作業文脈を残し、returnまたは
verified promptで再提示するS1〜S3である。S5は誤送信防止という別の利用目的を持ち、現行の
content-free OSC 133 lifecycleをcommand本文、input hold、reply authenticationまで拡張する。
Gate 1ではこのcostをS1〜S3へ波及させないためS5/S6を延期し、Gate 6の実証後に最終判断するとした。

## 対象範囲

- D-35〜D-42
- zsh ZLEの`accept-line`前でbufferを観測／保留できるかを確認するdisposable prototype
- user widget、plugin load order、multiline、vi/emacs keymapとのcompatibility risk
- PTY custom sequence、Unix-domain socket/helper、shell-specific widgetのtrust境界比較
- exact-command identity、秘密情報、timeout／stale response／crash、remote／multiplexer境界
- S5/S6の最終的なproduct classificationと、S1〜S3への影響

## 対象外

- 製品shell resource、protocol、matcher、key、checkpoint UI、test fixtureの実装
- command本文またはdigestの永続化
- S1〜S3のNote schema、trigger、rail、editor仕様の変更
- shellの安全性判定、policy enforcement、malicious processからのsecurity guarantee

## 依存関係

- 現行version 2 shell integrationはzsh、bash、fish、nushellへcontent-freeなOSC 7/133を出力する。
- S1/S2はshell integration非依存、S3はverified lifecycleだけを利用しcommand本文を取得しない。
- Gate 5のinteraction ownerはS1〜S3だけを持ち、Checkpoint modeを先行導入していない。
- S5を採用する場合はGate 3のschema/privacyとGate 5のinput authorityを再度開く必要がある。

## 完了条件

- D-35〜D-42を採用、延期、不採用のいずれかで閉じる。
- zsh prototypeの手順、期待値、結果をcommand本文を残さない形で記録する。
- transport、authentication、exact bytes、plugin order、state machine、remote、matcher、simulationの
  riskと成立条件を比較する。
- S5/S6の採否、再提案条件、S1〜S3から除外する型／protocol／UIを明記する。
- 親文書、原案、product slice文書、roadmapを更新し、次の未完了taskをGate 7にする。
- Markdown/link/order/diff scopeを検証し、このtaskだけをcommitする。

## 検証方針

- hostのinstalled zshを隔離設定で起動し、pre-submit capture、hold、delegate、後勝ちのwidget置換を
  再現する。temporary artifactだけを使い、repositoryのproduct codeへprototypeを残さない。
- 現行4-shell resourceを照合し、共有できるline-editor hookがないこととcontent-free boundaryを確認する。
- shell／transport／remote environment matrixとfault stateを静的にreviewする。
- changed Markdown link、whitespace、roadmap ordering、product-code差分なしを検査する。

## 調査記録

### 2026-09-20: 着手

- Gate 5はcommit `907c03f`で完了し、着手時のtracked worktreeはcleanだった。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、Gate 1〜5の仕様、repository構成を再確認し、
  Gate 6が最初の未完了taskであることを確認した。
- 添付画像はNoteのGUI affordanceの参考であり、画像内の文字やMiro固有操作をinstructionとして
  扱っていない。checkpointの採否は画像の外観ではなく、中心価値、trust、互換性、検証可能性で決める。
- 現行resourceはzshの`preexec`、bashの`PS0`、fishの`fish_preexec`、nushellの
  `hooks.pre_execution`で実行境界を通知するだけである。いずれもcommand本文を送らず、appからshellへ
  判断を返さず、line editorを保留しない。現在のversion 2 contractをそのままS5へ転用できない。

### 2026-09-20: disposable zsh prototype

対象hostは`zsh 5.9 (arm64-apple-darwin25.0)`である。`env -i`と`zsh -f`を使ったisolated interactive
shellだけで検証し、prototype file、history、product resourceを作らなかった。Command本文は成果物へ
保存せず、以下のcontent-free markerだけを判断証拠とした。

| Probe | 操作 | 期待 | 結果 |
| --- | --- | --- | --- |
| ZP-01 capture/delegate | user-defined widgetを`accept-line`へ登録し、`BUFFER`の文字数を出した後にbuiltin `.accept-line`へ一度delegate | shell実行前にeditable bufferを観測し、commandを一度だけ実行できる | pass。`PROBE_CAPTURE count=1 chars=12 multiline=0`の後にpromptへ戻った |
| ZP-02 hold/cancel | widgetから`.accept-line`を呼ばずbufferをredisplayし、別のbuiltin widgetでlineをcancel | bufferがshellへ渡らず、side effectが生じない | pass。`PROBE_HOLD chars=16`、cancel後は`PROBE_EXECUTED=0` |
| ZP-03 multiline | ZLE widgetで改行を含むbufferを作り、wrapped `accept-line`へ渡す | line editor上のmultilineを識別できる | pass。`PROBE_CAPTURE ... chars=25 multiline=1`。値はZLE character bufferで、encoded execution bytesではない |
| ZP-04 late replacement | wrapper登録後、別のuser widgetを同じ`accept-line`名へ登録 | singular widget ownershipのload-order conflictを再現する | pass。後続Enterは`PROBE_PLUGIN owns-enter`だけを出し、元wrapper countは9から増えなかった |
| ZP-05 preexec return | `add-zsh-hook preexec` hookがnon-zeroを返す | lifecycle hookだけで実行を止められないことを確認する | pass。`PROBE_PREEXEC return=1`の後もassignmentが実行され、`PROBE_PREEXEC_EXECUTED=1`だった |

このprobeが証明するのは、clean zshで一つの`accept-line` widgetを完全に所有すればpre-submit holdを
構成できることだけである。認証、timeout、GUI応答、shell/app crash、user typeahead、全keymap、plugin
chain、tmux/SSH、他shellとの互換性は証明しない。特に現行zsh bootstrapはuser `.zshenv`の後にintegrationを
読み込む一方、通常の`.zshrc`とpluginはその後に読み込まれる。S5 widgetを同じ位置で登録しても、
ZP-04と同じ後勝ちで迂回され得る。毎promptで再登録すれば逆にuser widgetを奪うため採用できない。

### 2026-09-20: shell compatibility review

| Environment | 現行contract | Pre-submit holdを追加する場合の差分 | Gate 6判断 |
| --- | --- | --- | --- |
| local zsh | `preexec`/`precmd`のcontent-free OSC 133 hook | ZLE widget ownership、全keymap、widget chain、async replyが必要 | prototype可能だが製品保証不成立 |
| local Apple bash 3.2 | `PS0`と`PROMPT_COMMAND` | Readline bindingを別実装し、既存binding／macro／modeと共存させる必要がある | zsh成果を再利用できない |
| local fish | event hook | fish readerのbindingとasync decisionを別実装する必要がある | hostに実shellがなく、resource contract以上の証拠なし |
| local nushell | config hook | Reedline/keybindingとasync decisionを別実装する必要がある | hostに実shellがなく、resource contract以上の証拠なし |
| nested local shell | outer integrationはinner line editorを所有しない | 最内shellのadapter discoveryとauthority移譲が必要 | authorityを一意にできない |
| tmux | bytesとpane mappingをmultiplexerが仲介する | exact source pane、passthrough、reply routeを認証する必要がある | initial support不可 |
| SSH/mosh/remote shell | line editorはremote host側にある | local secret/socketを公開せずremote adapterとclientをbindする仕組みが必要 | initial support不可 |
| REPL/TUI/direct executable | shell accept-lineが存在しない | application別adapterが必要 | 対象外 |

現行4-shell resourceが共有するのは、実行の前後にterminal outputへcontent-free markerを出す契約だけである。
Line editor、keymap、buffer representation、async wait APIは共有していない。S5を「zshだけのexperimental
機能」に縮めても、最初のrelease対象として宣言したshell-neutralなS1/S2と異なるcapability surface、設定、
説明、support負担を作る。

## Trust boundary review

### 候補transport

| 候補 | 成立する点 | 解消できない境界／追加cost | 判断 |
| --- | --- | --- | --- |
| PTY内 custom OSC/DCS request-reply | 現行parserとshell output routeに近く、追加socketなし | 同じPTYの任意process、remote output、replayed scroll outputを正規adapterと区別できない。reply byteはZLEのtypeahead/inputと競合し、nonceだけではrequest producerを認証できない | 不採用 |
| Per-pane Unix-domain socket + helper | PTY inputとcontrol replyを分離でき、0600 directory、peer credential、session nonceを設けられる | socket/token配布、同一uid process、cleanup、app restart、pane generation、sandbox、nested shell、remote非到達を新たに所有する。raw bufferをappへ渡すprivacy拡張も残る | 今回は不採用 |
| shell-specific widget内のlocal matcher | commandをPTYへ出さず、clean local shellなら低latency | rule/key配布、rotation、widget upgrade、4-shell重複実装、GUI本文取得と決定通知の別channelが必要。user pluginとのownership conflictは残る | 不採用 |

PTYはterminal applicationとchild processのdata transportであり、child内の「正規shell adapter」と「それ以外の
output」を認証するchannelではない。秘密nonceをOSCへ足しても、その秘密をshell environment／startup codeへ
配布した時点でnested processへのexposureとlifecycleを説明する必要がある。Unix socketならtransport spoofingを
狭められるが、S5のためだけのsession-authenticated control planeを新設することになり、既存OSC 133の小さな拡張
ではない。

### Command identity and secret handling

ZLEの`BUFFER`はline editorのcharacter bufferであり、「shellが最終的に実行するexact bytes」ではない。
少なくとも次の境界を一つのportable equalityへ畳み込めない。

- shell localeでのencodingとUTF-8、Unicode normalization、NULを表現できないshell変数
- final Enter/newline、leading/trailing whitespace、literal multiline
- history expansion、alias/function resolution、parameter/command substitution、parserによるtokenization
- user widgetがaccept前に行うbuffer rewrite、macro、completion、vi/emacs keymap固有action

Pre-expansion buffer equalityなら定義できるが、実行内容の同一性ではない。`Exact-command`という名称はその差を
隠しやすい。Raw bufferをappへ送ればcommand secretが既存privacy boundaryを越える。Per-install keyed digestを
shellで作るならkeyを全adapterへ安全に配布・rotate・revokeする必要があり、appで作るならraw bufferのtransferと
volatile handlingが必要である。Initial Note storeはKeychain、command digest、raw commandを持たないため、S5を
採用するとGate 3を再設計することになる。

### Hold state and failure behavior

製品化には少なくとも`idle -> requested -> held -> allow/cancel/edit/timeout -> idle`をbuffer revisionと
pane/session generationへbindし、duplicate、late reply、re-entry、shell exit、app crash、window close、inactive、
Secure Inputを処理する必要がある。Fail-openはavailabilityを保つが、app crashやtimeout時に利用者が止まると
期待したcommandを実行する。Fail-closedはshellをhangさせ、通常terminalとしてのrecoveryを損なう。どちらも
「付箋で文脈を再開する」というS1〜S3の中心価値には不要なriskである。

同様にterminal overlayだけでkeyboard/paste/mouseを止めても、script、別client、別terminal、remote automation、
shell自身のqueued actionは止まらない。S5をsecurity/policy boundaryにできないことは明示可能だが、その説明を
読んでもらうこと自体が製品complexityになる。

## Decisions

### Decision summary

| ID | 結果 | 決定 |
| --- | --- | --- |
| D-35 | **不採用** | Contextual memory productはpre-submit hookを要求しない。S5をS1〜S3のbacklog、schema、UI、capabilityへ含めない。 |
| D-36 | **不採用** | Bidirectional PTY control sequence、socket/helper、adapter authenticationを追加しない。現行shell integrationはcontent-free one-way lifecycleを維持する。 |
| D-37 | **不採用** | `ExactCommandBytes`等の型やportable equalityを定義しない。ZLE bufferは実行bytesと同一ではないため、この製品でexact-command claimを行わない。 |
| D-38 | **不採用** | ZLE `accept-line` wrapperを出荷しない。Clean zshでholdは可能だが、user widget、plugin order、keymap、nested shellを非侵襲に保証できない。 |
| D-39 | **不採用** | Request ID、buffer revision、timeout、duplicate/late replyを持つcheckpoint state machineを導入しない。従ってfail-open/fail-closed状態をUIへ露出しない。 |
| D-40 | **不採用** | local/remote/tmux別のcheckpoint adapterとcapability indicatorを導入しない。全environmentでS5をadvertiseせず、S1〜S3の既存capabilityだけを示す。 |
| D-41 | **不採用** | command rule、raw command、keyed digest、per-install key、conflict/rotation/migrationをNote storeへ追加しない。 |
| D-42 | **不採用** | S6 simulation/observe-onlyをstandalone機能として実装しない。S5がなければfake checkpointは実経路を検証せず、observeには同じcommand exposureが必要になる。 |

### Product classification

- S5 Exact-command checkpoint: **不採用**。
- S6 Simulation / observe: **不採用**。S5に従属するため単独価値として残さない。
- S1 Basic memory、S2 Park / next focus、S3 Next prompt: 判断も仕様も変更しない。
- S4 Invocation receipt: 延期を維持する。S5/S6不採用を理由に自動採用しない。

「不採用」は実装順を後ろへ送る意味ではない。Current contextual-memory roadmapにmatcher、rule、checkpoint、
input hold、simulationの互換予約を残さず、implementation taskも作らない。将来再検討する場合は本提案の延期項目を
再開せず、誤送信防止を中心価値にした**別product proposal**を作る。そのproposalには最低でも次の新しい証拠を
要求する。

1. Noteとは独立した利用者要求と、securityではない保証を誤認させない名称／success criterion。
2. 対象shellを明記した非侵襲adapter contractと、user widget/plugin/keymap matrixでの実PTY証拠。
3. PTY outputと分離したauthenticated control channel、session binding、cleanup、crash recovery。
4. Pre-expansion editable buffer等の正確なidentity名、secret transfer／key lifecycle／delete／diagnostics境界。
5. Fail-open/fail-closedの明示選択、input family全体、remote/tmux/nested/unsupported表示のacceptance。
6. 実経路と同一matcherを使い、real PTY transportを取得できないsimulation harness。

## Accepted contract after Gate 6

S1〜S3の実装仕様に次のsymbol、field、mode、action、resourceを予約しない。

- `Checkpoint` interaction owner、`Rule` entity、`ExactCommandBytes`、`CommandDigest`
- Allow/Run once/Edit command/Disable rule/Snooze control
- pre-submit trigger、held input、request/reply ID、adapter nonce、key reference
- checkpoint固有のshell integration version、bidirectional custom OSC/DCS、socket/helper、remote forwarding
- observe-only match event、synthetic terminal、rule import/export

Note bodyはplain textのままでcommandとして解釈せず、terminal inputをblockしない。Current shell integrationは
command本文を保持しない。Gate 7はS1〜S3だけを対象にarchitecture、verification、rolloutを凍結する。

## Verification vectors

| ID | 検証する境界 | Gate 6 acceptance |
| --- | --- | --- |
| F-01 | Clean zsh pre-submit observation | ZP-01で可能性と限定条件を記録 |
| F-02 | Hold without execution | ZP-02でside effectなしを確認 |
| F-03 | Multiline buffer | ZP-03でcharacter bufferとして観測できることを確認 |
| F-04 | Plugin/load-order conflict | ZP-04で後続widgetがwrapperを迂回することを確認 |
| F-05 | Existing `preexec` sufficiency | ZP-05でnon-zero returnでも実行を止めないことを確認 |
| F-06 | Four-shell common contract | 現行resourceがcontent-free one-way lifecycleだけを共有すると確認 |
| F-07 | Forged/replayed PTY request | producer認証不能のためPTY bidirectional案を不採用 |
| F-08 | Socket/helper lifecycle | 別control planeとsecret lifecycleが必要なためcurrent featureでは不採用 |
| F-09 | Exact identity | editor charactersとexecuted bytesの差を列挙し、exact claimを不採用 |
| F-10 | Remote/multiplexer authority | local appがremote line editorを所有しないため全S5 capabilityを非表示 |
| F-11 | Rule secret persistence | raw/digest/key fieldをinitial schemaへ追加しないことを静的検査 |
| F-12 | Simulation dependency | S5と同じpathなしでは意味ある証拠にならないためS6を不採用 |
| F-13 | Input/UI separation | S1〜S3 owner modelへCheckpoint case/controlを追加しないことを照合 |
| F-14 | Roadmap separation | Gate 7とimplementation planにS5/S6 taskがないことを照合 |

## 検証記録

2026-09-20に次を実行した。

- `/bin/zsh --version`: `zsh 5.9 (arm64-apple-darwin25.0)`。`env -i`、`zsh -f`、interactive
  PTYでZP-01〜ZP-05を実施し、capture/delegate、hold/cancel、multiline、late widget replacement、
  non-blocking `preexec`の期待結果を得た。Repository file、shell history、product resourceは作成しなかった。
- HostのbashはApple標準`GNU bash 3.2.57`、fish/nuは未導入だった。Bash/fish/nushellは既存resourceと
  launch contractを静的に照合し、zsh prototypeをcross-shell product proofとして扱っていない。
- D-35〜D-42のdecision row: 8件すべて`不採用`。ZP probe: 5件、verification vector: 14件。
- Slice classification: S1〜S3採用、S4延期、S5/S6不採用。Gate 3/5のS5-specific fieldとowner caseを
  不採用へ同期し、command matcher、digest、bidirectional adapter、checkpoint modeの互換予約がないことを確認した。
- Changed/new Markdown 8件のrelative link 59件: 全target存在。`git diff --check`: pass。
- Roadmap ordering: 先頭6 taskが完了し、最初の未完了taskはGate 7のarchitecture／verification／rollout。
- Diff scope: `ROADMAP.md`と`docs/proposals/`のMarkdownだけ。製品code、test、shell resource、build file、
  dependency、generated artifact、添付画像は変更またはcopyしていない。
- このtaskは設計判断とdisposable shell probeだけで製品codeを変更しないため、Dart unit test、native build、
  runtime acceptanceは対象外とした。ZP probeは製品採用の証拠ではなく、不採用判断のfeasibility evidenceである。
