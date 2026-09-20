# Phase 7 — Context Dock manual switch investigation

## 目的

実機でProcess InspectorからDirectory Navigatorへ切り替わらない現象を再現し、
shortcut、action availability、privacy、content projectionのどの境界が原因かを特定する。

## 背景

2026-09-20の実装では`view.toggle-context-dock-content`を
Control-Shift-Command-Nへ割り当て、unitとnative-content integrationは成功したが、
利用者の通常起動環境では表示が切り替わらない。

## 範囲

- native key／menu dispatchからshared action handlerまでの配送を確認する。
- 実PTY foreground job中のaction availabilityとDirectory privacy判定を確認する。
- Developer JITの通常起動条件と、既存integration fixtureの条件差を特定する。
- 原因、再現条件、影響範囲、修正方針候補を記録する。

## 対象外

- 原因特定後の製品code修正。
- shortcutの変更、privacy policyの緩和、UI仕様の変更。

## 依存関係

- `TerminalContextDockProcessController`のcontent toggle registrationと表示override。
- `contextDockCanObservePane`およびSecure Keyboard Entry／PTY ECHO状態。
- native menu shortcut arbitrationとaction dispatcher。

## 完了条件

- 利用者報告と一致する失敗経路を自動または実製品相当の検証で再現できる。
- 原因となる条件と、既存テストが見逃した理由をcode上の証拠で説明できる。
- 修正対象と必要なregression testを具体化し、実装を変更せず報告できる。

## 検証方針

- action handlerを直接呼ぶcontroller testとnative shortcut経路を分離して比較する。
- foreground commandのPTY ECHO、manual secure input、automatic secure inputの組み合わせを固定する。
- View menu itemのenabled／checked stateとsnapshot modeを観測する。

## 調査結果

### 2026-09-20 — 原因

原因はmacOS shortcutの競合ではなく、ECHO-off foreground processに対するDirectory privacy判定で
切替actionそのものを無効にしていることである。以前の実機報告で`node` REPLが`protected input`に
なった経路と一致する。

具体的な配送経路は次のとおり。

1. `terminal_application.dart`の`contextDockCanObservePane`は、現在のprocess snapshotと
   Secure Keyboard Entry statusを`TerminalContextDockPrivacyPolicy.canObserve`へ渡す。
2. `terminal_context_dock_path_handoff.dart`のpolicyは、foreground processで
   `terminalEchoEnabled == false`ならfalseを返す。manual Secure Inputもfalseになる。
3. このcallbackを`TerminalContextDockProcessController.canObserveDirectory`へそのまま渡している。
4. `_canToggleActiveWindowContent`はDirectory観測がfalseなら
   `view.toggle-context-dock-content`をunavailableにする。View menuはdisabledとなり、native shortcutと
   Command Paletteのどちらからもhandlerへ到達しない。
5. handlerを直接呼んだ場合も`toggleActiveWindowContent`内の同じ判定でreturnするため、表示は変わらない。
6. Directory controllerも同じ条件で既存snapshotをcancelし、working directoryとrowを持たない
   `privacyUnavailable` snapshotへ置換する。そのためaction enablementだけを変更してもNavigator内容は戻らない。

### 既存テストが見逃した理由

- native-content integrationの表示切替は、PTY ECHOが有効な`sh | cat` pipelineでのみ実行していた。
  この条件ではmenu itemがenabledなので成功する。
- 同じintegrationは後段で`stty -echo; sleep 4`を使い、ECHO-offでもProcess Inspectorを表示できることと
  Directory snapshotが`privacyUnavailable`になることを確認している。しかし、その状態ではcontent toggleを
  実行もavailability確認もしていない。
- controller unitにはDirectory privacy veto時にcontent toggleがdisabledになるassertionがあり、
  実機で期待された切替不能を、意図したsecurity挙動として固定してしまっていた。
- shortcut metadataとmenu itemからの直接`performAction`は検証しているが、disabledなECHO-off itemを使う
  実機条件は検証していない。

## 影響範囲

- `node` REPL、TUI、raw-mode applicationなど、foreground中にterminal ECHOを無効化するprocess。
- 利用者がmanual Secure Keyboard Entryを有効にした状態の全foreground process。
- ECHO-onの`cat`、`sleep`、通常pipelineでは切替可能なので、commandによって動作が異なって見える。
- action ID、shortcut chord、native modifier投影には、この調査で不整合は見つからなかった。

## 修正方針候補

推奨は、Directory Navigatorの権限を少なくとも次の二つへ分離することである。

- **表示権限:** foreground開始前に確定済みのimmutable directory snapshotをread-onlyで表示する。
- **再観測・操作権限:** filesystem再走査、Search／Go To、path copy／insertなどをprivacy policyで個別に制御する。

