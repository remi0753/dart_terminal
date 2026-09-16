# Phase 7 — Context Dock foreground process inspector feasibility and design

入力保護についての当初設計・受け入れ記録はhistoricalである。ECHO-off／manual secure時の
process metadata非表示は、後続の
[`入力保護と情報表示の分離`](context-dock-process-input-privacy.md)で改訂する。
Navigator／path insertionの入力保護とprocess情報表示は別のauthorityになる。

当初の上下分割UIもhistoricalである。Process Inspectorの一覧と詳細は後続の
[`単一表示への統合`](context-dock-process-inspector-unified-layout.md)で一つの全高文書へまとめる。
Directory Navigatorの固定詳細欄は変更しない。

## 目的

focused terminal paneでcommandが実行中の間、working directoryが`unknown`になる領域を
Directory Navigatorとして無理に表示せず、実行中foreground processの情報へ切り替える機能が
安全かつ実用的に実現できるかを調査する。実現可能な場合は、観測authority、状態遷移、UI、
privacy、performance、failure、検証の設計を実装可能な粒度まで確定する。

## 背景

現行Context Dockはfocused local paneのtrusted working directoryをrootにDirectory Navigatorを
表示する。command実行中はshellのworking directoryとして信頼できるauthorityを返せず、Dockに
`unknown`が表示される。この状態は単なる情報欠落ではなく、「shell待機中のdirectory探索」と
「foreground job実行中のprocess観測」でユーザーの関心が変わる境界として扱える。

## 範囲

- local PTY sessionが既に持つshell PID、foreground process group、termios、lifecycle情報を調べる。
- macOSでPID／process groupからexecutable path、command／arguments、開始時刻または経過時間を
  取得できるpublic APIと、必要なnative境界を調べる。
- idle shell、foreground command、pipeline／複数process、subshell、TUI、終了race、権限不足を
  区別する状態modelを設計する。
- Directory NavigatorとProcess Inspectorを同じ右Dock内で排他的に切り替えるUIを設計する。
- focused pane追従、keyboard ownership、refresh cadence、bounded resource、privacy、diagnostics、
  accessibility、failure表示、acceptanceを定義する。
- 成立性判断と実装順をROADMAPへ反映する。

## 対象外

- process inspectorの実装、native API追加、UI変更、keybind追加。
- processへのsignal送信、kill／pause／priority変更、stdin injectionなどの操作。
- CPU／memory／network／open fileの継続監視やActivity Monitor代替。
- remote SSH host上のprocess introspection。
- shell integrationを必須にするcommand trackingや、terminal outputからcommand文字列を推測する処理。
- environment variable、current terminal text、command output、full process treeの表示・永続化。

## 依存関係

- `dart_pty_macos`のsession identity、foreground process group query、lifecycle／termios snapshot。
- `TerminalProcessResourceSampler`とnative process resource adapterの既存PID観測境界。
- `TerminalContextDockCoordinator`、cwd observer、Directory Navigator state／native presenter。
- pane focus、close、worker再生成、secure input、diagnostics privacyの既存所有権contract。

## 完了条件

- 実現可否をpublic OS API、既存code path、race／permission境界の証拠付きで判断する。
- 表示対象processの選択規則と「実行中」の判定authorityが一意である。
- executable、command、elapsed timeの各fieldについて取得元、fallback、上限、privacyを定義する。
- Directory Navigatorとの切替条件、UI構造、keyboard／accessibility contractを定義する。
- polling／event更新、pane focus／process終了race、pipeline／TUI／権限不足をfail-closedに扱う。
- 実装subtask、依存関係、個別完了条件、検証方針をROADMAPと本メモに記録する。
- 文書差分を検証して単独commitにする。実装は行わない。

## 検証方針

1. repo内のPTY、process sampler、cwd、Context Dock、close-risk、native hierarchy codeとtestを照合する。
2. macOS SDK header／man page／既存native adapterからpublic APIのavailabilityと返却契約を確認する。
3. shell PID、foreground PGID、process enumeration、executable／argv／start time取得の候補を比較する。
4. 状態遷移とdata flowを例（simple command、pipeline、TUI、終了race）へ当てはめる。
5. ROADMAP link、Markdown、差分、既存生成物への影響を確認する。

## 調査記録

### 2026-09-16 — 着手時点

- branchは`codex/context-file-navigator-roadmap`、着手時HEADは`a8f064d`。
- working treeは本タスク追加前にcleanだった。
- READMEはContext Dockをtrusted local cwdに基づくDirectory Navigatorと定義し、foreground
  process中のpath handoffをfail closedにしている。
- FEATURE_MATRIXのUI-04は既にcontent-free foreground PGID risk分類をpane close policyで
  使用している。少なくとも「shell以外のforeground process groupが存在するか」の観測基盤は
  製品内にある。

### 2026-09-16 — 既存authorityとContext Dock境界

- `packages/dart_pty_macos/native/PtySession.cc`の`GetProcessSnapshot`は、同じnative call内で
  owning child PID、`getpgid(child)`、PTY masterへの`tcgetpgrp`、`tcgetattr`のECHOを取得する。
  `TerminalSession.processSnapshot()`はforeground PGIDがowning PGIDと異なる場合を
  `foregroundProcess`、同じPGIDでOSC 133 command-output中の場合を`owningShellCommand`、
  それ以外を`idleShell`に分類する。新機能の実行中判定にterminal textや`ps`出力を使う必要はない。
- 現行cwd fallbackはowning child PIDの`PROC_PIDVNODEPATHINFO`だけを観測し、別foreground
  PGID中はshell cwd authorityとして採用しない。現在の`unknown`はこのfail-closed境界から生じる。
- `TerminalContextDockDirectoryController`は75 ms debounce、window／pane generation、operation
  cancellationを持つ。`TerminalContextDockDirectoryPresenter`はterminalと右Dockを横に並べ、
  上段のscrollable native editorと下段の固定details viewを所有する。Process Inspectorはこの
  outer Dockと上下layoutを再利用できるが、Directory Navigatorとは別のdocument/stateにする必要がある。
- `TerminalContextDockPrivacyPolicy`はmanual secure input、およびECHO-offの
  `foregroundProcess`／`owningShellCommand`を観測不可にする。argvはcwd以上に機微な情報を
  含み得るため、このpolicyをProcess Inspectorにも適用し、不可になった時点でsnapshotを破棄する。
- `TerminalCurrentProcessResourceSampler`は製品自身のcontent-free CPU／RSSだけを扱い、PID、path、
  commandを意図的に保持しない。これを拡張して混ぜず、foreground job用の明示的なcontent-bearing
  capabilityを分離する。

### 2026-09-16 — macOS public API

deployment targetのmacOS 14で、次のpublic header APIを利用できる。

