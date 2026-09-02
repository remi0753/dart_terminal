# Dart Terminal

`dart_appkit` を土台に、Dart で独立実装する macOS 向けターミナル
エミュレーターです。Ghostty は機能・品質の比較基準としてのみ参照し、
Ghostty や `libghostty` を製品へ組み込みません。

主要な開発・実機受け入れ baseline は Apple M1/arm64 です。x86_64 は M1 上の
明示的 cross-build、Rosetta compatibility smoke、厳密な Universal audit を主要
gate とし、Intel-native 実機確認は主要ゴール後の低優先 follow-up として扱います。

現在の通常エントリーポイントはまだ command console ですが、Phase 0 の
feasibility gate と仕様凍結は完了しています。release AOT、worker isolate、
安全な PTY child、64 KiB batching、Metal、CoreText、日本語 IME、packed grid、
parser corpus、性能 baseline を、独立した Dart/native spike で実機検証済みです。
製品の developer JIT と release AOT は同じ root/worker isolate lifecycle 契約を
使い、起動、ready、request、正常停止、worker 障害、root 障害、bounded shutdown を
同じ integration suite で検証します。

## 現在できること

- AppKit のネイティブウィンドウを Dart から表示
- キー入力、Backspace/Delete、左右移動、Home/End
- 上下キーによるコマンド履歴
- `/bin/zsh -lc` によるコマンド実行と標準出力・標準エラーの表示
- `help`、`clear`、`cd PATH`、`exit` の組み込みコマンド
- Control-C による実行中プロセスへの割り込み
- ウィンドウサイズに合わせた簡易表示行数の調整
- AppKit main-thread root と長寿命 worker isolate の bounded lifecycle

## 起動

先に隣接する `dart_appkit` リポジトリで Engine の準備を済ませます。

```shell
cd ../dart_appkit
make engine
```

その後、このディレクトリで依存関係を解決し、製品の developer JIT
bundle を起動します。thin runtime target は architecture の省略や推測を
許可しないため、`RUNTIME_ARCH=arm64` または `RUNTIME_ARCH=x86_64` を必ず
指定します。

```shell
dart pub get
make RUNTIME_ARCH=arm64 developer-jit-run
```

開始ディレクトリなどのアプリ引数は `RUNTIME_ARGUMENTS` で渡します。

```shell
make RUNTIME_ARCH=arm64 developer-jit-run \
  RUNTIME_ARGUMENTS="--working-directory=/tmp"
```

自動終了を含む integration smoke:

```shell
make RUNTIME_ARCH=arm64 developer-jit-integration
```

developer JIT は、full linked Kernel と JIT Engine を含む開発専用 bundle
です。成果物は
`build/runtime/<architecture>/developer-jit/DartTerminalDeveloper.app` に
作られ、配布物には使用しません。

## Runtime lifecycle

通常起動では、root isolate が AppKit へ attach した後に同一 isolate group の
長寿命 worker を起動し、ready と request/reply を確認してから window lifecycle を
継続します。終了時は worker の stop acknowledgement と authoritative `onExit` を
期限内に回収し、期限を超えた場合は強制停止します。worker の uncaught error は
isolate 内へ封じ込め、root/host の fatal failure とは別に扱います。Engine teardown
は root を停止した後に VM-wide cleanup を行うため、root fatal 時に worker が残っても
snapshot storage より先に停止します。

integration で検証する終了状態は、正常または isolate-contained failure が `0`、
不正な application option が `64`、root/host fatal が `70`、shutdown timeout による
forced cleanup が `75` です。fault scenario の選択は integration-test gate がない通常
起動では拒否されます。

通常 smoke と lifecycle fault suite を別々に実行する場合:

```shell
make RUNTIME_ARCH=arm64 developer-jit-integration
make RUNTIME_ARCH=arm64 developer-jit-lifecycle
make RUNTIME_ARCH=arm64 release-aot-integration
make RUNTIME_ARCH=arm64 release-aot-lifecycle
```

両 runtime mode の lifecycle suite だけをまとめる場合:

```shell
make RUNTIME_ARCH=arm64 runtime-lifecycle-integration
```

## Release AOT

arm64 または x86_64 の thin release-AOT bundle を明示的に構築・監査・起動
できます。

```shell
make RUNTIME_ARCH=arm64 release-aot-build
make RUNTIME_ARCH=arm64 release-aot-audit
make RUNTIME_ARCH=arm64 release-aot-run
```

成果物は `build/runtime/<architecture>/release-aot/DartTerminal.app` です。製品の
`bin/main.dart` を AOT snapshot として含み、Kernel、JIT Engine、VM service
asset は含みません。各 thin bundle は単一 architecture の ad-hoc signed
中間成果物であり、Universal Binary や配布署名済みアプリとは呼びません。
build ごとの manifest は source/revision、実効設定、toolchain、および実際に
使用した Engine/compiler/platform/snapshotter の hash を common provenance と
architecture lane に分けて記録します。audit は署名済み bundle 全体の seal を
`build/runtime/<architecture>/<mode>/thin-audit.json` に保存します。bundle と
この receipt は一組の immutable handoff artifact として扱います。

両 architecture を独立監査し、revision・設定・全非 Mach-O 資産が一致する
場合だけ、fresh staging で Universal release-AOT bundle を組み立てます。

```shell
make universal-release-aot-audit
make universal-release-aot-integration
```

