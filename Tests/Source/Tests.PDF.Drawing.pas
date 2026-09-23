unit Tests.PDF.Drawing;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework;

type
  TDrawingTests = class(TTestCase)
  protected
    function SavedAsString(const ABuild: TProc<TObject>): string;
    function CountOccurrences(const ASubstring, AString: string): Integer;
  published
    // DrawLine
    procedure Test_DrawLine_emitsMoveLineStroke;
    procedure Test_DrawLine_setsStrokeColorFromPen;
    procedure Test_DrawLine_setsLineWidth;
    procedure Test_DrawLine_penNone_emitsNothing;
    procedure Test_DrawLine_dashedPen_emitsDashArray;

    // DrawBox
    procedure Test_DrawBox_strokeAndFill_emitsBStar;
    procedure Test_DrawBox_strokeOnly_emitsStroke;
    procedure Test_DrawBox_fillOnly_emitsFillEvenOdd;
    procedure Test_DrawBox_neitherStrokeNorFill_emitsNothing;
    procedure Test_DrawBox_emitsRectangleOperator;

    // DrawOval
    procedure Test_DrawOval_emitsFourCurveOperators;
    procedure Test_DrawOval_solidPenClearBrush_emitsStroke;

    // DrawMultiLine (open polyline)
    procedure Test_DrawMultiLine_emitsMoveAndLines;
    procedure Test_DrawMultiLine_emitsStrokeNotFill;
    procedure Test_DrawMultiLine_singlePoint_emitsNothing;

    // DrawPolygon
    procedure Test_DrawPolygon_singleSquare_emitsOneClose;
    procedure Test_DrawPolygon_squareWithSquareHole_emitsTwoCloses;
    procedure Test_DrawPolygon_unclosedFinalSubpath_isAutoClosed;
    procedure Test_DrawPolygon_consecutiveDuplicateOfStart_doesNotPrematurelyClose;
    procedure Test_DrawPolygon_usesEvenOddFillRule;
    procedure Test_DrawPolygon_strokeOnly_emitsStrokeWithoutFill;

    // DrawPolygon clipped to rect
    procedure Test_DrawPolygonClipped_emitsClipBeforePath;
    procedure Test_DrawPolygonClipped_emitsTwoQOperators;
  end;

implementation

uses
  StrUtils, IOUtils, Vcl.Graphics, smPDF;