| 欲しい情報 | API／field | 成立性とfailure |
| --- | --- | --- |
| foreground job | 既存`tcgetpgrp(PTY master)` | 既に製品で使用中。session終了、TTY消失、raceではtyped unavailableにする |
| group member | `proc_listpgrppids(foregroundPgid, ...)` | macOS 10.7以降。pipelineを単一processと決めつけずbounded listにできる |
| PID／PGID／name／wall start | `proc_pidinfo(PROC_PIDTBSDINFO)` | macOS 10.5以降。process終了や権限で個別fieldを失う |
| executable path | `proc_pidpath` | macOS 10.5以降。OSが返すpathであり、shell tokenや元のsymlink表記ではない |
| monotonic start | `proc_pid_rusage(RUSAGE_INFO_V0).ri_proc_start_abstime` | macOS 10.9以降。`mach_absolute_time`との差をtimebase変換してelapsedを得られる |
| argv | `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` | executable後のargv。permission、process終了、oversizeではfield単位でunavailableになり得る |

Apple SDK headerは`libproc.h`、`sys/proc_info.h`、`sys/resource.h`、`sys/sysctl.h`を確認した。
[`ri_proc_start_abstime`](https://developer.apple.com/documentation/kernel/rusage_info_v0/1577540-ri_proc_start_abstime)
はApple Developer Documentationにもpublic fieldとして掲載されている。
Release bundleのentitlementsは空でApp Sandboxを有効にしていないため、現行配布contractが追加の
process-info entitlementを要求する構成ではない。将来App Sandboxを有効にする場合は再検証が必要である。

### 2026-09-16 — local probe

- repo外の`/private/tmp/dt_foreground_process_probe.c`に一時probeを作り、子processを独立PGIDで
  `/bin/sleep`として起動した。最初のcompileは`kill`宣言用`<signal.h>`不足で失敗し、headerを追加して
  再実行した。同じ失敗を製品native testへ持ち込まない。
- 1-process groupで`proc_listpgrppids`が1、2-process groupで2を返した。`PROC_PIDTBSDINFO`は
  PID／同じPGID／name `sleep`／開始time、`proc_pidpath`は`/bin/sleep`、`KERN_PROCARGS2`は
  `argc == 2`と`["sleep", "3"]`、`proc_pid_rusage`は`mach_absolute_time()`より小さい非0の
  start absolute timeを返した。
- probeはAPIが同一userの子processで実際に成立することを確認するための調査物であり、repo成果物や
  製品実装には含めない。

### 2026-09-16 — command文字列の意味

- OSから取得できるのは実行後の`argv`であり、shellへ入力したsource文字列ではない。quoteの種類、
  whitespace、redirection、assignment、glob、alias/function展開、pipeline operatorは復元できない。
  process自身がargvを上書きする場合もある。そのためUIは「入力したcommandを正確に再現する」とは
  表現せず、`Command (process argv)`と注記する。
- pipelineは1つのforeground PGIDに複数processを持つ。代表processだけを真実として表示せず、
  foreground job summaryとbounded member listを表示する。
- shell builtin／functionは新しいPID／PGIDを作らない。OSC 133がある場合は既存の
  `owningShellCommand`で実行中と分かるが、command名や引数をOS process APIから得ることはできない。
  shell integrationを必須化しない条件では、`Shell command running`とelapsedだけを表示し、
  command detailを`Unavailable without shell integration`とする。OSC 133のないplain `sh`で
  builtinだけが走る短い期間はidleと区別できない。これは実装不良ではなく明示した限界である。
- `exec command`はshell PID／PGIDを維持することがある。OSC 133が有効ならshell-owned commandとして
  実行中を検出できるが、第1実装ではdistinct foreground PGIDだけをrich process inspection対象にする。
  `exec`後のidentity変化を確実に分類するにはlaunch時shell executable identityとの比較が必要なため、
  実装中に推測で加えない。

## 成立性判断

**local PTYのdistinct foreground jobについて実現可能**と判断する。

既存のforeground PGIDが「いまterminalを所有するjob」のauthorityを提供し、macOS public APIで
executable path、process argv、monotonic start、複数memberを取得できる。追加entitlement、shell
plugin、`ps` subprocess、terminal output parsingは不要である。取得に失敗するfieldはprocessが
実行中である事実まで否定せず、partial／unavailableとして縮退できる。

ただし、次は実現可能範囲に含めない。

- shellへ入力した元のcommand lineの完全復元
- shell integrationなしでのbuiltin／function名とargv取得、OSC 133のないshellでの実行中判定
- remote SSH host内のprocess、container／terminal multiplexer内部のprocess tree
- permissionで拒否された他UID processのpath／argv

したがって、要求の「実行ファイルの場所、実行時のコマンド、実行時間」は、distinct foreground
processではそれぞれ`proc_pidpath`、**process argv**、monotonic elapsedとして満たせる。UI表記で
shell sourceとの違いを隠さないことを受け入れ条件にする。

## 設計

### 1. 切替authority

Context Dockのviewはcwd解決結果ではなく、focused paneのprocess dispositionとprivacyだけで決める。
`workingDirectory == null`や表示文字列`unknown`をtriggerにしてはならない。

| process／privacy state | Context Dock view | directory処理 | input owner |
| --- | --- | --- | --- |
| `idleShell`、観測可 | Directory Navigator | 通常どおり同期 | 既存terminal／navigator ownerを維持 |
| `foregroundProcess`、観測可 | Process Inspector | operationをcancelし、visible projectionを外す | terminal |
| `owningShellCommand`、観測可 | Shell Command status | operationをcancelし、rich PID inspectionはしない | terminal |
| manual secureまたはECHO-off command | Protected | directory／process snapshotを即時破棄 | terminal |
| `unavailable`／`nonLive` | Context unavailable | operationとretained process dataを破棄 | terminal |

directory cwd取得だけがpermission／authority不足になったidle shellは、従来どおりDirectory Navigatorの
`unknown`／unavailable表示を保つ。processを捏造しない。foreground processが`ssh`や`tmux`の場合は
local client processだけを表示し、remote hostやmultiplexer内部を観測しない。

### 2. modelとidentity

新しいpure Dart projectionをDirectory snapshotと分離する。

- `TerminalContextDockContentMode`: `directoryNavigator`、`foregroundJob`、
  `shellOwnedCommand`、`protected`、`unavailable`。
- `TerminalForegroundJobIdentity`: `sessionId + paneId + foregroundPgid + foregroundEpoch`。
  epochはidle／unavailableを一度挟むかPGIDが変わるたびに増やし、PID／PGID再利用を同じjobと扱わない。
- `TerminalForegroundProcessIdentity`: `pid + pbi_start_tvsec + pbi_start_tvusec`。PID再利用時にretained
  rowを誤接続しない。
- `TerminalContextDockProcessSnapshot`: job identity、status、sample monotonic time、job elapsed、
  total／omitted member count、ordered member summaries、primary detail、field issue flagsを持つimmutable
  snapshot。path／argvは一般diagnostics用snapshotへ変換できない型境界に置く。
- statusは`loading`、`ready`、`partial`、`shellOwned`、`protected`、`unavailable`を区別する。
  processが終了したraceを`unknown working directory`へ変換しない。

`shellOwnedCommand`のelapsedはOS上のshell process開始時刻を使わず、OSC 133 command-output stateを
最初に観測したmonotonic timeからの`Observed elapsed`として表示する。実際の開始より最大でstate probe
間隔だけ短くなり得ることをlabelで隠さない。

primary processは、(1) PIDがPGIDと一致するlive group leader、(2)最も早いmonotonic start、
(3)PID昇順で決定する。member listはprimaryを先頭にし、残りをstart、PID順にする。job startは最初の
accepted snapshotで観測したmemberの最小
`ri_proc_start_abstime`を保持し、leaderが先に終了するpipelineでもelapsedを巻き戻さない。

### 3. native observation capability

既存`DptyProcessSnapshotV1`はcontent-free close policyとして凍結し、path／argvを追加しない。
`dart_pty_macos`へ明示的な`foregroundJobSnapshot` capabilityを別API／structとして追加する。
APIはcaller指定の任意PIDを観測せず、session handleから再取得した現在のforeground PGIDだけを対象にする。

native callは次の順序を守る。

1. session mutex内でlive child、master FD、owning PGID、foreground PGIDを取得する。distinct PGIDで
   なければ`notForegroundJob`を返す。
2. mutexを保持せず`proc_listpgrppids`でmemberを列挙し、basic infoとmonotonic startを取得する。
3. primaryを決定して、その1 processだけ`proc_pidpath`と`KERN_PROCARGS2`を取得する。
4. `KERN_PROCARGS2`は`argc`個のargvまでをparseし、その後ろに存在し得るenvironment領域をFFIへ
   返さない。temporary bufferは返却前にzeroizeする。
5. session mutex内でlive identityと`tcgetpgrp`を再取得し、変化していれば全contentを消して
   `stale`を返す。

`ps`／`pgrep`をsubprocess起動する案は採用しない。新しいprocess自体が観測noiseになり、locale／text
parsing、PATH、startup cost、command spoofing、cancellationが増えるためである。terminal screenやshell
historyから推測する案も、誤判定とprivacyのため採用しない。

hard limitは次を初期値とし、native／Dartの両境界で検証する。

- member: 最大32、超過時はtotal countとomitted countを返す
- process name: 256 UTF-8 byte、executable path: 16 KiB
- primary argv: 最大128 argument、packed 64 KiB、1 argument最大16 KiB
- retained foreground snapshot: windowごと128 KiB以下、同時native callはwindowごと1件

invalid UTF-8はreplacementで黙って同一視せず、control、newline、tab、bidi controlをescaped visual
representationへ変換する。切断はUTF-8 code point境界で行い、UIへ`truncated`／`omitted`を明示する。
path／argvが失敗してもname／PID／elapsedが取れれば`partial`として表示する。errnoはtyped issueへ
正規化し、raw path／argumentと共にlogへ出さない。

### 4. refreshとrace

`TerminalContextDockProcessController`をwindow-owned、focused-pane追従のcontrollerとして追加する。
Directory controllerとはsnapshotやoperationを共有しない。共通content coordinatorだけが上記matrixで
どちらをactiveにするかを決める。

- Dock非表示、window occluded／closed、pane非live、protectedではsampling timerを停止し、contentを
  破棄する。
- Dock可視時は既存terminal input／output／focus／visibility eventで75 ms coalesced state probeを行う。
  silent commandを取り逃がさないため、visible foreground候補中は最大250 ms間隔でcontent-free
  `processSnapshot()`を再確認する。
- `foregroundProcess`へ入ったらrich snapshotを1回取得する。表示済みjobのmember inventoryは1秒に
  1回だけ更新し、同時callを作らない。elapsed labelはcached monotonic startと現在時刻から1秒に1回
  再描画し、argv／path APIを呼び直さない。
- rich snapshot完了時にwindow、pane、session、Dock generation、foreground epoch、PGID、privacyを
  全て再検証する。1つでも変われば結果を捨てる。
- ごく短いcommandがrich snapshot前に終了した場合はProcess Inspectorを一度も投影せず、Directory
  Navigatorをfresh cwdへ更新する。これで`ls`等によるDock flickerを抑える。
- 表示済みjobが終了したらstale process detailを残さず、`Command finished — refreshing directory`
  というcontent-free transitionを最大1 directory refresh generationだけ表示してからNavigatorへ戻す。

native observationはmain UI isolate上のbounded synchronous callから開始し、32 memberのworst-case
benchmarkを受け入れ条件にする。p95が5 msを超える場合はUIへ接続せず、generation-bound session
referenceを保持してbefore／after PGIDを再検証するdedicated native sampling workerへ移す。性能未確認の
まま1秒pollを製品へ入れない。

### 5. UI

Process InspectorはDirectory Navigator上へのbannerではなく、同じ右Context Dock内の別documentとする。
Dock幅、外側split、上段scroll領域、固定下段details領域は再利用する。

上段は次を表示する。

```text
Process Inspector
Running · 00:42
Foreground job · 2 processes

● rg       PID 4211 · 00:42
  sed      PID 4212 · 00:42
```

下段の固定detailsはprimaryについて常に次を表示する。

```text
Executable
/opt/homebrew/bin/rg

Command (process argv)
rg  -n  needle  lib  test

PID 4211  ·  PGID 4211
Input: Terminal
```

- argvは各argumentの境界が分かるtoken表現にし、shell sourceの完全再現ではない旨を短く注記する。
- path／argv unavailable、member omitted、truncationは該当fieldの場所で示す。cwd `unknown`はprocess
  viewに表示しない。
- v1はread-onlyでprocess選択、copy、signal、kill actionを持たない。primary以外のmemberは上段の
  summaryだけを表示する。これによりterminal inputを奪う新modeやshortcutは不要になる。
- headerは`View: Process Inspector`、input ownerは`Input: Terminal`として別概念で表示する。既存の
  `Mode: Terminal`と矛盾させない。
- Process Inspectorへ切り替える時にNavigatorがfirst responderなら、generation-bound既存経路で
  terminalへfocusを戻してから投影する。Directoryのquery、selection、expanded subtree、hidden設定は
  pane stateとして保持するが、filesystem operationとcontent snapshotはcancel／破棄する。
- command終了後は保持したNavigator modeへ戻し、cwdとrowsだけをfreshに再取得する。
- `Shift-Command-F/G/M`がprocess view中に呼ばれても隠れたeditorへfocusを移さず、actionを消費して
  `Directory Navigator is available when the shell is idle`を一時表示する。beepとPTY writeは0。
  `Option-Shift-C`のDock toggleとEscapeのterminal focusは従来どおり使える。
- upper listとlower detailをread-only accessibility elementとして公開し、title、running／partial state、
  elapsed、process count、primary name／path／argv、omitted stateを読み上げる。1秒tickごとにwindow全体の
  focus通知を送らず、value changeだけをcoalesceする。

### 6. privacyとdiagnostics

- argvにはtoken、URL、hostname、file path等が含まれ得る。既定表示は利用者の要求どおり有効にするが、
  same-user local foreground processを画面上で見る用途に限定する。clipboard action、restoration、recent
  history、analytics、crash metadata、unified log、一般Terminal Inspector/exportへ追加しない。
- manual Secure Keyboard Entry、またはforeground／shell-owned commandでECHOがoffになった時点で
  timer、in-flight result、native／Dart retained buffer、native text documentを破棄し、`Protected input`
  のcontent-free表示だけにする。ECHOが戻った後はfresh snapshotだけで再開する。
- `KERN_PROCARGS2`のtemporary bufferにargvより後ろのenvironment dataが含まれ得るため、`argc`個より
  後ろをparse／copyせず、bufferをzeroizeする。environment key／valueをmodelに持たせない。
- diagnosticsに許可するのはcontent mode、ready／partial／protected等の固定status、member／omitted
  count、sampling latency bucket、stale／permission／oversize countだけとする。PID、PGID、name、path、
  argv、start wall time、elapsed exact valueは含めない。
- executable／argv取得がEPERM等で失敗した時に権限昇格や追加permission promptを出さず、partial表示へ
  fail closedする。

### 7. 採用しない案

- cwdが`unknown`なら常にprocess viewへ切り替える: idle shellのcwd failure／remoteと実行中を混同する。
- Directory Navigatorの下部だけをprocess detailへ差し替える: treeとprocessのauthority、input mode、
  lifecycleが混ざり、ユーザー要求の「別の表示」にならない。
- shell integrationを必須化する: OSC 133を提供しないlocal `sh`でも、distinct foreground PGIDに
  基づく価値を失う。
- 全descendant tree、CPU／memory、open filesを監視する: Activity Monitor化し、poll costとprivacy面積が
  増える。foreground PGIDの現在memberだけで目的を満たす。
- command終了後も履歴を残す: directoryへ戻る状態認知を遅らせ、secret-bearing argvの保持時間を増やす。

## 実装分割と検証計画

実装は次の順で4 subtaskに分ける。各subtaskを個別に検証、文書化、commitし、後続を先行しない。

### 1. bounded native snapshotとDart model

- `dart_pty_macos`にcontent-bearing foreground job snapshotを追加し、既存content-free snapshot／ABIを
  変更しない。
- group再検証、32 member cap、primary選択、path／argv／monotonic start、field failure、zeroization、
  invalid textをnative／Dart package testで固定する。
- simple child、2-process group、leader exit、33-member overflow、rapid exit、oversize argv、injected
  permission／staleを検証する。
- 32 member snapshotのp50／p95、allocation、retained bytesを測り、p95 5 ms以下またはdedicated native
  sampling worker化を完了条件とする。

### 2. content coordinatorとlifecycle

- content mode matrix、foreground epoch、process controller、timer／cancellation、directory suspension、
  privacy clear、focus restoreをpure Dartで実装する。
- idle→foreground→idle、short command、silent command、pipeline member change、pane／tab／window focus、
  hide／occlusion／close、session replacement、secure input、stale resultをfake clockで決定的に検証する。
- samplingは可視対象だけ、同時1 call、inventory毎秒1回以下、dispose後operation/timer 0を受け入れる。

### 3. native presentation、localization、accessibility

- existing Context Dock presenterをcontent presenterへ一般化し、DirectoryとProcessの別documentを排他的に
  投影する。upper bounded list／fixed details、partial／protected／transitionをEnglish／Japaneseで追加する。
- process viewのfirst responderは常にterminal、PTY write 0、Navigator state復元、shortcut no-beep、
  1秒tickのscroll／selection非破壊をnative hierarchy testで固定する。
- accessibility snapshot、malformed/control/bidi text、large Dynamic Type相当のlayout、narrow-window fallback、
  resource cleanupを検証する。

### 4. product acceptanceとreference

- real PTYで`/bin/sleep`、pipeline、subshell／TUI相当、OSC 133 shell builtin、rapid command、ECHO-off、
  permission／field failure、command終了後cwd refreshを検証する。
- Developer JITとRelease AOTで同じprocess情報、elapsed進行、terminal input、Dock toggle、pane追従、
  teardownを受け入れる。
- README、FEATURE_MATRIX、localization audit、diagnostics privacy allowlist、Phase 7 runtime marker、manual
  checklistを更新する。SSH remote process introspectionは追加しない。

## 設計検証結果

- 既存source、test、SDK header、empty entitlement、local public-API probeを相互照合し、distinct foreground
  processについて要求fieldの取得経路があることを確認した。
- simple command、pipeline、builtin、TUI、silent／short command、secure input、permission、rapid exit、
  pane focus、PID reuseへstate／failure規則を当てはめ、誤ってDirectory snapshotやstale argvを表示する
  経路を設計上遮断した。
- このtaskではrepository source／native API／UI／testは変更していない。ROADMAPと本設計メモだけを
  成果物とし、実装は後続4 subtaskに残す。
- `git diff --check`はwhitespace errorなし、design note／entitlements file存在確認と
  `plutil -lint resources/DartTerminal.entitlements`は成功した。placeholder語句と一時probeは残っていない。
- 最初のまとめpatchはcontextの並びを誤り適用されなかった。小さいhunkに分けて適用し、意図した箇所
  以外が変わっていないことを差分で再確認した。
- 最終文言修正後の最初の再stageはworkspace sandboxが`.git/index.lock`作成を拒否して失敗した。
  同じ対象fileだけを許可済みのrepository contextで再stageし、既存staged fileへ混入がないことを
  `git diff --cached --name-status`で再確認した。

## 実装記録

### 2026-09-16 — bounded native snapshotとDart model着手

- 目的: distinct foreground process groupについて、実行中jobのmember、primary executable、process
  argv、monotonic startをsession authorityからboundedに取得し、UIに依存しないtyped Dart modelまでを
  完成する。ユーザー向け表示名はDirectory Navigatorと区別して`Process Inspector`に固定する。
- 背景: 現行ABI v7の`DptyProcessSnapshotV1`はclose policy用content-free snapshot、
  `DptyWorkingDirectorySnapshotV1`はowning shell cwdだけを返す。path／argvを前者へ混ぜず、別の明示
  capabilityが必要である。
- 範囲: public C ABI、`PtySession`のbefore／after foreground PGID検証、macOS process group observation、
  Dart FFI／public immutable model、fake backend、native／Dart package test、snapshot latency計測。
- 対象外: Context Dock content切替、polling、native presentation、localization、accessibility、製品runtime
  acceptance。これらはROADMAPの後続subtaskで実施する。
- 依存関係: ABI v7 handle registry、session mutex、`tcgetpgrp`、`libproc`、`KERN_PROCARGS2`、
  `mach_absolute_time`、既存package test／native sanitizer gate。
- 完了条件: idle／exit／stale、simple command、pipeline、leader fallback、process/member/text hard cap、
  partial field failure、invalid UTF-8、zeroization境界、Dart validation、p95 latencyをtestで固定し、既存
  content-free snapshot／cwd／lifecycleを退行させない。
- 検証方針: header compile、native capability test、Dart fake／real PTY test、format／analyze、既存package
  aggregate、32-member benchmark、diff reviewを行う。p95が5 msを超える場合はUI接続可能とはせず、
  sampling worker化を同subtask内で解決する。
- 着手時branchは`codex/context-file-navigator-roadmap`、HEADは`59deb76`、working treeはcleanだった。

### 2026-09-16 — bounded native snapshot実装の判明事項

- content-freeな`DptyProcessSnapshotV1`を変更せず、ABI v8に独立した
  `DptyForegroundJobSnapshotV1`／`dpty_session_get_foreground_job_snapshot`を追加した。session handleから
  before／afterのchild、owning PGID、foreground PGIDを検証し、任意PIDをcallerから指定できない境界に
  した。非distinct、終了、raceではpath／argv／member bufferを返さない。
- retained snapshotはmember 32、name 256 UTF-8 byte、path 16 KiB、argv 128件／packed 64 KiB／1件
  16 KiBに制限した。primaryはlive group leader、leader消失時はmonotonic start、PIDの順で選び、先頭へ
  並べ替える。33-process pipelineでは32件と明示的な1件以上のomissionになった。
- `proc_listpgrppids(pgid, nullptr, 0)`の戻り値は対象group countとして利用できず、このhostでは789という
  process列挙の容量hintを返した。最初の実装はこれをgroup totalと誤解してnative testが失敗した。
  hintへ32件のrace marginを加え、64K PIDで上限を設けたtemporary bufferで実列挙し、その戻り値だけを
  group totalとするよう修正した。temporary allocation failureは`ENOMEM`のtyped unavailableになる。
- `proc_pidpath`を16 KiB ABI fieldへ直接書いた最初の実装ではNUL境界を検証できず`EOVERFLOW`になった。
  `PROC_PIDPATHINFO_MAXSIZE`のzero-initialized temporary bufferへ取得し、bounded lengthを確認してからABI
  fieldへcopyするよう修正した。
- 列挙bufferのcapacityをretained member上限として誤使用した途中版は33件目を32件配列の外へ書き得た。
  33-process testが`member_count == 33`を検出したため、retained判定を
  `DPTY_FOREGROUND_PROCESS_LIMIT`へ修正した。ASan／UBSanを含むnative sanitizer gateで再検証した。
- `KERN_PROCARGS2`は`argc`個だけをparseし、environment領域をcopyしない。64 KiBを超えるkernel blockは
  `E2BIG`とtruncated、invalid UTF-8 argumentはDart decoderでそのargumentだけを破棄し、field issueと
  truncationを付ける。native argv／path temporary bufferとDart FFI snapshotは利用後にzeroizeする。
- test-only buildだけにpath／argvの`EPERM`とpost-observation `ESTALE` injectionを追加した。permissionは
  member／timingを保つfield-local partial、staleは全contentをclearすることをnative testで固定した。

### 2026-09-16 — bounded snapshot検証経過

- 最初の`dart format`は対象4 fileのformat自体は完了したが、sandbox外の
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`のmtime更新を拒否されexit 1になった。同じ
  commandの再実行も2 fileをformat後に同じ理由でexit 1となった。sourceのformat結果は`dart analyze`で
  検証し、telemetry fileは変更していない。
- 最初のnative compileは、このSDKで宣言されない`explicit_bzero`とPGIDのsignedness warningを
  `-Werror`で検出した。volatile byte loopの`SecureZero`と明示型変換へ直した。
- `make dpty-native-test`はsimple foreground process、2-process pipeline、leader exit、33-process cap、
  path／argv permission、stale、exit後content clear、既存PTY lifecycleを通過した。最終64回の32-member
  retained snapshot計測はp50 273 us／p95 459 usで、5 ms gateを満たした。測定値は同一hostのdebug test artifactで
  あり、製品telemetryへ出さない。
- `make dpty-dart-test`はanalyzeと全package testを通過した。実interactive zshから通常pipeline、Perlで
  生成したinvalid UTF-8 argv、70,000 byte argvを起動し、FFI modelが通常content、field-local malformed、
  field-local oversizeへそれぞれ縮退することを確認した。fake backendとpublic modelのhard limit／immutable
  copyも通過した。
- `make product-native-sanitizer`はPTYを含む9 artifactのASan／UBSan gateを通過した。
- 最終aggregate再実行では`make dpty-native-test`成功後、sandbox内の`make dpty-dart-test`がsourceではなく
  上記telemetry session mtimeで停止した。workspace外への同じmetadata更新だけを許可して再実行し、analyze
  と全testが成功した。`git diff --check`はwhitespace errorなしだった。

### 2026-09-16 — content coordinator、refresh、privacy lifecycle着手

- 目的: focused paneのcontent-free process authorityとprivacyを1か所で評価し、Directory Navigator、
  `Process Inspector`、shell-owned command、protected、unavailableを排他的に切り替える。visible windowだけ
  boundedに再観測し、pane／session／PGID raceでcontentを残さない。
- 背景: 現行`TerminalContextDockDirectoryController`はDock可視時にcwdを直接解決するため、foreground
  command中の`unknown`をDirectoryのunavailableとして投影する。process表示のtriggerをcwd failureへ
  結び付けず、`TerminalPaneProcessSnapshot`のdispositionを先に評価するcoordinatorが必要である。
- 範囲: product-facing foreground snapshot model／observer、`TerminalSession` adapter、window-owned content
  coordinator、250 ms state probe、1 s rich refresh／elapsed tick、foreground epoch、directory suspension、
  focus／visibility／privacy／dispose cancellation、およびfake schedulerを使うdeterministic test。
- 対象外: AppKit documentの表示、localization、accessibility、shortcut message。これらは次のsubtaskで行う。
- 依存関係: `TerminalContextDockState`、`TerminalPaneProcessSnapshot`、`TerminalContextDockPrivacyPolicy`、
  `PtyForegroundJobObserver`、application window／pane identity、既存directory operation cancellation。
- 完了条件: idle→foreground→idle、short／silent command、pipeline member refresh、pane／window focus、Dock
  hide、session replacement、secure input、stale result、同時rich call 1、inventory毎秒1回以下、dispose後
  timer／operation 0をpure Dart testで固定し、foreground中にdirectory operationを保持しない。
- 検証方針: `test/terminal_context_dock_test.dart`へmanual fake clock／schedulerとobserverを追加し、product
  unit aggregate、format、analyze、diffを確認して単独commitにする。
- 着手時HEADは`1f6dab9`、working treeはcleanだった。

### 2026-09-16 — content coordinator実装の判明事項

- `TerminalContextDockProcessController`をDirectory controllerより前段へ置き、content-freeな
  `TerminalPaneProcessSnapshot`だけでdocument modeとfilesystem観測可否を決める構成にした。distinct
  foreground jobは75 ms安定してから`Process Inspector`へ切り替え、短時間でidleへ戻ればrich snapshotを
  取得せずDirectory Navigatorを維持する。terminal changeの75 ms debounceに加えて、出力しないcommandも
  検出できる250 ms pollをvisible／focused standard windowだけに所有させた。
- rich observationはwindow／pane／session／PGID／foreground epoch／content generationへ束縛し、同時requestを
  windowあたり1件、inventory refreshを1秒あたり1回以下とした。elapsed表示はretained sampleとmonotonic clock
  の差だけで進めるため、表示tickごとのnative callは発生しない。
- Dock非表示、window非提示、pane／session／PGID変更、ECHO-off、Secure Keyboard Entry、disposeでretained
  path／argvと論理requestを同期的に破棄する。遅れて完了したFutureは全identityを再検証して捨てる。
  foreground中はDirectory controllerの既存`canObservePane`をfalseにして、進行中のfilesystem operationも既存の
  cancellation経路で解放する。shell-owned commandは開始観測からのelapsedだけを表示し、path／argvを推測しない。
- `Stopwatch()..start()`をnullable ternaryのbranchへ直接置いた最初の記述はcascadeの優先順位によりparse errorに
  なったため括弧で囲んだ。また既存path handoffのtypedefとfocus callback名が衝突したためprocess固有名へ変更し、
  optional observerのpromotionが保証されない箇所は明示castにした。いずれもanalyzerで解消を確認した。
- format対象へ誤ってMarkdown task memoを含めた実行は、Dart source 6件のformatを完了した後にMarkdownのparse
  errorで終了した。文書は変更されず、以後は`.dart`だけをformat対象にした。
- 最初の`dart run test/run_tests.dart`はproduct application source hashの変更により
  `compatibility/ghostty_p0_p1_gap_inventory.json`のfreshnessで停止した。これは機能失敗ではなくpinned evidenceの
  期待された連鎖更新であり、`make ghostty-p0-p1-gap-inventory`で同じ分類・件数を保ったまま再生成した。
- gap inventory更新後のaggregateは、そのhashを入力に持つ
  `compatibility/release_candidate_daily_use_matrix.json`のfreshnessで停止した。
  `make release-candidate-daily-use-matrix`で後段のpinned matrixも再生成した。
- 続くaggregateは`terminal_application.dart`／`terminal_session.dart`／Context Dock testのsource hash更新により
  Phase 7 AppKit acceptanceのfreshnessで停止した。`make phase7-appkit-acceptance`を実行し、その更新を入力に
  持つdaily-use matrixも再生成した。分類やacceptance基準は変更せずsource hashだけを更新した。

### 2026-09-16 — content coordinator検証結果

- `dart format`（変更したDart 6件）: 成功、追加format差分なし。
- `dart analyze lib/src/terminal_application.dart lib/src/terminal_context_dock_process.dart lib/src/terminal_session.dart test/terminal_context_dock_test.dart test/run_tests.dart`: issue 0。
- `dart run test/terminal_context_dock_test.dart`: 成功。short／silent command、75 ms activation、250 ms poll、
  1 s inventory refresh、同時request 1、PGID／pane／same-pane session replacement、privacy、shell-owned、Dock
  visibility、dispose後resource 0をfake clockで確認した。
- `dart run test/run_tests.dart`: pinned evidence再生成後に成功し、最後まで`dart_terminal tests passed`を確認した。
  `TerminalSession` optional foreground observerのlive／terminated境界もaggregate内で通過した。
- `git diff --check`: whitespace errorなし。

### 2026-09-16 — read-only native presentation、localization、accessibility着手

- 目的: 同じ右Context Dockのouter／vertical splitを保ちながら、Directory Navigatorとユーザー向け名称
  `Process Inspector`を別documentとして排他的に表示する。foreground中の上段はbounded member summary、
  下段は固定primary detailとし、terminal first responderを維持する。
- 背景: coordinatorはmodeとprivacy-safe process snapshotを提供できるが、現行presenterは常にDirectory
  documentを構築するためforeground中もDirectoryの見出し／`unknown`しか表示できない。
- 範囲: presenterへのprocess projection接続、process／shell-owned／protected／unavailable document、
  elapsed／process count／field-local partial表示、English／Japanese文字列、read-only native configuration、
  accessibility label／help、process切替時のselection／scroll非破壊をnative hierarchy testで固定する。
- 対象外: process選択、copy、signal／kill、shortcut追加、real PTYのruntime acceptance、README／
  FEATURE_MATRIX更新。これらのうちacceptanceとreferenceは次のsubtaskで扱う。
- 依存関係: `TerminalContextDockProcessController`、既存directory presenter、AppKit `TextEditor`／
  `TextView`／`TwoPaneSplitView`、TerminalLocalization、terminal focus authority。
- 完了条件: Process Inspector名とDirectory Navigator名を混在させず、cwdをprocess documentへ表示せず、
  path／process argv／PID／PGID／elapsed／member omissionをboundedに投影する。process viewは常にread-onlyかつ
  terminal input、1秒更新でfirst responder／scroll／selectionを変えず、protected時にsecret-bearing native
  textを置換し、dispose後native resource 0とする。
- 検証方針: pure document assertionsとfake AppKit hierarchyでready／partial／shell-owned／protected、
  focus、fixed details layout、coalesced updates、localization／accessibility、cleanupを確認し、format、analyze、
  aggregate、generated evidence、diff review後に単独commitする。
- 着手時HEADは`99773b3`、working treeはcleanだった。

### 2026-09-16 — native presentation実装の判明事項

- 既存presenterへwindow別content snapshot resolverを追加し、`directoryNavigator`だけを従来documentへ、
  foreground／shell-owned／protected／unavailableを独立したProcess Inspector documentへ投影した。外側の
  terminal／Dock splitと、上段scroll／下段固定details splitは交換せず再利用するため、切替やelapsed更新で
  divider位置を変えない。
- 上段はtitle、`View: Process Inspector`、`Input: Terminal`、elapsed、total process count、bounded member
  list、omitted countを表示する。下段はprimary executable、引用符でargument境界を示すprocess argv、
  shell sourceではない旨、PID／PGIDを表示する。working directoryやDirectoryのpath actionはprocess
  documentへ混在させない。
- process name／path／argvはnative modelのbyte上限に加え、表示時にC0／C1、DEL、bidi embedding／override／
  isolate、backslash、argv内quoteを可視escapeへ変換する。field失敗、argument truncation、member／argument
  omissionは該当箇所でlocalizeして示し、shell-ownedはobserved elapsed以外を推測しない。
- fixed detailsをcustom-drawn `TextView`からread-only `TextEditor`へ置き換えた。上下ともnative
  `NSTextView`由来の読み上げ可能なtext valueを持ち、下段はfirst responderを受けず、Process Inspector中は
  上段もeditable=falseにする。title／state／count／path／argv／omissionをdocument textとして順番に公開する。
- process elapsed再描画では同じdocument kindのUTF-16 selectionを新text長へclampして保持し、
  `scrollSelectionToVisible`を呼ばない。member elapsedもjob snapshotと同じmonotonic advance分を進める。
- Search／Go To／Move actionには「現在はNavigatorへfocusできないがforeground process viewとしてkeyを消費
  する」policyを分離した。foreground／shell-owned中はactionを実行済みとして消費し、Dock state、first
  responder、PTYへ何も送らない。Process Inspector内のidle時利用可能hintで理由を示す。protected時は従来どおり
  actionをdisabledにしてprivacy policyを弱めない。
- 最初のlocalization auditは、focus guardのinternal `StateError`へ英語の製品名を直接書いたため失敗した。
  errorをUI copyではない固定technical classificationへ変更し、ユーザーに見える名称は
  `TerminalLocalization`だけが所有する境界へ戻した。

### 2026-09-16 — native presentation検証結果

- `dart analyze`（process／Dock state／directory content presenter／localization／product wiring／focused
  test 2件）: issue 0。
- `dart run test/terminal_context_dock_test.dart`: 成功。cached monotonic advanceがjobだけでなくmember elapsedへ
  反映されることを追加確認した。
- `dart run test/terminal_localization_test.dart`: 成功。English／JapaneseのProcess Inspector title、単数／複数
  process count、argv／protected copyを確認した。
- `make terminal-localization-check`: 最初のUI literal違反を修正後に成功し、16 source、4 resource family、
  21 resource keyのauditを通過した。
- `dart run test/terminal_native_hierarchy_test.dart`: 成功。loading→partial ready→elapsed update→shell-owned→
  protected→Directory復帰、control／bidi escape、omission、固定details、terminal first responder、Navigator
  shortcut消費、selection／scroll非破壊、460 px narrow fallback、resource cleanupをfake AppKitで確認した。
- `dart run test/terminal_application_acceptance_test.dart`と`dart run test/terminal_action_registry_test.dart`: 成功。
- `make phase7-appkit-acceptance`、`make ghostty-p0-p1-gap-inventory`、
  `make release-candidate-daily-use-matrix`: source hashを依存順に再生成し、分類／基準は変更なし。
- `dart run test/run_tests.dart`: 全aggregateが成功し、`dart_terminal tests passed`まで確認した。
- `git diff --check`: whitespace errorなし。

### 2026-09-16 — product privacy／performance gate、両runtime受け入れ、reference着手

- 目的: 実PTYと通常product compositionでProcess Inspectorの観測・表示・終了復帰を検証し、同じacceptanceを
  arm64 Developer JIT／Release AOTへ適用する。content-bearing path／argvが一般diagnostics、restoration、
  telemetryへ流れないことと、既存native latency／poll cadence gateを最終的な製品基準へ結び付ける。
- 背景: native API、coordinator、presentationは個別testを通過したが、real process groupからnative viewまでの
  end-to-end経路とbundle runtime差、および公開referenceはまだ未完了である。
- 範囲: native-content runtime suiteへreal `sleep`／pipeline／subshell／interactive command／OSC 133 shell-owned／
  rapid command／ECHO-off／cwd復帰を追加、privacy auditのowner追加、Developer JIT／Release AOT execution、
  README／FEATURE_MATRIX／manual checklist／pinned evidence更新。
- 対象外: SSH remote process introspection、process signal／kill、CPU／memory継続監視、App Sandbox変更、
  notarization／Intel-native実機。
- 依存関係: native snapshot p95 5 ms gate、content controllerの250 ms／1 s上限、native-content integration
  harness、arm64 bundle builders、diagnostics privacy audit、Phase 7／daily-use generated evidence。
- 完了条件: 実processでProcess Inspector名、executable、process argv、elapsed進行、pipeline member、terminal
  input、shortcut zero-write、protected clear、shell-owned縮退、終了後fresh Directoryを両runtimeで確認する。
  diagnostics auditがprocess contentを拒否し、全owner／timer／PTY／native handleをcleanに回収し、referenceと
  ROADMAP parentを完了して単独commitする。
- 検証方針: focused unit／native／privacy gate、native-content integrationを両runtime、aggregate `make test`、
  native sanitizer、generated evidence freshness、format／analyze／diffを実行する。GUIの視覚・VoiceOver確認だけは
  content-specific manual checklistへ明示する。
- 着手時HEADは`b979e10`、working treeはcleanだった。

### 2026-09-16 — product acceptance実装の判明事項

- 既存native-content suiteは`--shell-integration=none`の実PTY／AppKit productをDeveloper JITとRelease AOTで
  共通実行するため、Context Dockのend-to-end acceptanceを同suiteへ統合した。外部shell pluginなしでも
  distinct foreground PGIDは観測でき、OSC 133 shell-owned境界はtest commandが明示sequenceを出して検証する。
- 最初のanalyzeは、suite内の`dispatch` helperが成功を内部assertして`Future<void>`を返すにもかかわらず
  `TerminalActionDispatchResult`へ代入した箇所を検出した。戻り値を使わずhelperの既存成功contractへ合わせた。
- Developer JIT native-contentの最初の実行は、Process Inspector固有のassertへ到達する前に、既存の
  plain-sh cwd tree投影待ちが10秒で失敗した。直前にはPTY capabilityからidle shell／ECHO-on／期待cwdを
  確認できており、終了時resource回収もcleanだったため、起動直後のDock／directory非同期同期に関する一過性の
  timing候補として再実行で再現性を確認する。再現する場合は、失敗時のprocess content mode／directory statusを
  acceptance messageへ追加し、循環する観測許可または同期順を修正する。
- 直後の再実行はさらに前段のplain-sh idle／ECHO-on待ちで停止し、失敗位置が固定されなかった。native
  snapshotのdisposition、PGID、terminal attributesを次回の失敗文に含める診断を追加し、PTY状態そのものか
  test側の待機不足かを切り分ける。診断はcontent-freeな既存`machineLine()`だけを使い、path／argvは出力しない。
- 診断parameterの最初の追加は、同名の別acceptance helperへpatchが一致して対象helperには入らず、Kernel
  compileがunknown named parameterとして停止した。対象functionの固有contextで追加し直し、format／analyzeで
  signatureを確認する。
- content-free診断では`idleShell`、owning／foreground PGID一致、errno 0だがECHO-offだった。移行完了markerの
  全文が入力コマンド内にも存在し、zsh line editorが表示した未実行の入力を`_waitForAsciiMarker`が先に拾える
  fixture bugと判断した。markerを`printf` formatとargumentへ分離し、実際のcommand outputでしか完全なmarkerが
  現れないよう修正した。
- marker同期を直した後もidle時ECHO-offは維持された。これはzsh／shのinteractive line editorがidle promptを
  所有するときにもECHOを無効化し得る既知の状態で、製品privacy policyも明示的にidle shellを許可している。
  fixtureだけが「plain shなら必ずECHO-on」という過剰な前提を持っていたため、同期条件をcontent-freeな
  `idleShell`へ合わせた。ECHO-off privacyは後段のdistinct foreground processで別途検証する。
- idle条件修正後は再びcwd tree待ちで停止した。native-content harnessはbundle executableを直接起動するため
  AppKit applicationがinactiveのままであり、新しいprocess controllerの「visibleかつfocusedなactive windowだけ
  観測する」privacy／resource policyによりdirectory観測も正しく停止していた。既存Secure Keyboard Entry product
  acceptanceと同じApplicationActiveChanged eventをtestで注入し、windowがvisible／focusedであることも確認してから
  Context Dock acceptanceを開始するようにした。通常productのinactive時clear policyは変更しない。
- application active eventだけでは直接起動したheadless acceptance windowのfocus stateは変わらず、active／visible／
  focused gateで停止した。window focus eventも既存native event helperで明示し、両方の製品event routeを通して
  foreground observation authorityを確立するよう補った。
- active／focus補完後は既存Navigator acceptanceを通過して新規pipeline fixtureまで到達したが、inner `/bin/sh -c`
  scriptのdouble quoteをshellに対して一段過剰にescapeしており、ready markerが出ず停止した。script全体はsingle
  quote、`printf` formatは通常のdouble quoteとし、markerは2 argumentから連結して入力echoとoutputを区別する
  commandへ修正した。
- 引用符修正後もmarkerが出なかったため同じpipelineをhost shellで直接確認し、macOSではfixtureが指定した
  `/usr/bin/cat`が存在せずexit 127になることを確認した。製品が実際に対象とするmacOS標準pathの`/bin/cat`へ
  修正した。
- pipelineが実行された後のProcess Inspector待ちは、output markerを入力echoと区別するため2 tokenへ分けた一方、
  argv assertionだけが分割前の連続文字列を要求していたため停止した。process argvの同一script argument内に
  prefixとsuffixの両方が保持され、fixed detailsにも双方が投影されることを検証する条件へ合わせた。
- Process Inspector表示とelapsed検証は通過した。続くshortcut zero-write assertionはbaselineをpipeline command送信前に
  採って「command送信がwrite 1件」という実装詳細まで仮定していたため停止した。目的はshortcut自体がPTYへ書かない
  ことなので、Process Inspector表示後かつshortcut dispatch直前にbaselineを採り、delta 0を直接検証するよう直した。
- Developer JITは上記修正後にend-to-end acceptanceを成功した。Release AOTはprocess pipeline、elapsed、input、
  shell-ownedまで通過した後、rapid commandのDirectory復帰待ちで停止した。AOTの方が速く、直前のshell-owned
  commandがidleになった時点とnative presentationがDirectoryへ戻る時点を同一視したtest raceが露出した。
  shell-owned後はmodeとnative documentのDirectory復帰まで待ち、rapid commandも分割markerで実行完了を同期してから
  contentがDirectoryのまま／またはDirectoryへ戻ることを確認するようにした。
- 最初の最終`make test`はprocess-resource、PTY、renderer、AppleScript、App Intents、parser、configuration、
  keybind、localization、privacy、Phase 7、compatibility regression 9 caseを通過した後、
  `terminal_compatibility_regression_coverage.json`のsource hash freshnessで停止した。新しいproduct sourceを入力に持つ
  派生evidenceの期待された更新であり、coverageを再生成して下流inventory／matrixも依存順に更新してから再実行する。

### 2026-09-16 — product gate、reference、最終検証結果

- native-content product acceptanceは直接起動したappへactive／window focus eventを通し、実PTYの2-member以上の
  pipeline、absolute executable、process argv、monotonic elapsed、fixed details、terminal input、Navigator shortcut
  delta 0、終了後Directory復帰、interactive `cat`、OSC 133 shell-owned content-free表示、rapid command、ECHO-off
  protected clearを同一scenarioで確認する。終了時は4 sessionがcleanで、process controllerのoperation／timer、
  native handle、text input clientがすべて0になる。
- Developer JIT最終実行は
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=developer-jit ... process_inspector=true ... sessions=4 elapsed_ms=8608`、
  Release AOTは
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=release-aot ... process_inspector=true ... sessions=4 elapsed_ms=7482`
  で成功した。両者は同じsourceとacceptanceを使う。
- diagnostics privacy auditへapplication compositionとprocess content ownerを追加した。process snapshot/controller型を
  diagnostics assemblyへ渡さず、owner sourceにserialization、machine line、stdout／stderr／log、environment、file
  outputを追加しないことをstaticに拒否する。`make terminal-diagnostics-privacy-check`は
  `schema_keys=190 owners=11 top_level_keys=11`で成功した。
- `make dpty-native-test`は32 retained member／33 totalのsnapshotでp50 220 us／p95 244 usを記録し、5 ms gateを
  満たした。最終`make test`内の再計測もp50 220 us／p95 245 usだった。250 msのcontent-free poll、75 msの
  activation、1秒のrich refresh上限はfake clock unit testと両runtime product acceptanceで維持した。
- `make product-native-sanitizer`はPTY、renderer、AppleScript、App Intentsの4 suite／9 artifactを通過し、PTYを含む
  全artifactでASan、対象7 artifactでUBSan instrumentationを確認した。
- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`を依存順に再生成した。最終
  `make test`はformat 347 file、root analyze issue 0を含む全gateを通過し、`dart_terminal tests passed`を確認した。
- READMEとFEATURE_MATRIXへ、Directory Navigatorとは別名の`Process Inspector`、表示境界、bounded content、
  terminal focus、privacy、両runtime受け入れを反映した。視覚、VoiceOver、Full Keyboard Accessの外部確認は
  [Process Inspector manual checklist](context-dock-process-inspector-manual-checklist.md)へ分離した。SSH／remote process
  introspection、signal／kill、CPU／memory継続監視は引き続き対象外である。
- `git diff --check`はwhitespace errorなし。差分reviewでは実装中のdiagnosticがcontent-freeであること、生成物が
  source／reference hashだけを更新して分類・release blocker数を変えていないこと、build artifactや秘密情報を
  含まないことを確認した。
