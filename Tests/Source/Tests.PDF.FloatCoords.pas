unit Tests.PDF.FloatCoords;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TFloatCoordTests = class(TTestCase)
  protected
    function Build(const ABuild: TProc<TObject>): string;
  published
    procedure Test_FontSize_fractional_appearsVerbatimInTf;
    procedure Test_DoubleCoords_roundTripToThreeDecimals;
    procedure Test_NewPagePoints_A4_exactMediaBox;
    procedure Test_NewPagePoints_defaultsTo72Dpi;
    procedure Test_NewPagePoints_widerThanTall_isLandscape;
    procedure Test_NewPagePoints_nonPositive_raises;
    procedure Test_NewPage_paramless_afterPointsPage_keepsExactSize;
    procedure Test_NewPagePaperSize_mediaBoxIsExactPoints;
    procedure Test_YFlip_topEdgeMapsToPageHeight;
    procedure Test_YFlip_300dpi_oneInchDown;
    procedure Test_DrawText_integerOverload_stillResolves;
    procedure Test_DrawText_doubleOverload_placesFractionalBaseline;
    procedure Test_TextExtentF_isUnrounded;
    procedure Test_DrawPolygonF_emitsFractionalPath;
    procedure Test_DrawMultiLineF_emitsFractionalPath;
    procedure Test_DrawBoxAndOval_doubleOverloads;
  end;

implementation

uses
  Generics.Collections, Vcl.Graphics, smPDF;

function TFloatCoordTests.Build(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    ABuild(pdf);
    Result := PdfBytesToString(pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_FontSize_fractional_appearsVerbatimInTf;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size := 7.35;
    TsmPDF(o).DrawText('Label', 10, 10);
  end);
  AssertContains('/F1 7.35 Tf', s);
end;

procedure TFloatCoordTests.Test_DoubleCoords_roundTripToThreeDecimals;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawLine(10.12345, 20.5, 100.0006, 30.25);
  end);
  AssertContains('10.123 771.5 m', s);
  AssertContains('100.001 761.75 l', s);
end;

procedure TFloatCoordTests.Test_NewPagePoints_A4_exactMediaBox;
var
  pdf: TsmPDF;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(595.28, 841.89);
    s := PdfBytesToString(pdf.ToBytes);
    AssertContains('/MediaBox [0 0 595.28 841.89]', s);
    AssertEquals(595.28, pdf.WidthPt, 1e-12);
    AssertEquals(841.89, pdf.HeightPt, 1e-12);
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_NewPagePoints_defaultsTo72Dpi;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(2383.94, 3370.39);
    AssertEquals(72, pdf.DPI);
    AssertEquals(2384, pdf.Width);
    AssertEquals(3370, pdf.Height);
    AssertTrue(pdf.Size = psCustom, 'points page reports psCustom');
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_NewPagePoints_widerThanTall_isLandscape;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(3370.39, 2383.94);
    AssertTrue(pdf.Orientation = poLandscape);
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_NewPagePoints_nonPositive_raises;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  try
    raised := False;
    try
      pdf.NewPage(0.0, 100.0);
    except
      on EPDFError do raised := True;
    end;
    AssertTrue(raised, 'zero width must raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_NewPage_paramless_afterPointsPage_keepsExactSize;
var
  pdf: TsmPDF;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(500.5, 700.25);
    pdf.NewPage;
    s := PdfBytesToString(pdf.ToBytes);
    AssertEquals(2, CountSubstring('/MediaBox [0 0 500.5 700.25]', s));
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_NewPagePaperSize_mediaBoxIsExactPoints;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(psA4, poPortrait, 300);
    AssertContains('/MediaBox [0 0 595.28 841.89]', PdfBytesToString(pdf.ToBytes),
      'A4 at 300 DPI is not rounded through pixels');
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_YFlip_topEdgeMapsToPageHeight;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawLine(0, 0, 10, 792);
  end);
  AssertContains('0 792 m', s);
  AssertContains('10 0 l', s);
