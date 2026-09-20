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
