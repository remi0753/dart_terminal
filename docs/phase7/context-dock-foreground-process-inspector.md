# Phase 7 — Context Dock foreground process inspector feasibility and design

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
