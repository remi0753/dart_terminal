# DT-008 — Japanese `NSTextInputClient` and candidate-rect spike

- Status: accepted
- Date: 2026-09-01
- Scope: Phase 0 feasibility gate
- Related decisions: ADR-001 and ADR-002

> The recorded modified-Engine binary hash below identifies only the historical
> run. The surviving root-only IME target now builds through the clean official
> Engine gate and does not reproduce or accept that old Engine state.

## Question

Can a release-AOT Dart/AppKit terminal view implement the macOS text-input
contract for Japanese marked text, updates, commit, cancellation, and candidate
placement while keeping composition events separate from raw terminal keys and
without synchronously entering Dart from an AppKit input callback?

This is a native AppKit boundary for an independently implemented Dart
terminal emulator. It does not use Ghostty or `libghostty`.

## Acceptance criteria

1. A real first-responder `NSView<NSTextInputClient>` is connected to a live
   `NSTextInputContext` on the AppKit main thread.
2. Japanese preedit is installed and updated through `setMarkedText`, with
   valid `hasMarkedText`, `markedRange`, and `selectedRange` state.
3. `attributedSubstringForProposedRange` returns the current marked text and
   exact actual range.
4. `insertText` commits `日本語`, clears marked state, and advances selection.
5. A separate `かな` preedit can be cancelled by `unmarkText` without changing
   the committed document.
6. `firstRectForCharacterRange` returns a finite, positive screen-space
   candidate rectangle and exact marked range; conversion back to view space
   matches the cached caret within 0.01 pt.
7. `keyDown` offers events to `NSTextInputContext` first. Raw-key delivery is
   suppressed while composition is active and resumes after commit.
8. Candidate geometry is served from native cached view state with no
   synchronous native-to-Dart callback.
9. Cold and steady calls remain below the 4 ms main-run-loop ceiling.
10. Five consecutive repeat runs pass on real hardware.

## Implementation

`Phase0TextInputView` implements the required `NSTextInputClient` methods and
is installed as the window's first responder. Its `keyDown` method first calls
the view's `NSTextInputContext`; only an unhandled event can enter the raw-key
path. The deterministic scenario drives these protocol entry points:

```text
raw → にほん preedit → candidate rect → にほんご update
    → 日本語 commit → raw → かな preedit → cancel
```

The recorded event order is `R,P,X,P,C,R,P,U`. One additional attempted raw
delivery during the first composition is counted as suppressed and never
enters that ordered stream. This makes preedit/update/commit/cancel events a
separate channel from terminal key bytes.

The view stores a local caret rectangle during layout. Candidate lookup only
converts that cached rectangle through view, window, and screen coordinates;
it does not ask Dart for fresh grid geometry. The root-isolate call returns one
versioned 256-byte summary. Sixty-four scenarios are split across separate
run-loop turns so they do not form one artificial blocking handler.

The automated scenario calls the same `NSTextInputClient` entry points used by
an input method but deliberately does not change the user's selected macOS
input source. A release test must additionally exercise interactive conversion
and the visible candidate window with the system Japanese IME. That UI test is
not needed to establish this Phase 0 ownership and geometry boundary.

## Reproduction

```sh
make phase0-ime-build
make phase0-ime-run
```

The ProductARM64 AOT app is ad-hoc signed; strict deep signature verification
passes.

Artifact SHA-256 values for the accepted build:

| Artifact | SHA-256 |
| --- | --- |
| native host | `a73e4ced22c45bf7b549eab792435e405fb4cb7e7de2d7ea41634a2f07cf2ccf` |
| Dart AOT snapshot | `34afd20382dd274d97ba93a79e5de0aba7ea01703f859fb06f5dac37173b9a43` |
| patched ProductARM64 engine | `be9e6aed1505991cdac3fd9cf940de4f2ede7a8cf66f399786b8923e984bc8d1` |

## Real-hardware result

All accepted runs completed 64 full scenarios. The screen candidate rectangle
was consistently `(297, 335, 2, 24)` points and round-tripped to the cached
local caret `(137, 121, 2, 24)` within the required tolerance.

| Run | Native p95 (us) | Native max (us) | FFI p95 (us) | FFI max (us) | Root max turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 30 | 982 | 32 | 1,583 | 205 |
| 1 | 29 | 150 | 31 | 760 | 143 |
| 2 | 25 | 143 | 27 | 708 | 120 |
| 3 | 31 | 152 | 33 | 746 | 143 |
| 4 | 26 | 169 | 28 | 851 | 138 |
| 5 | 37 | 154 | 39 | 691 | 154 |

All six runs produced exactly three marked updates, one commit, one cancel,
two delivered raw events, one composition-time raw suppression, one candidate
query, the same event hash, and final document `prompt> 日本語`. The worst
steady FFI p95 was **39 us**. The cold maximum, including first input-context
creation, was **1,583 us**. The worst measured Dart root turn was **205 us**,
5.1% of the 4,000 us ceiling. Heartbeat gaps of 15.5–17.4 ms include timer and
OS scheduling and are not synchronous input-handler durations.

## Decision

Accepted. `NSTextInputClient`, first-responder ownership, and candidate
coordinate conversion must remain native/AppKit-main-thread responsibilities.
Dart owns terminal selection and text state, but native must cache the last
published caret/range geometry so synchronous candidate queries never reenter
Dart. Native sends versioned asynchronous preedit/update/commit/cancel events;
raw key encoding is used only after the input context declines the event and no
composition gate suppresses it.

Phase 4 must add generation IDs for cached geometry, stale-update handling,
actual Japanese IME candidate-window tests, replacement-range edge cases,
emoji/combining preedit, focus changes, accessibility synchronization, and
Secure Input interaction.
