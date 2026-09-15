# Context Dock and file/folder navigator roadmap

- Status: complete
- Date: 2026-09-14
- Scope: completed Phase 7 application UXに続く追加機能
- Related: UI-02、UI-05、UI-09、AX-01、AX-02、CFG-06、SEC-01、SEC-04

## 目的

terminalの右側に、必要な時だけ表示できるwindow-ownedな`Context Dock`を追加し、その最初の
moduleとしてfile／folder navigatorを提供する。terminalへ`pwd`や`ls -la`を入力せずにfocused
paneのworking directory、直下と展開済みsubtree、hidden entry、選択entryの主要metadataを確認
できるようにする。file／folder名を入力すると同じ領域が検索結果へ連続的に変わり、現在地以外も
keyboardだけで探せるようにする。

検索へ移った後の矢印入力がterminalとnavigatorのどちらへ届くかを曖昧にしない。表示状態とinput
ownershipを分離し、`Shift+Command+F`でnavigatorへ移り、`Escape`またはstable action
`view.focus-terminal`で1操作のうちにterminalへ戻る契約を先に固定する。terminal ownership中の
可視Dockは保持中のNavigator modeではなく`Mode: Terminal`を表示する。

## 背景と利用者が嬉しい場面

- `cd`直後やpane／tabを切り替えた直後に、現在地と周辺構造を再確認したい。
- command lineを壊したりscrollbackへ補助commandの出力を増やしたりせず、dotfileを含むentryと
  permission、owner、size、更新時刻、symlinkであることを確認したい。
- 名前の一部だけ覚えているfile／folderを、current directoryの外も含めて探したい。
- 検索結果のpathを次のcommandへ使いたいが、mouse操作や手入力は避けたい。
- rich shell pluginがないplain `sh`でも、local processから安全に取得できる情報は使いたい。
- SSH中にlocal pathをremote pathと誤認したくない。remote filesystemを扱う場合もterminal出力の
  盗み読みやhidden command注入ではなく、明示した別capabilityとして扱いたい。

## Product outcome

### 配置と通常表示

- Context Dockはterminalの上へ重ならず、windowの右側でterminal contentと並ぶ。新規windowの
  既定幅は380 ptとする。hide時はterminalが空いた幅を取り戻し、再表示時は利用者が最後に選んだ
  bounded widthを復元する。
- Dockはwindowごとに1つだけ所有し、selected tabのfocused live paneへ追従する。paneごとのtree
  expansion、browse location、query、selection、scroll位置はbounded stateとして保持し、pane close
  と同時に解放する。
- headerは対象pane、trusted working directory、local／remote／unknown capabilityを常に示す。
  breadcrumbからparent、back、forward、working directoryへkeyboardで戻れる。
- queryが空ならworking directoryをrootにしたfile＋folder treeを表示する。dotfileも既定で表示し、
  `Shift+Command+H`でfocused paneのdot-prefixed file／folderとそのsubtreeをtree、Search、Go Toから
  一括で表示／非表示にする。folderはlazy展開する。header、query、row、coverageは上段のbounded scroll領域へ置き、名前と種類を
  優先する。選択entryのpath action、permission、owner／group、size、mtime、symlink targetなどは
  多数のrowがあっても見失わない下段の固定compact detailへ置く。読めないentryは消さず理由を示す。
- Context Dockは後からprocessやsystem stateを載せられるmodule boundaryを持つが、空のtabや未実装の
  placeholderは出さない。本taskで利用者へ公開するmoduleはDirectoryだけとする。

### 検索

- `Shift+Command+F`はDockがhiddenなら表示し、Directory moduleのqueryをfirst responderにして、
  既存queryを全選択する。queryが変わるとtreeの同じlist領域が検索結果へ変わり、別tabや
  Folder／Subtree／Everywhere modeを選ばせない。
- 結果はまずcurrent working directory subtreeを返し、その後にopened／recent locationと、OSが
  許可するsystem-wide metadata indexの結果をprogressiveに追加する。section labelとprovider状態で
  検索範囲を伝え、`Everywhere`を独立した操作modeにはしない。
- system-wide searchのためにfilesystem rootを常時walkしない。indexedでないvolume／directoryは
  利用者が明示したsearch rootだけをbounded direct traversalの対象にする。permission、sandbox、
  index未収録により「全て」を保証できない場合はcoverageを明示し、結果0と取得不能を区別する。
- 検索対象はbasename、relative／absolute path、file kind、基本metadataとし、file content検索は
  初期scopeに含めない。queryをclearすると、検索前のtree expansion、selection、scrollへ戻る。
- 空白区切りはAND、quoted phraseは連続一致として扱い、basename prefix、basename substring、
  cwd内、recent、path depthの順に決定的rankingを行う。exact weightsとhard capsは最初のsubtaskで
  benchmark fixtureとともに固定する。

## Keyboard focusとinput ownership

Dockのvisibilityはinput ownerを意味しない。terminalを操作中もDockは参照でき、navigatorが
first responderの間はterminal paneがlogical focusとcontext targetを保ってもPTY input authorityを
持たない。

| 状態 | 主な入力 | 結果 | PTY write |
| --- | --- | --- | --- |
| Terminal owns input | 通常のtext／navigation key | 従来どおりfocused paneへencode | 従来どおり |
| Terminal／Navigator owns input | `Option+Shift+C` | Dock visibilityをtoggle。非表示時はterminalへfocusを戻す | 0 byte |
| Terminal／Navigator owns input | `Shift+Command+H` | focused paneのhidden file／folder表示をfocus不変でtoggle | 0 byte |
| Terminal owns input | `Shift+Command+F` | Dockを表示してSearchへfocusし、query末尾に点滅caretを表示 | 0 byte |
| Terminal owns input | `Shift+Command+G` | Dockを表示してGo Toへfocusし、treeを保ったまま一致rowへ移動 | 0 byte |
| Terminal owns input | `Shift+Command+M` | Dockを表示してMoveへfocusし、tree navigationだけを有効化 | 0 byte |
| Search／Go To owns input | printable／Delete／Command+A | modeごとの独立queryだけを編集 | 0 byte |
| Move owns input | printable／Delete／Command+A | queryを変更せず消費 | 0 byte |
| Navigator owns input | Up／Down、Page Up／Down | result selectionだけを移動 | 0 byte |
| Navigator owns input | Return | tree folderをcollapse／expand。Searchのcurrent-root resultはMove treeへrevealし、folderならexpand | 0 byte |
| Navigator owns input | Command+Left／Right | treeのfolder／ancestorをcollapse／expand。SearchのCommand-Rightはcurrent-root resultをreveal | 0 byte |
| Navigator owns input | `Escape`または`view.focus-terminal` | 現在のstill-live focused paneをfirst responderへ戻す | 0 byte |

追加の契約:

- `Option+Shift+C`はstable action `view.toggle-context-dock`のnative menu shortcutとし、terminal／Navigatorの
  first responderより先にexactly onceで捕捉する。Navigatorからhideする場合はstill-live terminalへinputを戻してからDockを閉じる。
- `Shift+Command+H`はstable action `view.toggle-hidden-files`としてView menu、Command Palette、keybind referenceで共有し、
  現在のinput ownership、query、mode、expanded stateを保ったままpane-local visibilityだけを切り替える。hidden directoryのdescendantも
  Search／Go Toから除外し、再表示時は保持snapshotからtree contextを復元する。
- `Shift+Command+F`、`Shift+Command+G`、`Shift+Command+M`はそれぞれstable action
  `view.search-files-and-folders`、`view.goto-file-or-folder`、`view.move-in-directory-navigator`としてView menu、Command
  Palette、keybind referenceで共有する。native shortcutがどのfirst responderからもexactly onceで
  捕捉し、terminal bytesへfall throughしないようにする。
- Search／Go Toではnative editorをeditableかつDart-only key routingにし、zero-length selectionをquery末尾へ置いてAppKit標準の
  点滅caretを表示する。Moveでは同じeditorをfirst responderに保ちながらread-onlyへ戻し、文字編集の見かけを出さない。
- Go Toはwide Searchと別のcurrent-subtree-only bounded operationを使い、現在visibleなmatchを優先する。deep matchはrootから順に
  実際にdirectoryとして観測できたancestorだけを1段ずつlazy展開してselectionへrevealし、対象folder自体はReturnまで閉じたままにする。
- Search resultのReturn／Command-Rightはnormalized pathが現在のresolved working directory配下の場合だけMoveへ切り替える。ancestorを
  同じbounded手順でrevealし、対象folderも展開する。外部result、stale query／cwd、permission failure、expanded-directory上限超過では
  mode、root、selectionを維持してfail closedとし、自動`cd`やshell commandを実行しない。
