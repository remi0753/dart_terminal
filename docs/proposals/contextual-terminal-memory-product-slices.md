# Contextual terminal memory product slice decisions

- 状態: Gate 1 完了（製品コード実装未承認）
- 作成日: 2026-09-20
- Branch: `codex/contextual-memory-design`
- 親文書: [`contextual-terminal-memory-design-decisions.md`](contextual-terminal-memory-design-decisions.md)
- 原案: [`contextual-terminal-memory-and-input-checkpoints.md`](contextual-terminal-memory-and-input-checkpoints.md)
- Overlay仕様: [`contextual-terminal-memory-overlay-editor-accessibility.md`](contextual-terminal-memory-overlay-editor-accessibility.md)

## 目的

Contextual terminal memory の中心価値と最初に届ける製品 slice を定め、S1〜S6を
採用、延期、不採用のいずれかへ分類する。併せて、成功・中止基準、safety claim、
対象環境、user-facing terminology を確定し、後続の scope／identity 設計が暗黙の
製品判断を背負わない状態にする。

## 背景

利用者は terminal 上の note を、Miro の付箋のように短い情報を色と面で認識できる
GUI として構想している。添付画像は visual reference であり、画像内の文字、toolbar、
collaboration UI、whiteboard layout は要件や操作指示として扱わない。また、Miro の
外観を複製することも目的にしない。

原案は basic note、next-focus、next-prompt、invocation receipt、exact-command checkpoint
を一つの MVP に含めている。しかし各 slice は shell integration、input authority、privacy、
security 上の依存が異なるため、個別に採否を決める必要がある。

## 対象範囲

- D-01〜D-06 の製品判断
- S1〜S6 の採用、延期、不採用と再検討条件
- 付箋らしい GUI の product-level visual direction
- 最小 release slice と後続 release 候補
- privacy-safe な成功・中止基準

## 対象外

- overlay の native primitive、寸法、配置、色 token の最終仕様
- scope ID、session lifetime、trigger state machine の確定
- store schema、暗号化、shell adapter protocol の設計または prototype
- production code、test code、asset の実装
- infinite canvas、自由座標配置、矢印、共同編集、Miro 互換 UI

## 依存関係

- root [`ROADMAP.md`](../../ROADMAP.md) の Gate 1
- 設計判断一覧の D-01〜D-06 と、既存 contract の調査結果
- 現行の tabs、splits、windows、Context Dock、trusted application chrome
- terminal geometry、PTY bytes、scrollback、focus semantics を変えないという原則

## 完了条件

- D-01〜D-06 に選択結果、理由、既存 contract への影響、acceptance を記録する。
- S1〜S6を採用、延期、不採用のいずれかへ分類し、実装順とは分離する。
- 付箋 visual direction の必須要素と非目標を明記する。
- success metric、kill criterion、safety claim、対象環境、用語を定義する。
- 親文書と原案の status を更新し、`ROADMAP.md` の次の未完了 task が Gate 2/4 になる。
- Markdown link、roadmap ordering、diff scope を検証し、この task だけを commit する。

## 検証方針

- decision table の全 D-01〜D-06 と S1〜S6 に未決定状態が残らないことを機械的に確認する。
- changed Markdown の相対 link target と whitespace を静的検査する。
- `ROADMAP.md` の完了順序と、次の未完了 task を検査する。
- product code、generated artifact、画像 file が差分に含まれないことを確認する。

## 調査記録

### 2026-09-20: 着手

- 作業開始時の tracked worktree は clean だった。
- `main` の `87c9a70` から `codex/contextual-memory-design` を新規作成した。
- `README.md`、`ROADMAP.md`、`FEATURE_MATRIX.md`、原案、設計判断一覧、repository 構成を
  再確認した。Gate 1 が最初の未完了 task である。
- visual reference は 2400×1350 の Miro UI screenshot で、白い canvas 上の色付き付箋、
  card、軽い shadow、選択 outline、inline toolbar により object と状態を terminal text とは
  別の GUI surface として認識させている。

## Product decisions

### Product statement

この機能の中心価値は、**terminal の作業文脈を、terminal text とは別の視覚的な付箋として
残し、利用者が選んだ意味のある時点で再提示すること**である。一般的な notebook ではなく、
現在の pane で短い意図や申し送りを残し、戻ったときに思考を再開できることを優先する。

付箋は GUI の card surface として存在するが、terminal session を自由座標へ配置する
whiteboard にはしない。tabs、splits、windows が session layout の正本であり、note は
pane chrome に anchor された一覧と一時的な overlay で表示する。

### D-01〜D-06

