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

Application capability registration and Dart Terminal model adaptation are
intentionally deferred to product composition. Package tests load the code
asset directly, so this package can be verified before manifest registration.

The native surface is an AppKit child overlay with a 44×44 point trailing
badge hit target, an optional 240–360 point rail, and at most 32 materialized
card views. Cards use the six canonical opaque light/dark sRGB palettes,
fixed status shapes, an eight-line preview, and bounded 12–24 point body text.
Small panes retain a non-content badge and never expose a rail. Hidden,
background, and collapsed card bodies are omitted from the accessibility tree.

`dtn_surface_attach_to_host` is a native-to-native composition seam; its
opaque `NSView` pointer must never cross Dart FFI. Dart can update bounded
layout and read content-free geometry/appearance snapshots. Actual host
attachment remains product composition work and does not require any
Dart-Terminal-specific API in `dart_appkit`.