- Navigatorで同じmode shortcutを再度押した場合はqueryとcaretを保持してfocusを再確認するだけで、terminalへtoggleしない。
  戻る方向は別の`view.focus-terminal` actionへ固定し、同じchordの状態依存挙動を避ける。
- `Escape`はquery clearを先に要求せず、常に1回で`view.focus-terminal`を実行する。Dock、query、
  results、selectionは残り、mode copyだけが`Terminal`へ変わる。次の`Shift+Command+F`で同じ調査へ戻れる。
- `view.focus-terminal`はmenu／Command Palette／設定可能なkeybindからも呼べるstable actionとする。
  Navigator-localなdefault keyは`Escape`とし、追加のglobal default chordは衝突監査なしに決めない。
- Navigator focus中はsearch caretとactive selection／focus ringを明示し、terminal cursorはnon-input
  状態として停止またはdimする。terminalへ戻ると逆転する。色だけに依存せずborder、caret、
  accessibility focused stateでも所有者を表す。
- Command+Fは本taskで予約せず、terminal pane内scrollback searchの既存／将来のownershipに残す。
- app action key equivalent、text editing command、tree navigation、PTY encoderの優先順位を1か所で
  決める。dismiss、pane close、tab change、window close、action failureの各経路でstale native viewを
  first responderにしない。

## Navigatorでのpath操作

- selectionだけではterminalへbytesを送らない。Returnはselected folderをDock内でbrowse／expandし、
  展開済みなら同じfolderをcollapseする。fileではtree stateを変えずdetail表示だけを維持する。
  terminal processのcwdを暗黙には変更しない。
- Command+Cは選択pathをplain textとしてcopyする。Option+Returnは既存のpaste admissionと
  shell-literal quotingを使い、改行を付けずにstill-live focused terminalへpathだけを挿入してから
  terminal focusへ戻る。remote providerは接続先のpath／shell contractを別途満たすまでこのactionを
  unavailableにする。
- `cd`の自動送信、Returnの自動実行、foreground TUIへのblind input、shell command lineの読み取りは
  行わない。将来`Change Terminal Directory`を追加する場合も、semantic prompt state、shell kind、
  quoting、exactly-once送信を別taskで合意する。

## Working directoryとfilesystem authority

### Local pane

- sourceは、accepted local OSC 7、owning local shellについてOSが返すcontent-free cwd snapshot、
  trusted launch cwdの順でgeneration付きに解決する。terminal textやprompt文字列からpathを推測せず、
  pathがunknownならその状態を明示する。
- descriptive OSC 7をfilesystem authorityへ格上げしない。既存
  `TerminalTabPresentationResolver.localFilePath`と同じくlocal `file:` authority、absolute path、
  control／bidi rejectionを満たした値だけをdirectory providerへ渡す。
- directory enumeration、metadata取得、searchはAppKit main threadとterminal-engine isolateを塞がない
  cancellable ownerで実行する。pane／cwd／query generationが変わった結果は破棄する。
- symlinkは既定でfollowせず、explicit browseでもdevice／inode相当のvisited identityとdepth／entry／
  byte／deadline capでloopを防ぐ。permission denied、vanished entry、invalid encoding、mount detach、
  watcher overflow、memory pressureはtree全体を壊さないtyped stateとして返す。
- hidden Dockはfilesystem watchとbackground searchを最小化し、terminal出力、render、input latencyを
  優先する。current treeのrefreshはcwd change、explicit refresh、bounded filesystem eventでcoalesceする。

### SSH／remote pane

- remote OSC 7のhost/pathは表示上のremote identityには使えてもlocal filesystem access authorityには
  しない。同名local pathへfallbackしない。ただしlocal interactive shell自身がforegroundを保持し、同じchild PIDの
  kernel cwdを取得できる場合、machine hostname付きOSC 7はremote sessionではなくlocal shell hookのhost aliasとして扱う。
  別foreground processが所有する時はこの例外を適用しない。
- PTYへhidden `find`／`ls`／`pwd`を注入する、shell promptやcommand outputをscreenからscrapeする、
  password／agent credentialを取得する方式は採用しない。alternate screen、running command、shell差、
  quoting、scrollback汚染のいずれにも安全な一般解にならないためである。
- remote navigationは保留し、現在のROADMAPでは追跡しない。将来userが再開を明示した場合にだけ、
  明示したside-channel provider（例: user-approved SFTP／remote helper capability）のconnection identity、
  authentication owner、cancellation、path encoding、permission、disconnectを独立taskとして設計する。
  capabilityがなければDockは`Remote filesystem unavailable`を表示し、local resultを混ぜない。

## 対象外

- terminal scrollbackのCommand+F検索
- file content検索、file編集、preview／Quick Lookの再設計、Finder代替
- emulatorからchild processのcwdを直接変更すること、暗黙の`cd`実行
- process list、resource meter、Git statusなど、Directory以外のContext Dock module
- remote terminalの画面scrape、hidden command injection、credential自動発見
- Linux／Windows UI、network filesystemのoffline mirror

## 依存関係とownership

- `TerminalApplicationState`／`TerminalNativeHierarchyAdapter`: selected tab、focused pane、pane lifecycle、
  projected split layout、first responder mutation。
- `TerminalActionCatalog`／`TerminalProductHierarchyActionCoordinator`: stable action、availability、menu、
  Command Palette、exactly-once dispatch、focus restoration policy。
- native key-equivalent priorityと`TerminalKeyEventRouter`: application actionをnavigator editingより先に
  消費し、navigator-owned keyをPTY encoderへ渡さない境界。
- `TerminalSessionMetadata`／`TerminalTabPresentationResolver.localFilePath`: bounded OSC 7 stateとtrusted
  local path変換。remote URIはdescriptive stateのままにする。
- existing Services／drop／paste policy: shell-literal quoting、large／control input admission、still-live pane
  resolution。Navigatorは新しいunbounded write pathを作らない。
- Secure Keyboard Entry: explicit manual secure input、またはECHO-offのowning-shell command／foreground
  process中はnavigator focusとpath insertionをunavailableにし、terminal first responderを保持する。zsh／shが
  idle line editingでECHOを切る場合は利用可能性を維持する。遮断時はDockの既存snapshotと進行中operationを破棄し、
  privacy-safeなunavailable stateを表示する。
- reusable AppKit split/sidebar、outline/list、search-field、accessibility primitiveが不足する場合は、
  generic APIだけを`dart_appkit`へ先に追加し、productのcwd／search policyは本repositoryに残す。

## 分割と実施順

1. **window-owned Context Dock state、action、keyboard focus contract**
   - Dock／Directory state、per-pane bounded navigation state、visibilityとinput ownerの独立state machineを
     pure Dartで固定する。
   - `view.search-files-and-folders`、`view.focus-terminal`、`view.toggle-context-dock`のstable action、
     localization、availability、menu／palette／keybind policyを追加する。
   - `Shift+Command+F`、Navigator `Escape`、矢印、dismiss／close時のexact routingとPTY write 0をfake
     first-responder testで固定する。必要なgeneric AppKit primitiveとownershipをこの段階で確定する。
2. **trusted local cwd観測とbounded・cancellable directory snapshot**
   - local OSC 7／owning-shell cwd／launch cwdのgeneration付きresolverと、filesystem authority adapterを
     terminal coreから分離して実装する。
   - lazy tree enumeration、metadata、permission error、symlink、mount change、cancellation、cache／watch
     budgetをfake filesystemとtemporary fixtureで検証する。
3. **working directory tree、metadata、pane追従のnative side-dock表示**
   - terminalと並ぶhideable／resizable右Dock、breadcrumb、tree、detail、empty／loading／error／unknown／
     remote-unavailable stateを実装する。
   - window／tab／pane focus、split resize／zoom、fullscreen、restoration、appearance、Reduce Motion／Contrast、
     VoiceOver、Full Keyboard Accessとnative owner cleanupを統合する。
4. **current subtreeからsystem-wideへ連続するfile／folder search**
   - 1つのqueryとlistでcwd subtree、recent／opened root、system metadata index、explicit fallback rootを
     progressiveに統合し、source／coverageを表示する。
   - cancellation、deterministic ranking、duplicate identity、renamed／removed result、huge directory、rapid
     query／cwd change、index unavailableをhard cap内で検証する。
5. **path handoff、hardening、通常製品受け入れ**
   - copy path、quoted path insertion、still-live target resolution、secure input／foreground TUI safety、
     privacy診断を既存policyへ統合する。
   - generated action reference、README、FEATURE_MATRIX、manual accessibility checklistを更新し、focused
     tests、full gate、Developer JIT／Release AOTの実AppKit／PTY／Metal受け入れを完了する。