content toggleは表示権限だけを要求し、ECHO-offでも保持済みtreeへ切り替えられるようにする。一方で
protected input中の新規filesystem readやpath actionを許可するかは、既存privacy方針を維持するならblockedのままにできる。
Directory controllerはforeground ECHO-offでsnapshotを破棄せず凍結し、job終了後に従来どおり一回だけfresh refreshする。

必要なregression testは、ECHO-off foreground jobでmenu／palette／shortcut actionがenabled、保持treeが表示され、
同じactionで同一Process Inspectorへ戻り、PTY writeが0であること、および新規filesystem operationがpolicyどおり
発生しないことのDeveloper JIT／Release AOT確認である。

## 検証記録

### 2026-09-20

- `test/terminal_context_dock_test.dart`のprivacy policy、content toggle availability、ECHO-off integrationを
  codeとline単位で照合し、上記の同一条件連鎖を確認した。
- sandbox内での最初の`dart run test/terminal_context_dock_test.dart`は、Metal compilerが
  `~/.cache/clang/ModuleCache`へ書けず失敗した。製品・テストfailureではない。
- 同じtestを通常のbuild環境で再実行し成功した。現在のunitは
  `directory privacy veto disables switching away from Process Inspector`を明示的に受け入れており、
  報告された挙動を再現する証拠になっている。
- 製品codeは変更していない。

## 修正実装

### 2026-09-20 — retained displayとfresh observationの分離

調査後のfollow-up修正では、ECHO-offまたはmanual Secure Input中も、foreground開始前に確定した
Directory snapshotだけをread-only表示へ切り替えられることを範囲とした。protected期間中のfilesystem再観測、
Search／Go To／Move、path actionは対象外とし、job終了後の一回のrefreshで通常状態へ戻ることを完了条件とした。

- process controllerへDirectoryのdisplay authorityを追加し、fresh filesystem observation authorityと分離した。
  content toggleは、通常の観測権限または同じpaneの確定済みsnapshotがあれば利用できる。
- foreground候補としてDirectory処理をsuspendした時点から、directory controllerは完成済みroot／subtree／Search
  snapshotを破棄せず凍結する。Process Inspector確定後まで待つと75 msの候補期間にsnapshotを失うため、
  `directorySuspended`をretention authorityとして使用する。
- 凍結時はroot／child／search snapshotを保持しながら、root／subtree load、refresh、Search、Go Toの進行中operationを
  cancelする。新規resolve／list／searchを開始せず、manual refreshとtree intentも拒否する。
- 表示切替後もterminalがinputを所有するため、Search／Go To／Moveとpath selectionは有効にならない。
  detailsにはprocess実行中のpath操作不可を表示する。
- Directory documentは明示切替中だけ`Snapshot updates: Paused while process is running`を表示する。
  75 ms未満のshort command候補では内部snapshotを保護するが、pause noticeを投影しない。
- job終了後は既存のcommand-completion debounceで一回だけfresh refreshし、凍結状態を解除する。
- Dock hide、pane／session変更、利用可能なretained snapshotがない場合は従来どおりfail closedとする。

## 修正中に判明した事項

- 最初の実PTY検証では、retentionを`foregroundJob` modeだけに限定したため、foreground確定前の候補期間に
  Directory snapshotが先に`privacyUnavailable`へ置換された。retention開始を`directorySuspended`へ前倒しして解消した。
- Developer JITは成功した後、最初のRelease AOT検証だけが直前のcommand-completion refreshと次のECHO-off fixtureの
  開始順で競合した。fixtureを確定済みsnapshot／operation 0から開始するようにし、製品側の保持条件と検証前提を分離した。
- sandbox内のformat／analyzeは処理自体に成功した後、`~/.dart-tool` telemetry sessionのmtime更新拒否で終了コード1に
  なった。通常環境で再実行し、format変更0／analyze問題0を確認した。

## 修正検証

- `test/terminal_context_dock_test.dart`: 成功。候補期間からのretention、観測権限なしの表示、display authority失効、
  privacy unavailable fallback、operation 0を固定した。
- `test/terminal_localization_test.dart`: 成功。
- `test/terminal_action_menu_test.dart`: 成功。
- `dart analyze`: `No issues found!`。
- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`: Developer JIT／Release AOTとも成功した。
  ECHO-offとmanual Secure Inputで保持treeを表示し、同一Process Inspectorへ復帰、terminal focus、operation 0、
  PTY write 0を確認した。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功し、関連する受け入れ証跡を再生成した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。format 351 files／変更0、静的解析問題0を含む
  repository全体のtestを通過した。
- `git diff --check`: 成功。

未検証事項および残存するtask固有の阻害要因はない。
