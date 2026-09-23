program smPDF_ExportDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Types,
  System.Classes,
  System.UITypes,
  System.Math,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Imaging.JPEG,
  Vcl.Imaging.PngImage,
  smPDF;

procedure DrawPage1Primitives(pdf: TsmPDF);
var
  pts: TPDFPointList;
begin
  // Page 1: A4 portrait at 72 dpi -> 595 x 842 user pixels.

  // ---- Lines ----
  pdf.Pen.Color := clBlack;
  pdf.Pen.Width := 1.0;
  pdf.Pen.Style := penSolid;
  pdf.DrawLine(40, 40, 555, 40);                // top horizontal rule

  pdf.Pen.Color := clRed;
  pdf.Pen.Width := 2.0;
  pdf.Pen.Style := penDash;
  pdf.DrawLine(40, 60, 555, 60);                // dashed red rule

  pdf.Pen.Color := $00B07020;                   // mustard
  pdf.Pen.Width := 1.5;
  pdf.Pen.Style := penDot;
  pdf.DrawLine(40, 80, 555, 80);                // dotted

  // ---- Boxes ----
  pdf.Pen.Color   := clBlack;
  pdf.Pen.Width   := 1.5;
  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;                // outline-only
  pdf.DrawBox(40, 110, 270, 240);

  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $00FFD08B;                 // pale blue
  pdf.DrawBox(310, 110, 555, 240);              // filled + outlined

  // ---- Ovals ----
  pdf.Brush.Style := brushClear;
  pdf.DrawOval(40, 270, 270, 400);              // outline-only ellipse

  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $0080C080;                 // pale green
  pdf.DrawOval(310, 270, 555, 400);

  // ---- Polygon with a square hole ----
  pdf.Pen.Color   := clBlack;
  pdf.Pen.Width   := 1.5;
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $004060FF;                 // warm red
  pts := TPDFPointList.Create;
  try
    // outer square
    pts.Add(TPoint.Create(60,  430));
    pts.Add(TPoint.Create(260, 430));
    pts.Add(TPoint.Create(260, 630));
    pts.Add(TPoint.Create(60,  630));
    pts.Add(TPoint.Create(60,  430));   // closes outer
    // inner square (hole)
    pts.Add(TPoint.Create(120, 490));
    pts.Add(TPoint.Create(200, 490));
    pts.Add(TPoint.Create(200, 570));
    pts.Add(TPoint.Create(120, 570));
    pts.Add(TPoint.Create(120, 490));   // closes inner
    pdf.DrawPolygon(pts);
  finally
    pts.Free;
  end;

  // ---- Clipped concave polygon (5-point star clipped to a rectangle) ----
  pdf.Brush.Color := $0020A8E0;                 // amber
  pts := TPDFPointList.Create;
  try
    // Star points around centre (440, 530), outer radius 110, inner radius 45
    pts.Add(TPoint.Create(440, 420));
    pts.Add(TPoint.Create(465, 510));
    pts.Add(TPoint.Create(550, 510));
    pts.Add(TPoint.Create(480, 555));
    pts.Add(TPoint.Create(505, 640));
    pts.Add(TPoint.Create(440, 590));
    pts.Add(TPoint.Create(375, 640));
    pts.Add(TPoint.Create(400, 555));
    pts.Add(TPoint.Create(330, 510));
    pts.Add(TPoint.Create(415, 510));
    // even-odd self-intersection of a star naturally produces a hole in the centre
    pdf.DrawPolygon(pts, TRect.Create(360, 460, 520, 600));
  finally
    pts.Free;
  end;

  // Outline of the clip rectangle so the clipping is visible
  pdf.Pen.Color   := clBlack;
  pdf.Pen.Width   := 0.5;
  pdf.Pen.Style   := penDash;
  pdf.Brush.Style := brushClear;
  pdf.DrawBox(360, 460, 520, 600);

  // ---- Bottom-right open polyline (zigzag) ----
  pdf.Pen.Color := $00606060;
  pdf.Pen.Width := 1.0;
  pdf.Pen.Style := penSolid;
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(40,  720));
    pts.Add(TPoint.Create(80,  680));
    pts.Add(TPoint.Create(120, 720));
    pts.Add(TPoint.Create(160, 680));
    pts.Add(TPoint.Create(200, 720));
    pts.Add(TPoint.Create(240, 680));
    pts.Add(TPoint.Create(280, 720));
    pdf.DrawMultiLine(pts);
  finally
    pts.Free;
  end;
end;

procedure DrawPage2PenStyles(pdf: TsmPDF);
var
  y: Integer;
begin
  // Page 2: A4 landscape at 72 dpi -> 842 x 595 user pixels.

  pdf.Brush.Style := brushClear;
  pdf.Pen.Color   := clBlack;
  pdf.Pen.Width   := 1.0;

  y := 80;
  pdf.Pen.Style := penSolid;     pdf.DrawLine(60, y, 800, y);   Inc(y, 40);
  pdf.Pen.Style := penDash;      pdf.DrawLine(60, y, 800, y);   Inc(y, 40);
  pdf.Pen.Style := penDot;       pdf.DrawLine(60, y, 800, y);   Inc(y, 40);
  pdf.Pen.Style := penDashDot;   pdf.DrawLine(60, y, 800, y);   Inc(y, 60);

  // Boxes with increasing line widths
  pdf.Pen.Style := penSolid;
  pdf.Pen.Width := 0.5; pdf.DrawBox(60,  y, 200, y + 80);
  pdf.Pen.Width := 1.5; pdf.DrawBox(220, y, 360, y + 80);
  pdf.Pen.Width := 3.0; pdf.DrawBox(380, y, 520, y + 80);
  pdf.Pen.Width := 5.0; pdf.DrawBox(540, y, 680, y + 80);

  // Filled ovals row
  Inc(y, 130);
  pdf.Brush.Style := brushSolid;
  pdf.Pen.Width   := 1.0;

  pdf.Brush.Color := $004080FF; pdf.DrawOval(60,  y, 200, y + 100);
  pdf.Brush.Color := $0080C080; pdf.DrawOval(220, y, 360, y + 100);
  pdf.Brush.Color := $00C08080; pdf.DrawOval(380, y, 520, y + 100);
  pdf.Brush.Color := $00C080C0; pdf.DrawOval(540, y, 680, y + 100);