各subtaskは上記順に実装、検証、記録、ROADMAP更新、commitする。先行subtaskが完了するまで次へ
進まない。SSH／remote providerは本計画の実施対象に含めない。

## 完了条件

- Dockの表示／非表示とinput ownerが独立し、どちらがkeyを受け取るかをvisual stateとaccessibility state
  の両方で常に判別できる。
- `Shift+Command+F`はどのterminal paneからも検索へ移り、Up／Downはnavigator selectionだけを動かす。
  `Escape`／`view.focus-terminal`は1操作で現在のstill-live terminalへ戻り、queryを失わない。
- Navigator focus、検索、tree操作、dismiss、stale target、secure input unavailableの全経路で意図しない
  PTY writeが0である。quoted path insertionだけが明示actionのexact payloadを1回送る。
- focused local paneのtrusted cwd、dotfileを含むtree、lazy subtree、主要metadataが表示され、pane／tab／
  cwd changeへgeneration-safeに追従する。hidden visibilityはpaneごとに独立して切り替えられ、unknown／permission denied／remoteをlocal pathとして偽装しない。
- query入力だけでcwd subtreeからwider local searchへ結果が連続表示され、clear後は元のtree contextへ
  戻る。unindexed／denied scopeはcoverageとして利用者に分かる。
- main-thread filesystem I/O、unbounded root walk、symlink loop、stale result適用、hidden-Dockの継続的な
  heavy scanがない。定義したentry／byte／result／deadline／cache capをboundary testで守る。
- keyboard-only、VoiceOver、Reduce Motion／Contrast、English／Japanese copyが揃い、window／tab／pane／
  Dock／filesystem ownerがclose、reload、memory pressure、shutdown後に残らない。
- focused test、format、analysis、generated freshness、`make test`、Developer JIT、Release AOTの通常製品
  acceptanceが成功し、README、FEATURE_MATRIX、reference、task memo、ROADMAPが一致する。

## 検証方針

- pure state test: Dock visibility、input owner、per-pane state、query clear／resume、focus target generation、
  action availability、deterministic ranking。
- fake filesystem: dotfile、deep／wide tree、permission、symlink loop、rename／remove、invalid name、volume detach、
  cancellation、watch overflow、hard-cap exact boundary。
- fake AppKit: side layout、resize／hide、first responder、key equivalent priority、menu／palette dispatch、tree
  accessibility、stale handle、balanced teardown。
- product integration: 2 window、複数tab／split／cwd、rapid focus change、secure input、alternate screen、hidden
  Dock、search cancellation、copy／insertを通し、terminal write deltaと全owner baselineを照合する。
- runtime acceptance: M1/arm64 Developer JITとRelease AOTで実zsh cwd、plain local `sh`のOS cwd fallback、
  tree／search、keyboard往復、resize／fullscreen、cleanupを同じscenarioで確認する。

## 検討した選択肢

1. Dock全体をterminalへoverlayする案は、terminal行を覆いpointer／selectionと競合するため不採用。右側の
   sibling layoutを採用する。
2. Folder／Subtree／Everywhereをtabで分ける案は、scope選択が検索前の負担になるため不採用。empty query
   はtree、non-empty queryは同じlist上のprogressive searchとする。
3. `Shift+Command+F`をfocus toggleにする案は、同じkeyの結果が現在のfirst responderへ依存するため
   不採用。検索focusとterminal復帰を別actionにする。
4. 最初の`Escape`でqueryをclearし、二度目でterminalへ戻る案は、入力先を素早く戻したい要求に反する
   ため不採用。1回で戻り、queryは保持する。
5. filesystem rootを常時再帰scanする案は、latency、battery、privacy、permission、network volumeの上限を
   守れないため不採用。lazy tree、OS index、explicit fallback rootを組み合わせる。
6. SSH paneへ`find`を自動送信して結果をparseする案は、shell／TUI stateを破壊しscrollbackを汚すため
   不採用。remoteは明示side-channel capabilityへ分離する。

## 調査記録

### 2026-09-14 第1サブタスク着手

- 目的: Context Dockのvisibility、focused pane context、terminal／navigator input ownershipを
  filesystemやnative viewから独立したpure Dart stateとして固定し、後続UIが同じ契約を投影できるように
  する。3つのstable actionとNavigator-owned key controllerも同じ段階で定義する。
- 範囲: window／pane generationに追従するbounded state、query／selectionの最小contract、
  `view.search-files-and-folders`、`view.focus-terminal`、`view.toggle-context-dock`、English／Japanese copy、
  `Shift+Command+F` native reservation、Escape／editing／Up／Down／Page Up／Page Down／tree expansion request、
  action coordinatorのavailability／focus callback／dispose、generated action reference、unit test。
- 対象外: native right-side layout、filesystem enumeration／cwd fallback、実検索ranking、path copy／insert、
  Secure Keyboard Entryとの製品統合、README／FEATURE_MATRIX上の完成機能表示、実runtime acceptance。これらは
  後続subtaskの順序を維持する。
- 依存関係: `TerminalApplicationState`のactive window／selected tab／focused live pane、
  `TerminalActionCatalog`のnative shortcut precedence、`TerminalAppKitKeyAdapter`のphysical key変換、既存
  Command Paletteのindependent key ownership／terminal focus restoration contract。
- リスク: native viewがまだない段階でactionを通常製品へ登録すると利用者に空のDockを見せるため、catalogと
  reusable coordinatorだけを追加し、product registrationはnative side-dock subtaskまで行わない。native
  shortcutはcatalogに現れるためgenerated referenceとreserved chordを同じcommitで更新する。
- 完了条件: stateのwindow／pane cleanupとhard cap、Dock表示とinput ownerの独立性、search focusの再要求、
  Escapeからshared `view.focus-terminal`のexactly-once dispatch、Navigator-owned keyのPTY payload非生成、
  unavailable／busy／failure時のfail-closed、action metadata／localization／reference freshnessをtestで固定する。
- 検証方針: 新規focused unit test、action registry／localization／keybind referenceの関連test、format、analysis、
  full `make test`を順に実行する。native UIとproduct registrationが対象外なのでDeveloper JIT／Release AOTの
  visual acceptanceはこのsubtaskでは実行しない。

### 2026-09-14 第1サブタスク実装結果

- `lib/src/terminal_context_dock.dart`へwindow-owned state authorityを追加した。standard windowだけを保持し、
  selected tabのfocused live paneをtargetにする。query、result count、selection、query selection generationは
  paneごとに保持し、pane／window closeとapplication shutdownで対応stateを除去する。queryは256 UTF-16
  code unit、resultは512件、page moveは10件を既定上限とし、window／pane総数は既存application state上限へ
  従う。
- visibilityとinput ownerを別stateにした。toggleはterminal ownershipを保ったまま表示でき、search requestは
  Dockを先に表示してgeneration-boundなnative focus callbackが成功した後だけnavigator ownershipを確定する。
  terminal focus callbackが失敗した場合もnavigator ownershipを保持し、どちらの失敗も入力先を推測して変更
  しないfail-closed contractとした。
- `view.toggle-context-dock`、`view.search-files-and-folders`、`view.focus-terminal`をstable action catalogへ追加し、
  English／Japanese titleとsearch keywordをlocalization catalogへ追加した。`Shift+Command+F`はnative menu
  shortcutとして予約し、search actionだけはdispatch後にterminal focusを自動復元しない。native Dockがない
  現段階では通常製品のdispatcherへcoordinatorを登録せず、menu／palette上はunavailableに留める。
- Navigator key controllerはfirst responder中のeventを専有する。printable text、Backspace、Command+A、
  Up／Down、Page Up／Down、exact Command+Left／Rightをtyped resultへ変換し、Escapeはshared
  `view.focus-terminal` actionをdispatchする。unsupported key、key-up、busy／unavailable Escapeも消費するため、
  navigator ownership中にPTY encoderへfall throughする経路はない。Shift付きnavigationは無修飾／exact
  Command操作として扱わない。
- focused testは複数window／paneの分離とcleanup、hard capのatomic rejection、search再focus時のquery保持、
  toggleとinput ownershipの独立性、navigator／terminal focus callback failure、action availability、busy action、
  query editing、selection clamp、tree intent、全navigator-owned eventのPTY write 0を検証する。共通test runnerと
  localization auditへ追加し、action／keybind generated referenceも更新した。
- READMEは完成機能としての説明を追加せず、stable action catalogの事実上の件数だけ37から40へ更新した。
  生成artifactのsource hash連鎖によりcompatibility regression coverage、Ghostty gap inventory、daily-use matrixを
  各既定generatorで更新した。意味上の互換性判定、gap、release blockerの数は変化していない。

