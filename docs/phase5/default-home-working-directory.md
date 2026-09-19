# Phase 5 — default fresh-session working directory

## 目的

設定、復元状態、または既存paneから継承するworking directoryがないfresh terminalを、
アプリprocessのcurrent working directoryではなくログインユーザーのhome directoryから
開始する。Finder、Dock、公証済みdistribution bundleから起動した場合も`/`ではなく
`~`をDirectory NavigatorとPTYの初期working directoryにする。

## 背景

2026-09-20時点の`TerminalOptions.parse`は、`working-directory`が未設定なら
`initialWorkingDirectory`へ`null`を保持する。`TerminalSession`はその`null`を
`Directory.current.path`へfallbackするため、LaunchServicesがアプリを`/`から起動した
distribution経路ではshellも`/`から開始する。

## 範囲

- 未指定のfresh terminalについて、起動environmentのユーザーhomeを初期working directoryにする。
- `working-directory`のfile／CLI設定を引き続き最優先にする。
- 復元pane、Finder Service、AppleScript、既存paneからのtab／split cwd継承を変更しない。
- product option解決とsession境界の双方で、process cwd `/`を模した回帰testを追加する。
- READMEと生成configuration referenceにzero-configの既定値を反映する。

## 対象外

- 実行中shellの`cd`、OSC 7、kernel cwd観測、Directory Navigatorの更新方針。
- home directoryを選択する設定UI、sandbox containerへの移行、SSH／remote cwd。
- explicitな`working-directory`、復元cwd、Service／AppleScript指定cwdの存在確認方針の変更。

## 依存関係

- `TerminalOptions.parse`のenvironment／currentDirectory injection。
- `TerminalSession`のPTY launch working-directory contract。
- `TerminalProductConfigSchema.workingDirectory`のnew-session優先順位。
- macOSの通常起動environmentが提供する絶対`HOME`。

## 完了条件

- `HOME=/Users/example`、process cwd `/`相当、設定未指定ならfresh session cwdが
  `/Users/example`になる。
- 明示した`working-directory`はhome既定値を上書きする。
- homeが利用不能な異常environmentでは既存の絶対process cwd fallbackを維持し、起動を壊さない。
- unit／product-level regression、静的解析、format、arm64 Developer JIT／Release AOT buildが成功する。
- 変更内容と検証結果を本書へ記録し、ROADMAPを完了へ更新して単独commitにする。

## 検証方針

- config integration testで未指定、explicit file／CLI、HOME欠落を決定的に検証する。
- session configuration testでinitial path未指定時のenvironment HOME採用とexplicit path優先を検証する。
- 通常test suiteと静的解析を実行する。
- Developer JIT／Release AOT bundleをbuildし、可能ならprocess cwd `/`相当で通常product経路を起動して
  shell／Directory Navigatorの初期cwdを観測する。

## 調査記録

### 2026-09-20 — 初期経路

- `bin/main.dart`の配布entry pointは`TerminalOptions.parse(arguments)`を使う。
- `TerminalOptions.parse`は設定snapshotのnullableな`working-directory`をそのまま
  `initialWorkingDirectory`へ保存する。
- `TerminalSession`は`initialWorkingDirectory ?? Directory.current.path`をPTY起動cwdにする。
- normal hierarchyのfresh windowはoptionsの初期値を使い、tab／splitは設定値、focused paneの
  trusted cwd、pane launch cwd、process-wide初期値の順に解決する。この継承優先順位は維持する。
- config loaderは既に同じ起動environmentの`HOME`をdefault config path解決に使用している。
- 採用仮説は、非空かつabsoluteな`HOME`をzero-config fresh-session既定値とし、欠落または
  relativeな異常値だけ絶対process cwdへfallbackすることである。session境界にも同じresolverを
  適用し、直接構築経路がprocess cwdへ退行しないようにする。

### 2026-09-20 — 実装判断

- `resolveTerminalDefaultWorkingDirectory`を単一のresolverとして追加した。起動environmentの
  `HOME`が非空、absolute、かつ実在directoryならそれを返し、異常environmentだけprocess cwdの
  absolute pathへfallbackする。symlinkの実体解決は行わず、ユーザーに見えるhome pathを保つ。
- `TerminalOptions.parse`はconfig file／CLIの`working-directory` winnerを先に採用し、未指定時だけ
  resolverを使う。これによりnormal hierarchyがfresh windowへhomeを明示的に引き渡す。
- `TerminalSession`にも同じfallbackを置いた。`TerminalOptions.parse`を通らない直接構築経路でも、
  explicit launch cwdがなければshell launch planまたはsession environmentの`HOME`をPTY commandへ渡す。
- 復元、Finder Service、AppleScript、tab／split inheritanceは既にnon-nullなlaunch cwdを渡すため、
  resolverを通って上書きされない。
- schemaのdefault値自体はenvironment非依存の`null`を維持し、説明を「unsetはuser home」に更新した。
  README、生成configuration reference、feature matrixも同じcontractへ同期した。

### 2026-09-20 — 検証と結果

- `dart run test/terminal_config_test.dart`: 成功。process cwd `/`相当でも実在するabsolute `HOME`を
  選び、relative HOMEではabsolute process cwdへfallbackし、既存のfile／CLI winnerを維持した。
- `dart run test/terminal_session_configuration_test.dart`: 初回は追加testの`dart:io` import不足で
  compile failureになった。import追加後は成功し、session propertyとfake PTY commandの双方が
  HOMEを受け取ることを確認した。
- sandbox内の単独`dart format`は対象6 fileを変更なしと判定した後、workspace外のDart telemetry
  log削除権限で失敗した。通常ユーザー権限の最終`make test`に含まれるformat gateを正本とした。
- `make phase7-appkit-acceptance`、`make terminal-compatibility-regression-coverage`、
  `make ghostty-p0-p1-gap-inventory`、`make release-candidate-daily-use-matrix`を実行した。生成差分は
  今回変更したsource、README、feature matrixと、それらを参照する証跡のSHA-256更新だけだった。
- `make test`: 最終実行成功。351 fileのformat変更0、`dart analyze`は`No issues found`、native package、
  configuration reference、AppKit acceptance、compatibility、distribution policy、全Dart testが成功した。
- `make RUNTIME_ARCH=arm64 developer-jit-build release-aot-build`: 成功。
  `build/runtime/arm64/developer-jit/DartTerminal.app`と
  `build/runtime/arm64/release-aot/DartTerminal.app`を生成し、両Info.plist検証とbundle署名が成功した。
- 公証serviceを再利用するsigned distribution buildは行っていない。distributionと同じ`bin/main.dart`、
  `TerminalOptions.parse`、Release AOT application codeを上記buildと回帰testで検証した。

## 残課題

- 本修正に関する残作業はない。異常に`HOME`が欠落、relative、または存在しない環境だけは、
  起動不能にせずabsolute process cwdへfallbackする。