| ID | 結果 | 決定 | 理由と downstream 影響 |
| --- | --- | --- | --- |
| D-01 | 採用 | GUI-native な contextual note と、pane に戻ったときの return cue を中心課題にする。exact-command の誤操作防止は中心課題にしない。 | 利用者が示した付箋の mental model と、一般 note app にはない terminal transition を組み合わせられる。S1/S2を優先し、S5を基盤要件から外す。 |
| D-02 | 採用 | 最小 release slice は S1+S2。S2は note の再提示までで、input hold は含めない。S3は次の increment として採用する。 | shell adapter と global checkpoint authority なしで end-to-end value を検証できる。S3は静的 note との差別化を強めるが、verified lifecycle event が必要なので分離する。 |
| D-03 | 採用 | production telemetry を追加せず、scripted acceptance、moderated usability、明示的な opt-in feedback で判断する。hard safety invariant と product comprehension を別 gate にする。 | note本文や利用時刻を収集せずに価値を評価できる。基準未達時は default-on や次 slice を停止する。詳細は「成功・中止基準」に固定する。 |
| D-04 | 採用 | S1〜S3を「記憶と再開の補助」と表現し、security、policy、command safety を名乗らない。初期 release は terminal input を block しない。 | 色も risk 判定を意味しない。将来の checkpoint は別機能として unavailable/fail-open を明示し、別途採否する。 |
| D-05 | 採用 | S1/S2は macOS 14+ のすべての pane と shell/TUI で local feature として提供する。S3は verified prompt capability がある local shell だけを対象とする。 | tmux/SSH/alternate screen で推測しない。capability が確認できない場合も note は失わず、passive note として閲覧可能にする。 |
| D-06 | 採用 | user-facing object は `Note`、entry point は `Notes`、expanded collection の内部名は `note rail` とする。`Checkpoint` と `Rule` は S5 専用に予約する。 | 一般 note と input-blocking behavior を言葉で混同しない。workspace/receipt は採用されるまで UI 用語にしない。 |

## Slice classification

ここでの「採用」は後続の仕様確定対象に入れることを意味し、直ちに製品コードの実装を
承認するものではない。「延期」は現在の initial implementation backlog に入れず、表の
再検討条件が満たされた場合だけ再判断する。

| Slice | 判断 | Release boundary | 含むもの | 含まないもの／再検討条件 |
| --- | --- | --- | --- | --- |
| S1 Basic memory | **採用** | 最初の release slice | pane から note を作成・閲覧・編集・resolveできる。付箋らしい card、collapsed badge、expanded note railを持つ。 | 自由座標、workspace自動検出、command rule、terminal textへの埋め込みは含めない。 |
| S2 Park / next focus | **採用** | 最初の release slice | 利用者が明示的に return note を arm し、対象 pane へ戻ったとき一度だけ card を展開する。 | input hold、resume 強制、TUI 操作の阻止は含めない。focus と exactly-once の詳細は Gate 2/4 で決める。 |
| S3 Next prompt | **採用** | S1/S2の acceptance 後の次 increment | verified prompt-ready event で user-authored note を一度だけ提示し、unsupported/degraded を明示する。 | command text収集、screen scraping、input hold、未確認 event の推測は含めない。 |
| S4 Invocation receipt | **延期** | initial roadmap外 | なし。 | S1〜S3の価値検証後、利用者が過去 command 単位の紐付けを必要とし、live-only/durable receipt identity を説明できた場合に再検討する。 |
| S5 Exact-command checkpoint | **延期** | initial roadmap外の独立 product fork | なし。 | Gate 6 で user value、pre-submit hook、trust boundary、secret handling、fail-open が成立し、利用者が明示的に採用した場合だけ再検討する。S1〜S3の設計を阻害しない。 |
| S6 Simulation / observe | **延期** | S5と同時にのみ再検討 | なし。 | S5を採用しない限り standalone feature として実装しない。S5採用時は active rule の必須前段として再評価する。 |

### 明示的に不採用とする製品方向

- infinite canvas、zoomable whiteboard、session の自由座標配置
- session 間の arrow、diagram、visual pipeline
- collaboration cursor、comment thread、multi-user editing
- Miro の toolbar、layout、brand、interaction の複製
- terminal cell、scrollback row、TUI element へ付箋を追従させること
- note 色から危険度、host、environment を自動推論すること

## Visual direction

### 必須の体験

- Note は terminal glyph と明確に異なる、theme-aware な card surface として描画する。
- Card は背景色または accent、境界／shadow、padding を持ち、短い文章を面として認識できる。
- 利用者は bounded palette から色を選べる。色は整理と想起のための user-authored metadata で、
  自動 severity や安全判定には使わない。