#### 検討と引き継ぎ

- 1つのfocus toggle actionは採用せず、検索へ入るactionとterminalへ戻るactionを分離した。これにより
  `Shift+Command+F`の意味は現在のfirst responderに依存せず、Navigator内で再実行した場合もquery selection
  generationを進めるだけになる。
- native presenterはhierarchy／focus mutation後にcoordinatorの`synchronize()`を呼び、FocusRequestのwindow、
  pane、state generationをnative handle解決時にも照合する必要がある。Navigator viewへ届いたkeyは本controller
  だけへ渡し、`notOwned`が返るまでterminal text-input routeへ渡してはならない。
- native side-dock、filesystem state、secure-input admission、visual／accessibility focus表現は未実装であり、
  ROADMAP上の後続subtaskへ残す。このsubtaskでは空のnative UIを公開しないため、Developer JIT／Release AOTの
  visual acceptanceは対象外のままである。

#### 検証と失敗記録

- 最初のsandbox内`dart format`はsourceのformat自体を完了した後、SDK telemetry logのworkspace外書き込みで
  `PathAccessException`になった。最初のfocused testもClang ModuleCacheとtelemetry pathのsandbox制約で失敗
  した。いずれもsource／test failureではなく、同じcommandを許可済みnative cache環境で再実行して成功した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
- `terminal_action_registry_test.dart`、`terminal_localization_test.dart`、`terminal_key_binding_test.dart`、
  `keybind_action_reference_test.dart`、`terminal_config_test.dart`の各focused実行: すべて成功。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_localization_audit_test.dart`: 成功。15 source、
  4 resource family、21 resource keyを監査した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: `No issues found!`。
- 初回の`make test`はREADME hashを追うregression coverage freshnessで、再実行はその連鎖を追うGhostty gap
  inventory、次の再実行はdaily-use matrix freshnessで順に停止した。各artifactを
  `make terminal-compatibility-regression-coverage`、`make ghostty-p0-p1-gap-inventory`、
  `make release-candidate-daily-use-matrix`で再生成した。
- 生成後の`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。format 340 filesで変更0、analysis指摘0、
  compatibility／differential／application／terminfo／shell integration／distribution gateを通過し、最後に
  `dart_terminal tests passed`を確認した。

### 2026-09-14 第2サブタスク着手

- 目的: shell pluginがOSC 7を送らないplain local `sh`でも、owning shellのOS cwdを補助authorityとして
  観測し、focused paneへgeneration付きのtrusted local cwdを返せるようにする。そのcwd直下はAppKit main
  threadを塞がないbounded／cancellable snapshotとして取得し、後続native treeが安全にlazy展開できる
  provider contractを作る。
- 範囲: local OSC 7、owning shell cwd、trusted launch cwdの優先resolver、remote OSC 7のlocal fallback拒否とlocal shell hostname alias、
  macOS PTY child cwdの専用native snapshot、absolute／UTF-8／control／bidi path validation、非再帰directory
  listing、dotfile、file／folder／symlink種別、permission／owner／group／size／mtime／symlink target、
  entry／metadata concurrency／deadline上限、typed partial／unavailable state、generationとcancel owner、fake
  filesystemおよびtemporary fixture test。
- 対象外: native Dock表示、tree rowのexpand state、filesystem watcher、recursive subtree search、Spotlight等の
  system index、path copy／insert、remote filesystem provider、Secure Keyboard EntryとのUI連動。これらは
  後続subtaskの順序を維持する。
- 依存関係: `TerminalSessionMetadata`と`TerminalTabPresentationResolver.localFilePath`のlocal `file:` trust、
  `TerminalPaneProcessSnapshot.childProcessId`のowning session identity、`dart_pty_macos`のnative session owner、
  Dart async `Directory.list`／`FileStat`、第1サブタスクのpane generation／cleanup contract。
- リスク: process cwdはpathというsensitive dataなので既存content-free process diagnosticsへ混ぜず、明示した
  working-directory APIだけから取得する。remote OSC authorityがあるpaneへlocal child／launch cwdを混ぜない。
  symlinkはentryとして表示してもfollowせず、1 snapshotは直下だけに限定する。Dart I/O自体を中断できない
  metadata callはlate completionをgeneration／cancel tokenで破棄し、同時実行数とdeadlineを固定する。
- 完了条件: priorityとremote拒否が決定的で、PID／session generation mismatchを受け入れず、native／fake cwd
  observationがtypedに失敗する。directory snapshotはunsafe／escape path、duplicate、permission、vanish、
  symlink、entry cap、deadline、explicit cancellationをbounded resultへ還元し、cancel後のlate resultを公開
  しない。focused tests、package native tests、format、analysis、generated freshness、full `make test`を通す。
- 検証方針: pure resolver／fake filesystem test、temporary directoryでdotfileとsymlinkを使うreal adapter test、
  `dart_pty_macos` native capabilityとDart FFI test、session fallback test、関連metadata／presentation test、full
  gateを順に実行する。native Dockが対象外なのでDeveloper JIT／Release AOTのvisual acceptanceは実行しない。

### 2026-09-14 第2サブタスク実装結果

- `dart_pty_macos` ABIをv7へ更新し、既存のcontent-free process snapshotとは別の明示的な
  `PtyProcess.workingDirectorySnapshot()`を追加した。native側はsession mutex下でstill-owned child PIDを確定し、
  `proc_pidinfo(PROC_PIDVNODEPATHINFO)`から最大4,095 UTF-8 byteのabsolute cwdを同じcallで返す。終了済み、lookup
  failure、過長pathはpathを残さずtyped system errorにする。診断event、process snapshot、loggerにはcwdを追加
  していない。
- native capability testでは初期`/private/tmp`に加え、interactive shellへ通常の`cd /`を送った後にcwd snapshotが
  `/`へ追従することを固定した。Dart package testはpluginを使わない`/bin/sh -c`の実childでもPIDとcwdが一致する
  ことを確認する。fake backendと`TerminalSession`にも同じAPIを投影し、non-live／disposed sessionはstale pathを
  返さない。
- `TerminalWorkingDirectoryResolver`はcurrent session identityを必須とし、accepted local OSC 7、同じchild PIDの
  owning-shell snapshot、trusted launch cwdの順に解決する。absolute pathをlexical normalizeし、UTF-8 byte上限、
  control、bidi、NUL、rootより上への`..`を拒否する。remote hostを持つsafe OSC 7は、別foreground processがある場合や
  same-PID kernel cwdを証明できない場合に`remoteUnavailable`とし、同名local process／launch pathを混ぜない。local shell自身が
  foregroundを保持する時だけkernel cwdを優先し、後発のuser hookがmachine hostnameを送る通常zshでもlocal treeを維持する。
- `TerminalDirectorySnapshotService`をone-shotのasync filesystem providerとして追加した。任意のtrusted rootの直下
  だけを`followLinks: false`で列挙するため、同じprimitiveをfolder展開時に呼ぶことでlazy subtreeになる。folder、
  file、symlink、otherとdotfileを保持し、folder-first／case-folded name／exact nameの順で決定的にsortする。
- 1 snapshotはretained entry 2,048、scan 4,096、retained path合計1 MiB、name 1,024 byte、symlink target
  4,096 byte、issue 128件、metadata同時実行16、既定deadline 1.5秒／最大5秒へ制限した。結果はgenerationを持つ
  immutableなcomplete／partial／unavailable／cancelled stateで、unsafe child、duplicate、permission、vanish、
  mount detach、metadata failure、各cap、deadlineをtyped issueに還元する。explicit cancelはentryを公開せず、
  Dart I/Oのlate completionも完成済み結果を変更しない。
- このone-shot層自身のcache capacityとfilesystem watcher capacityはともに0とした。hidden Dockを含むUI lifecycleに
  先行してbackground ownerを作らず、cache、event coalescing、watcherは次のnative tree ownerで別のbounded policyを
  持たせる。real temporary fixtureはtop-level snapshotでnested fileとself-loop symlinkを辿らず、subdirectoryを
  明示要求した時だけnested fileを返すことを検証する。
- real `dart:io` adapterが返すmetadataはmode、size、mtimeとsymlink targetである。owner／group IDはprovider DTO上で
  optional fieldとして固定しfake境界を検証したが、Dart `FileStat`がuid／gidを公開しないためreal adapterではnullに
  なる。native treeのdetail表示を実装する次subtaskで、main threadを塞がないnative metadata enrichmentを追加する。

#### 検証と失敗記録