成果物は `build/runtime/universal/release-aot/DartTerminal.app` です。
launcher、Product AOT Engine、AOT snapshot のすべてが正確に arm64/x86_64 の
2 slice を持ち、組み立て後に再度 ad-hoc 署名されます。これはローカル整合性
確認用で、Developer ID 署名、hardened runtime、notarization を終えた配布物では
ありません。Apple Silicon 上の x86_64 smoke は Rosetta 互換性の証拠であり、
Intel 実機テストの代替にはなりません。

Universal assembly は監査済み thin input を変更せず、全検証と再署名を
sibling staging で終えてから atomic publish します。既存の正常出力がある場合も、
失敗時は最後の bundle と2つの receipt を同じ世代のまま保持します。組立記録は
`assembly-report.json`、独立した署名済み bundle receipt は
`universal-audit.json` に保存され、3成果物を含む親ディレクトリが一度だけ
atomic publish されます。

### 低優先の Intel-native handoff

Intel Mac では、転送済みの x86_64 thin bundle、Universal bundle、および
対応する3つの audit receipt だけを再監査・native smoke できます。この target に
build 依存関係はなく、Rosetta または Apple Silicon host では開始前に失敗します。
主要ゴール後に追加互換性証跡を得る際は、すべての path に絶対 path、evidence
出力に未作成の path を指定してください。

```shell
make intel-native-runtime-verify \
  INTEL_DEVELOPER_JIT_BUNDLE=/abs/handoff/x86_64/developer/DartTerminalDeveloper.app \
  INTEL_DEVELOPER_JIT_REPORT=/abs/handoff/x86_64/developer/thin-audit.json \
  INTEL_RELEASE_AOT_BUNDLE=/abs/handoff/x86_64/release/DartTerminal.app \
  INTEL_RELEASE_AOT_REPORT=/abs/handoff/x86_64/release/thin-audit.json \
  INTEL_UNIVERSAL_BUNDLE=/abs/handoff/universal/DartTerminal.app \
  INTEL_UNIVERSAL_REPORT=/abs/handoff/universal/universal-audit.json \
  INTEL_HARDWARE_LABEL=intel-ci-runner-name \
  INTEL_EVIDENCE_OUTPUT=/abs/evidence/intel-native-runtime.json
```

成功時は host model/CPU/macOS build、receipt hash、fresh audit、3つの native
smoke を上書き不可の evidence JSON に保存します。この evidence がないローカル
matrix 結果は明示的に「Intel-native 未実施」と表示しますが、Apple M1 baseline の
Universal task や主要ゴールの完了を阻害しません。Rosetta を Intel-native とみなさない
区別自体は維持します。

## ローカルチェック

```shell
make runtime-source-check
make RUNTIME_ARCH=arm64 runtime-bundle-audit
make RUNTIME_ARCH=arm64 runtime-integration
```

developer JIT と release AOT の source check、build、bundle audit、共通
integration suite をまとめて実行する場合:

```shell
make RUNTIME_ARCH=arm64 runtime-verify
make RUNTIME_ARCH=x86_64 runtime-verify
make runtime-matrix-verify
```

`runtime-matrix-verify` は両 thin lane、Universal assembly/audit、fail-closed
負テスト、freshness 回帰、利用可能な native/Rosetta smoke をまとめて実行
します。Intel 実機 handoff は主要ゴール後の別 follow-up であるため、この command
は最後に未実施状態を情報として表示します。

`runtime-integration` と `runtime-verify` は通常 smoke に加え、developer JIT と
release AOT の同一 lifecycle fault suite も実行します。

Phase 0 全体（debug/JIT、全 release-AOT spike、benchmark、bundle 監査）を
歴史的な feasibility regression として再検証する場合:

```shell
make phase0-verify
```

個別の再現方法と測定結果は [`docs/phase0`](docs/phase0)、設計判断は
[`docs/adr`](docs/adr)、runtime matrix と Universal assembly の契約は
[`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)
にあります。

## 構成

```text
bin/main.dart                         エントリーポイント
lib/src/terminal_application.dart    AppKit ウィンドウとキーイベント
lib/src/runtime_lifecycle.dart       root/worker lifecycle coordinator
native/macos/runtime/                JIT/AOT lifecycle host integration
lib/src/terminal_session.dart        コマンド実行バックエンド
lib/src/terminal_buffer.dart         入力、履歴、スクロールバック
test/run_tests.dart                  UI 非依存部分の最小テスト
```

## 製品実装へ進む際の境界

通常エントリーポイントは一つのコマンドごとに `zsh -lc` を起動する
「コマンドコンソール」です。現時点の `dart_appkit` 公開 API は
単一 `TextView` へのプレーンテキスト描画までなので、対話型 TUI を含む
本格的なターミナルエミュレーターには、次の実装が必要です。

1. `forkpty(3)` / `openpty(3)` を扱う macOS FFI ブリッジ
2. 継続するシェルセッションとウィンドウサイズ通知 (`TIOCSWINSZ`)
3. ANSI / VT シーケンスのパーサーと画面バッファ
4. 色・属性・カーソル・選択・スクロールを描画する AppKit ビュー
5. IME、クリップボード、キーバインドの仕上げ

`TerminalSession` が将来の PTY バックエンドとの交換点、`TerminalBuffer` が
ANSI 画面モデルへ発展させる場所になるよう分離しています。

Ghostty クラスの品質へ進めるために必要な機能、目標アーキテクチャ、段階別の
完了条件、性能予算、テスト戦略、リスクは [`ROADMAP.md`](ROADMAP.md) に
まとめています。
