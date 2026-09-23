# Changelog

All notable changes to smPDF are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Work towards **2.0.0**, the release that makes smPDF a replacement for Gnostice
eDocEngine in AlignMix's map export. Several changes below alter output or
break source compatibility; they are marked **Breaking**.

### Changed

- **`CompressStreams` is now honoured.** It always defaulted to `True` but was
  never read, so page content and embedded fonts were written raw. Page content
  streams and `/FontFile2` font programs are now Flate-compressed (`/Length1`
  keeps the uncompressed font length). The Map demo shrinks from 4.0 MB to
  0.69 MB. Set `CompressStreams := False` to inspect content bytes.
- **Faster, leaner output.** Content streams are built in one growable byte
  buffer with numbers written digit by digit (byte-identical to the previous
  `FormatPdfNumber`), instead of a string and a `TBytes` per operator.
  `Save(FileName)` streams through a 1 MB `TBufferedFileStream` and
  `Save(Stream)` writes straight to the stream; neither builds the whole
  document in memory first. `ToBytes` hands back its buffer without a final
  copy. Flate runs at zlib level 4 (about 4× faster than level 6 on map
  content, ~10% larger).

- **Breaking: `Font.Size` is now `Double`.** Assignments compile unchanged;
  code that passes `Font.Size` where an `Integer` is expected needs a
  `Round`. Fractional sizes are written verbatim (`/F1 7.35 Tf`).
- **Breaking (output): the Y flip is now `H − Y`, not `(H − 1) − Y`.** Everything
  on a page moves up by one pixel, so pixel `Y = 0` is the top edge of the page
  and `Y = Height` is the bottom edge.
- **Breaking (output): the MediaBox uses exact point sizes.** A4 is
  `595.28 × 841.89` at any DPI; previously it was rounded through whole pixels
  (A4 at 300 DPI came out as `595.2 × 841.92`).
- **Breaking (output): text is no longer snapped to whole pixels.** Baselines,
  underline ends, and aligned/centred positions inside `DrawText(Rect)` and
  `DrawParagraph` keep their fractional pixel values.
- Paper-size and custom pages keep their exact point size across the
  parameterless `NewPage`.

### Added

- `NewPage(AWidthPt, AHeightPt: Double; ADPI = 72; APaperColor = clWhite)` —
  page size in points, used exactly for the MediaBox. At 72 DPI one drawing
  pixel is one point, so callers can work in points directly.
- `Double` overloads: `DrawLine`, `DrawBox`, `DrawOval`, `DrawText(s, X, Y, Angle)`,
  `DrawPicture(Picture, TRectF, …)`, and `TPDFPointFList = TList<TPointF>`
  overloads of `DrawMultiLine` and `DrawPolygon` (including the clip-rect form).
- `TextWidthF`, `TextHeightF`, `TextExtentF` — unrounded measurements.
- `WidthPt`, `HeightPt` — the current page size in points.
- `Tests/Bench/smPDF_Bench.dpr` — throughput benchmark (1M polygon vertices,
  2,000 outlined labels, A0 at 72 DPI).
- `Save(AStream: TStream)` overload — writes the PDF at the stream's current
  position and returns the byte count, so output never has to touch the disk.
- `ToBytes: TBytes` — returns the complete PDF as a byte array.

### Changed

- `Save(AFileName)` no longer creates an empty file when it raises because no
  pages were added.

## [1.0.0] — 2026-05-03

First public release. The library is feature-complete across the six
originally-planned phases, has 277 tests passing, and is published under MIT.

### Added

- **PDF 1.4 export** in pure Object Pascal — no third-party dependencies.
- **Graphics primitives**: `DrawLine`, `DrawBox`, `DrawOval`, `DrawMultiLine`,
  `DrawPolygon` (with even-odd holes via repeated start-points), and a
  `DrawPolygon(points, clipRect)` overload that installs a PDF clip path.
- **Standard 14 fonts** (Helvetica, Times, Courier, Symbol, ZapfDingbats and
  bold/italic variants) with bundled AFM metrics.
- **TrueType embedding** — any installed Windows font is looked up via the
  registry and embedded as a full `/FontFile2` stream. Each `(family, bold,
  italic)` combination resolves to its own physical file.
- **Text layout**: per-line `DrawText` (point, rect, rect+alignment) plus
  multi-line `DrawParagraph` with word wrap and `tpNone`/`tpTight`/`tpSingle`/
  `tpDouble` line spacing.
- **Text styling**: outlined glyphs via `Font.StrokeStyle` + `Font.StrokeColor`
  (PDF text-render mode 2, ssThin/ssMedium/ssThick widths scaled to font size);
  text background fill (Brush mirrors VCL `TCanvas.TextRect` behaviour);
  underlines; rotation around the `(X, Y)` anchor at any CCW degrees angle
  via the 4-arg `DrawText` overload.
- **Text measurement**: `TextWidth`, `TextHeight`, `TextExtent`, and
  `MeasureParagraph` for laying out around text before drawing.
- **Images**: JPEG passthrough (`DCTDecode`), opaque PNG/BMP via
  flate-compressed `XObject`, and PNG with alpha emitted as image + `SMask`.
- **Multi-page** documents with mixed paper sizes, orientations, and DPIs;
  parameter-less `NewPage` inherits the previous page's settings.
- **Save returns `Int64`** (the byte count written) so callers don't need
  `TFile.GetSize`.
- **Per-page paper colour** — non-white paper is painted as a full-page filled
  rectangle before any user drawing.
- **Tiled watermark example** (`PAID` at 45° across the Invoice demo).
- **Demos**: Showcase (7-page), Invoice (single-page with watermark), Map (A3
  landscape sales-territory choropleth from a 74 MB GeoJSON), Simple (minimal
  VCL form).
- **Version constant** `SMPDF_VERSION = '1.0.0'` exposed from `smPDF`.

### Compatibility

- **Delphi XE8 (2015) or newer.** No inline `var` declarations, no multi-line
  strings, no `TFile.GetSize` — all post-XE8 features are deliberately avoided
  so the same source compiles on every supported toolchain.
- **Windows only.** Font lookup is `HKLM\…\Fonts`-based.
- **WinAnsi (cp1252) only.** CJK, Cyrillic, Greek, Vietnamese, and emoji are
  out of scope (would require CID fonts and `/Identity-H` encoding).

### Out of scope

PDF reading, parsing, form filling, encryption, digital signatures,
annotations, tagged PDF / PDF/UA / PDF/A, TTF subsetting, justified text,
kerning, vertical text, CMYK / 16-bit PNG / palette-PNG transparency.

[1.0.0]: https://github.com/stevemaughan/smPDF/releases/tag/v1.0.0