- 最初の`dart analyze`でnullable PIDの比較、`dart:convert` import不足、export順序の3件を検出して修正した。test追加後
  にfake field／method名の衝突とrunner import順序も検出して修正し、以降のanalysisは指摘0になった。
- sandbox内で環境変数なしに実行した`dart format`はformat自体を終えた後、workspace外のDart telemetry session file
  のmtime更新を拒否されて停止した。以降は`CI=true DART_SUPPRESS_ANALYTICS=true`を付け、format checkは変更0、
  `dart analyze`は`No issues found!`で成功した。
- `terminal_directory_snapshot_test.dart`: 成功。authority priority／remote拒否／identity mismatch、unsafe path、
  deterministic order、dotfile、optional metadata、permission、duplicate／escape、vanish、mount detach、cancel／late
  completion、deadline、entry／path byte cap、real temporary directory、lazy subtree、symlink非追跡を検証した。
- `terminal_session_configuration_test.dart`: 成功。launch cwd、live PTY cwd、dispose後のstale拒否を検証した。
- `make dpty-native-test`: 成功。ABI/header、initial cwd、plain `cd`追従、終了後／stale handle errorを含むnative
  capability contractを通した。
- `make dpty-dart-test`: 成功。fakeと実`/bin/sh`のcwd snapshot、FFI、lifecycleを含むpackage gateを通した。
- 初回のfull gateは`terminal_application.dart`／`terminal_session.dart`のhash変更によりPhase 7 acceptance freshnessで
  停止した。`make phase7-appkit-acceptance`でreview済みsource hashだけを更新した。次回はその連鎖によるGhostty gap
  inventory freshnessで停止したため、`make ghostty-p0-p1-gap-inventory`と
  `make release-candidate-daily-use-matrix`を再生成した。判定数、gap、release blocker数は変わっていない。
- 生成後の`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。342 Dart fileのformat変更0、analysis指摘0、
  PTY／renderer／AppleScript／App Intents／compatibility／differential／application／terminfo／shell integration／
  distribution gateを通過し、最後に`dart_terminal tests passed`を確認した。
- native Dockは未実装であるためDeveloper JIT／Release AOTのvisual acceptanceはこのsubtaskでは未実施で、次の
  native side-dock subtaskへ残す。SSH／remote filesystem機能は計画どおり実装していない。

### 2026-09-14 第3サブタスク着手

- 目的: 第1サブタスクのwindow-owned stateと第2サブタスクのlocal directory providerを通常製品へ接続し、
  terminalへ重ならない右側のnative Dockとしてfocused paneのcwd、tree、selection metadataを常時参照できる
  ようにする。
- 範囲: selected tabのterminal rootを左、Dockを右に置くhideable／resizable native split、bounded width復元、
  native read-only tree surface、breadcrumb相当のtrusted cwd header、loading／empty／partial／permission／unknown／
  remote-unavailable state、folderのkeyboard lazy expand／collapse、selection detail、localization、pane／tab／window／
  cwd generation追従、snapshot cancel／cleanup、terminal viewport縮小、通常action registrationとfirst responder往復。
- 対象外: non-empty queryの実検索、recent／opened／system index、path copy／insert、Secure Keyboard Entryによる
  navigation抑止の最終統合、完成README／FEATURE_MATRIX、Developer JIT／Release AOTの最終製品受け入れ。これらは
  後続subtaskの順序を維持する。
- 依存関係: `TerminalContextDockState`／key controller、`TerminalDirectorySnapshotService`、`TerminalSession`の
  generation-bound cwd、`TerminalNativeHierarchyAdapter`のtab root／layout projection、`TwoPaneSplitView`、native
  `TextEditor`、existing action dispatcher／menu／palette／window event routing。
- 設計前提: `dart_appkit`にはoutline／search-field専用primitiveがまだない。新しいproduct固有native widgetを
  generic packageへ追加せず、既存のscrollable native `TextEditor`へDart-owned tree document、style、selected-line
  highlightをatomic projectionする。query editingはwindow key eventを第1サブタスクのkey controllerへ渡し、実検索は
  次subtaskまでtree contextを維持する。
- リスク: native tabはtabごとに`NSWindow`を持つ一方、Dock stateはlogical window ownerである。1 logical windowにつき
  1つのDock view／outer splitだけを所有し、selected native tabへだけreparentする。layout計算前にDock幅をterminal
  available sizeから差し引き、native dividerから観測した幅だけをbounded stateへ戻す。非選択tab、hidden Dock、closed
  paneへstale view／snapshotを残さない。
- 完了条件: toggle／search actionが通常製品でavailableになり、表示時だけ右Dockがterminal幅を取り、hide時は全幅を
  返す。focused pane／cwd変更で古いoperationがcancelされ、tree、dotfile、主要metadata、folder expansion、typed
  unavailable stateがgeneration-safeに投影される。Navigator ownership中のkeyはwindow routeで消費されPTYへ届かず、
  Escapeはstill-live terminal viewへ戻る。window／pane closeとshutdown後にsplit、editor、timer、snapshot ownerが残らない。
- 検証方針: pure directory-tree owner test、fake AppKitでroot decoration／width／first responder／key routing／cleanup、
  native hierarchy callback regression、localization、format／analysis／generated freshness／full `make test`を実行する。

### 2026-09-14 計画着手時

- `main`はcleanで`origin/main`と同じ`31d6634`にあり、user指定に従い
  `codex/context-file-navigator-roadmap`を作成した。
- 通常Phase 0–11と直近のpane focus拡張は完了済みで、残るunchecked項目は明示的な低優先／外部環境
  follow-upだけだった。本featureをその前の追加機能として挿入し、最初の未完了taskにした。
- current action catalogは37 stable actionを持ち、`Shift+Command+P`のCommand Paletteと
  `Option+Command+I`のTerminal Inspectorは`restoresTerminalFocusAfterInvocation: false`を使う。
  Command Palette presenterは独立した`dartOnly` key routingを持ち、close時にstill-live terminal viewを
  再解決してfirst responderを戻す。Navigatorもこのexact ownershipを一般化できる。
- native AppKit menu shortcutはraw terminal routerより先に消費され、native reservationはconfigurable
  keybindとのconflict境界になる。`Shift+Command+F`はnavigator first responder中にも動くwindow-level
  actionとして所有者を一つにする必要がある。
- current terminal key routerはapplication action、pane action、PTY encodingを区別し、schedulerがない
  application actionもfail closedで消費する。Navigator key controllerからPTY encodingへfall through
  しない別routeを追加する必要がある。
- bounded cwd/titleは既に`TerminalSessionMetadata`にあり、product authorityへの変換は
  `TerminalTabPresentationResolver.localFilePath`がlocal `file:` URIだけを許可する。既存設計はremote
  authority、filesystem probing、symlink resolutionを意図的に拒否しており、Navigatorはこのtrust境界を
  維持する。
- existing shell integrationはzsh／bash／fish／nushellでlocal OSC 7を更新するが、plain local `sh`や
  shell integrationなしでは同じ保証がない。plugin非依存のlocal fallbackにはowning processの
  content-free OS cwd観測が必要である。
- existing Services／drop pathはlocal file URLをshell literalとしてquoteし、既存paste policyへ渡す。
  Navigatorのexplicit path insertionはこのtested admissionを再利用できる。
- source inspectionはREADME、ROADMAP、FEATURE_MATRIX、action registry、Command Palette presenter、cwd
  metadata／tab presentation、key router、Phase 7／8 task memoとrepository構成を対象にした。今回は計画
  だけを変更し、product code、generated reference、README、FEATURE_MATRIXは未変更とする。

## 今回の計画変更の検証

- Markdown link、ROADMAP上の最初のunchecked task、local subtask順、既存follow-upとの順序を
  read-only commandで確認する。
- `git diff --check`でwhitespace errorがないことを確認し、差分に本memoとROADMAP以外が含まれないことを
  照合する。
- product codeを変更しないためDart test、analysis、Developer JIT／Release AOTは実行対象外とする。

### 2026-09-14 結果

- ROADMAPのunchecked項目を抽出し、local Context Dock parentと5 subtaskが先頭、その後に既存の
  低優先follow-up 3件となる順序を確認した。SSH／remote providerはuser指定によりROADMAPから外した。
- ROADMAPから本memoへのrelative linkと、設計が参照する既存source／documentの存在を確認した。
- tracked差分と新規memoのwhitespace checkは指摘0だった。変更対象はROADMAPと本memoだけであり、
  product code、generated artifact、README、FEATURE_MATRIXに差分はない。
- 今回は計画のみの変更なので、Dart test、analysis、Developer JIT／Release AOTは実行していない。

### 2026-09-14 第3サブタスク結果

#### 実装と設計判断

- `TerminalNativeHierarchyAdapter`へproduct-neutralなtab layout-size resolverとtab-root decoratorを追加した。
  hidden／非選択tabは従来のterminal rootとfull content sizeをそのまま使い、visibleなselected tabだけをterminal rootと
  read-only native `TextEditor`のhorizontal `TwoPaneSplitView`へ構成する。terminal tree自体のownership／dispose順は
  hierarchyに残し、outer splitとDock内部のvertical split、上段editor、下段details viewをContext Dock presenterが所有する。
- Dock幅はlogical windowごとに380 ptを既定値として保持し、220–640 ptへ制限した。幅不足時はterminal 240 ptを優先して
  Dockを投影せず、表示可能な場合はdivider 1 ptとDock幅をterminal available sizeから引く。native divider fractionは次の
  reconcileで読み戻してstateへ保持し、hide時はterminalへfull widthを返す。native tab切替時は1 logical windowにつき1組の
  split／editorをselected native tabへだけreparentする。
- `TerminalContextDockDirectoryController`を追加し、visibleなstandard windowのfocused paneだけについてtrusted cwdを
  generationごとに再解決する。rootは最大512件／path合計512 KiB、展開folderは1件あたり最大128件／128 KiB、paneごとの
  展開状態は32 folder、windowごとのchild snapshotも32件、flattened rowは512件へ制限した。folder展開は既存one-level
  snapshotを明示要求時だけ開始し、collapse、cwd／pane／window変更、hide、disposeで該当operationをcancelする。
- 通常のterminal outputごとに`proc_pidinfo`とdirectory projectionを同期実行しないよう、cwd再観測はcontroller-ownedの
  75 ms単一timerへcoalesceする。hierarchy mutationやDock action時は即時同期する。filesystem watcherと永続cacheはまだ
  持たず、第2サブタスクで決めたbackground ownerなしの境界を維持した。
- native documentは上段のscrollable editorへtrusted cwd、入力owner、query、folder-first tree、dotfile、folder／file／symlink／
  other marker、loading／empty／partial／unavailable／remote-unavailableを投影する。下段のfirst responderにならない固定details
  viewへ選択項目のpath／kind／mode由来permissions／size／mtime／optional uid／gid／symlink targetとpath actionを投影する。
  permission failureを含むmetadata failureは固定表示へ縮退し、terminal textやcommand injectionは使わない。
- `Shift+Command+F`のshared actionはDockを表示してnative editorへfirst responderを移し、その後にだけnavigator input
  ownershipを確定する。navigator中のwindow key eventは既存key controllerへ渡し、上下／Page Up／Page Down、query、
  `Command+Left／Right` lazy collapse／expandをPTYへ渡さない。`Escape`はshared focus action経由でstill-live focused paneの
  terminal viewへfirst responderと`appKitOnly` routingを戻す。pane／tab切替中もwindow-owned ownershipを維持する。
- 次subtaskを先取りするrecursive／system-wide search providerは実装していない。non-empty queryは現在読み込み済みtreeの
  bounded rowだけをfilterするUI projectionであり、未展開subtreeを探索しない。次subtaskでこのquery surfaceをcurrent
  subtreeからsystem-wideへ連続するsearch ownerへ差し替える。
- `TerminalDirectorySnapshotRequest`へhard maximum以下のrequest-local entry／path-byte capを追加した。既存callerのdefault
  contractは不変で、Dockだけがより小さい予算を指定する。localization auditは新しいpresenterを16番目の監査sourceとして
  登録し、production localization injection 13件を固定した。
- SSH／remote filesystem providerは追加していない。実remote foregroundのhost付きOSC 7は`remoteUnavailable`を表示し、local
  launch cwdや同名pathへfallbackしない。local owning shellのmachine hostname aliasだけはsame-PID kernel cwdで識別する。

#### 検証と失敗記録

- focused `terminal_context_dock_test.dart`: 成功。bounded width、root order、dotfile、metadata、lazy child、focused pane／cwd
  追従、remote拒否、hidden時cancel／late completionを検証した。
- focused `terminal_native_hierarchy_test.dart`: 成功。right sibling composition、terminal viewport縮小／復元、Japanese
  remote state、navigator first responderとwindow routing、Escape復帰、native divider幅保持、logical window内のnative tab
  reparent、shutdown後のnative handle 0件を検証した。
- 初回focused testはsandbox外のClang module cacheへMetal build hookが書けず停止した。承認済みのtest実行権限で再実行し、
  product failureではないことを確認した。その後test fixtureで非const constructorをconst指定したcompile errorを修正した。
  divider testではstateへ観測幅399.5 ptを保存した直後も古いimmutable snapshotの320 ptで同一reconcileをlayoutしていたため、
  native width capture後にstate snapshotを再取得するよう修正した。
- 初回full gateは新しい`localization: localization` injectionで静的監査の固定件数が変わり停止した。新presenterのcatalog
  ownership rule、必須phrase、source countと合わせて更新し、単体auditは
  `TERMINAL_LOCALIZATION_AUDIT_PASS sources=16 resource_families=4 resource_keys=21`で成功した。
- 続くfull gateはreview対象source hash変更によりPhase 7 acceptance freshnessで停止した。承認済みsource／test hashだけを
  再生成し、その依存連鎖でstaleになったGhostty gap inventoryとrelease-candidate daily-use matrixも順にcheckして再生成した。
  判定はaccepted 97、actionable P0/P1 0、release blockers 0のまま変わっていない。
- 最終`CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。343 Dart fileのformat変更0、analysis指摘0、focused testを含む
  package／native／compatibility／differential／application／terminfo／shell integration／distribution全gateを通過し、最後に
  `dart_terminal tests passed`を確認した。
