# notarytool Accepted log null issues

## 目的

Appleが返すAcceptedかつissue 0の公証logで`issues`が`null`になる形式を、非空issueや
schema driftを許可せずissue count 0へ正規化する。

## 背景

2026-09-19、句点なしsubmit message対応後の実`release-distribution-verify`はsubmit parsing、
独立waitの`Accepted`、公証log downloadまで通過し、`notary log does not match the accepted
submission`で停止した。再取得した実logは`jobId`一致、`status: Accepted`、
`logFormatVersion: 1`であり、`issues`だけが空配列ではなく`null`だった。

## 範囲

- Accepted logの`issues: null`をimmutableな空issue listへ正規化する。
- 既存の空配列もissue 0として維持する。
- 非空配列は従来通り件数付きで拒否し、string、object、numberなど他型も拒否する。
- generic／terminal全gateと実distribution verifyを再実行する。

## 対象外

- issueを含む公証logの許可やwarningの無視。
- job ID、Accepted status、integer log format versionの検証緩和。
- logのarchive filename、hash、ticket内容の保存や一般diagnosticsへの追加。
- credential、署名、entitlements、Apple service policyの変更。

## 依存関係

- generic distribution publisherの`_reviewNotaryLog`。
- 前段で完了したsubmit message variant対応。
- AppleがAccepted判定した実submission log。

## 完了条件

- `issues: null`と`issues: []`はissue 0として受理される。
- `issues`の非空配列と他型は拒否される。
- job ID、status、format version driftの既存negative contractが維持される。
- generic focused test／全gateとterminal全gateが成功する。
- 実配布がlog reviewを通過し、staple、Gatekeeper、最終監査まで完了する。

## 検証方針

- fakeの既定Accepted logを実toolと同じ`issues: null`へ変更する。
- empty list compatibility、nonempty list、wrong-type fixtureを分離して検証する。
- `dart format`、`dart analyze`、focused test、両repositoryの`make test`を実行する。
- 実credentialで`release-distribution-verify`を再実行する。

## 判明事項・判断記録

- 実logのtop-level keyと型だけを一時ファイルで確認し、job ID、Accepted status、format 1、
  `issues: null`を確認した。archive path、ticket内容、hashなどは成果物や一般diagnosticsへ保存しない。
- `issues` keyの欠落と明示的`null`は区別できないため、単純な`value['issues'] == null`だけでは
  欠落も受理してしまう。`containsKey('issues')`を併用して明示的nullだけを許可する。

## 検証記録

- 2026-09-19: generic fakeの既定を`issues: null`へ変更し、空配列互換、key欠落、wrong type、
  nonempty issueのfixtureを追加した。format、analyze、focused publisher test、generic
  `make test`はすべて成功した。
- 2026-09-19: 実`make release-distribution-verify`は全terminal gateとUniversal build、
  Developer ID署名、signed-entitlements canonical比較、submit、wait Accepted、format 1／issue 0
  log review、staple／validate、post-staple signature、Gatekeeperを通過した。
- atomic outputにはstapled `DartTerminal.app`、`DartTerminal.zip`、manifestだけが公開され、
  product最終監査は`code=9 notarization=Accepted issues=0`で成功した。manifestはhardened runtime、
  secure timestamp、stapled、Gatekeeper acceptedを保持する。clean-machine no-rebuild確認は別follow-upである。