end;

procedure TFloatCoordTests.Test_YFlip_300dpi_oneInchDown;
var
  pdf: TsmPDF;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(psLetter, poLandscape, 300);
    pdf.DrawLine(0, 100, 300, 300);
    s := PdfBytesToString(pdf.ToBytes);
    // 100 px at 300 DPI = 24 pt below the 612 pt top edge.
    AssertContains('0 588 m', s);
    AssertContains('72 540 l', s);
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_DrawText_integerOverload_stillResolves;
var s: string;
begin
  s := Build(procedure(o: TObject)
  var
    x, y: Integer;
  begin
    x := 10;
    y := 20;
    TsmPDF(o).DrawText('A', x, y);
    TsmPDF(o).DrawText('B', 10, 20, 0);
  end);
  // Helvetica ascent 0.718 * 12 = 8.616; baseline 28.616 px -> 792 - 28.616.
  AssertEquals(2, CountSubstring('1 0 0 1 10 763.384 Tm', s));
end;

procedure TFloatCoordTests.Test_DrawText_doubleOverload_placesFractionalBaseline;
var s: string;
begin
  s := Build(procedure(o: TObject)
  var
    x, y: Double;
  begin
    x := 10.5;
    y := 20.25;
    TsmPDF(o).DrawText('A', x, y);
    TsmPDF(o).DrawText('B', 10.5, 20.25, 0);
  end);
  AssertEquals(2, CountSubstring('1 0 0 1 10.5 763.134 Tm', s));
end;

procedure TFloatCoordTests.Test_TextExtentF_isUnrounded;
var
  pdf: TsmPDF;
  ext: TSizeF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    ext := pdf.TextExtentF('Hi');
    AssertEquals(11.328, ext.cx, 1e-4);
    AssertEquals(14.4, ext.cy, 1e-4);
    AssertEquals(11.328, pdf.TextWidthF('Hi'), 1e-9);
    AssertEquals(14.4, pdf.TextHeightF('Hi'), 1e-9);
    AssertEquals(11, pdf.TextWidth('Hi'));
  finally
    pdf.Free;
  end;
end;

procedure TFloatCoordTests.Test_DrawPolygonF_emitsFractionalPath;
var s: string;
begin
  s := Build(procedure(o: TObject)
  var
    pts: TPDFPointFList;
  begin
    pts := TPDFPointFList.Create;
    try
      pts.Add(TPointF.Create(10.5, 20.25));
      pts.Add(TPointF.Create(110.5, 20.25));
      pts.Add(TPointF.Create(60.125, 90.75));
      TsmPDF(o).Brush.Style := brushSolid;
      TsmPDF(o).DrawPolygon(pts);
    finally
      pts.Free;
    end;
  end);
  AssertContains('10.5 771.75 m', s);
  AssertContains('60.125 701.25 l', s);
  AssertContains('B*', s);
end;

procedure TFloatCoordTests.Test_DrawMultiLineF_emitsFractionalPath;
var s: string;
begin
  s := Build(procedure(o: TObject)
  var
    pts: TPDFPointFList;
  begin
    pts := TPDFPointFList.Create;
    try
      pts.Add(TPointF.Create(1.5, 2.5));
      pts.Add(TPointF.Create(3.5, 4.5));
      TsmPDF(o).DrawMultiLine(pts);
    finally
      pts.Free;
    end;
  end);
  AssertContains('1.5 789.5 m', s);
  AssertContains('3.5 787.5 l', s);
end;

procedure TFloatCoordTests.Test_DrawBoxAndOval_doubleOverloads;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawBox(10.5, 20.5, 30.5, 40.5);
    TsmPDF(o).DrawOval(10.5, 20.5, 30.5, 40.5);
  end);
  AssertContains('10.5 751.5 20 20 re', s);
  AssertContains('20.5 771.5 m', s, 'oval starts at the top centre');
end;

initialization
  TTestRegistry.RegisterTestCase(TFloatCoordTests);

end.