- 最終確認時の`dart format`へ誤ってMarkdown 2ファイルも渡したため、Dart source 2件のformatは変更0で完了した後に
  Markdown parse errorを返した。対象をDart sourceだけに限定してfocused 3 testと`dart analyze`を再実行し、すべて成功した。
  request-local snapshot budgetも2件上限／3件入力でpartialになることとhard maximum超過拒否を追加検証した。
- Developer JIT／Release AOTの完成製品visual acceptanceは本subtaskの対象外として未実施である。system-wide search、path
  handoff、accessibilityの最終監査、privacy／performance gate、両runtime受け入れはROADMAPの後続unchecked taskに残る。

### 2026-09-14 第4サブタスク着手

- 目的: empty queryのworking-directory treeと同じlist surfaceを、文字入力だけでcurrent subtreeからwider local scopeへ
  progressiveに広がるfile／folder name searchへ切り替え、現在地以外のpathもmode選択なしで発見できるようにする。
- 範囲: bounded query parser、current cwd subtree、観測済みrecent cwd、macOS metadata index、明示fallback rootを同じ
  generation-owned operationへ統合する。source／coverage／partial／index unavailableを表示し、dedupe、deterministic ranking、
  rapid query／cwd／pane／hide cancellation、symlink非追跡、result／scan／depth／byte／deadline／process-output capを実装する。
- 対象外: file content検索、filesystem rootの常時walk、Spotlight非収録scopeの完全性保証、検索結果pathのcopy／terminal挿入、
  secure input最終統合、README／FEATURE_MATRIX、Developer JIT／Release AOTの最終受け入れ、SSH／remote search。
- 依存関係: `TerminalContextDockState` query generation、trusted local cwd、one-level snapshot service、Directory controllerの
  lifecycle、native document projection、`/usr/bin/mdfind`のshellを介さないargv／NUL-delimited output、existing typed
  filesystem metadataとpath safety policy。
- 設計判断: queryは空白区切りANDとquoted phraseをbounded tokenへparseする。まずcwdをBFSで直接探索し、次に重複しない
  recent／explicit root、最後にOS metadata indexを追加する。system index queryはbasename metadataだけへ固定してuser文字列を
  escapeし、任意predicate／shell syntaxにしない。全providerの結果はsafe absolute pathで再検証し、同一pathを一度だけ公開する。
- 完了条件: query入力でtree contextを保持したままsearch結果へ切り替わり、sourceとcoverageが段階的に見える。query clearで
  retained expansionを使うtreeへ戻る。stale／cancelled result、remote pane、hidden Dockはbackground searchを残さず、結果数は
  512以内である。index unavailableと結果0は異なるstateとなり、同順位は決定的path orderになる。
- 検証方針: fake directory／system indexでparser、progress order、ranking、dedupe、unavailable、cancel／late completion、huge
  directoryとhard capsを検証する。real `mdfind`は環境依存結果をassertせず、argv／parser adapterをfake process境界で検証する。
  focused test、format、analysis、freshness check、full `make test`を実施する。

