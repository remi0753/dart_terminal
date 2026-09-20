# Phase 10 — Native-content Secure Input activation determinism

## 目的

`runtime-native-content-integration`後段のmanual Secure Keyboard Entry fixtureが、実際には
foregroundでないapplicationに対してowner取得を待ち続ける非決定性を解消する。

## 背景

foreground-process Directory interactionの最終検証では、同一product sourceのDeveloper JIT／Release AOTが
ともにnative-content acceptanceを完走した。一方、その後の再実行では新しいDirectory操作をすべて通過した後、
manual Secure fixtureだけが`manual_requested=true`、`desired=true`、`owned=false`、`os_status=0`で繰り返し失敗した。
起動時machine lineも`application_active=false`であり、productは非active時のowner取得を正しくfail closedしている。

同種の問題とdelayed Launch Services activationの設計履歴は
[`docs/phase11/release-candidate-daily-use-program.md`](../phase11/release-candidate-daily-use-program.md)にある。

## 範囲

- native-content acceptance processの実PID／bundle identityとforeground activationの確認。
- 既存Secure Keyboard Entry専用harnessのdelayed activation経路を再利用できるかの調査。
- foreground preconditionを満たせないrunを、owner取得失敗と誤分類せずcontent-freeに診断するfixture更新。
- Developer JIT／Release AOTの反復検証。

## 対象外

- productの非active時fail-closed policyの緩和。
- Accessibility permission、entitlement、synthetic focusだけによるSecure Event Input取得。
- Directory Navigator／Process Inspectorのauthority変更。

## 完了条件

- native-content acceptanceがreal active/focused windowでmanual Secure ownerの取得と解放を検証する。
- foreground activation不能時は原因が明確なprecondition failureとなり、stale ownerを残さない。
- 複数回のDeveloper JIT／Release AOT実行でDirectory操作fixtureとSecure fixtureが同じrun内で安定して完走する。

## 検証方針

- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`を複数回実行する。
- `make RUNTIME_ARCH=arm64 runtime-secure-keyboard-entry-integration`とactivation／cleanup証跡を比較する。
- repository全体testと生成証跡を再検証する。
