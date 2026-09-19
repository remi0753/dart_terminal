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
