# Phase 7 — Foreground-process Directory override stability

## 目的

foreground process実行中にProcess InspectorからDirectory Navigatorへ手動切替した後、
次のprocess pollやapplication reconcileで勝手にProcess Inspectorへ戻らないようにする。

## 背景

foreground中のDirectory操作を追加した後、保持済みtreeへ一度は切り替わるものの、実環境では
すぐProcess Inspectorへ戻る回帰が確認された。切替直後だけでなく、250 ms周期のprocess同期と
Directory controllerの再同期を含む状態遷移を検証する必要がある。

## 範囲

- 同じwindow、pane、session、foreground PGIDへ明示切替したDirectory snapshotの再開処理。
- foreground中のprocess poll／application reconcileをまたぐcontent overrideの維持。
- 保持rootを使うtree移動、subtree展開、Search／Go To、hidden切替、manual refresh。
- job終了またはauthority失効時の既存fail-closed cleanup。

## 対象外

- foreground processのcwdを新たに推測または表示すること。
- SSH先filesystem、remote process introspection、filesystem watcherの追加。
- foreground processへのpath insertion、自動`cd`、command実行。

## 依存関係

- `TerminalContextDockProcessController`のcontent override、poll、retention authority。
- `TerminalContextDockDirectoryController`のfrozen snapshot、cwd resolution、bounded operation。
- application側のprocess-aware Directory observation callbackとreconcile順序。

## 完了条件

- 明示切替後のprocess pollとDirectory再同期を繰り返しても、同一jobのDirectory表示を維持する。
- foreground中にcwdを再解決できなくても、command開始前に保持したrootを失わない。
- 保持root上のbounded操作を使え、Process Inspector表示中はfilesystem observationを停止する。
- pane、session、PGID、Dock visibility、display authority、job終了の境界では従来どおりoverrideと保持内容を破棄する。

## 検証方針

- Directory controller unitで、凍結snapshotの再開時にcwd resolverが利用不能でもrootを維持することを固定する。
- process controllerとDirectory authorityの回帰testで、poll後もoverrideと操作権限を維持することを確認する。
- formatter、静的解析、repository全体testを実行する。
- 実AppKit native-content acceptanceをDeveloper JIT／Release AOTで実行し、切替後のpollをまたぐ表示と操作を確認する。

## 調査記録

### 2026-09-20 — 着手時

- content toggleは一度Directoryを投影し、Move modeへfocusできているため、shortcut配送自体は成功している。
- process controllerは250 msごとの同期で`canDisplayDirectory`を再確認し、falseならoverrideを解除する。
- applicationのdisplay authorityはprocess controllerのretention authorityとDirectory controllerの
  `hasRetainedSnapshot`を組み合わせている。

### 2026-09-20 — 原因確認

- 明示overrideによりDirectory observationが再開すると、Directory controllerの通常同期は凍結前のrootを使わず、
  cwd resolverをもう一度呼ぶ。
- foreground process実行中はcwd resolverが`unavailable`になり得る。この場合、保持済みtreeをrootなしの
  unavailable stateへ置換し、`hasRetainedSnapshot`がfalseになる。
- 次のprocess同期はdisplay authority失効と判断してoverrideを解除するため、利用者からは切替直後に
  Process Inspectorへ勝手に戻ったように見える。
- 同一jobのretention authorityがある期間は、表示対象はforeground processのcwdではなくcommand開始前に
  確定したrootである。したがって再開時のcwd再解決は不要であり、authorityを循環的に失う原因になる。

### 2026-09-20 — 回帰fixture

- Directory controller testへ、凍結済み`/other` snapshotをforeground override相当の
  `canObserve == true`かつ`canRetain == true`で再開し、cwd resolverを利用不能にするfixtureを追加した。
- 修正前は最初の再同期で保持snapshotがunavailableへ置換され、
  `explicit foreground Directory observation reuses its retained root across polls without resolving unavailable cwd`
  が失敗して実不具合と同じauthority喪失を再現した。
- 初回sandbox内testはMetal build hookが`~/.cache/clang/ModuleCache`へ書けず失敗したため、通常のcache権限で
  再実行して上記product assertion failureを確認した。これはsourceのtest failureとは別の実行環境制約である。

### 2026-09-20 — 全体検証中の生成証跡

- 初回`CI=true DART_SUPPRESS_ANALYTICS=true make test`はpackage testsとroot側の先行auditを通過した後、
  `Phase 7 AppKit acceptance is stale`で停止した。
- product source変更に対して生成証跡のsource hashが古いことが原因であり、受け入れ条件の失敗ではない。
  Phase 7 acceptanceと依存するcompatibility／gap／daily-use証跡を再生成してから全体testを再実行する。

### 2026-09-20 — 実装

- Directory controllerの観測可能経路で、同じpaneにforeground-job retention authorityと利用可能な保持snapshotが
  ある場合は、通常のcwd resolutionより先に保持rootを再開するようにした。
- 再開後の同期も保持rootを使うため、250 ms process pollやapplication reconcileのたびにforeground processの
  不確定なcwdを解決せず、`hasRetainedSnapshot`とprocess overrideのdisplay authorityを維持する。
- tree／Search／Go Toのbounded operation、hidden visibility、result countを通常どおり再開する。manual refreshは
  保持rootと展開済みsubtreeをatomicに再取得し、Navigator input中に予約されたcommand-completion refreshは
  従来どおりdeferする。
- retention authorityがない通常idle同期は既存のcwd resolutionを使う。保持rootがない、privacy restricted、
  pane不一致の場合も新経路を拒否するため、job／pane／session／PGID等の既存fail-closed境界は変えていない。

### 2026-09-20 — 検証結果

- `dart run test/terminal_context_dock_test.dart`: 成功。cwd resolverを利用不能にしたまま凍結rootを2回同期し、
  Directory表示、保持snapshot、refresh availability、resolver呼び出し0を確認した。保持rootのmanual refreshも
  1回だけcommitし、cwd resolverを呼ばないことを確認した。
- `dart format lib/src/terminal_context_dock_directory.dart test/terminal_context_dock_test.dart`: 成功、変更0。
- `dart analyze`: 成功、issue 0。
- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true ... elapsed_ms=24225`。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true process_inspector=true exact_pty=true ... elapsed_ms=22411`。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功。source変更に対応する生成証跡を更新した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 再生成後に成功。351 filesのformat変更0、root／package analyzer、
  unit、security stress、compatibility／generated evidence checkを完走した。
- `git diff --check`: 成功。
- sandbox内の初回`git add`は`.git/index.lock`作成権限がなく失敗したため、repository metadataへの通常権限で
  taskに属する6 filesだけをstageしてcommitする。

残存するtask固有の阻害要因、未検証事項、追加ROADMAP項目はない。
