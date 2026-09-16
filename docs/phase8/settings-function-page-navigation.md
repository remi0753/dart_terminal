# Settings Function page navigation

- Status: planned
- Date/environment: 2026-09-17, macOS arm64

## Purpose and background

Make Fn+Up/Down useful for fast movement through the Settings document. The
current NORMAL controller handles only single-row arrows/j/k; PageUp/Down
are ignored. Keep the same attributed editor and existing selection reveal.

## Scope and exclusions

Support native PageUp/PageDown and Function+Up/Down representations in NORMAL.
Ordinary arrows retain single-line movement. INSERT remains AppKit-owned,
including marked text and native page commands. SEARCH retains its query and
match ownership; define and test its page behavior before implementation.
No terminal input routing changes, new setting, config mutation, native API,
or unrelated navigator shortcut changes.

## Dependencies, acceptance, risks and verification

Begin after the Control+Tab diagnosis task is complete. Reuse
`moveCaretVertical` and the existing `scrollSelectionToVisible` presenter
contract: move the selection, then reveal it without recreating the document,
styles or editor. Bound/clamp movement at document edges and UTF-16 scalar
boundaries. Test repeated commands, ordinary arrows, modifiers, SEARCH and
INSERT, and fake/native viewport follow. Run formatter, analyzer, focused
tests, generated evidence freshness and both runtime configuration acceptance;
record actual results and review the diff before the completion commit.
