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

Foreground color is applied when the alpha mask becomes a glyph instance.
Background, selection, images below text, glyphs, images above text,
decorations, and cursor retain the established layer order. Underline,
overline, strike, inverse, faint, hover, and selection behavior therefore stays
independent of the synthetic geometry.

## Reproducible evidence

The checked-in version-one DTGI corpus contains four colored rows covering Box,
Block, Braille, all 18 accepted Powerline forms, blank Braille, and U+E0C0 font
fallback:

- `test/goldens/cell-glyphs/synthetic-corpus-1x.dtgi` — 71,624 bytes,
  SHA-256 `dfe94356493b698b6a2d4b916a7d340d0efb3e6492b6804385d0d752292d3930`
- `test/goldens/cell-glyphs/synthetic-corpus-2x.dtgi` — 285,995 bytes,
  SHA-256 `d104ea9df96eb2e2c4ab0fbd4694b8dda7b718f7494d47f00c862d8e6da8a58b`

Ordinary tests reconstruct each image through the CPU reference renderer,
require byte-exact equality with the checked-in artifact, and compare the same
atlas entries and packed positions with real Metal readback using the existing
one-channel-value tolerance. Pure raster tests exhaustively cover all 434
accepted scalars at representative odd/even 1x and 2x device grids.

The bounded product acceptance emits the relevant UTF-8 bytes through a real
PTY and verifies canonical screen cells, exact scale-aware atlas keys, adjacent
font fallback, an accepted Metal frame, and clean teardown in Developer JIT and
Release AOT. Re-run the focused and product evidence with:

```shell
dart run test/terminal_screen_metal_compositor_test.dart
make RUNTIME_ARCH=arm64 runtime-terminal-display-integration
```

Goldens are never rewritten by an ordinary test. A deliberate reviewed update
uses `--write-cell-goldens`, followed by visual/diff review and the normal full
repository gate.
