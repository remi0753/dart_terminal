# dart_terminal_notes_macos

Product-owned, bounded macOS presentation capability for Dart Terminal Notes.
It is deliberately separate from `dart_appkit`: the generic UI library owns no
terminal Note concepts, packet schema, card tokens, or product policy.

The v1 projection packet is canonical little-endian binary data:

- 128-byte header with pane/surface/projection generations, unsigned 64-bit
  store revision, visibility, eligibility, and bounded counts;
- zero to 64 fixed 32-byte card records containing only process-local tokens
  and presentation enums;
- one contiguous UTF-8 body area, limited to 4,096 bytes per card and 256 KiB
  in aggregate.

Persistent Note or context IDs, timestamps, paths, and shell content are not
part of the ABI. Collapsed packets never contain card bodies. Native apply is
atomic: malformed, unsupported, cross-surface, or stale packets leave the last
accepted projection intact.

The same ABI version includes a fixed semantic intent/result boundary. An
intent carries only surface/projection/event/draft generations, an ephemeral
card token, the expected store revision, a fixed kind, and a bounded payload.
Only Save and explicit Copy can carry body bytes; only Save and Change Color
can carry a six-color key. Each surface admits one outstanding intent, delivers
it once, and rejects mismatched or duplicate results without mutating the last
projection. Results contain only a fixed disposition and new revision/
generation values; they never echo body content or persistent identity.

The rail also owns one standard plain-text `NSTextView` editor. Draft text,
selection, marked text, scroll position, and Undo remain native and volatile;
only Save snapshots a validated body. Every typing, IME, paste, plain-text
drop, and Services mutation passes the same whole-draft admission (4,096 UTF-8
bytes, 64 lines, no forbidden control/bidi/unpaired scalar). Rich, custom, and
file pasteboard types are rejected. Dirty cancellation uses an inline
Discard/Keep Editing confirmation, and fixed AppKit controls expose the six
colors and semantic card actions without hover-only affordances.

The content-free state snapshot reports only dirty/confirmation flags and the
current native focus target. `focus` moves first responder within the surface;
the product must still perform its generation-bound interaction-authority
request before calling it and confirm only after focus succeeds. Current input
events are never replayed by this package.

Application capability registration and Dart Terminal model adaptation are
intentionally deferred to product composition. Package tests load the code
asset directly, so this package can be verified before manifest registration.
`TerminalNotesNativeSurface.tryOpen` reports `nativeUnavailable` without
throwing when the capability is absent or cannot be opened. The caller keeps
the last projection and terminal session state; this package never mutates
grid, drawable, PTY winsize, `SIGWINCH`, or input ownership as fallback.

The native surface is an AppKit child overlay with a 44×44 point trailing
badge hit target, an optional 240–360 point rail, and at most 32 materialized
card views. Cards use the six canonical opaque light/dark sRGB palettes,
fixed status shapes, an eight-line preview, and bounded 12–24 point body text.
The authority-projected Current/Detached selector is semantic rather than local
UI state. Detached uses exact-total 64-card pages with Previous/Next controls,
a localized range, non-reused ephemeral card tokens, and an explicit
Attach-to-This-Terminal action on every materialized card; it never suggests or
performs automatic reattachment.
Small panes retain a non-content badge and never expose a rail. Hidden,
background, and collapsed card bodies are omitted from the accessibility tree.
English and Japanese fixed accessibility labels are selected by the bounded
projection locale. A ready announcement is emitted once only after the rail is
actually visible; the snapshot exposes eligibility generation/count state, not
card content or a durable acknowledgement mutation.

`dtn_surface_attach_to_host` is the primitive native-to-native composition
seam; its opaque `NSView` pointer must never cross Dart FFI.
`TerminalNotesNativeSurface.attachToRenderer` instead accepts the product
renderer's volatile opaque handle/generation. The Notes dylib resolves the
matching bound renderer view inside native code and attaches above it, including
when the renderer dylib was loaded locally. Unknown, stale, or unbound
generations fail soft; a surface already attached to another host reports
`busy`. Dart can update bounded layout and read content-free
geometry/appearance snapshots. This boundary adds no Dart-Terminal-specific API
to generic `dart_appkit` and passes no Note content or geometry to the renderer.