- Collapsed state は pane chrome の小さな note badge とし、件数と due state を表示する。
- Expanded state は pane に anchor された note rail で card を順序付きに並べる。一つの card を
  読む／編集するときは terminal の一部を一時的に覆ってよいが、rows/columns は変えない。
- Create、edit、color、show timing、resolve の controls は GUI として discoverable にし、同じ操作を
  keyboard でも完結できるようにする。
- 選択、due、waiting、resolved は色だけに依存せず、label、icon、shape、accessibility value の
  組合せで区別する。
- alternate screen や continuously redrawing TUI ではpassive Noteをcollapsed badgeに留める。
  Due Noteだけは単一railをnon-blockingに展開し、terminal focus/inputを変えない。

### Gate 5で確定したvisual/interaction

- Terminal native view内のinteractive AppKit child overlayとtrailing railを使い、geometryを変えない。
- Opaque paper card、6色のlight/dark token、10 pt corner、bounded shadow、non-color status chipを使う。
- Explicit Save/Cancelのplain-text native editorとvolatile Undoを使い、Markdown/autosaveは導入しない。
- Card reorder、keyboard equivalent、VoiceOver、英語／日本語、contrast、Reduce Motionを同じcontractにする。

正確なgeometry、palette、owner/input matrix、TUI/DEC focus、accessibility acceptanceは
[`overlay/editor仕様`](contextual-terminal-memory-overlay-editor-accessibility.md)を正本とする。
この結果もMiroのscreenshotをpixel-level specificationとして扱わない。

## Release boundaries

### Initial release: Visual return notes

S1とS2だけを含む。利用者は active pane から色付き Note を作成し、passive または
`On Return` を選び、note rail で管理できる。return note は対象 pane へ戻ったときに
一度だけ展開するが、terminal input を停止しない。

### Next increment: Prompt notes

Initial release の hard invariant と product validation を満たした後、S3を追加する。
`At Next Prompt` は verified capability がある場合だけ選択可能で、capability を失った note は
消去せず `Waiting for supported prompt integration` と同等の neutral state で rail に残す。

S4〜S6はこの2段階の schema、protocol、UI extension point を先回りして複雑化させない。
将来の互換性のためだけの optional field、digest、checkpoint mode は initial model に入れない。

## 成功・中止基準

### Hard release invariants

一件でも違反した場合は該当 release を停止する。

- Note の create/open/edit/close/trigger で PTY へ意図しない byte を一度も送らない。
- terminal grid、cursor、scrollback、selection、reported rows/columns、`SIGWINCH` を変えない。
- overlay を閉じた後に key、IME commit、paste、mouse event を遅延 replay しない。
- note body、色、scope、trigger、利用時刻を一般 diagnostics、crash metadata、analyticsへ含めない。
- unsupported trigger を delivered、matched、safe と表示しない。
- alternate screen、tmux、SSH、shell integrationなしでも S1/S2 の note を失わない。

### Product comprehension gate

Default-on を検討する前に、少なくとも5人の representative evaluator に scripted task を
実施し、次を満たす。

- 4/5以上が補助なしで Note を作り、色を選び、`On Return` を設定し、戻った後に resolveできる。
- 5/5が Note を application UI と認識し、shell output／prompt text ではないと説明できる。
- 5/5が note body の command text は自動実行されないと説明できる。
- 4/5以上が passive、on-return、resolved の状態を card と non-color cue から区別できる。

Product はこの評価の本文を自動収集しない。結果は匿名化した count、観察した混乱、設計変更だけを
task memo に手動記録する。外部 evaluator を用意できない間は opt-in preview のままとし、
成功したものとして扱わない。

### Slice progression / kill criteria

- S1/S2で上記4/5基準を一回の改善 iteration 後も満たせなければ default-on を中止し、
  note rail または feature 自体を再設計する。
- evaluator の2人以上が Note を shell content、security warning、command blocker と誤認した場合、
  文言とvisual hierarchyを直すまで releaseを進めない。
- S1/S2の workflow で return timing が一般 note app との差として利用されない場合、S3へ進まず、
  static note surfaceを製品に持つ価値から再評価する。
- S3は supported、degraded、unavailable の scripted sequence 各20回で false delivery 0、lost note 0、
  duplicate delivery 0を満たさなければ releaseしない。
- S4〜S6は延期条件を満たさない限り、未実装であることを欠落として扱わない。

## Safety claim