#### 検証中の失敗記録

- 初回full `CI=true DART_SUPPRESS_ANALYTICS=true make test`は、Dart／native／compatibility／Phase 7 acceptanceを含む
  先行gateを通過した後、`RELEASE_CANDIDATE_DAILY_USE_MATRIX_FAIL`で停止した。今回追加したsearch source／testに対して
  release-candidate daily-use matrixのsource hashが古いためであり、product test failureではない。生成commandで証跡を更新し、
  freshnessを含むfull gateを再実行する。
- deadline後もUIにsearching coverageが残る差分レビュー上の不備を修正した後、sandbox内のfocused再検証はformat変更0の後、
  Dart telemetry sessionとClang Metal module cacheへの書き込み拒否でtest起動が停止した。`dart analyze`の解析本体は
  `No issues found!`だったがtelemetry更新失敗によりexit 1となったため成功扱いにせず、analytics抑止と承認済みcache権限で
  同じfocused test／analysisを再実行する。

### 2026-09-14 第4サブタスク結果

#### 実装と設計判断

- `TerminalFileSearchService`を追加し、1 operation内でcurrent cwd subtree、重複しないrecent cwd、明示された追加root、macOS
  metadata indexの順に探索する。各scope完了時とlocal walk 16 directoryごとに同じresult listをprogressive更新し、pathを
  dedupeして、basename完全一致、prefix、substring、source、depth、pathの順で決定的に順位付けする。empty queryではserviceを
  起動せず、従来のworking-directory treeを表示する。
- query parserは空白区切りANDとdouble-quoted phraseを扱い、小文字化した最大16 term、1 term 64 UTF-16 unitへ制限する。
  current／recent／explicit scopeはone-level directory snapshotをBFSで再利用し、symlinkを辿らない。全operation共通で最大512
  directory、4096 scanned entry、depth 12、512 result、retained path 1 MiB、3秒deadlineを適用する。recentとexplicitは各8 root、
  各directory listingは最大128 entry／128 KiB／500 msに制限した。
- system-wide補助には`/usr/bin/mdfind`をshellなしの固定argvで起動し、user termはbasename predicateの値としてbackslash、quote、
  wildcardをescapeする。NUL-delimited stdoutは1 MiB／256 path、1.2秒で打ち切り、返却pathはsafe normalized absolute path、
  basename、query一致、実在kindを再検証してから採用する。Spotlight unavailableは結果0と区別し、未収録scopeを完全探索したとは
  表示しない。filesystem rootをfallbackでwalkする処理は追加していない。
- Directory controllerはlogical window／focused pane／query／cwd generationにsearch operationを結び付け、query変更、pane／cwd変更、
  Dock hide、window破棄、disposeでcancelする。late progressはidentityとgenerationで拒否する。内部deadlineで終了した受理対象snapshotは
  残りのsearching coverageをpartialへ確定し、UIが永久に検索中にならない。query clear時はsearch snapshotだけを破棄し、既存の
  lazy tree expansion snapshotへ即座に戻す。
- native Dock documentは結果を同じlist／selection surfaceへ出し、Current subtree、Recent locations、Chosen locations、System indexの
  source見出しと、Searching／Complete／Partial／Unavailableのcoverageを英語／日本語で示す。検索結果をterminal inputへ挿入・実行する
  actionはまだ持たず、read-only補足情報という境界を維持した。
- SSH／remote searchは実装していない。remote working directoryではlocal fallbackや`mdfind`を起動せず、既存のremote-unavailable
  表示を維持する。

#### 検証結果と残る境界

- `terminal_file_search_test.dart`: 成功。AND／quoted phrase／term cap、metadata wildcard escape、current→recent→explicit→systemの
  progressive merge、exact-name ranking、path dedupe、local resultのindex待機中公開、index unavailableと0件の区別、misbehaving
  providerに対するaggregate 512 result cap、cancel後のlate result拒否とcoverage確定を検証した。
- `terminal_context_dock_test.dart`: 成功。expanded working-directory treeからquery searchへ切り替わり、current subtreeとsystem indexの
  結果が同じsnapshotへ統合され、query clear後に4 rowとroot expansionが復元されることを検証した。既存のfocused pane／cwd／remote／
  hidden cancellationも継続して成功した。
- localization auditは`TERMINAL_LOCALIZATION_AUDIT_PASS sources=16 resource_families=4 resource_keys=21`、focused後の
  `dart analyze`は`No issues found!`で成功した。Phase 7 freshness checkもcriteria 4、source refs 14、unit tests 12、integration tests 4、
  UI assertions 10で成功した。
- staleだったrelease-candidate daily-use matrixを管理commandで再生成した。最終
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`はDart 345 fileのformat変更0、analysis指摘0、localization／privacy／Phase 7／
  compatibility／differential／application／distributionを含む全gateを通過し、`dart_terminal tests passed`で終了した。
- 実環境のSpotlight収録内容はmachine stateに依存するため結果を固定assertしていない。shellを介さない固定executable／argvはsource review、
  query expressionとprovider contractはunit testで検証した。実際のDeveloper JIT／Release AOT UI、path handoff、accessibility、secure-input、
  privacy／performanceの最終監査は次のuncheckedサブタスクで扱う。

### 2026-09-14 第5サブタスク着手

- 目的: Directory Navigatorを参照専用surfaceから、安全な明示操作で選択pathを再利用できる完成機能へ仕上げ、keyboard-only、
  accessibility、privacy／performance、通常製品runtimeの受け入れ証跡を揃えてparent featureを完了可能にする。
- 範囲: 選択pathのplain-text copy、existing shell-literal／paste admissionを通る改行なしのterminal挿入、still-live target再解決、
  file／folder Return動作、secure-input／foreground TUIでのfail-closed availability、PTY write exactness、native accessibility projection、
  owner cleanup、generated references、README、FEATURE_MATRIX、manual checklist、focused／full gate、Developer JIT／Release AOT受け入れ。
- 対象外: 自動`cd`／Return送信、file content preview／編集、Finder起動、terminal command line読取り、remote path handoff、SSH provider、
  filesystem watcher、Linux／Windows UI、Spotlight収録範囲の保証。
- 依存関係: Context Dock state／Directory controller／native presenter、application action coordinator、selected row generation、existing
  paste／drop／Services shell-literal quotingとbracketed-paste policy、secure keyboard entry owner、alternate-screen／foreground process state、
  `dart_appkit` accessibility API、Phase 7 acceptance／localization／privacy／release-candidate evidence generators。
- 完了条件: selectionのみでは0 byte、copyはclipboardだけ、明示insertだけがsafe quoted payloadをstill-live focused local paneへexactly once
  書きterminal focusへ戻る。remote／stale／secure／TUIではinsert不可で0 byteとなる。全操作がmouseなしで到達でき、role／label／value／
  selected／focused stateが公開され、hide／close／shutdown後にnative／search ownerが残らない。文書とgenerated referenceがproductに一致し、
  focused test、format、analysis、freshness、full `make test`、Developer JIT／Release AOT scenarioが成功する。
- 検証方針: fake clipboard／terminal write／first responder／secure-input／alternate-screenでcopy・insert・stale target・exact payload・0-byte経路を
  固定する。fake AppKit accessibilityとteardownを検証し、bounded searchのlatency／operation／retained-state contractをprivacy auditへ追加する。
  最後に通常productを両runtimeで起動し、cwd tree、search、keyboard往復、path handoff、resize、cleanupを同じscenarioで記録する。

#### 途中検証と失敗記録

- `DART_SUPPRESS_ANALYTICS=true dart format ...`は対象9ファイルのformatを完了した後、SDK telemetryの
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`更新がworkspace sandboxに拒否されて終了code 1に
  なった。source format自体は完了しており、同じ制約を受ける解析とtestは許可済みnative cache環境で再実行した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: `No issues found!`。
- `terminal_context_dock_test.dart`と`terminal_native_content_test.dart`のfocused実行: 成功。
- 最初のDeveloper JIT native-content acceptanceはplain `sh`のcwd markerまでは進んだが、fixtureが
  `/var/folders/...`、kernel cwd capabilityがcanonical `/private/var/folders/...`を返したため文字列比較で停止した。
  filesystem ownerの誤りではなくmacOS temp path aliasをfixtureが正規化していなかったことが原因であり、作成直後に
  `resolveSymbolicLinksSync()`した実体pathをfixture全体のauthorityにして再実行する。