end;

procedure DrawPage3Text(pdf: TsmPDF);
const
  LOREM = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod ' +
          'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, ' +
          'quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo ' +
          'consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse ' +
          'cillum dolore eu fugiat nulla pariatur.';
var
  y: Integer;
begin
  // Page 3: A4 portrait at 72 dpi -> 595 x 842 user pixels.

  // Reset Brush (Page 2 left it brushSolid for filled ovals). Brush.Style is
  // now consulted by DrawText / DrawParagraph as a text-background fill, so
  // pages that don't want highlighter text must opt out explicitly.
  pdf.Brush.Style := brushClear;

  // Title
  pdf.Font.Name      := 'Helvetica';
  pdf.Font.Bold      := True;
  pdf.Font.Italics   := False;
  pdf.Font.Underline := False;
  pdf.Font.Size      := 28;
  pdf.Font.Color     := clBlack;
  pdf.DrawText('smPDF ' + #$2014 + ' Phase 3 Text', 50, 50);

  // Subtitle (italic, lighter)
  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 12;
  pdf.Font.Color   := $00606060;
  pdf.DrawText('Standard 14 fonts, alignment, paragraphs, and underlines', 50, 95);

  // Font samples
  y := 140;
  pdf.Font.Color   := clBlack;
  pdf.Font.Italics := False;

  pdf.Font.Name := 'Helvetica';  pdf.Font.Bold := False; pdf.DrawText('Helvetica regular',  50, y); Inc(y, 20);
  pdf.Font.Name := 'Helvetica';  pdf.Font.Bold := True;  pdf.DrawText('Helvetica bold',     50, y); Inc(y, 20);
  pdf.Font.Italics := True;
  pdf.Font.Name := 'Helvetica';  pdf.Font.Bold := False; pdf.DrawText('Helvetica oblique', 50, y); Inc(y, 20);
  pdf.Font.Italics := False;

  pdf.Font.Name := 'Times';      pdf.Font.Bold := False; pdf.DrawText('Times Roman',       50, y); Inc(y, 20);
  pdf.Font.Name := 'Times';      pdf.Font.Bold := True;  pdf.DrawText('Times Bold',        50, y); Inc(y, 20);
  pdf.Font.Italics := True;
  pdf.Font.Name := 'Times';      pdf.Font.Bold := False; pdf.DrawText('Times Italic',      50, y); Inc(y, 20);
  pdf.Font.Italics := False;

  pdf.Font.Name := 'Courier';    pdf.Font.Bold := False; pdf.DrawText('Courier (mono)',    50, y); Inc(y, 30);

  // Coloured + underlined
  pdf.Font.Name      := 'Helvetica';
  pdf.Font.Bold      := False;
  pdf.Font.Italics   := False;
  pdf.Font.Underline := True;
  pdf.Font.Color     := $004060FF;  // warm red
  pdf.DrawText('Underlined coloured text', 50, y);
  pdf.Font.Underline := False;
  Inc(y, 30);

  // Alignment in rectangle
  pdf.Font.Color := clBlack;
  pdf.Brush.Style := brushClear;
  pdf.Pen.Color   := $00B0B0B0;
  pdf.Pen.Style   := penDash;
  pdf.Pen.Width   := 0.5;
  pdf.DrawBox(50, y, 545, y + 35);
  pdf.Pen.Style   := penSolid;

  pdf.Font.Size  := 11;
  pdf.DrawText('left aligned',   TRect.Create(50, y, 545, y + 35), taLeftJustify);
  pdf.DrawText('centered',       TRect.Create(50, y, 545, y + 35), taCenter);
  pdf.DrawText('right aligned',  TRect.Create(50, y, 545, y + 35), taRightJustify);
  Inc(y, 50);

  // Paragraph with single padding (left aligned)
  pdf.Font.Size := 10;
  pdf.Pen.Color := $00B0B0B0;
  pdf.Pen.Style := penDash;
  pdf.DrawBox(50, y, 295, y + 200);
  pdf.DrawParagraph(LOREM, TRect.Create(55, y + 5, 290, y + 200),
    taLeftJustify, tpSingle);

  // Paragraph centered with double padding
  pdf.DrawBox(305, y, 545, y + 200);
  pdf.DrawParagraph(LOREM, TRect.Create(310, y + 5, 540, y + 200),
    taCenter, tpDouble);
  pdf.Pen.Style := penSolid;
  Inc(y, 220);

  // Justified-right paragraph at the bottom
  pdf.Font.Size := 9;
  pdf.Font.Italics := True;
  pdf.DrawParagraph(
    'The 14 standard fonts are WinAnsi (cp1252) only ' + #$2014 +
    ' use an embedded TrueType font for anything else (page 8); ' +
    'Bold/Italic widths approximated from regular Helvetica/Times; ' +
    'no kerning, no justified text.',
    TRect.Create(50, y, 545, y + 80),
    taRightJustify, tpTight);
end;

procedure DrawPage4TTF(pdf: TsmPDF);
var
  y: Integer;
begin
  // Page 4: A4 portrait at 72 dpi -> 595 x 842 user pixels.
  pdf.Brush.Style := brushClear;

  // Title in embedded Arial Bold
  pdf.Font.Name      := 'Arial';
  pdf.Font.Bold      := True;
  pdf.Font.Italics   := False;
  pdf.Font.Underline := False;
  pdf.Font.Size      := 28;
  pdf.Font.Color     := clBlack;
  pdf.DrawText('Phase 4 ' + #$2014 + ' TrueType embedding', 50, 50);

  // Subtitle
  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 12;
  pdf.Font.Color   := $00606060;
  pdf.DrawText('Installed Windows fonts, subset and embedded as CID fonts', 50, 95);

  // Section: Arial family (all 4 variants embedded as separate TTFs)
  y := 140;
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Italics := False;
  pdf.Font.Bold    := True;
  pdf.Font.Color   := clBlack;
  pdf.Font.Size    := 11;
  pdf.DrawText('Arial family (4 faces, each subset):', 50, y);
  Inc(y, 22);

  pdf.Font.Name := 'Arial';
  pdf.Font.Size := 14;

  pdf.Font.Bold := False; pdf.Font.Italics := False; pdf.DrawText('Arial regular',     70, y); Inc(y, 22);
  pdf.Font.Bold := True;  pdf.Font.Italics := False; pdf.DrawText('Arial Bold',        70, y); Inc(y, 22);
  pdf.Font.Bold := False; pdf.Font.Italics := True;  pdf.DrawText('Arial Italic',      70, y); Inc(y, 22);
  pdf.Font.Bold := True;  pdf.Font.Italics := True;  pdf.DrawText('Arial Bold Italic', 70, y); Inc(y, 30);

  // Section: Calibri (modern Microsoft font, distinct from Arial)
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 11;
  pdf.DrawText('Calibri:', 50, y);
  Inc(y, 22);

  pdf.Font.Name := 'Calibri';
  pdf.Font.Size := 14;
  pdf.Font.Bold := False; pdf.Font.Italics := False; pdf.DrawText('Calibri regular',   70, y); Inc(y, 22);
  pdf.Font.Bold := True;  pdf.Font.Italics := False; pdf.DrawText('Calibri Bold',      70, y); Inc(y, 22);
  pdf.Font.Bold := False; pdf.Font.Italics := True;  pdf.DrawText('Calibri Italic',    70, y); Inc(y, 30);

  // Section: Verdana
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 11;
  pdf.DrawText('Verdana:', 50, y);
  Inc(y, 22);

  pdf.Font.Name := 'Verdana';
  pdf.Font.Size := 14;
  pdf.Font.Bold := False; pdf.Font.Italics := False; pdf.DrawText('Verdana regular',   70, y); Inc(y, 22);
  pdf.Font.Bold := True;  pdf.Font.Italics := False; pdf.DrawText('Verdana Bold',      70, y); Inc(y, 30);

  // Section: side-by-side Standard 14 vs TTF
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 11;
  pdf.DrawText('Standard 14 vs embedded TTF (same words, different metrics):', 50, y);
  Inc(y, 22);

  pdf.Font.Bold := False;
  pdf.Font.Size := 14;

  pdf.Font.Name := 'Helvetica';      pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 22);
  pdf.Font.Name := 'Arial';          pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 22);
  pdf.Font.Name := 'Times';          pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 22);
  pdf.Font.Name := 'Times New Roman';pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 22);
  pdf.Font.Name := 'Courier';        pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 22);
  pdf.Font.Name := 'Courier New';    pdf.DrawText('The quick brown fox jumps over the lazy dog.', 70, y); Inc(y, 30);

  // Accented text through an embedded TrueType font.
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 11;
  pdf.DrawText('Accented text via embedded Arial:', 50, y);
  Inc(y, 22);

  pdf.Font.Name := 'Arial';
  pdf.Font.Size := 14;
  pdf.Font.Bold := False;
  pdf.DrawText('caf' + #$E9 + ' na' + #$EF + 've r' + #$E9 + 'sum' + #$E9 +
               ' fa' + #$E7 + 'ade ' + #$A3 + #$20AC + ' ' + #$AB + 'guillemets' + #$BB,
               70, y);
  Inc(y, 30);

  // Bottom note
  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 9;
  pdf.Font.Color   := $00606060;
  pdf.DrawParagraph(
    'Fonts are found through GDI (so .ttc collections and per-user fonts work) ' +
    'and embedded as subsets carrying only the glyphs drawn: a page of Arial ' +
    'adds about 20 KB instead of 1 MB. Each TrueType font is a Type0 / ' +
    'CIDFontType2 font with Identity-H encoding and a ToUnicode map, so any ' +
    'character the font has can be drawn, searched and copied.',
    TRect.Create(50, y, 545, y + 100), taLeftJustify, tpSingle);
