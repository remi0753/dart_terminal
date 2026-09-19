# notarytool submit evidence compatibility

## 目的

現行`notarytool submit`の非wait JSONを、upload成功の証拠を弱めずに受理し、独立した
`notarytool wait`、log review、staple、Gatekeeper検証へ進める。

## 背景

2026-09-19、署名済みentitlementsのXML canonical比較を直した実
`make release-distribution-verify`はApple側に公証jobを作成した後、generic publisherの
`notary submission returned invalid evidence`で停止した。同じKeychain profileの
`notarytool history --output-format json`にはjobが`In Progress`として存在し、credential、
upload、submission ID発行は成功している。

publisherはsubmit JSONにUUIDと`status`を必須としていた。しかし`submit`は既定でwaitせず、
現行toolは成功時に`message`、`id`、`path`を返す。terminal statusは後続の独立した
`notarytool wait`で取得する契約であり、submit応答に`status`がないことをupload失敗とは
扱えない。

## 範囲

- 非wait submit応答のUUID、成功message、送信archive pathを完全一致で検証する。
- 旧toolが返す既存のbounded status形式との互換性を維持する。
- message、path、UUID、statusの改変をfail closedにするunit testを追加する。
- 実credentialでwait、log、staple、Gatekeeper、最終distribution auditまで再実行する。

## 対象外

- Apple credential、Keychain profile、証明書、秘密鍵の変更。
- 公証jobの取消し、Apple serviceの処理時間や判定policyの変更。
- submit／wait responseの未検証fieldを成果物証拠として保存すること。
- clean-machine no-rebuild受け入れ。

## 依存関係

- `/Users/remi/dart/dart_appkit/packages/dart_macos_runtime`のgeneric distribution publisher。
- Apple `notarytool`の非wait submitと独立wait contract。
- 前項で完了したsigned-entitlements XML extraction。

## 完了条件

- current-style submit JSONは、正しいUUID、成功message、同一archive pathの場合だけ受理される。
- legacy bounded status応答は従来通り受理され、未知statusは拒否される。
- malformed JSON、message drift、path drift、UUID driftをunit testが拒否する。
- generic全gateとterminal全gateが成功する。
- 実配布が公証Accepted、issue 0 log、staple、Gatekeeper、最終distribution auditを通るか、
  外部serviceの明確な後段結果を安全に記録する。

## 検証方針

- generic publisher fakeを現行非wait responseへ合わせ、成功と各field driftを検証する。
- `dart format`、`dart analyze`、focused publisher test、generic `make test`を実行する。
- terminalの生成証跡を依存順に更新し、`make release-distribution-verify`を再実行する。

## 判明事項・判断記録

- Apple側のsubmission historyにjobが存在するため、最初の失敗はupload／authentication失敗では
  ない。publisherが応答を解釈した後、waitを呼ぶ前に停止している。
- Appleのnotarization workflow資料は、非wait submit成功でsubmission identifierとupload成功を
  返し、そのIDを後続確認に使う手順を示す。statusの確定はwaitの責務として分離する。
- success messageだけの受理は行わない。UUID、exact message、callerが渡したarchiveのexact pathを
  組にして検証し、旧status形式も既知値だけに限定する。

## 検証記録

- 2026-09-19: generic publisherはcurrent-style responseを`message`、grouped hexadecimal UUID、
  exact archive pathの組で検証する。statusが存在するlegacy responseは既知の4値だけを受理する。
  malformed JSON、message drift、path drift、invalid ID、unknown legacy statusはすべて拒否する。
- 2026-09-19: generic側の`dart format`、`dart analyze`、focused
  `distribution_publisher_tests.dart`、`CI=true DART_SUPPRESS_ANALYTICS=true make test`は成功した。
  generic repositoryに元からあるEngine関連3ファイルは変更もstageもしていない。
- 2026-09-19: terminal側の`CI=true DART_SUPPRESS_ANALYTICS=true make test`は成功した。
  release-candidate evidenceはfreshで、release blocker 0、distribution policy全case、format、analyze、
  全Dart統合testが通過した。
- 先行実送信で作成された1件の公証jobを`notarytool wait --timeout 10m --no-progress
  --output-format json`で追跡したが、Apple serviceはterminal statusを返さず、600秒でtimeoutした。
  応答には同じsubmission IDとtimeout分類だけが含まれ、jobは引き続き`In Progress`である。
- service処理中に同一payloadを重複送信しない判断を採用した。このため本タスクではresponse parserの
  修正と全ローカルgateを完了とし、実公証Accepted、staple、Gatekeeper、clean-machine受け入れは
  既存の後続ROADMAP項目を未完了のまま維持する。credentialや秘密値は記録していない。
- 2026-09-19: 後続の実tool variant修正後、実配布は公証Accepted、issue 0、staple、
  Gatekeeper、最終product auditまで成功した。ここで記録した初回timeoutは当時の事実として残し、
  現在の未完了範囲はclean-machine no-rebuild受け入れだけである。
