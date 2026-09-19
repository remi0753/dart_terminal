# notarytool submit message variant

## 目的

Xcode同梱`notarytool 1.1.3 (42)`が非wait submit成功時に返す句点なしmessageを、UUIDと
送信archive pathの厳密検証を維持したまま受理する。

## 背景

2026-09-19、current-style submit JSON対応後も実`make release-distribution-verify`が
`notary submission returned invalid evidence`で停止した。Appleのsubmission historyでは今回と
先行の2 jobがともに`Accepted`であり、証明書、Keychain profile、署名、upload、公証判定は正常である。

搭載toolは`notarytool 1.1.3 (42)`で、binaryが持つsubmit成功messageは
`Successfully uploaded file`である。既存parserとfakeは末尾ピリオド付き
`Successfully uploaded file.`だけを許可していたため、実応答を拒否した。

## 範囲

- 句点なしと句点付きの2つの既知success messageをexact matchで許可する。
- grouped hexadecimal UUID、exact archive path、status不在というcurrent-style応答の残りの条件を維持する。
- 両既知variantの正例と、類似message、path、UUID、未知statusの負例を固定する。
- generic／terminal全gateと実配布を再検証する。

## 対象外

- success messageのprefix／contains／大文字小文字非区別による緩い判定。
- credential、証明書、Keychain profile、entitlementsの変更。
- Appleの公証policyや処理時間の変更。
- clean-machine no-rebuild受け入れ。

## 依存関係

- `/Users/remi/dart/dart_appkit/packages/dart_macos_runtime`のgeneric distribution publisher。
- 前項のcurrent-style／legacy submit evidence validation。
- 実環境のXcode同梱`notarytool 1.1.3 (42)`。

## 完了条件

- 句点なし／付きの両既知messageが正しいUUIDとpathとの組で受理される。
- それ以外のmessage variantは拒否される。
- generic focused test／全gateとterminal全gateが成功する。
- 実`release-distribution-verify`がsubmit parsingを通過し、wait、log、staple、Gatekeeperへ進む。

## 検証方針

- fakeの既定応答を実toolと同じ句点なしへ変更し、句点付きcompatibility caseを分離する。
- malformed／drift fixtureが引き続きfail closedであることを確認する。
- `dart format`、`dart analyze`、focused test、両repositoryの`make test`を実行する。
- 利用者が指定した実credentialでdistribution verifyを再実行する。

## 判明事項・判断記録

- submission historyの2 jobはともに`Accepted`である。parser exceptionはApple側のrejectではなく、
  upload成功後のローカルresponse validationだけで発生した。
- 先行実装はhistory JSONの句点付きmessageと資料上の表示からsubmit messageも同一と仮定した。
  実tool binaryではsubmitとhistoryが異なる固定messageを持つため、この仮定は誤りだった。
- 任意のmessageを許可せず、観測済みの句点なしと既存compatibilityの句点付きだけを列挙する。

## 検証記録

- 2026-09-19: generic fakeの既定を句点なしへ変更し、句点付きcompatibility caseを追加した。
  format、analyze、focused publisher test、generic `make test`はすべて成功した。
- 実`release-distribution-verify`はsubmit parsingとwaitの`Accepted`を通過し、公証logを
  downloadした。したがって本message variant修正は実応答で成立した。
- 後段はAccepted logの`issues: null`互換差分で停止した。これは別child taskとして記録し、
  parentの実配布受け入れはstaple／Gatekeeperまで完了するまで未完了とする。
- `issues: null`対応後の再実行でも句点なしsubmit parsingは成功し、wait、log review、staple、
  Gatekeeper、最終product auditまで通過した。句点付き互換と全negative caseもgeneric全gateで成功した。
