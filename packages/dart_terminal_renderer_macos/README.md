# dart_terminal_renderer_macos

This package owns the native macOS view used by Dart Terminal's renderer. Its
Dart 3.13 build hook compiles the Objective-C implementation as a code asset;
`dart_macos_runtime` stages and retains that image. The public Dart facade
initializes the versioned capability and creates an ordinary `dart_appkit`
`View` without exposing Objective-C objects or native registry handles.

The capability provides a paused, on-demand, framebuffer-only, flipped
`MTKView`, generation-owned CoreText font catalogs, and a bounded Metal
pipeline resource set. Catalogs resolve actual
or explicit synthetic regular/bold/italic/bold-italic styles, ordered CJK and
color-emoji fallback, terminal cell/decorations metrics, and complete shaped
runs. The versioned packed shaping result contains copied run/face/glyph data,
UTF-16 cluster spans, positions, advances, and feature identity. Calls and the
Dart-owned LRU shaping cache are independently bounded. A coarse glyph-set call
also copies 16.16-scale CoreText output as top-down alpha8 masks or straight
RGBA8 color glyphs with baseline-relative bearings. The native ABI also copies
bounded alpha/color atlas dirty rectangles and renders an ordered packed frame
through a build-time-compiled Metal library. Its synchronous RGBA readback is
the deterministic correctness path. Production submission copies into one of
three fixed native slots, returns immediate backpressure when they are busy,
and lets the bound native view select the newest ready frame; a slot retires
only after it is dropped before encoding or its GPU command completes. These
calls are intended for a font/render worker domain rather than an AppKit event
handler. Terminal grids, atlas allocation policy, and application policy remain
outside this package boundary. The product view also implements
`NSTextInputClient`: native marked state and synchronous candidate lookup use a
generation-tagged cached caret rectangle, while raw/preedit/commit/cancel events
cross a bounded copied queue after a scalar-only asynchronous Dart notification.
The same view is a read-only AppKit accessibility text area. Dart publishes a
bounded, generation-tagged copy of visible text, UTF-16 line and terminal-column
boundaries, selection, cursor, cell geometry, and the nonnegative logical
content origin; VoiceOver point/range/frame queries use only the native copy,
reject padding/out-of-grid hits, and never synchronously enter Dart.

Creation failures classify device, embedded shader/function/pipeline, and
bounded resource allocation without publishing a handle. Runtime state keeps
drawable misses transient while exposing a terminal command/device fault for
the current renderer generation. A missing drawable retains READY work and
`requestPresentation` explicitly retries it at the next useful visibility
epoch; native does not install an automatic retry loop.

Atlas generations identify complete Dart-owned snapshots. Incrementally
advancing a snapshot preserves unchanged native slices so dirty rectangles
remain sufficient; a newer page generation clears only its reused texture
slice before upload. `resetAtlas` advances an empty or populated full rebuild
without a synthetic glyph and clears every old slice before new definitions.

Applications declare the following native capability in their runtime manifest:

```json
{
  "id": "dart_terminal_renderer_macos",
  "package": "dart_terminal_renderer_macos",
  "library": "libdart_terminal_renderer_macos.dylib",
  "abiVersion": 11,
  "abiVersionSymbol": "dtr_abi_version",
  "initializerSymbol": "dtr_initialize"
}
```

Call `TerminalRendererMacos.initialize()` after attaching the AppKit
application, then use `TerminalRendererMacos.createView()`.

Attach `TerminalTextInputClient` to that view when the owning window uses
`KeyEventRouting.appKitOnly`. Listen to its typed event stream and publish the
newest local caret rectangle with `publishCaretRect`. One text field is limited
to 64 KiB UTF-8; a client queue is limited to 256 events and 1 MiB, coalesces
adjacent preedit updates, and reports explicit overflow instead of growing.
Disposal detaches native queue ownership. Composition policy and terminal byte
encoding remain Dart-owned.

Attach `TerminalAccessibilityClient` to the same view and publish immutable
`TerminalAccessibilityViewSnapshot` values after visible text, selection,
cursor, or cell metrics change. Text is limited to 4 MiB UTF-8 and 2 Mi UTF-16
code units, with at most 4096 lines and bounded column-boundary tables. The
facade verifies canonical line topology, surrogate-safe ranges, monotonic
terminal-column mappings, a finite 0...4096 logical-point content origin, and
strictly increasing generations before the native view atomically replaces its
copy. Range frames add the origin once; point lookup subtracts it and treats
padding or coordinates beyond the published grid as not found. Publishing an
identical value under a new generation does not emit redundant AppKit value or
selection changes.

Create bounded GPU resources with `TerminalMetalRenderer.open()`, bind them to
that view with `bindToView`, reset complete atlas snapshots with `resetAtlas`,
upload typed `TerminalMetalAtlasUpload` rectangles, and build immutable frames
through `TerminalMetalFrameEncoder`. `submit`
distinguishes accepted, stale, and backpressured outcomes; `state` exposes the
bounded retirement watermark, drawable count, typed fault state, successful GPU
timing totals/maxima, and accepted atlas upload count/bytes.
`renderRgba` is the synchronous test/oracle path, not the production
presentation path. Dispose the renderer explicitly from its owner domain.

Font work does not require AppKit initialization. Create a catalog with
`TerminalFontCatalog.open()`, resolve whole grapheme/text units with `resolve`,
shape complete text units with `shape`, optionally retain repeated results in a
bounded `TerminalShapingCache`, and call `dispose` from the owning worker
domain. Use `rasterizeShaped` to batch unique face/glyph keys at the active
backing scale. No native call retains a Dart pointer, and disposed resource
generations cannot be reused.
