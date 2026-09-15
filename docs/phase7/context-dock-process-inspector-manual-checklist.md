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
3. Option-Shift-Cで右側のContext Dockを表示し、idle時に`Directory Navigator`が表示されることを確認する。
4. VoiceOverまたはAccessibility Inspectorを使う場合も、画面収録、terminal diagnostics export、argvの転記は
   行わない。

## 表示切替とlayout

- [ ] `/bin/sleep 5`を実行すると75 ms後に見出しが`Directory Navigator`から`Process Inspector`へ変わり、
  command終了後はfreshなDirectory Navigatorへ戻る。短い`/usr/bin/true`では表示が点滅しない。
- [ ] Process Inspector上段には`Foreground job`、経過時間、process数、process名が表示され、経過時間が
  およそ1秒ごとに進む。更新のたびに選択、scroll位置、divider位置が飛ばない。
- [ ] `/bin/sh -c 'sleep 5' | /bin/cat`では複数processを同じjobとして表示し、上段だけがscrollする。
  下段のDetailsは固定されたままで、primary executable、process argv、PID、PGIDを確認できる。
- [ ] Process Inspectorにはworking directory、Directory Navigatorのtree、Path actions、Search queryを混在させない。
- [ ] 狭いwindow、Dock幅変更、上下divider移動、fullscreenでもterminalへ重ならず、上段と固定detailsの最小高を
  保つ。長いargvはDock外へ描画せず、truncation／partial／omitted状態を文字で区別できる。
- [ ] command実行中にDockを隠して再表示すると、非表示中の古い内容を一瞬復元せず、現在のjobを再観測する。

## Terminal inputとkeyboard-only操作

- [ ] `/bin/cat`を実行中もterminalがinput ownerであり、入力した安全なfixture文字列が通常どおり届く。
  Control-Dで終了するとDirectory Navigatorへ戻る。
- [ ] Process Inspector表示中のShift-Command-F、Shift-Command-G、Shift-Command-Mはbeepせず、query caretを出さず、
  terminalへ文字やescape sequenceを送らない。command終了後は同じshortcutでNavigatorへ移れる。
- [ ] Option-Shift-CはProcess Inspector表示中もDockだけを開閉し、foreground commandを停止・変更しない。
- [ ] terminalの通常入力、Control-C、scroll、selectionはProcess Inspector表示中も従来どおり機能する。
- [ ] shell builtinまたはshell integrationがprocess argvを安全に特定できないcommandでは、`Shell command running`
  と観測経過時間だけを表示し、shell入力文字列を推測してDetailsへ出さない。

## Privacy、focus、lifecycle

- [ ] `stty -echo; /bin/sleep 3; stty echo`のECHO-off foreground区間では`Protected input`へ切り替わり、
  直前のexecutable／argv／process listが上下どちらにも残らない。ECHO復帰後はDirectory Navigatorを再取得する。
- [ ] manual Secure Keyboard Entryを有効にした場合も同様にcontentを破棄し、解除までNavigator shortcutを
  利用できない。
- [ ] command実行中に別pane、tab、windowへfocusを移すと、Dockは新しいfocused paneだけを反映し、旧jobの
  executable／argvを表示しない。appを非activeにした間も旧contentを保持・再表示しない。
- [ ] pipeline leaderが先に終了する、process数が上限を超える、権限によりpath／argvの一部が読めない場合も、
  UIは操作可能なままpartial／omittedを表示し、Directoryの`unknown`とは混同しない。
- [ ] tab/window close、Dock hide、app Quit後にpoll timer、process observation、PTY、native text view、
  Secure Keyboard Entry ownerが残らない。

## VoiceOverと記録

- [ ] VoiceOverは`Process Inspector`をterminalと別のsiblingとして読み、上段でstate、elapsed、process countと
  member、下段でexecutable、process argv、PID／PGIDをvisual orderどおり読める。
- [ ] 上下ともread-onlyと伝わり、terminalだけがinput focusを持つ。1秒更新ごとにfocus通知や文書全体の
  読み上げを強制せず、利用者が現在位置を保てる。
- [ ] Englishでは`Process Inspector`、Japaneseでは`プロセスインスペクタ`と表示され、
  `Directory Navigator`／`ディレクトリナビゲータ`とは別の名前として区別できる。
- [ ] 結果記録にはprocess名、path、argv、PID、PGID、cwd、terminal outputを含めず、pass/failとcontent-freeな
  操作・visible stateの要約だけを残す。
