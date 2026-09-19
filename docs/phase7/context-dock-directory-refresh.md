# Context Dock Directory refresh

## 目的

Directory Navigatorが同じworking directoryを表示し続けている場合でも、terminalで実行した
コマンドによるfile／directoryの作成、削除、名前変更、metadata変更を自動的に再取得する。
あわせて、ユーザーが任意の時点でContext Dockを手動更新できるactionを提供する。

## 背景

2026-09-19時点のcontrollerはterminal sessionの変更を75 msでcoalesceしてcwdを再解決するが、
pane、path、dispositionが同一なら既存のdirectory snapshotを再利用する。このため
`touch a.txt`のようにcwdを変えないコマンドの終了後もtreeが古いまま残る。

## 範囲

- localで観測可能なfocused paneの同一cwd snapshotをterminal activity後に再取得する。
- rootと開いているsubtreeを更新し、展開状態、Navigator mode、query、input ownershipを保持する。
- 連続するterminal outputをboundedにcoalesceし、実行中processのprivacy／suspension境界を守る。
- 手動refreshをapplication actionとしてmenu、Command Palette、keybind設定から呼べるようにする。
- 実terminal commandでfileを作成し、手動同期なしでtreeへ現れることを両runtimeで確認する。

## 対象外

- filesystem watcherによるterminal commandと無関係な常時監視。
- remote／SSH先filesystemの走査。
- hidden entryの既存表示方針、検索上限、path action semanticsの変更。
- refreshのためのterminal command、cwd、file名のdiagnostics記録。

## 依存関係

- `TerminalContextDockDirectoryController`のgeneration、cancellation、bounded snapshot処理。
- terminal session変更通知とProcess Inspectorのforeground-process観測。
- bounded application action catalog、native menu、Command Palette、keybind設定。

## 分割と実施順

1. 同一cwdのterminal activity refresh
   - coalesced terminal changeを通常のcwd同期と明示的なsnapshot refreshとして区別する。
   - stale operationをgeneration単位で破棄し、rootと展開済みsubtreeを再読込する。
   - expansion、mode、query、ownershipを保持するmodel testを追加する。
2. 手動refresh action
   - stable action ID、表示名、availability、menu／palette dispatch、keybind surfaceを追加する。
   - hidden、process、remote、非表示Dockでは既存privacy policyに従いfail closedまたは安全に再同期する。
3. 製品受け入れ
   - 実PTYでcwdを変えないcommandによりfileを作成し、手動controller呼び出しなしでtreeが更新されることを確認する。
   - Developer JITとRelease AOT、全test／format／生成物freshnessを確認する。

## 完了条件

- `touch`に限定せず、terminal commandの完了を伴うterminal activity後に同一cwdの表示を更新する。
- file作成、削除、rename、metadata変更を次のsnapshotで反映できる。
- 開いているfolderを閉じず、選択は新しいresult countへ安全にclampされる。
- 手動refreshがmenu、Command Palette、keybind設定からterminalへbyteを送らずに実行できる。
- process実行中、secure／privacy suspension、remote cwd、Dock非表示ではfilesystem情報を漏らさない。

## 検証方針

- mutable fake filesystemで同一cwd refresh、展開保持、stale completion拒否、coalescingを検証する。
- action registry、availability、menu／palette dispatch、terminal write 0を既存action testへ追加する。
- native-content acceptanceで実shell commandからfileを作り、自動投影を待つ。
- Developer JIT、Release AOT、`make test`、format／analyze／生成物freshnessを実行する。

## 判明事項・判断記録

- terminal sessionの変更通知は既にProcess Inspector同期の後にDirectory controllerへ配送される。
  現行の欠落は通知自体ではなく、同一pane／pathでsnapshotを保持する分岐にある。
- output chunkごとの即時filesystem走査は行わず、既存75 ms debounceでburstをまとめる。
  foreground process中は既存のdirectory observation suspensionを維持し、終了後の通知で再取得する。
- filesystem watcherはcommand完了との対応付け、resource寿命、remote境界が別問題になるため採用しない。
- `TerminalPaneConfiguration.onChanged`は変更元の`PaneId`を保持しているため、Directory controllerへ
  そのIDを渡す。複数windowの全snapshotではなく、75 msの間にactivityがあったtarget paneだけを
  refresh対象にする。
- 同一cwdのrefresh時は既存window stateをin-place更新しない。新しいgenerationのstateへ置換し、
  旧root／child／search／Go To operationをcancelすることで、refresh前の遅延完了を拒否する。
  展開path集合はpane単位でcontrollerが別所有しているため、新generationでも開いたsubtreeを再取得できる。
- terminal activityはProcess controllerの同期を先に予約している。長時間process中は既存の
  `canObserveDirectoryPane`がDirectory走査を停止し、短時間commandはProcess Inspectorを点滅させずに
  activity refreshだけを行う。
