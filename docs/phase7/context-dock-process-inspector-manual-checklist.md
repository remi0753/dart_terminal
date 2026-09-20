# Process Inspector manual acceptance checklist

- Status: manual verification checklist
- Date: 2026-09-16
- Scope: macOS standard windowのContext Dock／local foreground process表示
- Automated companion: `make RUNTIME_ARCH=arm64 runtime-native-content-integration`

この確認票は、自動testだけでは評価できないProcess Inspectorの視認性、VoiceOverの読み上げ品質、
keyboard-only操作を確認する。実行command、path、argv、terminal outputの写しは結果へ記録せず、OS version、
architecture、Developer JIT／Release AOT、pass/failとcontent-freeな失敗概要だけを残す。

## 対象と準備

1. token、password、個人情報を含まないlocal fixtureだけを使う。SSH／remote process introspectionは対象外とする。
2. Developer JITは`make RUNTIME_ARCH=arm64 developer-jit-run`、Release AOTは
   `make RUNTIME_ARCH=arm64 release-aot-run`で起動し、両方で同じ項目を確認する。
3. 初期表示trueの右側Context Dockでidle時に`Directory Navigator`が表示されることを確認する。
   非表示設定の場合だけOption-Shift-Cで表示する。
4. VoiceOverまたはAccessibility Inspectorを使う場合も、画面収録、terminal diagnostics export、argvの転記は
   行わない。

## 表示切替とlayout

- [ ] `/bin/sleep 5`を実行すると75 ms後に見出しが`Directory Navigator`から`Process Inspector`へ変わり、
  command終了後はfreshなDirectory Navigatorへ戻る。短い`/usr/bin/true`では表示が点滅しない。
- [ ] Process Inspectorには`Foreground job`、経過時間、process数、process名が表示され、経過時間が
  およそ1秒ごとに進む。更新のたびに選択、scroll位置、divider位置が飛ばない。
- [ ] `/bin/sh -c 'sleep 5' | /bin/cat`では複数processを同じjobとして表示し、同じ全高のscroll領域で
  primary executable、process argv、PID、PGIDも確認できる。独立したProcess Details欄と上下dividerはない。
  `Directory Navigator is available...`の案内はEnglish／Japaneseのどちらにも表示しない。
  `Each quoted token is...`の引数説明もEnglish／Japaneseのどちらにも表示せず、argvの引用符自体は維持する。
  command終了後はDirectory Navigatorの一覧と下端の固定file／directory詳細欄が復元される。
- [ ] Process Inspectorにはworking directory、Directory Navigatorのtree、Path actions、Search queryを混在させない。
- [ ] 狭いwindow、Dock幅変更、fullscreenでもterminalへ重ならず、Process InspectorだけがDock全高を使う。
  長いargvはDock外へ描画せず、truncation／partial／omitted状態を文字で区別できる。
- [ ] Process Inspectorのfont／size／background／foreground／opacityもfocused terminalと一致し、通常文字色のopaqueな境界は常に見える。
  opacityを0／0.5／1へreloadしても、viewportと余白の背景alphaが同じままでscrollによる重複合成がない。
  Light／Dark／custom palette／pane切替／live opacity更新でscrollやinput ownerがリセットされない。
- [ ] command実行中にDockを隠して再表示すると、非表示中の古い内容を一瞬復元せず、現在のjobを再観測する。

## Terminal inputとkeyboard-only操作

- [ ] `/bin/cat`を実行中もterminalがinput ownerであり、入力した安全なfixture文字列が通常どおり届く。
  Control-Dで終了するとDirectory Navigatorへ戻る。
- [ ] Process Inspector表示中のShift-Command-F、Shift-Command-G、Shift-Command-Mはbeepせず、query caretを出さず、
  terminalへ文字やescape sequenceを送らない。command終了後は同じshortcutでNavigatorへ移れる。
- [ ] foreground job実行中にControl-Shift-Command-Nを押すとDirectory NavigatorのMove modeへfocusし、上下／Page移動、
  ReturnまたはCommand-Right／Leftによるfolder展開・折り畳み、Shift-Command-F／G／M、hidden切替、手動refreshが
  terminal write 0で動作する。同じキーで同一jobのProcess Inspectorへ戻り、terminal inputも復元する。
  job終了後と次のjobでは自動表示policyへ戻る。