end;

// ---- Image helpers used by the Phase 5 demo page ----

function MakeRainbowBitmap(AWidth, AHeight: Integer): TBitmap;
var
  x, y: Integer;
  hue, sat, val: Double;
  r, g, b: Byte;
  c, n, k, m: Double;
  rs, gs, bs: Double;
begin
  // Simple HSV-to-RGB rainbow gradient. Hue varies by x, value falls off near edges.
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  for y := 0 to AHeight - 1 do
    for x := 0 to AWidth - 1 do
    begin
      hue := (x / AWidth) * 360.0;
      sat := 0.85;
      val := 0.6 + 0.4 * (1.0 - Abs((y / AHeight) - 0.5) * 2.0);

      c := val * sat;
      n := hue / 60.0;
      k := c * (1.0 - Abs((n - 2.0 * Floor(n / 2.0)) - 1.0));
      m := val - c;
      case Trunc(n) mod 6 of
        0: begin rs := c; gs := k; bs := 0; end;
        1: begin rs := k; gs := c; bs := 0; end;
        2: begin rs := 0; gs := c; bs := k; end;
        3: begin rs := 0; gs := k; bs := c; end;
        4: begin rs := k; gs := 0; bs := c; end;
      else
            begin rs := c; gs := 0; bs := k; end;
      end;
      r := Byte(Round((rs + m) * 255));
      g := Byte(Round((gs + m) * 255));
      b := Byte(Round((bs + m) * 255));
      Result.Canvas.Pixels[x, y] := RGB(r, g, b);
    end;
end;

