program smPDF_InvoiceDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Types,
  System.Classes,
  System.UITypes,
  Vcl.Graphics,
  smPDF;

procedure InvoiceLineItem(pdf: TsmPDF; ATop: Integer;
  const ADescription: string; AQty: Integer; AUnitPrice, ALineTotal: Double);
begin
  pdf.Font.Name    := 'Helvetica';
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

procedure DrawInvoice(pdf: TsmPDF);
const
  MARGIN   = 50;
  PAGE_W   = 595;
  PAGE_H   = 842;
  RIGHT    = PAGE_W - MARGIN;
var
  x, y, tableTop: Integer;
  subtotal, tax, total: Double;
begin
  // Logo: three overlapping discs in the top-left
  pdf.Brush.Style := brushSolid;
  pdf.Pen.Style   := penNone;

  pdf.Brush.Color := $00B0682C;
  pdf.DrawOval(MARGIN,        50, MARGIN + 30,        80);
  pdf.Brush.Color := $002878DC;
  pdf.DrawOval(MARGIN + 18,   50, MARGIN + 48,        80);
  pdf.Brush.Color := $0048A030;
  pdf.DrawOval(MARGIN + 36,   50, MARGIN + 66,        80);

  pdf.Pen.Style   := penSolid;
  pdf.Brush.Style := brushClear;

  // Company name + tagline
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

  // Right-aligned address block
  pdf.Font.Italics := False;
  pdf.Font.Size    := 9;
  pdf.Font.Color   := $00404040;
  pdf.DrawText('123 Threefold Lane',         TRect.Create(MARGIN, 50,  RIGHT, 64),  taRightJustify);
  pdf.DrawText('Edinburgh EH1 1AA',          TRect.Create(MARGIN, 64,  RIGHT, 78),  taRightJustify);
  pdf.DrawText('+44 131 555 0100',           TRect.Create(MARGIN, 78,  RIGHT, 92),  taRightJustify);
  pdf.DrawText('hello@acmetrifecta.example', TRect.Create(MARGIN, 92,  RIGHT, 106), taRightJustify);

  // Horizontal divider
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  pdf.DrawLine(MARGIN, 130, RIGHT, 130);

  // INVOICE heading + invoice metadata
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

  // Bill-to block
  y := 230;
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 9;
  pdf.Font.Color := $00808080;
  pdf.DrawText('BILL TO', MARGIN, y);
  Inc(y, 16);

  pdf.Font.Bold  := False;
  pdf.Font.Size  := 11;
  pdf.Font.Color := $00303030;
  pdf.DrawText('Cozmix Software Ltd.', MARGIN, y); Inc(y, 14);
  pdf.DrawText('Attn: Steve Maughan',  MARGIN, y); Inc(y, 14);
  pdf.DrawText('1 Holyrood Road',      MARGIN, y); Inc(y, 14);
  pdf.DrawText('Edinburgh EH8 8AS',    MARGIN, y);

  // Line items table
  tableTop := 320;
  pdf.Font.Bold  := True;
  pdf.Font.Size  := 9;
  pdf.Font.Color := clWhite;

  // Table header bar
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := $00604030;
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
  InvoiceLineItem(pdf, y, 'Phase 1 - Foundation (writer, geometry, page skeleton)', 1, 1200.00, 1200.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 2 - Graphics primitives (lines, polygons, clip)',  1,  800.00,  800.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 3 - Standard 14 fonts + paragraph layout',         1,  900.00,  900.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 4 - TrueType embedding (Win registry lookup)',     1, 1500.00, 1500.00); Inc(y, 22);
  InvoiceLineItem(pdf, y, 'Phase 5 - JPEG / PNG / BMP / SMask images',              1, 1000.00, 1000.00); Inc(y, 22);

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

  pdf.Font.Bold  := True;
  pdf.Font.Size  := 12;
  pdf.Font.Color := clWhite;
  pdf.DrawText('TOTAL',
    TRect.Create(380, y, 460, y + 16), taRightJustify);
  pdf.DrawText(Format('$%.2f', [total]),
    TRect.Create(465, y, RIGHT, y + 16), taRightJustify);

  // Notes / payment terms
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
  pdf.DrawParagraph(
    'Payment is due within 30 days of the issue date by bank transfer to ' +
    'GB29 NWBK 6016 1331 9268 19. Please reference invoice 2026-0042 in the ' +
    'transfer description. Late payments accrue 2% interest per month.',
    TRect.Create(MARGIN, y, RIGHT, y + 80), taLeftJustify, tpSingle);

  // Footer rule + page number
  pdf.Pen.Color := $00C0C0C0;
  pdf.Pen.Width := 0.5;
  pdf.DrawLine(MARGIN, PAGE_H - 50, RIGHT, PAGE_H - 50);

  pdf.Font.Bold    := False;
  pdf.Font.Italics := True;
  pdf.Font.Size    := 8;
  pdf.Font.Color   := $00808080;
  pdf.DrawText('Acme Trifecta Co. ' + #$2014 + ' Registered in Scotland SC123456 ' +
               #$2014 + ' VAT GB123456789',
    MARGIN, PAGE_H - 40);
  pdf.DrawText('Page 1 of 1',
    TRect.Create(MARGIN, PAGE_H - 40, RIGHT, PAGE_H - 26), taRightJustify);

  // Tiled "PAID" watermark drawn LAST so it sits on top of the invoice
  // content. The 4-arg DrawText overload takes a CCW degrees angle and
  // rotates around the (X, Y) anchor — tile anchors on a regular grid and
  // each glyph row becomes a diagonal band at 45 degrees. Range extends past
  // the page edges so the rotated bounding boxes still cover the corners;
  // anything outside the MediaBox is clipped by the viewer.
  pdf.Font.Name        := 'Helvetica';
  pdf.Font.Bold        := True;
  pdf.Font.Italics     := False;
  pdf.Font.Underline   := False;
  pdf.Font.Size        := 60;
  pdf.Font.Color       := $00D0D0D0;        // light grey (no transparency in PDF 1.4 path)
  pdf.Font.StrokeStyle := ssNone;
  pdf.Brush.Style      := brushClear;       // don't paint a background behind the watermark
  y := -180;
  while y < PAGE_H + 180 do
  begin
    x := -180;
    while x < PAGE_W + 180 do
    begin
      pdf.DrawText('PAID', x, y, 45);
      Inc(x, 180);
    end;
    Inc(y, 180);
  end;
end;

var
  pdf: TsmPDF;
  outDir, outFile: string;
  nBytes: Int64;
begin
  try
    outDir  := ExtractFilePath(ParamStr(0));
    outFile := TPath.Combine(outDir, 'invoice.pdf');

    pdf := TsmPDF.Create;
    try
      pdf.NewPage(psA4, poPortrait, 72);
      DrawInvoice(pdf);
      nBytes := pdf.Save(outFile);
    finally
      pdf.Free;
    end;

    Writeln('OK: wrote ', outFile);
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