function TDrawingTests.SavedAsString(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  fn: string;
  bytes: TBytes;
  i: Integer;
begin
  fn := TPath.Combine(TPath.GetTempPath, 'smPDF-tests-draw.pdf');
  if TFile.Exists(fn) then TFile.Delete(fn);

  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    ABuild(pdf);
    pdf.Save(fn);
  finally
    pdf.Free;
  end;
  bytes := TFile.ReadAllBytes(fn);
  SetLength(Result, Length(bytes));
  for i := 0 to High(bytes) do
    Result[i + 1] := Char(bytes[i]);
end;

function TDrawingTests.CountOccurrences(const ASubstring, AString: string): Integer;
var
  p, found: Integer;
begin
  Result := 0;
  if ASubstring = '' then Exit;
  p := 1;
  repeat
    found := PosEx(ASubstring, AString, p);
    if found > 0 then
    begin
      Inc(Result);
      p := found + Length(ASubstring);
    end;
  until found = 0;
end;

// ===== DrawLine =====

procedure TDrawingTests.Test_DrawLine_emitsMoveLineStroke;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawLine(10, 10, 100, 100);
  end);
  AssertContains(' m'#10, s, 'moveto');
  AssertContains(' l'#10, s, 'lineto');
  AssertContains('S'#10, s, 'stroke');
end;

procedure TDrawingTests.Test_DrawLine_setsStrokeColorFromPen;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Color := clRed;        // VCL clRed = $0000FF -> R=1, G=0, B=0
    TsmPDF(o).DrawLine(0, 0, 100, 100);
  end);
  AssertContains('1 0 0 RG', s);
end;

procedure TDrawingTests.Test_DrawLine_setsLineWidth;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Width := 3.5;
    TsmPDF(o).DrawLine(0, 0, 50, 50);
  end);
  AssertContains('3.5 w', s);
end;

procedure TDrawingTests.Test_DrawLine_penNone_emitsNothing;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Style := penNone;
    TsmPDF(o).DrawLine(0, 0, 50, 50);
  end);
  AssertFalse(Pos(' m'#10, s) > 0, 'no moveto when pen is penNone');
  AssertFalse(Pos('S'#10, s) > 0, 'no stroke when pen is penNone');
end;

procedure TDrawingTests.Test_DrawLine_dashedPen_emitsDashArray;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Style := penDash;
    TsmPDF(o).DrawLine(0, 0, 100, 0);
  end);
  AssertContains('[3 2] 0 d', s);
end;

// ===== DrawBox =====

procedure TDrawingTests.Test_DrawBox_strokeAndFill_emitsBStar;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertContains('B*'#10, s, 'fill+stroke even-odd');
end;

procedure TDrawingTests.Test_DrawBox_strokeOnly_emitsStroke;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushClear;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertContains('S'#10, s);
  AssertFalse(Pos('B*'#10, s) > 0, 'no fill+stroke');
  AssertFalse(Pos('f*'#10, s) > 0, 'no fill');
end;

procedure TDrawingTests.Test_DrawBox_fillOnly_emitsFillEvenOdd;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Style   := penNone;
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertContains('f*'#10, s);
  AssertFalse(Pos('B*'#10, s) > 0, 'fill-only must not stroke');
end;

procedure TDrawingTests.Test_DrawBox_neitherStrokeNorFill_emitsNothing;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Style   := penNone;
    TsmPDF(o).Brush.Style := brushClear;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertFalse(Pos(' re'#10, s) > 0, 'no rectangle path emitted');
end;

procedure TDrawingTests.Test_DrawBox_emitsRectangleOperator;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawBox(10, 20, 110, 120);
  end);
  AssertContains(' re'#10, s);
end;

// ===== DrawOval =====

procedure TDrawingTests.Test_DrawOval_emitsFourCurveOperators;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawOval(0, 0, 200, 200);
  end);
  AssertEquals(4, CountOccurrences(' c'#10, s), 'four cubic-bezier curves');
end;

procedure TDrawingTests.Test_DrawOval_solidPenClearBrush_emitsStroke;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawOval(10, 10, 100, 100);
  end);
  AssertContains('S'#10, s);
end;

// ===== DrawMultiLine =====

procedure TDrawingTests.Test_DrawMultiLine_emitsMoveAndLines;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(10, 10));
    pts.Add(TPoint.Create(50, 30));
    pts.Add(TPoint.Create(100, 80));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawMultiLine(pts);
    end);
  finally
    pts.Free;
  end;
  AssertEquals(1, CountOccurrences(' m'#10, s), 'one moveto for the first point');
  AssertEquals(2, CountOccurrences(' l'#10, s), 'two linetos for the remaining points');
end;

procedure TDrawingTests.Test_DrawMultiLine_emitsStrokeNotFill;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(0, 0));
    pts.Add(TPoint.Create(100, 100));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).Brush.Style := brushSolid;  // even with solid brush, polyline doesn't fill
      TsmPDF(o).DrawMultiLine(pts);
    end);
  finally
    pts.Free;
  end;
  AssertContains('S'#10, s);
  AssertFalse(Pos('f*'#10, s) > 0, 'open polyline must never fill');
end;

procedure TDrawingTests.Test_DrawMultiLine_singlePoint_emitsNothing;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(10, 10));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawMultiLine(pts);
    end);
  finally
    pts.Free;
  end;
  AssertFalse(Pos(' m'#10, s) > 0, 'single point should not produce a path');
end;

// ===== DrawPolygon (hole detection) =====

procedure TDrawingTests.Test_DrawPolygon_singleSquare_emitsOneClose;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(10, 10));
    pts.Add(TPoint.Create(110, 10));
    pts.Add(TPoint.Create(110, 110));
    pts.Add(TPoint.Create(10, 110));
    // not explicitly closed — auto-close at end
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertEquals(1, CountOccurrences('h'#10, s), 'exactly one ClosePath for one subpath');
end;

procedure TDrawingTests.Test_DrawPolygon_squareWithSquareHole_emitsTwoCloses;
var
  s: string;
  pts: TPDFPointList;
begin
  // Outer square 0..100, inner hole 30..70. Outer closed by repeating start point;
  // inner subpath also closed by repeating its start.
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(0,   0));
    pts.Add(TPoint.Create(100, 0));
    pts.Add(TPoint.Create(100, 100));
    pts.Add(TPoint.Create(0,   100));
    pts.Add(TPoint.Create(0,   0));    // closes outer
    pts.Add(TPoint.Create(30,  30));   // starts inner
    pts.Add(TPoint.Create(70,  30));
    pts.Add(TPoint.Create(70,  70));
    pts.Add(TPoint.Create(30,  70));
    pts.Add(TPoint.Create(30,  30));   // closes inner
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertEquals(2, CountOccurrences('h'#10, s), 'two subpaths -> two ClosePaths');
end;

procedure TDrawingTests.Test_DrawPolygon_consecutiveDuplicateOfStart_doesNotPrematurelyClose;
var
  s: string;
  pts: TPDFPointList;
begin
  // A ring whose second vertex equals the first (e.g. caller projected
  // dense geographic coordinates to integer pixels and adjacent vertices
  // collapsed onto the start). The whole sequence must form one subpath
  // with one ClosePath, not split into degenerate subpaths.
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(10, 10));
    pts.Add(TPoint.Create(10, 10));   // collapsed-to-start duplicate
    pts.Add(TPoint.Create(50, 10));
    pts.Add(TPoint.Create(50, 50));
    pts.Add(TPoint.Create(10, 50));
    pts.Add(TPoint.Create(10, 10));   // real ring closure
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertEquals(1, CountOccurrences('h'#10, s),
    'leading duplicate-of-start must not close the subpath');
end;

procedure TDrawingTests.Test_DrawPolygon_unclosedFinalSubpath_isAutoClosed;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    // First subpath explicitly closed; second not — should still close.
    pts.Add(TPoint.Create(0,   0));
    pts.Add(TPoint.Create(50,  0));
    pts.Add(TPoint.Create(50,  50));
    pts.Add(TPoint.Create(0,   50));
    pts.Add(TPoint.Create(0,   0));    // closes first
    pts.Add(TPoint.Create(60,  60));
    pts.Add(TPoint.Create(80,  60));
    pts.Add(TPoint.Create(80,  80));
    // omitted return-to-start
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertEquals(2, CountOccurrences('h'#10, s),
    'unclosed final subpath should be auto-closed -> two total closes');
end;

procedure TDrawingTests.Test_DrawPolygon_usesEvenOddFillRule;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(10, 10));
    pts.Add(TPoint.Create(50, 10));
    pts.Add(TPoint.Create(50, 50));
    pts.Add(TPoint.Create(10, 50));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).Brush.Style := brushSolid;
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertContains('B*'#10, s, 'even-odd fill+stroke');
  AssertFalse(Pos(' f'#10, s) > 0, 'must not use non-zero fill operator');
end;

procedure TDrawingTests.Test_DrawPolygon_strokeOnly_emitsStrokeWithoutFill;
var
  s: string;
  pts: TPDFPointList;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(0, 0));
    pts.Add(TPoint.Create(50, 0));
    pts.Add(TPoint.Create(50, 50));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).Brush.Style := brushClear;
      TsmPDF(o).DrawPolygon(pts);
    end);
  finally
    pts.Free;
  end;
  AssertContains('S'#10, s);
  AssertFalse(Pos('f*'#10, s) > 0, 'fill must not appear when brush is brushClear');
  AssertFalse(Pos('B*'#10, s) > 0, 'fill+stroke must not appear when brush is brushClear');
end;

// ===== DrawPolygon clipped =====

procedure TDrawingTests.Test_DrawPolygonClipped_emitsClipBeforePath;
var
  s: string;
  pts: TPDFPointList;
  posWStar, posM: Integer;
begin
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(0, 0));
    pts.Add(TPoint.Create(200, 0));
    pts.Add(TPoint.Create(200, 200));
    pts.Add(TPoint.Create(0, 200));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts, TRect.Create(50, 50, 150, 150));
    end);
  finally
    pts.Free;
  end;
  posWStar := Pos('W*'#10, s);
  posM     := Pos(' m'#10, s);
  AssertTrue(posWStar > 0, 'clip operator W* present');
  AssertTrue(posM > 0,     'polygon moveto present');
  AssertTrue(posWStar < posM, 'clip must be set before the polygon path is constructed');
end;

procedure TDrawingTests.Test_DrawPolygonClipped_emitsTwoQOperators;
var
  s: string;
  pts: TPDFPointList;
begin
  // The clipped overload wraps in q ... Q like the unclipped one. We don't
  // double-nest here. Exactly one save/restore pair.
  pts := TPDFPointList.Create;
  try
    pts.Add(TPoint.Create(0, 0));
    pts.Add(TPoint.Create(100, 0));
    pts.Add(TPoint.Create(100, 100));
    s := SavedAsString(procedure(o: TObject)
    begin
      TsmPDF(o).DrawPolygon(pts, TRect.Create(10, 10, 90, 90));
    end);
  finally
    pts.Free;
  end;
  AssertEquals(1, CountOccurrences('q'#10, s), 'exactly one SaveState');
  AssertEquals(1, CountOccurrences('Q'#10, s), 'exactly one RestoreState');
end;

initialization
  TTestRegistry.RegisterTestCase(TDrawingTests);

end.