function MakeCheckerPng(AWidth, AHeight, ATileSize: Integer): TPngImage;
var
  x, y: Integer;
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AWidth, AHeight);
    for y := 0 to AHeight - 1 do
      for x := 0 to AWidth - 1 do
        if ((x div ATileSize) + (y div ATileSize)) mod 2 = 0 then
          bmp.Canvas.Pixels[x, y] := RGB(48, 110, 200)
        else
          bmp.Canvas.Pixels[x, y] := RGB(240, 240, 240);
    Result := TPngImage.Create;
    Result.Assign(bmp);
  finally
    bmp.Free;
  end;
end;

function MakeAlphaCirclePng(ASize: Integer): TPngImage;
var
  x, y: Integer;
  cx, cy, r, dist, alpha: Double;
  alphaRow: PByteArray;
begin
  Result := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, ASize, ASize);
  cx := ASize / 2.0;
  cy := ASize / 2.0;
  r  := ASize / 2.0;
  for y := 0 to ASize - 1 do
  begin
    alphaRow := Result.AlphaScanline[y];
    for x := 0 to ASize - 1 do
    begin
      dist := Sqrt(Sqr(x - cx) + Sqr(y - cy));
      // Solid teal inside, faded to transparent at the rim
      Result.Pixels[x, y] := RGB(0, 130, 150);
      if dist >= r then
        alpha := 0
      else
        alpha := 1.0 - (dist / r);
      alphaRow^[x] := Byte(Round(alpha * 255));
    end;
  end;
end;

function MakeRainbowJpeg(AWidth, AHeight: Integer): TJPEGImage;
var
  bmp: TBitmap;
begin
  bmp := MakeRainbowBitmap(AWidth, AHeight);
  try
    Result := TJPEGImage.Create;
    Result.CompressionQuality := 85;
    Result.Assign(bmp);
    Result.Compress;  // ensure JPEG bytes are in the internal buffer
  finally
    bmp.Free;
  end;
end;

procedure DrawPage5Images(pdf: TsmPDF);
var
  picBmp, picPng, picAlpha, picJpeg: TPicture;
  bmp:        TBitmap;
  png:        TPngImage;
  alphaPng:   TPngImage;
  jpeg:       TJPEGImage;
  y:          Integer;
