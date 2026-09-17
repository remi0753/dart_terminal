# Directory Navigator manual acceptance checklist

- Status: manual verification checklist
- Date: 2026-09-14
- Scope: macOS standard windowのContext Dock／Directory Navigator
- Automated companion: `make RUNTIME_ARCH=arm64 runtime-native-content-integration`

この確認票は、APIから判定できないVoiceOverの読み上げ品質、Full Keyboard Accessの実際のfocus ring、
外観設定、resize/fullscreenの視認性を確認する。terminal text、command、path、clipboard内容を記録せず、
確認結果にはOS version、architecture、Developer JIT／Release AOT、pass/failだけを残す。

## 準備

1. local standard windowを開き、空白、apostrophe、Unicode、dotfile、folder、symlinkを含む一時directoryへ移動する。
2. password、token、private filenameを含まないfixtureだけを使う。SSH／remote providerは本確認の対象外とする。
3. Developer JITとRelease AOTで同じ項目を実行する。AppKit Accessibility InspectorまたはVoiceOverを使う場合も
   内容のscreen recordingや診断exportは保存しない。
4. default設定では初期表示true／380 ptでterminalがinput ownerになる。
   `context-dock-visible = false`なら新規windowは非表示、`context-dock-width = 420`なら420 ptで表示されることも確認する。
   visibleのreloadは既存windowの手動開閉を変えず、width値を変更すると既存windowもresizeされる。

## Keyboard-onlyとfocus ownership

- [ ] Terminal focus中にOption-Shift-Cを押すたびDockだけが表示／非表示になり、terminalへ文字や制御byteが入らない。
- [ ] Navigator focus中のOption-Shift-Cはterminalへfocusを安全に戻してDockを閉じ、再度押すとquery／tree contextを保持して表示する。
- [ ] Terminal focus中にShift-Command-Fを1回押すと右DockへSearch focusが移り（非表示なら表示され）、query末尾にnativeの入力caretが表示され、2回以上点滅する。terminalへ文字は入らない。
- [ ] Shift-Command-GでGo Toへ移るとtreeを保ったまま独立queryを入力でき、current subtree内の深い一致file/folderまで必要なancestorだけが開いてselectionが移る。対象folderはReturnまで閉じている。
- [ ] Shift-Command-MでMoveへ移るとquery caretが消え、文字、Delete、Command-AはqueryもPTYも変更せず、Up/Down/Page Up/Page Downだけがselectionを動かす。
- [ ] Terminal／Navigatorのどちらがfocus中でもShift-Command-Hを押すたびdot-prefixed file/folderとそのsubtreeが一括で非表示／表示になり、focus、query、expanded state、PTY inputは変わらない。
- [ ] Terminal／Navigatorのどちらがfocus中でもControl-Shift-LeftでDockが1文字幅ずつ広がり、Control-Shift-Rightで狭まる。境界のmouse dragとresize cursorは無効で、terminalのfont／倍率は変わらず、列数と折り返しが横幅に追従する。query／selection／focusは保たれ、上下限では停止する。
  ShiftなしのControl-arrowは既定では境界を動かさず、macOSの操作スペース移動と競合しない。
- [ ] Search／Go Toの文字入力、Delete、Command-Aは現在modeのqueryだけを変え、modeを往復しても両queryを個別に保持する。
- [ ] 空queryでReturnまたはCommand-Rightを押すとfolderがDock内で展開し、同じfolder上の再度のReturnで閉じる。自動`cd`やcommand実行は起きない。
- [ ] Command-Leftでsubtreeを畳み、selectionがvisible parentへ戻る。
- [ ] Escapeを1回押すとquery/resultを保持したままterminalへ戻り、Dockが`Mode: Terminal`を表示する。再度Shift-Command-Fで同じcontextへ戻る。
- [ ] Dock表示中でもterminal focusなら通常のterminal key、selection、scrollが従来どおり動作する。
- [ ] 初回表示のDockは従来より広い380 ptで、狭いwindow、resize、keyboard境界操作、fullscreen、tab/pane切替、Dock hide/showでもterminalと重ならず、focused paneのcwdへ追従する。

