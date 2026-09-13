# Terminal rendering reference

This document describes the product-owned text and cell-glyph boundary used by
Dart Terminal on macOS. It is an implementation and verification reference,
not a promise that every private-use or geometric character is synthesized.

## Text and cell ownership

Ordinary printable text is resolved, shaped, and rasterized through CoreText.
Runs preserve terminal-grid cluster positions, style, foreground color, wide
cells, interned graphemes, fallback faces, and the cursor-cell shaping break.

The following exact set is instead rendered as deterministic alpha geometry in
the device-pixel rectangle of one plain narrow terminal cell:

- Box Drawing U+2500–U+257F (128 scalars)
- Block Elements U+2580–U+259F (32 scalars)
- Braille Patterns U+2800–U+28FF (256 scalars)
- Powerline U+E0B0–U+E0BF, U+E0D2, and U+E0D4 (18 scalars)

The allow-list contains 434 scalars. A supported scalar inside a multi-scalar
grapheme remains CoreText-owned and atomic. Wide cells, preedit text, adjacent
private-use values such as U+E0C0, other Nerd Font glyphs, and every scalar
outside the allow-list also remain on the normal CoreText fallback path.

## Pixel geometry and resources

The compositor rounds every grid edge independently at the current backing
scale. A cell raster receives the difference between its rounded left/right and
top/bottom edges, so fractional font metrics do not stretch a cached bitmap or
leave a gap between neighboring cells. Line thickness comes from the scaled
font underline thickness and is clamped to the exact cell.

Each raster is an immutable tightly packed alpha mask. The request contract
limits each dimension to 4,096 device pixels and total coverage to 16 MiB.
Atlas identity includes catalog generation, fixed scale, scalar, exact width,
height, and thickness. Cell masks use a namespace distinct from positive
CoreText face IDs and Kitty image tiles, while sharing the normal bounded alpha
atlas, uploads, LRU eviction, build/submission pins, reset, renderer recovery,
and Metal frame lifetime.

Foreground color is applied when the alpha mask becomes a glyph instance. The
complete order is frame clear, extreme-negative images below cell backgrounds,
cell backgrounds, selection/search fills, ordinary-negative images below text,
glyphs, nonnegative images above text, hyperlink/inspector/search decorations,
and cursor. Underline, overline, strike, inverse, faint, hover, selection, and
diagnostic behavior therefore stays independent of the synthetic geometry and
never mutates canonical terminal cells.

## Canonical color and blending

Palette, OSC, style, CoreText color-glyph, Kitty, packed-instance, and golden
bytes are canonical straight-alpha RGBA8 sRGB. Explicitly tagged Display P3
colors or bitmaps are converted once at the reference/atlas admission boundary
through the fixed D65 matrix, clipped to sRGB gamut, and stored without the
source tag; alpha is unchanged. Row padding is copied but never color-converted.

Packed solid/mask colors are decoded by the Metal shader. Color-atlas textures,
the offscreen correctness target, and the bound `MTKView` use
`RGBA8Unorm_sRGB`; the native layer also declares the sRGB color space. Metal
therefore samples and blends in linear light and encodes only on destination
storage. The Dart oracle mirrors decode, straight-alpha source-over,
unpremultiplication, encode, and final-byte rounding. Alpha masks remain
coverage-only `R8Unorm`. Opaque colors are byte exact; real-Metal 1x/2x parity
permits one byte per channel for GPU rounding.

## Reproducible evidence

The checked-in version-one DTGI corpus contains four colored rows covering Box,
Block, Braille, all 18 accepted Powerline forms, blank Braille, and U+E0C0 font
fallback:

- `test/goldens/cell-glyphs/synthetic-corpus-1x.dtgi` — 71,624 bytes,
  SHA-256 `fcb22fbdfcc70fcd9e9292c97c8342c14484c7ba608bd2dac0cc4b23861e7dcc`
- `test/goldens/cell-glyphs/synthetic-corpus-2x.dtgi` — 285,995 bytes,
  SHA-256 `c985379f3b075b987e7f65b0cf739dbefe59569f31b26f750919ef013b335eec`

Ordinary tests reconstruct each image through the CPU reference renderer,
require byte-exact equality with the checked-in artifact, and compare the same
atlas entries and packed positions with real Metal readback using the existing
one-channel-value tolerance. Pure raster tests exhaustively cover all 434
accepted scalars at representative odd/even 1x and 2x device grids.

The compact overlay/color corpus combines all three Kitty image bands, normal
and selected search fills, hyperlink and inspector prompt/input decorations,
translucent linear-light source-over, and a tagged Display P3 image:

- `test/goldens/overlay-color/closure-1x.dtgi` — 675 bytes, SHA-256
  `59caaf1a008c5d795a09d6f8178db1c98951a63a23448bf2885dead488c829c6`
- `test/goldens/overlay-color/closure-2x.dtgi` — 2,213 bytes, SHA-256
  `701a2caf0634009f7b1fa91c014a3c59346ccf6fd1568caa863b9a224506473c`

Its ordinary test requires exact checked-in CPU bytes and compares the same
instances against real Metal. Search state retains only stable ranges and a
selected index. Inspector state retains only bounded hyperlink and semantic
prompt/input geometry; semantic output and text never enter its overlay.

The bounded product acceptance emits the relevant UTF-8 bytes through a real
PTY and verifies canonical screen cells, all three signed-z image bands,
normal/selected search presentation and clear, explicitly tagged P3 conversion
at 1x/2x, exact scale-aware atlas keys, adjacent font fallback, accepted Metal
frames, and clean teardown in Developer JIT and Release AOT. The diagnostics
product scenario separately verifies inspector activation, focus handoff,
privacy, clear, and owner teardown in both modes. Re-run the focused and product
evidence with:

```shell
dart run test/terminal_screen_metal_compositor_test.dart
dart run test/metal_pipeline_test.dart
make RUNTIME_ARCH=arm64 runtime-terminal-display-integration
make RUNTIME_ARCH=arm64 runtime-diagnostics-integration
```

Goldens are never rewritten by an ordinary test. A deliberate reviewed update
uses `--write-cell-goldens`, followed by visual/diff review and the normal full
repository gate. The overlay/color pair similarly uses
`--write-overlay-color-goldens`.