begin
  // Build the four images
  bmp      := MakeRainbowBitmap(240, 80);
  png      := MakeCheckerPng(240, 80, 20);
  alphaPng := MakeAlphaCirclePng(160);
  jpeg     := MakeRainbowJpeg(240, 80);

  picBmp   := TPicture.Create; picBmp.Assign(bmp);
  picPng   := TPicture.Create; picPng.Assign(png);
  picAlpha := TPicture.Create; picAlpha.Assign(alphaPng);
  picJpeg  := TPicture.Create; picJpeg.Assign(jpeg);

  try
    // Title
    pdf.Brush.Style    := brushClear;
    pdf.Font.Name      := 'Arial';
    pdf.Font.Bold      := True;
    pdf.Font.Italics   := False;
    pdf.Font.Underline := False;
    pdf.Font.Size      := 28;
    pdf.Font.Color     := clBlack;
    pdf.DrawText('Phase 5 ' + #$2014 + ' Images', 50, 50);

    pdf.Font.Bold    := False;
    pdf.Font.Italics := True;
    pdf.Font.Size    := 12;
    pdf.Font.Color   := $00606060;
    pdf.DrawText('TBitmap, PNG (opaque + alpha), and JPEG embedded as XObjects', 50, 95);

    // Section labels in bold Helvetica; images draw at native pixel size.
    pdf.Font.Italics := False;
    pdf.Font.Bold    := True;
    pdf.Font.Color   := clBlack;
    pdf.Font.Name    := 'Helvetica';

    y := 140;

    pdf.Font.Size := 11;
    pdf.DrawText('TBitmap (FlateDecode RGB):', 50, y);
    Inc(y, 20);
    pdf.DrawPicture(picBmp, 50, y);
    Inc(y, 100);

    pdf.DrawText('PNG checkerboard (FlateDecode RGB, opaque):', 50, y);
    Inc(y, 20);
    pdf.DrawPicture(picPng, 50, y);
    Inc(y, 100);

    pdf.DrawText('PNG with alpha (SMask) over a coloured rectangle:', 50, y);
    Inc(y, 20);
    // Draw the colored rectangle behind the alpha-circle so the transparency is visible
    pdf.Brush.Style := brushSolid;
    pdf.Brush.Color := $00B0B0E0;       // pale lavender
    pdf.Pen.Style   := penNone;
    pdf.DrawBox(50, y, 50 + 200, y + 160);
    pdf.Brush.Style := brushClear;
    pdf.Pen.Style   := penSolid;
    pdf.DrawPicture(picAlpha, 70, y);
    Inc(y, 180);

    pdf.DrawText('JPEG (DCTDecode passthrough):', 50, y);
    Inc(y, 20);
    pdf.DrawPicture(picJpeg, 50, y);
    Inc(y, 100);

    // Same picture drawn twice — only one XObject should appear in the PDF
    pdf.DrawText('Same TPicture drawn twice (one XObject, two cm/Do calls):', 50, y);
    Inc(y, 20);
    pdf.DrawPicture(picBmp, 50,  y);
    pdf.DrawPicture(picBmp, 310, y);
    Inc(y, 110);

    // Bottom note
    pdf.Font.Bold    := False;
    pdf.Font.Italics := True;
    pdf.Font.Size    := 9;
    pdf.Font.Color   := $00606060;
    pdf.DrawParagraph(
      'Phase 5 supports JPEG (DCTDecode passthrough), opaque PNG/BMP (FlateDecode RGB), ' +
      'and PNG with an alpha channel (SMask). 8-bit images only; CMYK JPEGs and palette ' +
      'PNGs are not handled. A single TPicture instance drawn multiple times produces ' +
      'just one Image XObject thanks to TsmPDF''s pointer-keyed dedup.',
      TRect.Create(50, y, 545, y + 80), taLeftJustify, tpSingle);
  finally
    picJpeg.Free;
    picAlpha.Free;
    picPng.Free;
    picBmp.Free;
    jpeg.Free;
    alphaPng.Free;
    png.Free;
    bmp.Free;
  end;
end;

// ---- Page 6: realistic invoice combining text + graphics + images ----

procedure InvoiceLineItem(pdf: TsmPDF; ATop: Integer;
  const ADescription: string; AQty: Integer; AUnitPrice, ALineTotal: Double);
begin
  pdf.Font.Name    := 'Calibri';
  pdf.Font.Bold    := False;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 10;
  pdf.Font.Color   := $00303030;

  pdf.DrawText(ADescription,                                       60,  ATop);
  pdf.DrawText(IntToStr(AQty),                                    340,  ATop);
  pdf.DrawText(Format('$%.2f', [AUnitPrice]),
    TRect.Create(380, ATop, 460, ATop + 14), taRightJustify);
  pdf.DrawText(Format('$%.2f', [ALineTotal]),
    TRect.Create(465, ATop, 545, ATop + 14), taRightJustify);
end;

procedure DrawPage6Invoice(pdf: TsmPDF);
const
  MARGIN   = 50;
  PAGE_W   = 595;
  PAGE_H   = 842;
  RIGHT    = PAGE_W - MARGIN;
var
  y, tableTop: Integer;
  subtotal, tax, total: Double;
begin
  // ---- Logo: three overlapping discs in the top-left ----
  pdf.Brush.Style := brushSolid;
  pdf.Pen.Style   := penNone;

  pdf.Brush.Color := $00B0682C;            // teal-ish blue
  pdf.DrawOval(MARGIN,        50, MARGIN + 30,        80);
  pdf.Brush.Color := $002878DC;            // warm orange
  pdf.DrawOval(MARGIN + 18,   50, MARGIN + 48,        80);
  pdf.Brush.Color := $0048A030;            // forest green
  pdf.DrawOval(MARGIN + 36,   50, MARGIN + 66,        80);

  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;

  // ---- Company name + tagline ----
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 22;
  pdf.Font.Color   := $00404040;
  pdf.DrawText('Acme Trifecta Co.', MARGIN + 80, 50);

  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 10;
  pdf.Font.Color   := $00808080;
  pdf.DrawText('Three things, done well, every time.', MARGIN + 82, 80);

  // ---- Right-aligned address block ----
  pdf.Font.Italics := False;
  pdf.Font.Size    := 9;
  pdf.Font.Color   := $00404040;
  pdf.DrawText('123 Threefold Lane',         TRect.Create(MARGIN, 50,  RIGHT, 64),  taRightJustify);
  pdf.DrawText('Edinburgh EH1 1AA',          TRect.Create(MARGIN, 64,  RIGHT, 78),  taRightJustify);
  pdf.DrawText('+44 131 555 0100',           TRect.Create(MARGIN, 78,  RIGHT, 92),  taRightJustify);
  pdf.DrawText('hello@acmetrifecta.example', TRect.Create(MARGIN, 92,  RIGHT, 106), taRightJustify);

  // ---- Horizontal divider ----
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  pdf.DrawLine(MARGIN, 130, RIGHT, 130);

  // ---- INVOICE heading + invoice metadata ----
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Size    := 32;
  pdf.Font.Color   := $00404040;
  pdf.DrawText('INVOICE', MARGIN, 150);

  pdf.Font.Size  := 10;
  pdf.Font.Bold  := False;
  pdf.DrawText('Invoice #',   TRect.Create(MARGIN, 152, RIGHT - 80, 166), taRightJustify);
  pdf.DrawText('2026-0042',   TRect.Create(MARGIN, 152, RIGHT,      166), taRightJustify);
  pdf.DrawText('Issue date',  TRect.Create(MARGIN, 168, RIGHT - 80, 182), taRightJustify);
  pdf.DrawText('1 May 2026',  TRect.Create(MARGIN, 168, RIGHT,      182), taRightJustify);
  pdf.DrawText('Due date',    TRect.Create(MARGIN, 184, RIGHT - 80, 198), taRightJustify);
  pdf.DrawText('31 May 2026', TRect.Create(MARGIN, 184, RIGHT,      198), taRightJustify);

  // ---- Bill-to block ----
  y := 230;
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 9;
  pdf.Font.Color := $00808080;
  pdf.DrawText('BILL TO', MARGIN, y);
  Inc(y, 16);

  pdf.Font.Bold  := False;
  pdf.Font.Size  := 11;
  pdf.Font.Color := $00303030;
  pdf.Font.Name  := 'Calibri';
  pdf.DrawText('Cozmix Software Ltd.', MARGIN, y); Inc(y, 14);
  pdf.DrawText('Attn: Steve Maughan',  MARGIN, y); Inc(y, 14);
  pdf.DrawText('1 Holyrood Road',      MARGIN, y); Inc(y, 14);
  pdf.DrawText('Edinburgh EH8 8AS',    MARGIN, y);

  // ---- Line items table ----
  tableTop := 320;
  pdf.Font.Name  := 'Helvetica';
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 9;
  pdf.Font.Color := clWhite;

  // Table header bar
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $00604030;            // dark teal
  pdf.Pen.Style   := penNone;
  pdf.DrawBox(MARGIN, tableTop, RIGHT, tableTop + 22);
  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;

  pdf.DrawText('DESCRIPTION', 60, tableTop + 6);
  pdf.DrawText('QTY',         340, tableTop + 6);
  pdf.DrawText('UNIT',
    TRect.Create(380, tableTop + 6, 460, tableTop + 20), taRightJustify);
  pdf.DrawText('TOTAL',
    TRect.Create(465, tableTop + 6, 545, tableTop + 20), taRightJustify);

  // Items
  y := tableTop + 32;
  InvoiceLineItem(pdf, y, 'Phase 1 — Foundation (writer, geometry, page skeleton)',  1, 1200.00, 1200.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 2 — Graphics primitives (lines, polygons, clip)',   1,  800.00,  800.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 3 — Standard 14 fonts + paragraph layout',          1,  900.00,  900.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 4 — TrueType embedding (Win registry lookup)',      1, 1500.00, 1500.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 5 — JPEG / PNG / BMP / SMask images',               1, 1000.00, 1000.00); Inc(y, 22);

  // Subtotal/tax/total
  Inc(y, 6);
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  pdf.DrawLine(380, y, RIGHT, y);
  Inc(y, 8);

  subtotal := 5400.00;
  tax      := subtotal * 0.20;
  total    := subtotal + tax;

  pdf.Font.Bold := False;
  pdf.Font.Size := 10;
  pdf.Font.Color := $00404040;
  pdf.DrawText('Subtotal', TRect.Create(380, y, 460, y + 14), taRightJustify);
  pdf.DrawText(Format('$%.2f', [subtotal]),
    TRect.Create(465, y, RIGHT, y + 14), taRightJustify);
  Inc(y, 16);

  pdf.DrawText('VAT 20%', TRect.Create(380, y, 460, y + 14), taRightJustify);
  pdf.DrawText(Format('$%.2f', [tax]),
    TRect.Create(465, y, RIGHT, y + 14), taRightJustify);
  Inc(y, 22);

  // Total bar
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $00604030;
  pdf.Pen.Style   := penNone;
  pdf.DrawBox(380, y - 4, RIGHT, y + 22);
  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;

  pdf.Font.Bold := True;
  pdf.Font.Size := 12;
  pdf.Font.Color := clWhite;
  pdf.DrawText('TOTAL',
    TRect.Create(380, y, 460, y + 16), taRightJustify);
  pdf.DrawText(Format('$%.2f', [total]),
    TRect.Create(465, y, RIGHT, y + 16), taRightJustify);

  // ---- Notes / payment terms ----
  y := y + 80;
  pdf.Font.Color := $00808080;
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 9;
  pdf.DrawText('NOTES', MARGIN, y);
  Inc(y, 16);

  pdf.Font.Bold    := False;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 10;
  pdf.Font.Color   := $00303030;
  pdf.Font.Name    := 'Calibri';
  pdf.DrawParagraph(
    'Payment is due within 30 days of the issue date by bank transfer to ' +
    'GB29 NWBK 6016 1331 9268 19. Please reference invoice 2026-0042 in the ' +
    'transfer description. Late payments accrue 2% interest per month.',
    TRect.Create(MARGIN, y, RIGHT, y + 80), taLeftJustify, tpSingle);

  // ---- Footer rule + page number ----
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  pdf.DrawLine(MARGIN, PAGE_H - 50, RIGHT, PAGE_H - 50);

  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 8;
  pdf.Font.Color   := $00808080;
  pdf.DrawText('Acme Trifecta Co. ' + #$2014 + ' Registered in Scotland SC123456 ' +
               #$2014 + ' VAT GB123456789',
    MARGIN, PAGE_H - 40);
  pdf.DrawText('Page 6 of 6',
    TRect.Create(MARGIN, PAGE_H - 40, RIGHT, PAGE_H - 26), taRightJustify);
end;

procedure DrawPage7Rotation(pdf: TsmPDF);
const
  PAGE_W = 595;
var
  cx, cy, radius, i: Integer;
  angleDeg, thetaRad: Double;
  px, py: Integer;
  rowY: Integer;
begin
  // Defensive reset: prior pages may have left graphics state set
  pdf.Brush.Style      := brushClear;
  pdf.Pen.Style        := penSolid;
  pdf.Pen.Color        := clBlack;
  pdf.Pen.Width        := 1.0;
  pdf.Font.Color       := clBlack;
  pdf.Font.StrokeStyle := ssNone;
  pdf.Font.Underline   := False;
  pdf.Font.Bold        := False;
  pdf.Font.Italics     := False;
  pdf.Font.Name        := 'Helvetica';

  // Title
  pdf.Font.Bold := True;
  pdf.Font.Size := 28;
  pdf.DrawText('Phase 7 ' + #$2014 + ' Rotated text', 50, 50);

  // Subtitle
  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 12;
  pdf.Font.Color   := $00606060;
  pdf.DrawText(
    'DrawText(s, X, Y, AAngle) where AAngle is CCW degrees (matches TFont.Orientation)',
    50, 90);
  pdf.Font.Italics := False;
  pdf.Font.Color   := clBlack;

  // ---- Compass rose: 12 'smPDF' spokes at 30 deg intervals ----
  cx     := PAGE_W div 2;
  cy     := 280;
  radius := 70;

  pdf.Font.Bold := True;
  pdf.Font.Size := 14;
  for i := 0 to 11 do
  begin
    angleDeg := i * 30.0;
    thetaRad := angleDeg * Pi / 180.0;
    // Anchor sits on a circle of radius `radius` at visual CCW angle angleDeg.
    // User Y is top-down so we subtract sin to go visually north.
    px := cx + Round(radius * Cos(thetaRad));
    py := cy - Round(radius * Sin(thetaRad));
    pdf.DrawText('smPDF', px, py - 8, angleDeg);
  end;

  // Tiny dot at the centre so the radial geometry reads cleanly
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := clBlack;
  pdf.Pen.Style   := penNone;
  pdf.DrawOval(cx - 3, cy - 3, cx + 3, cy + 3);
  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;

  // ---- Three real-world labelled examples ----
  rowY := 430;

  pdf.Font.Bold  := True;
  pdf.Font.Size  := 10;
  pdf.Font.Color := $00606060;
  pdf.DrawText('VERTICAL COLUMN HEADER (-90 deg)', 50,  rowY);
  pdf.DrawText('SPINE LABEL (+90 deg)',            240, rowY);
  pdf.DrawText('SLIGHT TILT (+5 deg)',             420, rowY);
  pdf.Font.Color := clBlack;
  pdf.Font.Bold  := False;

  // (1) Vertical column header — reads downward at -90 deg
  pdf.Pen.Color := $00B0B0B0;
  pdf.DrawBox(60, rowY + 20, 110, rowY + 180);
  pdf.Font.Bold := True;
  pdf.Font.Size := 14;
  pdf.DrawText('REVENUE', 100, rowY + 30, -90);
  pdf.Font.Bold := False;

  // (2) Spine label — reads upward at +90 deg
  pdf.DrawBox(250, rowY + 20, 300, rowY + 180);
  pdf.Font.Bold := True;
  pdf.Font.Size := 14;
  pdf.DrawText('Volume IV', 270, rowY + 170, 90);
  pdf.Font.Bold := False;

  // (3) Slight tilt — sub-header on a casual angle
  pdf.Font.Bold := True;
  pdf.Font.Size := 18;
  pdf.DrawText('Quarterly', 420, rowY + 60, 5);
  pdf.Font.Bold := False;
  pdf.Font.Size := 11;
  pdf.Font.Color := $00808080;
  pdf.DrawText('FY 2026', 420, rowY + 90, 5);
  pdf.Font.Color := clBlack;
  pdf.Pen.Color  := clBlack;

  // ---- Combined-styling watermark: Brush + StrokeStyle + AAngle ----
  // Demonstrates that the text-background fill and the glyph outline rotate
  // along with the text — they're all wrapped in the same q/cm/Q transform.
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 10;
  pdf.Font.Color := $00606060;
  pdf.DrawText('BRUSH + STROKESTYLE + ANGLE ALL ROTATE TOGETHER:', 50, 660);
  pdf.Font.Color := clBlack;
  pdf.Font.Bold  := False;

  pdf.Brush.Style      := brushSolid;
  pdf.Brush.Color      := $0080FFFF;          // pale yellow
  pdf.Font.StrokeStyle := ssThick;
  pdf.Font.StrokeColor := $00404040;          // dark grey outline
  pdf.Font.Color       := $004040FF;          // warm red fill
  pdf.Font.Size        := 60;
  pdf.Font.Bold        := True;
  pdf.DrawText('DRAFT', 100, 740, -20);
  pdf.Brush.Style      := brushClear;
  pdf.Font.StrokeStyle := ssNone;
  pdf.Font.Color       := clBlack;
  pdf.Font.Bold        := False;
end;

// ---- Page 8: smPDF 2.0 features ----

procedure DrawSection(pdf: TsmPDF; const ATitle: string; Y: Double);
begin
  pdf.Font.Name := 'Helvetica';
  pdf.Font.Bold := True;
  pdf.Font.Italics := False;
  pdf.Font.Size := 11;
  pdf.Font.Color := clBlack;
  pdf.Font.StrokeWidth := 0;
  pdf.Brush.Style := brushClear;
  pdf.DrawText(ATitle, 50, Y);
end;

procedure DrawUnicodeLine(pdf: TsmPDF; const AFamily, ACaption, AText: string; Y: Double);
begin
  pdf.Font.Name := 'Helvetica';
  pdf.Font.Bold := False;
  pdf.Font.Size := 9;
  pdf.Font.Color := $00606060;
  pdf.DrawText(ACaption, 70, Y + 3);
  pdf.Font.Name := AFamily;
  pdf.Font.Size := 14;
  pdf.Font.Color := clBlack;
  pdf.DrawText(AText, 190, Y);
end;

procedure DrawPage8Maps(pdf: TsmPDF);
var
  frame: TRectF;
  ring: TArray<TPointF>;
  y: Double;
  i: Integer;
  m: TPDFTextMetrics;
  labels: array[0..2] of string;
begin
  pdf.Brush.Style := brushClear;
  pdf.Pen.Style := penSolid;
  pdf.Font.Name := 'Arial';
  pdf.Font.Bold := True;
  pdf.Font.Italics := False;
  pdf.Font.Size := 28;
  pdf.Font.Color := clBlack;
  pdf.DrawText('smPDF 2.0 ' + #$2014 + ' Unicode and map text', 50, 50);

  // Unicode through CID fonts.
  y := 105;
  DrawSection(pdf, 'Unicode text (each TrueType font is a Type0 font with Identity-H):', y);
  y := y + 24;
  DrawUnicodeLine(pdf, 'Arial', 'Polish, Czech, Hungarian', 'Łódź · Dvořák · Győr · Kraków · Brno', y);    y := y + 22;
  DrawUnicodeLine(pdf, 'Arial', 'Vietnamese',               'Hà Nội · Hồ Chí Minh · Đà Nẵng', y);          y := y + 22;
  DrawUnicodeLine(pdf, 'Arial', 'Greek, Cyrillic',          'Αθήνα · Θεσσαλονίκη · Москва · Київ', y);     y := y + 22;
  DrawUnicodeLine(pdf, 'Microsoft YaHei', 'Chinese (YaHei)','北京市 · 上海市 · 广州市 · 深圳市', y);          y := y + 24;
  DrawUnicodeLine(pdf, 'Yu Gothic', 'Japanese (Yu Gothic)', '東京都 · 大阪府 · 札幌市 · さいたま市', y);      y := y + 24;
  DrawUnicodeLine(pdf, 'Malgun Gothic', 'Korean (Malgun)',  '서울특별시 · 부산광역시 · 인천', y);            y := y + 34;

  // A small map: clip frame, poly-polygon with a hole, road, haloed labels, icons.
  DrawSection(pdf, 'Map drawing: clip, poly-polygons, roads, halo labels, outline icons:', y);
  y := y + 22;
  frame := TRectF.Create(50, y, 545, y + 250);
  pdf.Pen.Color := $00808080;
  pdf.Pen.Width := 1;
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $00F4EEE6;
  pdf.DrawRoundRect(frame, 10, 10);

  pdf.PushClipRect(TRectF.Create(frame.Left + 4, frame.Top + 4, frame.Right - 4, frame.Bottom - 4));
  // Territory with a lake: outer ring plus hole, explicit counts.
  ring := TArray<TPointF>.Create(
    TPointF.Create(20, y + 20),  TPointF.Create(330, y + 10), TPointF.Create(380, y + 150),
    TPointF.Create(250, y + 280), TPointF.Create(30, y + 220),
    TPointF.Create(150, y + 90), TPointF.Create(230, y + 80), TPointF.Create(240, y + 150),
    TPointF.Create(160, y + 170));
  pdf.Brush.Color := $00B8D8F0;
  pdf.Pen.Color := $00406080;
  pdf.Pen.Width := 1.2;
  pdf.Pen.LineJoin := ljRound;
  pdf.DrawPolyPolygon(ring, [5, 4], frEvenOdd);
  ring := TArray<TPointF>.Create(
    TPointF.Create(380, y + 150), TPointF.Create(600, y + 40), TPointF.Create(600, y + 300),
    TPointF.Create(250, y + 280));
  pdf.Brush.Color := $00C8E8C8;
  pdf.DrawPolyPolygon(ring, [4], frNonZero);
  // A road.
  pdf.Pen.Color := $003070C0;
  pdf.Pen.Width := 3;
  pdf.Pen.LineCap := lcRound;
  pdf.DrawPolyline(TArray<TPointF>.Create(TPointF.Create(40, y + 240), TPointF.Create(160, y + 200),
    TPointF.Create(300, y + 215), TPointF.Create(420, y + 120), TPointF.Create(560, y + 110)));
  pdf.Pen.LineCap := lcButt;

  // Halo labels: stroke under the fill vs over it.
  pdf.Brush.Style := brushClear;
  pdf.TextOrigin := toGdiTop;
  pdf.Font.Name := 'Oswald';
  pdf.Font.Bold := False;
  pdf.Font.Size := 15.5;
  pdf.Font.Color := $00202020;
  pdf.Font.StrokeColor := clWhite;
  pdf.Font.StrokeWidth := 1.2;
  pdf.Font.StrokeMode := smUnderFill;
  pdf.DrawText('North East District', 80, y + 40);
  pdf.Font.Size := 11;
  pdf.DrawText('halo under fill (smUnderFill)', 80, y + 62);
  pdf.Font.StrokeMode := smOverFill;
  pdf.DrawText('stroke over fill (smOverFill)', 300, y + 62);
  pdf.Font.StrokeMode := smUnderFill;
  pdf.Font.Size := 12;
  pdf.DrawText('Lake Winnipesaukee', 150, y + 185, 12);

  // Rep icons drawn as vector outlines of Ionicons glyphs.
  pdf.Font.Name := 'Ionicons';
  pdf.Font.Size := 22;
  pdf.Font.Color := $000030C0;
  pdf.Font.StrokeWidth := 1;
  for i := 0 to 3 do
    pdf.DrawTextOutlines(#$F202, 420 + i * 28, y + 180);
  pdf.DrawTextOutlines(#$F25D, 420 + 4 * 28, y + 180);
  pdf.PopClip;
  pdf.Font.StrokeWidth := 0;

  // GDI metrics: stacked labels measured like TCanvas.
  y := frame.Bottom + 24;
  DrawSection(pdf, 'Labels stacked with GDI metrics (TextOrigin = toGdiTop; boxes are TextHeight):', y);
  y := y + 24;
  labels[0] := 'Worcester';
  labels[1] := 'Charmain Speer';
  labels[2] := '$5,457,842';
  pdf.Font.Name := 'Oswald';
  pdf.Font.Color := clBlack;
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  for i := 0 to 2 do
  begin
    pdf.Font.Size := 16 - i * 3;
    m := pdf.FontMetrics;
    pdf.Brush.Style := brushClear;
    pdf.DrawBox(70, y, 70 + pdf.TextWidthF(labels[i]), y + m.LineHeight);
    pdf.DrawText(labels[i], 70, y);
    y := y + m.LineHeight;
  end;
  pdf.TextOrigin := toTypoTop;

  pdf.Font.Name := 'Helvetica';
  pdf.Font.Bold := False;
  pdf.Font.Italics := True;
  pdf.Font.Size := 9;
  pdf.Font.Color := $00606060;
  pdf.DrawParagraph(
    'Fonts that are not installed fall back to Helvetica and are listed in ' +
    'TsmPDF.Warnings, as is any character a font cannot show. Complex-script ' +
    'shaping (Arabic, Indic, Thai) and right-to-left text are not supported.',
    TRect.Create(50, Round(y) + 20, 545, Round(y) + 80), taLeftJustify, tpSingle);
end;

var
  pdf: TsmPDF;
  outDir, outFile: string;
  nBytes: Int64;
  i: Integer;
begin
  try
    outDir  := ExtractFilePath(ParamStr(0));
    outFile := TPath.Combine(outDir, 'sample.pdf');

    pdf := TsmPDF.Create;
    try
      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage1Primitives(pdf);

      pdf.NewPage(psA4, poLandscape, 72);
      DrawPage2PenStyles(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage3Text(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage4TTF(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage5Images(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage6Invoice(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage7Rotation(pdf);

      pdf.NewPage(psA4, poPortrait,  72);
      DrawPage8Maps(pdf);

      pdf.Title := 'smPDF ' + SMPDF_VERSION + ' showcase';
      for i := 0 to pdf.Warnings.Count - 1 do
        Writeln('warning: ', pdf.Warnings[i]);

      nBytes := pdf.Save(outFile);
    finally
      pdf.Free;
    end;

    Writeln('OK: wrote ', outFile);
    Writeln('     pages: 8');
    Writeln('     bytes: ', nBytes);
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