User-facing copy は `reminder`、`return note`、`show at next prompt` を使う。`protect`、`safe`、
`guard`、`policy`、`block dangerous command` は使わない。色付き card、特に赤や黄も security
severity を自動的に意味しない。初期 release では Note 表示中も terminal input は通常どおり
利用できるため、この挙動を GUI 内で隠さない。

将来 S5 を採用する場合も checkpoint は一つの client における mistake-prevention であり、
authorization boundary ではない。adapter unavailable／timeout は明示し、no-match と
safe state を区別する。

## Target environment matrix

| Environment | S1 Basic memory | S2 On Return | S3 At Next Prompt |
| --- | --- | --- | --- |
| macOS 14+、通常 local pane | 対応 | 対応 | verified integration 時に対応 |
| zsh / bash / fish / nushell | shell非依存 | shell非依存 | 各既存 adapter の verified OSC lifecycle がある場合だけ対応 |
| alternate screen / Vim / Codex / TUI | badgeと明示open | 対象 pane 復帰時にcard。inputはblockしない | prompt event がない間は待機し、推測しない |
| local tmux | 対応 | 対応 | active shellのcapabilityをend-to-end確認できない限り unavailable |
| SSH / remote shell | local pane noteとして対応 | local pane復帰として対応 | remote側eventがverifiedでない限り unavailable |
| shell integration disabled / missing | 対応 | 対応 | unavailable。noteはpassiveに閲覧可能なまま保持 |
| x86_64 / Rosetta / Universal build | distribution baselineに従う | distribution baselineに従う | capability behaviorをarchitecture間で一致させる |

## Terminology

| Concept | User-facing | Internal / note |
| --- | --- | --- |
| Feature entry | `Notes` / `ノート` | contextual terminal memory |
| Visual object | `Note` / `ノート` | annotation entity |
| Expanded collection | UI titleは `Notes`。`memory`とは呼ばない | note rail |
| Passive timing | `Always available` / `常に表示可能` | passive |
| Return timing | `On Return` / `戻ったとき` | next-focus trigger |
| Prompt timing | `At Next Prompt` / `次のプロンプト` | next-prompt trigger |
| Completed item | `Resolved` / `解決済み` | resolved state |
| Input hold | initial UIには出さない | checkpoint。S5専用 |
| Exact matcher | initial UIには出さない | rule。S5専用 |
| Past command attachment | initial UIには出さない | invocation receipt。S4専用 |
| Workspace | 定義完了までUIに出さない | Gate 2で採否するscope候補 |

## 後続 gate への制約

Gate 2/4の結果は
[`contextual-terminal-memory-scope-trigger-semantics.md`](contextual-terminal-memory-scope-trigger-semantics.md)
を正本とする。以下の制約を保ったまま、`This Terminal` scope、durable note context、
deterministic On Return／At Next Prompt semanticsを採用した。

- Gate 2/4 は S1〜S3だけを current scope とし、S4〜S6のための durable receipt、digest、
  rule scope、checkpoint stateを先行設計しない。
- Gate 2では initial release の attach target を pane/session のどちらとして userへ説明するか、
  app restart、pane close、restoration を跨ぐかを最初に決める。
- Gate 3では note entity と store を設計し、exact-command secret field は含めない。
- Gate 5では本書のvisual directionをinteractive child overlay、edge badge、trailing railとして確定した。
  Infinite canvasやcell-relative positioningは候補へ戻さない。
- Gate 6は S5/S6だけの独立再評価であり、S1〜S3の採用を取り消したり、その model を
  speculative checkpoint fieldsで汚染したりしない。

## 検証記録

2026-09-20 に次を実行した。

- `git diff --check`: pass。
- changed/new Markdown 4件の相対 link target 検査: pass。
- D-01〜D-06 decision row と S1〜S6 classification の機械検査: pass。
  最初の2回の script は検証方針／検証記録に書いた「未決定」や literal
  `` `| 未決定 |` `` まで検索して false failure になった。最終 script は `D-01`〜`D-06` と
  `S1`〜`S6` で始まる decision row だけを抽出し、6件ずつの件数、D項目の`採用`、
  sliceの期待分類を直接検査した。
- roadmap ordering 検査: pass。archive/intake と Gate 1が完了し、最初の未完了 task は
  scope、identity、lifecycle、trigger delivery semantics の Gate 2/4になった。
- diff scope review: `ROADMAP.md` と `docs/proposals/` の Markdownだけが変更対象で、
  production code、test code、generated artifact、参照画像は変更またはcopyしていない。
- 文書のみのproduct decision taskであるため、Dart unit test、native build、実機acceptanceは
  対象外とした。各sliceの実装時に本書のhard invariantを対応するautomated/manual gateへ
  落とし込む。
