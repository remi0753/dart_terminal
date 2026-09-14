# Context Dock and file/folder navigator roadmap

- Status: planned
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
`view.focus-terminal`で1操作のうちにterminalへ戻る契約を先に固定する。

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

- Context Dockはterminalの上へ重ならず、windowの右側でterminal contentと並ぶ。hide時はterminal
  が空いた幅を取り戻し、再表示時は利用者が最後に選んだbounded widthを復元する。
- Dockはwindowごとに1つだけ所有し、selected tabのfocused live paneへ追従する。paneごとのtree
  expansion、browse location、query、selection、scroll位置はbounded stateとして保持し、pane close
  と同時に解放する。
- headerは対象pane、trusted working directory、local／remote／unknown capabilityを常に示す。
  breadcrumbからparent、back、forward、working directoryへkeyboardで戻れる。
- queryが空ならworking directoryをrootにしたfile＋folder treeを表示する。dotfileも既定で表示し、
  folderはlazy展開する。rowは名前と種類を優先し、選択entryのpermission、owner／group、size、mtime、
  symlink targetなどは下部のcompact detailへ置く。読めないentryは消さず理由を示す。
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
| Terminal owns input | `Shift+Command+F` | Dockを表示しqueryへfocus、queryを全選択 | 0 byte |
| Navigator owns input | printable／Delete／Command+A | queryを編集して結果を更新 | 0 byte |
| Navigator owns input | Up／Down、Page Up／Down | result selectionだけを移動 | 0 byte |
| Navigator owns input | Command+Left／Right | tree時だけfolderをcollapse／expand | 0 byte |
| Navigator owns input | `Escape`または`view.focus-terminal` | 現在のstill-live focused paneをfirst responderへ戻す | 0 byte |

追加の契約:

- `Shift+Command+F`はstable action `view.search-files-and-folders`としてView menu、Command
  Palette、keybind referenceで共有する。native shortcutがどのfirst responderからもexactly onceで
  捕捉し、terminal bytesへfall throughしないようにする。
- Navigatorで再度`Shift+Command+F`を押した場合はqueryを全選択するだけで、terminalへtoggleしない。
  戻る方向は別の`view.focus-terminal` actionへ固定し、同じchordの状態依存挙動を避ける。
- `Escape`はquery clearを先に要求せず、常に1回で`view.focus-terminal`を実行する。Dock、query、
  results、selectionは残り、次の`Shift+Command+F`で同じ調査へ戻れる。
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

- selectionだけではterminalへbytesを送らない。ReturnはfolderをDock内でbrowse／expandし、fileは
  detailを開く。terminal processのcwdを暗黙には変更しない。
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
  しない。同名local pathへfallbackしない。
- PTYへhidden `find`／`ls`／`pwd`を注入する、shell promptやcommand outputをscreenからscrapeする、
  password／agent credentialを取得する方式は採用しない。alternate screen、running command、shell差、
  quoting、scrollback汚染のいずれにも安全な一般解にならないためである。
- remote navigationはlocal navigator完了後の独立ROADMAP itemとする。明示したside-channel provider
  （例: user-approved SFTP／remote helper capability）だけがconnection identity、authentication owner、
  cancellation、path encoding、permission、disconnectを宣言して参加できる。capabilityがなければDockは
  `Remote filesystem unavailable`を表示し、local resultを混ぜない。

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
- Secure Keyboard Entry: ECHO-offまたはsecure-input ownerがactiveな間はnavigator focusとpath insertionを
  unavailableにし、terminal first responderを保持する。Dockの既存snapshotは更新を止め、privacy-safeな
  unavailable stateを表示する。
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
6. **SSH／remote session向けexplicit directory provider（別ROADMAP item）**
   - local featureの完了後にremote connection authorityとtransportを別task memoへ具体化する。screen
     scrapeやhidden PTY commandを使わず、local／remote resultの混在0を最初の受け入れ条件にする。

各subtaskは上記順に実装、検証、記録、ROADMAP更新、commitする。先行subtaskが完了するまで次へ
進まない。remote itemはlocal parentを完了してから着手する。

## 完了条件

- Dockの表示／非表示とinput ownerが独立し、どちらがkeyを受け取るかをvisual stateとaccessibility state
  の両方で常に判別できる。
- `Shift+Command+F`はどのterminal paneからも検索へ移り、Up／Downはnavigator selectionだけを動かす。
  `Escape`／`view.focus-terminal`は1操作で現在のstill-live terminalへ戻り、queryを失わない。
- Navigator focus、検索、tree操作、dismiss、stale target、secure input unavailableの全経路で意図しない
  PTY writeが0である。quoted path insertionだけが明示actionのexact payloadを1回送る。
- focused local paneのtrusted cwd、dotfileを含むtree、lazy subtree、主要metadataが表示され、pane／tab／
  cwd changeへgeneration-safeに追従する。unknown／permission denied／remoteをlocal pathとして偽装しない。
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
- remote itemではfake provider、disconnect／reconnect、permission、host identity change、path encoding、auth
  cancellation、local result混在0を先に固定し、実remote受け入れはcredentialをrepositoryへ保存しない
  manual／opt-in gateへ分離する。

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

- Markdown link、ROADMAP上の最初のunchecked task、subtask順、remote dependency順をread-only commandで
  確認する。
- `git diff --check`でwhitespace errorがないことを確認し、差分に本memoとROADMAP以外が含まれないことを
  照合する。
- product codeを変更しないためDart test、analysis、Developer JIT／Release AOTは実行対象外とする。

### 2026-09-14 結果

- ROADMAPのunchecked項目を抽出し、local Context Dock parentと5 subtaskが先頭、その直後に依存する
  remote provider、続いて既存の低優先follow-up 3件となる順序を確認した。
- ROADMAPから本memoへのrelative linkと、設計が参照する既存source／documentの存在を確認した。
- tracked差分と新規memoのwhitespace checkは指摘0だった。変更対象はROADMAPと本memoだけであり、
  product code、generated artifact、README、FEATURE_MATRIXに差分はない。
- 今回は計画のみの変更なので、Dart test、analysis、Developer JIT／Release AOTは実行していない。