## Tree、search、path handoff

- [ ] 空queryではdotfileを含むfile/folderがfolder-firstで表示され、選択項目のkind、permission、owner/group、size、mtime、symlink targetが読める。
- [ ] hidden非表示中はdot-prefixed directory配下の通常名fileもtree、Search、Go Toに現れず、再表示すると同じexpanded contextから参照できる。
- [ ] query入力直後にcurrent subtreeの結果が現れ、後からRecent locations／Chosen locations／System indexのcoverageが同じlistへ追加される。
- [ ] current working directory配下のSearch resultでReturn／Command-Rightを押すとMove treeへrevealされ、folderは展開されて直下を続けて操作できる。外部resultではSearch、root、selectionが変わらない。
- [ ] 数百件のtree/search resultでも上段だけがscrollし、下段のPath actions／Detailsは常に見える。Up/Down/Page移動で同じ固定領域の選択情報だけが更新される。
- [ ] Spotlightやpermissionが利用不能なscopeは`Unavailable`／`Partial`と表示され、0件と混同しない。
- [ ] Command-Cは選択absolute pathだけをclipboardへcopyし、focusをNavigatorに残す。terminalへのwriteはない。
- [ ] Option-Returnは空白、apostrophe、Unicodeを含むpathを1 shell wordとして挿入し、改行を送らずterminalへfocusを戻す。
- [ ] folder/fileを選択しただけではPTY write、自動`cd`、自動実行、Finder起動が発生しない。
- [ ] alternate-screen applicationまたはforeground command中はInsert quoted pathがunavailableで、入力を送らない。
- [ ] manual Secure Keyboard Entry中、およびECHO-off foreground process中はcwd/result/detailが消え、検索へfocusできない。解除後は再取得される。

## VoiceOverとFull Keyboard Access

- [ ] VoiceOverはDock上段を`Directory Navigator`というnative text areaとして到達可能にし、terminalとは別のsiblingとして読む。Search／Go To入力中だけeditable、Move／terminal focus中はread-onlyと伝わる。
- [ ] title、input owner、working directory、Search query、tree/search rows、coverageを上段で、Path actions、Detailsを下段の非focus text viewでvisual orderどおり読める。
- [ ] result移動時にselected rowが読み上げられ、folder markerだけに依存せず名前と末尾`/`でfolderを区別できる。
- [ ] terminal/Navigatorのfocus移動が読み上げられ、terminal cursorとNavigator selectionを同時にactiveと誤認しない。
- [ ] Full Keyboard Accessを有効にしてもShift-Command-F、Escape、Command-C、Option-Return、tree/search navigationがmouseなしで完結する。
- [ ] EnglishとJapaneseの両localeでaction、status、coverage、privacy、path actionの意味が欠落せず、path自体は翻訳・並び替えされない。

## Appearance、cleanup、記録

- [ ] background-opacityを0／0.5／1へreloadし、一覧・固定detailsの空白と余白がterminalと同じ透過度になる。
  長いtreeをscrollしても背景が濃くならず、文字／caret／境界線は薄くならない。
- [ ] custom foreground／background、font-family／font-size／regular variation／padding、live opacityで上下ともterminalと揃う。
  Light／Darkやfocused pane変更で追従し、背景と文字を同色にしてもopaqueな境界が見える。query caret／selection／scroll／focusはstyle更新でリセットされない。
- [ ] Light/Dark、Increase Contrast、Differentiate Without Colorでselection/focus/disabled stateを色だけに依存せず区別できる。
- [ ] Reduce MotionでDock操作に不要なanimationが加わらず、focus/resultの意味が変わらない。
- [ ] Dock hide、tab/window close、app Quit後に残留window、filesystem activity、Spotlight process、Secure Keyboard Entry ownerがない。
- [ ] 結果記録にはfixture path、query、clipboard、terminal outputを含めず、失敗時も操作とvisible stateの要約だけを残す。