- 2回目のDeveloper JIT acceptanceはcanonical cwd観測を通過した後、search action availabilityで停止した。
  processのECHOは既にonだったがSecure Keyboard Entry projectionが直前のzsh stateを保持しており、fixtureがprocess state変化後の
  product reconcileを省略していたことが原因だった。通常製品と同じreconcileを明示してsecure／Dock projectionを揃えてからactionを
  dispatchするよう修正した。
- 3回目はplain `sh`移行直後のECHO-on待機が不定に失敗した。interactive zshがline editor用に変更したtermiosを
  `exec /bin/sh -i`へ引き継ぐタイミングへ依存していたため、plain-shell fixture境界で`stty echo icanon`を明示してOS cwd fallbackを
  検証する前提を決定的にした。これは製品processへhidden commandを送る実装ではなく、明示されたruntime test fixture内だけの設定である。
- 4回目の診断で、plain `sh`も次のpromptを読み始めるとECHO-offへ戻ることを実確認した。ECHO-offだけをprivacy signalにすると
  zsh／shの通常line editingでもNavigatorが常時使用不能になるため、判定を精密化した。explicit manual Secure Keyboard Entryは
  process stateにかかわらず遮断し、automatic ECHO-offはowning-shell commandまたは別foreground processの時に遮断する。idle shellの
  line editingだけは観測を許可する。runtime privacy fixtureはECHO-off foreground `sleep`中にsnapshot／operationを消すことで、password
  helper／TUI相当のfail-closed境界を検証する。
- privacy policy精密化後のDeveloper JIT acceptanceはtree、search、native read-only document、raw path copy、Option-Returnの1 writeまで
  成功したが、exact path判定で停止した。command line自体に`__DT_NAV_PATH_MISMATCH__`というfixture文字列を含めていたため、成功branchの
  出力とcommand表示を区別できない誤検出だった。markerを`%s`引数で分割し、実行結果だけがcomplete markerになるよう修正した。
- marker分割後はcomplete markerが出ず、zshから`exec sh`したfixtureがDEC bracketed-paste modeを解除していないことを確認した。
  Navigator insertionは既存paste transportに従って正しくbracket wrapperを付けた一方、plain shはその制御列を編集機能として解釈しない。
  shell切替fixtureが`CSI ? 2004 l`を明示し、emulator stateと受け手shell capabilityを一致させるよう修正した。
- bracketed-paste解除後も成功markerが出なかったためfixture commandを再確認し、inserted pathとtest終端`]`の間の空白が欠けていたことを
  発見した。path payloadはexactly onceで正しく届いており、後続fixture suffixだけが`'/path']`という別operandを作っていた。終端前の
  空白を修正し、shell-literal結果そのものを判定できる形にした。
- 空白修正後はexact pathとforeground ECHO-off privacy消去まで成功し、復帰時の`echo == true` assertionだけが停止した。plain shは
  fixture内でECHOを戻した後、次のidle prompt用line editingで再びECHO-offにするためである。精密化したproduct policyどおり、復帰条件は
  `idleShell`へ変更し、その状態でsearch actionが再び有効になることを後続dispatchで検証する。
- 文書／監査更新後の最初のlocalization auditは、catalogが実際に使うmacOS glyph表記`⌘C`／`⌥↩`に対し、audit側で
  `Command-C`／`Option-Return`という別表記を要求したため停止した。catalog/UIは変更せず、監査tokenを実際のlocalized copyへ一致させた。
- Phase 7 acceptanceへ第5 criteriaを追加した後、daily-use matrix generatorがcriteria数4を固定していたため、生成前の
  evidence validationで停止した。Phase 7 generator testの期待markerとdaily-use側のschema assertionをcriteria数5／新しい
  source・test・UI assertion数へ更新し、古いacceptance shapeを誤って受理しないようにした。

### 2026-09-14 第5サブタスク結果

#### 実装と設計判断

- `TerminalContextDockPathHandoffController`を追加した。Command-Cはnavigatorが保持するgeneration-boundな選択entryの
  absolute pathだけをclipboardへ書き、PTYへ送らない。Option-Returnは選択とactive window／focused pane／live ownerを再解決し、
  existing file-path admission、shell-literal quoting、paste transportを通した1 pathだけを改行なしで送る。paste完了後にshared
  `view.focus-terminal` actionでterminalへ戻るため、stale focusを独自に推測しない。
- insertionはlocal idle shellだけで有効にした。remote／unknown cwd、stale target、manual secure input、alternate screen、owning-shell
  command／別foreground process、busy／disposedではfail closedにし、選択やReturnだけでは`cd`、改行、commandを送らない。copyもmanual
  secure input中は無効にし、protected pathをclipboardへ出さない。通常foreground中のcopyは明示clipboard操作として残すが、ECHO-offで
  privacy policyが発動した時点で選択snapshot自体が消える。
- privacy policyはexplicit manual secure inputと、ECHO-offのowning-shell command／foreground processを保護対象にする。通常のinteractive
  zsh／shがidle line editingでECHOを無効にする状態は観測可能とし、Navigatorが常時使用不能になる誤判定を避ける。保護状態へ入ると進行中
  tree／searchをcancelし、cwd、rows、detailを破棄した`privacyUnavailable`へ置き換え、terminal first responderを復元する。
- read-only native `TextEditor`のvalueとselectionへtitle、input owner、cwd、query、source／coverage、tree/search row、path action
  availability、detailをvisual orderどおり投影した。navigator focus中のselected rowとquery selectionを標準native accessibility stateで
  公開し、hide／window close／shutdownではpath handoff、search、directory、native editor/split ownerの順序付きcleanupへ統合した。
- runtime native-content scenarioを拡張し、実zshからplain interactive `sh`へ移行してOS cwd fallback、dotfileを含むtree、search、read-only
  native document、raw path copy、apostropheを含むquoted pathのexactly-once insertion、alternate-screen 0 write、ECHO-off foreground中の
  privacy消去、idle復帰、Escapeでquery保持、全owner回収を同じ通常製品上で検証する。fixtureはshell capabilityに合わせてbracketed-pasteを
  明示解除するが、製品からhidden commandを注入する経路は追加していない。
- README、FEATURE_MATRIX、English／Japanese catalog、localization／diagnostics privacy audit、Phase 7 acceptance、runtime marker、manual
  checklistを完成機能へ合わせた。一般diagnostics/exportのallowlistへcwd、query、file名、path、metadata、coverageは追加していない。
  directory/searchは既存のentry／byte／depth／deadline capとgeneration cancellationを維持し、path handoffは1 path／1 MiB以内かつ既存の
  bounded paste transportだけを使う。SSH／remote providerは計画どおり実装・追跡していない。

#### 検証結果と残る外部確認

- format: 346 Dart file、変更0。`CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: `No issues found!`。
- focused: `terminal_context_dock_test.dart`、`terminal_native_content_test.dart`、`terminal_diagnostics_privacy_audit_test.dart`、
  `phase7_appkit_acceptance_test.dart`が成功した。path copy／insert、apostrophe／空白quote、stale／remote／secure／alternate／foreground／busy、
  terminal focus、0-byte routing、idle-shell privacy exception、native read-only projectionとcleanupを含む。
- static/generated: keybind referenceは105 key、4 pane action、40 application action、9 standard binding、14 reserved shortcutでfresh。
  localization auditは16 source／4 resource family／21 resource key、privacy auditは190 schema key／10 owner／11 top-level keyで成功した。
  Phase 7 acceptanceは5 criteria／19 source reference／16 unit test／5 integration test／11 UI assertionで成功した。
- runtime: `make RUNTIME_ARCH=arm64 developer-jit-native-content`は
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS ... navigator=true exact_pty=true sessions=4 elapsed_ms=5434`、
  `make RUNTIME_ARCH=arm64 release-aot-native-content`は同markerで`elapsed_ms=4143`として成功した。どちらもnative architectureで実
  AppKit／PTY／Metalと4 session cleanupを通した。
- generated dependency chainはcompatibility regression coverage、Ghostty P0/P1 gap inventory、release-candidate daily-use matrixを正規
  generatorで更新した。判定はactionable P0/P1 0、release blocker 0のままである。最終
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`は全native／Dart／compatibility／application／distribution gateを通過し、
  `dart_terminal tests passed`で終了した。
- VoiceOverの読み上げ品質、Full Keyboard Accessの実focus ring、Light/Dark・Increase Contrast・Differentiate Without Color・Reduce
  Motionの視認性はOS UIを人が判断する外部確認である。自動acceptanceを完了条件の根拠としつつ、実機確認手順とprivacy-safeな記録条件を
  [`context-dock-directory-navigator-manual-checklist.md`](context-dock-directory-navigator-manual-checklist.md)へ残した。これは未実装作業や
  release blockerではなく、環境依存の補助確認である。
