# Phase 5 — macOS input-source manual checklist

This checklist covers system UI and physical-key behavior that automated tests
must not change globally. Run it on a non-sensitive shell and record only the
result fields below; do not paste terminal contents, command history, or input
method learning data into the evidence.

## Preparation

1. Record the macOS version, Mac architecture, keyboard hardware (`ANSI` or
   `JIS`), and the currently selected input-source name/ID.
2. Build and launch the Developer JIT or Release AOT app normally. Confirm the
   terminal view has focus and the insertion cursor is visible.
3. Add a requested input source in System Settings only if you choose to do so.
   The automated suite never installs, removes, or switches an input source.
4. For byte-level evidence, run `od -An -tx1` in the terminal, enter one test
   value, press Return, then interrupt `od` with Control-C. Do not use this step
   for text that is sensitive.

## Cases

| Case | Setup and action | Expected behavior |
| --- | --- | --- |
| US letters | Select `ABC`/US. Type `a`, then Shift-A. | Exactly `aA` is inserted; Shift changes produced text without duplicate raw input. UTF-8 is `61 41`. |
| US dead key | Under `ABC`/US, press Option-E, then `e`. | The dead-key accent is intermediate system state; exactly one composed `é` is committed. UTF-8 is `c3 a9`. |
| JIS yen/underscore | Connect a JIS keyboard and select an appropriate Roman input source. Press Yen, then Shift plus the JIS underscore key. | Exactly `¥_` is committed. UTF-8 is `c2 a5 5f`; no escape sequence or duplicate text appears. |
| JIS Eisu/Kana | With a JIS keyboard, press Eisu, then Kana, and observe the menu-bar input indicator. | The source changes as macOS specifies. The switching keys themselves do not insert terminal bytes. Restore the intended source before continuing. |
| Japanese composition | Select Japanese Hiragana. Type `nihongo`, use Space to choose the `日本語` candidate, then Return. Repeat with `kana` and press Escape. | Marked text is underlined, the composition caret tracks its selection, and the candidate window is anchored near the terminal caret. Commit inserts `日本語` once; cancel inserts nothing. |
| Chinese commit | If a Chinese input method is already installed, compose and commit `中文`. | Preedit remains an overlay and exactly `中文` is committed. UTF-8 is `e4 b8 ad e6 96 87`. |
| Korean commit | If a Korean input method is already installed, compose and commit `한글`. | Preedit remains an overlay and exactly `한글` is committed. UTF-8 is `ed 95 9c ea b8 80`. |
| Emoji picker | Press Control-Command-Space, choose “woman technologist” (`👩‍💻`), and insert it. | The picker is anchored by AppKit and the ZWJ sequence is committed once as one visible grapheme. UTF-8 is `f0 9f 91 a9 e2 80 8d f0 9f 92 bb`. |
| Unicode Hex Input | If `Unicode Hex Input` is already installed, select it, hold Option, and type `2318`. | Exactly `⌘` is committed. UTF-8 is `e2 8c 98`; the hexadecimal keystrokes are not separately delivered. |
| Key repeat | Return to ABC/US. At a shell prompt, hold Right Arrow long enough to repeat. | The initial move and subsequent repeats are delivered in order; the UI stays responsive and no repeated event is coalesced into text. In normal cursor mode each event is `1b 5b 43`. |

“If installed” cases may be recorded as `not available`; they do not authorize
changing a shared machine's input-source configuration. The deterministic
native/PTY matrix covers their common final `insertText:` boundary regardless
of installed system sources.

## Restoration

1. Restore the input source recorded during preparation.
2. Remove an input source only if you added it specifically for this check and
   want it removed. Do not alter another user's source list.
3. Exit the test shell and verify the app closes without an input-client or PTY
   resource leak.

## Evidence record

Record one row per case with these content-free fields:

- date, macOS version, architecture, runtime mode;
- keyboard hardware and input-source name/ID;
- case ID, `pass` / `fail` / `not available`;
- candidate anchored, commit once, cancel empty, repeat responsive booleans as
  applicable;
- optional screenshot path after ensuring it contains no sensitive terminal
  content;
- defect link for a failure, without copying private input or command history.
