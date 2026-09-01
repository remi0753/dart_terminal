# DT-002 — release AOT main-thread root isolate spike

- Status: accepted
- Date: 2026-08-31
- Scope: Phase 0 feasibility gate
- Related decision: `docs/adr/ADR-001-dart-native-boundary.md`

## Question

Can a release-like Dart AOT snapshot be embedded in a native macOS application
while AppKit owns the process main loop and the root Dart isolate runs on the
process main thread?

This spike intentionally tests the hosting boundary only. It is not a Ghostty
embedding and does not link Ghostty or `libghostty`; the terminal emulator will
be implemented independently in Dart behind the boundary fixed by ADR-001.

## Acceptance criteria

The spike passes only when all of the following are true:

1. The application is a signed `.app` bundle containing an arm64 AOT snapshot
   and the revision-matched Product AOT Dart Engine.
2. AppKit owns the process main loop.
3. The root isolate is created and its `main()` is invoked on the process main
   thread.
4. A Dart `Timer` callback is serviced by the AppKit-backed message pump and is
   still on the process main thread.
5. One message-pump turn is bounded to at most 64 messages and 4,000 us.
6. The application reports failure and exits non-zero if any invariant fails.
7. Five consecutive validation runs pass on real hardware.

## Implementation

- `tool/phase0/aot_app.dart` is compiled with `dart compile aot-snapshot`.
- `native/macos/phase0/AotHost.mm` embeds the Dart Engine and creates the root
  isolate from that snapshot.
- `NSApplicationMain`/AppKit owns the main loop. A custom
  `CFRunLoopSource` adapts scheduled Dart messages into the AppKit run loop.
- Each source turn stops after 64 messages or 4,000 us, whichever comes first,
  and re-signals itself when work remains.
- A coarse, versioned C ABI lets Dart check thread identity, create the test
  window, report success, and request termination.
- `Makefile` assembles and ad-hoc signs
  `build/phase0/aot/DartTerminalPhase0Aot.app`.

The first trial used a Release engine and correctly failed snapshot validation:
the `dart compile aot-snapshot` output required a Product engine. The build now
uses the revision-matched `ProductARM64/libdart_engine_aot_shared.dylib`. This is
kept as an explicit compatibility requirement rather than suppressing the VM's
snapshot check.

## Test environment

| Item | Value |
| --- | --- |
| Hardware architecture | Apple arm64 |
| macOS | 26.6.2 (25G83) |
| Xcode | 26.6 (17F113) |
| Dart SDK | 3.13.2 stable, macos_arm64 |
| Dart Engine source | `dart_appkit` pinned engine checkout |
| Engine configuration | ProductARM64 |
| Deployment target | macOS 14.0 |

## Reproduction

```sh
make phase0-aot-engine
make phase0-aot-build
make phase0-aot-run
```

The bundle was also checked with `file`, `otool -L`, `nm -gU`, and
`codesign --verify --deep --strict`:

- host executable: Mach-O 64-bit executable arm64
- snapshot: Mach-O 64-bit dynamically linked shared library arm64
- engine linkage: `@rpath/libdart_engine_aot_shared.dylib`
- all five `dt_phase0_aot_*` ABI symbols exported
- bundle signature valid on disk and satisfies its designated requirement

Artifact hashes for this run:

```text
phase0_app.aot
  2f14ec318a5724a889c5b1e99b8c5791fbf20a33bb0d846cc093640d3160a9c9
libdart_engine_aot_shared.dylib
  be9e6aed1505991cdac3fd9cf940de4f2ede7a8cf66f399786b8923e984bc8d1
```

## Real-hardware result

All six runs passed (one initial validation run plus five consecutive repeat
runs). The repeated runs produced the following native message-pump maxima:

| Run | Dart timer elapsed (us) | Messages | Turns | Re-signals | Max turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| Initial | 302,909 | 1 | 1 | 0 | 162 |
| 1 | 301,502 | 1 | 1 | 0 | 153 |
| 2 | 299,519 | 1 | 1 | 0 | 123 |
| 3 | 297,823 | 1 | 1 | 0 | 118 |
| 4 | 302,206 | 1 | 1 | 0 | 182 |
| 5 | 299,273 | 1 | 1 | 0 | 117 |

Every run reported:

```text
PHASE0_AOT_START abi=1 main_thread=1 show_status=0
PHASE0_AOT_DART_PASS timer_main_thread=1 ... report_status=0
PHASE0_AOT_NATIVE_PASS main_thread=1 ...
```

Worst occupancy through the original DT-003 regression was **204 us**, 5.10%
of the 4,000 us hard turn budget. Two final DT-012 integrated rebuilds passed at
315 us and 235 us; the 315 us maximum is 7.88% of the same budget. Source-only
standard formatting changed the AOT snapshot hash recorded above. This test
has only one scheduled Dart message, so it proves the host, thread, and bounded-
pump mechanism; sustained-load fairness remains a benchmark harness
responsibility in DT-011.

After DT-003 added same-group worker-isolate initialization to the pinned
embedder, this spike was rebuilt and rerun as a regression check. It passed
with the root and Timer still on the main thread and a 204 us maximum turn. The
engine hash above reflects that worker-capable build.

## Decision

Accepted. A release-like Dart AOT root isolate can be hosted on the AppKit main
thread without transferring ownership of the main loop to Dart. The bounded
message-pump adapter is viable for the project boundary.

This closes only the AOT hosting risk. The next Phase 0 item, DT-003, must prove
that long-lived worker isolates can be started, exercised under bulk transfer,
and stopped without violating root-isolate/UI ownership or the 4 ms main-loop
budget.