- [ ] `node` REPLなどECHO-offのProcess InspectorでもControl-Shift-Command-Nが有効で、command開始前のtreeを
  interactiveに再開する。表示中だけSearch／Go To／Move、展開、hidden切替、手動refreshがboundedに動き、
  Process Inspectorへ戻るとfilesystem operationを停止する。foreground processへのOption-Return挿入は拒否し、
  終了後の一回refreshで最新状態へ戻る。
- [ ] ECHO-offのProcess Inspector表示中に別applicationへfocusを移して戻っても、同じjobなら
  Control-Shift-Command-Nで保持treeへ切り替わる。非active中にDirectory内容を投影せず、session／PGIDが
  変わった場合は古いtreeを表示しない。
- [ ] foreground jobのpaneから同じwindow内の別split pane／tabへ移動中は、旧paneのprocess詳細／poll／filesystem
  operationを持たない。元paneへ戻った時、同じsession／PGIDならProcess Inspectorから保持treeへ切り替えられる。
  別windowへの移動、tab／pane close、app非active中の別tab cache、session／PGID変更後は古いtreeを表示しない。
- [ ] Option-Shift-CはProcess Inspector表示中もDockだけを開閉し、foreground commandを停止・変更しない。
- [ ] View > Show Process Arguments（日本語: プロセスの引数を表示）のcheckを外すとargvだけが非表示となり、
  process名、実行ファイル、PID／PGID、経過時間は維持される。Shift-Command-Pから同じactionを検索し、
  Returnで再表示できる。再取得中の表示後にfreshなargvが戻り、terminalに文字を送らない。
- [ ] argv非表示はECHO状態／Secure Keyboard Entryから独立し、新commandや別paneでも維持される。
  VoiceOverでも非表示のargvや引数の省略／truncation情報を読み上げない。
- [ ] terminalの通常入力、Control-C、scroll、selectionはProcess Inspector表示中も従来どおり機能する。
- [ ] shell builtinまたはshell integrationがprocess argvを安全に特定できないcommandでは、`Shell command running`
  と観測経過時間を表示し、shell入力文字列を推測して出さない。

## Privacy、focus、lifecycle

- [ ] `stty -echo; /bin/sleep 3; stty echo`のECHO-off foreground区間でもProcess Inspectorを表示し、
  executable／argv／process listを確認できる。終了後はDirectory Navigatorを再取得する。
  Nodeを利用できる場合は`node`のREPLでも同じ表示を確認する。
- [ ] manual Secure Keyboard Entryを有効にしても実行中process情報は表示され、入力保護indicatorは維持される。
  Process Inspector表示中のNavigator shortcutは入力を奪わない。Control-Shift-Command-Nで明示的にDirectoryへ
  切り替えた時だけNavigatorがinputを所有し、path挿入は引き続き拒否する。
- [ ] command実行中に別pane、tab、windowへfocusを移すと、Dockは新しいfocused paneだけを反映し、旧jobの
  executable／argvを表示しない。同じwindow内のsplit pane／tab round trip用に保持するのは非投影のtreeと
  照合identityだけで、app非active中や別pane／tab表示中にprocess詳細を保持・再表示しない。
- [ ] pipeline leaderが先に終了する、process数が上限を超える、権限によりpath／argvの一部が読めない場合も、
  UIは操作可能なままpartial／omittedを表示し、Directoryの`unknown`とは混同しない。
- [ ] tab/window close、Dock hide、app Quit後にpoll timer、process observation、PTY、native text view、
  Secure Keyboard Entry ownerが残らない。

## VoiceOverと記録

- [ ] VoiceOverは`Process Inspector`をterminalと別のsiblingとして読み、一つの文書でstate、elapsed、process countと
  member、executable、process argv、PID／PGIDをvisual orderどおり読める。空の下段詳細文書を読み上げない。
- [ ] Process Inspectorがread-onlyと伝わり、terminalだけがinput focusを持つ。1秒更新ごとにfocus通知や文書全体の
  読み上げを強制せず、利用者が現在位置を保てる。
- [ ] Englishでは`Process Inspector`、Japaneseでは`プロセスインスペクタ`と表示され、
  `Directory Navigator`／`ディレクトリナビゲータ`とは別の名前として区別できる。
- [ ] 結果記録にはprocess名、path、argv、PID、PGID、cwd、terminal outputを含めず、pass/failとcontent-freeな
  操作・visible stateの要約だけを残す。
