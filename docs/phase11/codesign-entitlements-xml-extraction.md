# codesign entitlements XML extraction

## 目的

現行macOSの`codesign`から署名済みapplicationのentitlementsを機械可読なXML plistとして
取得し、Developer ID配布publisherとDart Terminal配布監査のcanonical比較を通す。

## 背景

2026-09-19、実`Developer ID Application: Yuki Otsuka (92BGB7S5D9)`で
`make release-distribution-verify`を実行したところ、全nested code imageとouter applicationの
署名後に`property-list canonicalization failed with exit code 1`で停止した。現行`codesign`は
`--display --entitlements -`だけでは空dictionaryをXMLではなく`[Dict]`というabstract
representationで出力するため、後続`plutil -convert json`が入力をproperty listとして解釈できない。

## 範囲

- 汎用`dart_macos_runtime:distribute`の署名後entitlements抽出へ`--xml`を指定する。
- Dart Terminalの最終distribution監査でも同じXML抽出契約を使用する。
- 両方のcommand contract testで`--xml`を必須化する。
- credentialを使わないpreflight／unit testと、利用者が準備した実credentialによる配布再実行で確認する。

## 対象外

- 証明書、秘密鍵、Keychain trust、`notarytool` credentialの生成・変更。
- entitlement内容の追加やsecurity authorityの拡大。
- 公証service、stapling、Gatekeeper policyそのものの変更。

## 依存関係

- `/Users/remi/dart/dart_appkit/packages/dart_macos_runtime`のgeneric distribution publisher。
- `tool/terminal_distribution_policy.dart`のproduct-owned最終監査。
- 空dictionaryを唯一の入力とする`resources/DartTerminal.entitlements`。

## 完了条件

- `codesign --display --entitlements - --xml`のstdoutを`plutil`がcanonical JSONへ変換できる。
- publisherとproduct auditの両command contractがXML指定の欠落を検出する。
- credential-independent distribution test／preflightと全repository gateが成功する。
- 実credential再実行が少なくともplist canonicalizationを通過し、後続結果を正確に記録する。

## 検証方針

- 空entitlementsで署名した一時Mach-Oから、`--xml`なしの`[Dict]`と`--xml`付きXMLを再現する。
- generic publisher unit、terminal distribution policy unit、distribution preflightを実行する。
- `dart analyze`、関連format、`make test`、実`release-distribution-verify`を順に確認する。

## 判明事項・判断記録

- 失敗したstagingでは全9 code imageとouter applicationのDeveloper ID署名まで成功しており、
  `notarytool submit`より前のsigned-entitlements canonical比較で停止した。証明書とnotary profileは
  本障害の原因ではない。
- `codesign`の現行man pageは、display時の`--entitlements path`がabstract representationを出力し、
  desired formatには`--xml`または`--der`を指定できると明記する。旧`:-`指定はXMLを返すがdeprecated
  warningを出すため採用せず、公開された現行`--xml` optionを使う。
- 空entitlementsでad-hoc署名した`/usr/bin/true`のcopyに対し、`--xml`なしは`[Dict]`、
  `--xml`付きは`<plist><dict></dict></plist>`を返すことを再現した。一時fixtureは確認後に削除した。

## 検証記録

- 2026-09-19: `dart analyze`はissue 0、
  `dart run test/terminal_distribution_policy_test.dart`は全case成功した。追加caseは
  product最終監査が`codesign --display --entitlements - --xml`を完全一致で要求する。
- 2026-09-19: generic runtime側の`dart analyze`、
  `dart run test/distribution_publisher_tests.dart`、
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`はすべて成功した。既存の利用者変更3件には
  触れていない。
- 2026-09-19: `make release-distribution-preflight`はUniversal Release AOT bundleの9 code
  image、空entitlements、product policyをすべて受理した。
- 2026-09-19: 正規generatorでrelease-candidate daily-use matrixを再生成した。変更は
  `tool/terminal_distribution_policy.dart`のsource hashだけで、program分類、gate、既知制約、
  release blocker数は変わっていない。
- 2026-09-19: 実credential付き`make release-distribution-verify`は、全repository gate、
  Universal build、preflight、9 code imageとouter applicationのDeveloper ID署名、署名済み
  entitlementsのXML canonical比較を通過した。元の`property-list canonicalization failed`は
  再現せず、XML抽出修正の正の受け入れ条件を満たした。
- 同実行はその後、Apple側に公証jobを作成した直後、submit JSONをpublisherが
  `notary submission returned invalid evidence`として拒否して停止した。履歴ではjobが
  `In Progress`として存在するため、uploadやcredentialの失敗ではなく、submit応答契約の
  別問題である。公証完了、staple、Gatekeeperは本タスクの完了とはせず、直後の独立タスクで
  submit応答をfail-closedに受理して再検証する。