- 手動操作は`view.refresh-directory-navigator`というstable actionにした。既定shortcutは追加せず、
  View menuとCommand Paletteへ表示し、任意の非予約chordを`keybind`から割り当てられる。
- actionは可視かつlocalで観測可能なDirectory Navigator snapshotがある時だけ有効になる。
  Dock非表示、remote、Process Inspector／privacy suspension、controller disposalではfail closedとし、
  terminal／Navigatorのinput owner、mode、query、selectionを変更しない。
- action catalogは47件になった。生成keybind/action referenceとREADME／feature matrixの件数・
  Directory Navigator操作説明を同時に更新した。
- terminal outputがない長時間commandでも更新するため、Process controllerがDirectory Navigatorを
  再び観測可能にしたpaneを検出し、そのpaneだけへrefreshを予約する。foreground中のrich metadata
  更新では予約せず、foreground／shell-ownedからidle shellへ戻るtransitionだけを補完経路にする。
- 自動refresh timerの到着時にNavigatorがinputを所有していた場合、tree／Search／Go To操作を
  loading stateで中断しないようpane単位で保留する。Escape等でterminal ownershipへ戻った次の
  synchronizeで適用する。明示的なmanual refreshはユーザー操作なのでNavigator ownership中も即時実行する。

## 検証記録

### 同一cwdのterminal activity refresh

- `dart format lib/src/terminal_context_dock_directory.dart lib/src/terminal_application.dart
  test/terminal_context_dock_test.dart`: 成功、変更なし。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  mutable fake filesystemでroot／展開済みchildへのfile追加、file削除、metadata size変更、
  expansion維持、同一75 ms内の2通知が各path 1回のlistになることを確認した。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `git diff --check`: 成功。
- 初回検証ではMarkdownを`dart format`へ誤って渡してparse errorになった。Dart sourceだけへ
  対象を修正した。sandbox内の初回testは`~/.dart-tool`と`~/.cache/clang`へ書けず失敗し、
  同一testを通常開発環境権限で再実行して成功した。

### 手動refresh action

- `dart format`（変更したDart source／test）: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_action_registry_test.dart`: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  visible/local availability、active window/pane dispatch、query／Navigator focus保持、hidden／remote／
  privacy fail-closed、実snapshot再取得を確認した。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_localization_test.dart`: 成功。
- `DART_SUPPRESS_ANALYTICS=true dart run test/terminal_native_hierarchy_test.dart`: 成功。
- `make keybind-action-reference`: 成功。47 actionの生成referenceを更新した。
- `make keybind-action-reference-check`: 成功、`application_actions=47`。
- `make terminal-localization-check`: 成功、16 source／4 resource family／21 paired key。
- `git diff --check`: 成功。
- sandbox内の`dart format`はsource format自体を完了後、telemetry sessionのmtime更新だけを拒否された。
  source差分と後続のanalyze／testsでformat・構文を確認した。

### 実PTY／AppKit製品受け入れと全gate

- native-content scenarioへ次を追加した。
  - plain interactive `/bin/sh`の同一cwdで`touch command-created.txt`を実行し、controllerを直接呼ばず
    treeに現れること。
  - `PS1=''`かつ出力なしの`sleep 1; touch silent-command-created.txt`がidle shellへ戻った後、
    Process transition経路でtreeに現れること。
  - terminal外で作成した`manual-refresh.txt`が`view.refresh-directory-navigator` dispatch後に現れ、
    terminal ownershipとPTY write countが変わらないこと。
- 最終sourceの`make RUNTIME_ARCH=arm64 developer-jit-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、`elapsed_ms=13530`、4 session clean。
- 最終sourceの`make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`、`elapsed_ms=12940`、4 session clean。
- 両runtimeの途中runで、refresh timerがNavigatorのfolder toggle／Search Returnと競合し、
  一時的な空rowsまたはpending reveal消失を生じることを確認した。自動refreshのNavigator ownership中
  deferを追加し、unit testと両runtime再実行で解消した。acceptanceの非空list前提も明示的にguardした。
- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`で、変更source／test hashを持つ
  生成証跡を最終sourceに合わせて更新した。
- 最終`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功、`dart_terminal tests passed`。
  format 348 files変更なし、全体analyze `No issues found!`、47 action reference、localization、privacy、
  AppKit、compatibility、differential、application、release-candidate、distributionを完走した。
- 全gateの途中で、生成前のcoverage／gap inventory／daily-use matrixが順にstaleとして正しく拒否された。
  各正規generatorで更新した。また既存ROADMAP項目のPTY competing-reaper fixtureが1回`No element`で
  非決定的に失敗したが、`make dpty-dart-test`単独と後続の複数full gateでは成功した。今回の変更で
  既存follow-upを完了扱いにはしていない。
