unit Tests.PDF.PolyPolygon;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TPolyPolygonTests = class(TTestCase)
  protected
    function Build(const ABuild: TProc<TObject>): string;
    function ContentOf(const APdf: string): string;
  published
    procedure Test_TwoParts_emitTwoMoveTosAndTwoCloses;
    procedure Test_RingTouchingItsStart_isNotSplit;
    procedure Test_DefaultRule_fillAndStroke_isBStar;
    procedure Test_EvenOdd_fillOnly_isFStar;
    procedure Test_NonZero_fillOnly_isF;
    procedure Test_NonZero_fillAndStroke_isB;
    procedure Test_StrokeOnly_isS;
    procedure Test_PartsUnderTwoPoints_areSkipped;
    procedure Test_CountsExceedingPoints_raise;
    procedure Test_NegativeCount_raises;
    procedure Test_IntegerPointOverload_emitsPath;
    procedure Test_Polyline_strokesOpenPath;
    procedure Test_Polyline_countLimitsPoints;
    procedure Test_Polyline_countTooLarge_raises;
    procedure Test_Polyline_penNone_emitsNothing;
  end;

implementation

uses
  StrUtils, Vcl.Graphics, smPDF;

function TPolyPolygonTests.Build(const ABuild: TProc<TObject>): string;
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

function TPolyPolygonTests.ContentOf(const APdf: string): string;
var
  a, b: Integer;
begin
  a := Pos('stream'#10, APdf);
  b := PosEx(#10'endstream', APdf, a);
  Result := Copy(APdf, a + 7, b - a - 7);
end;

function SquareWithHole: TArray<TPointF>;
begin
  Result := TArray<TPointF>.Create(
    TPointF.Create(10, 10), TPointF.Create(110, 10), TPointF.Create(110, 110), TPointF.Create(10, 110),
    TPointF.Create(40, 40), TPointF.Create(80, 40), TPointF.Create(80, 80), TPointF.Create(40, 80));
end;

procedure TPolyPolygonTests.Test_TwoParts_emitTwoMoveTosAndTwoCloses;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4]);
  end));
  AssertEquals(2, CountSubstring(' m'#10, s));
  AssertEquals(6, CountSubstring(' l'#10, s));
  AssertEquals(2, CountSubstring(#10'h'#10, s));
end;

procedure TPolyPolygonTests.Test_RingTouchingItsStart_isNotSplit;
var s: string;
begin
  // The third point equals the first; DrawPolygon would have closed the ring there.
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyPolygon(TArray<TPointF>.Create(
      TPointF.Create(10, 10), TPointF.Create(50, 10), TPointF.Create(10, 10),
      TPointF.Create(50, 50), TPointF.Create(10, 50)), [5]);
  end));
  AssertEquals(1, CountSubstring(' m'#10, s));
  AssertEquals(4, CountSubstring(' l'#10, s));
  AssertEquals(1, CountSubstring(#10'h'#10, s));
end;

procedure TPolyPolygonTests.Test_DefaultRule_fillAndStroke_isBStar;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4]);
  end));
  AssertContains(#10'B*'#10, s);
end;

procedure TPolyPolygonTests.Test_EvenOdd_fillOnly_isFStar;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Pen.Style := penNone;
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4], frEvenOdd);
  end));
  AssertContains(#10'f*'#10, s);
end;

procedure TPolyPolygonTests.Test_NonZero_fillOnly_isF;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Pen.Style := penNone;
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4], frNonZero);
  end));
  AssertContains(#10'f'#10, s);
  AssertEquals(0, Pos('f*', s), 'non-zero fill must not use f*');
end;

procedure TPolyPolygonTests.Test_NonZero_fillAndStroke_isB;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4], frNonZero);
  end));
  AssertContains(#10'B'#10, s);
  AssertEquals(0, Pos('B*', s));
end;

procedure TPolyPolygonTests.Test_StrokeOnly_isS;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyPolygon(SquareWithHole, [4, 4], frNonZero);
  end));
  AssertContains(#10'S'#10, s);
end;

procedure TPolyPolygonTests.Test_PartsUnderTwoPoints_areSkipped;
var s: string;
begin
  // Parts of 1 and 0 points are skipped, but their points are still consumed.
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyPolygon(TArray<TPointF>.Create(
      TPointF.Create(1, 1),
      TPointF.Create(10, 10), TPointF.Create(20, 10), TPointF.Create(20, 20)), [1, 0, 3]);
  end));
  AssertEquals(1, CountSubstring(' m'#10, s));
  AssertContains('10 782 m', s);
end;

procedure TPolyPolygonTests.Test_CountsExceedingPoints_raise;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    raised := False;
    try
      pdf.DrawPolyPolygon(SquareWithHole, [4, 5]);
    except
      on EPDFError do raised := True;
    end;
    AssertTrue(raised, 'counts summing past the point array must raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TPolyPolygonTests.Test_NegativeCount_raises;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    raised := False;
    try
      pdf.DrawPolyPolygon(SquareWithHole, [4, -1]);
    except
      on EPDFError do raised := True;
    end;
    AssertTrue(raised, 'a negative count must raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TPolyPolygonTests.Test_IntegerPointOverload_emitsPath;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyPolygon(TArray<TPoint>.Create(
      Point(10, 10), Point(20, 10), Point(20, 20),
      Point(30, 30), Point(40, 30), Point(40, 40)), [3, 3], frNonZero);
  end));
  AssertEquals(2, CountSubstring(' m'#10, s));
  AssertContains('30 762 m', s);
end;

procedure TPolyPolygonTests.Test_Polyline_strokesOpenPath;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyline(TArray<TPointF>.Create(
      TPointF.Create(1.5, 2), TPointF.Create(3, 4), TPointF.Create(5, 6)));
  end));
  AssertContains('1.5 790 m', s);
  AssertEquals(2, CountSubstring(' l'#10, s));
  AssertContains(#10'S'#10, s);
  AssertEquals(0, CountSubstring(#10'h'#10, s), 'a polyline is not closed');
end;

procedure TPolyPolygonTests.Test_Polyline_countLimitsPoints;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawPolyline(TArray<TPointF>.Create(
      TPointF.Create(1, 2), TPointF.Create(3, 4), TPointF.Create(5, 6)), 2);
  end));
  AssertEquals(1, CountSubstring(' l'#10, s));
end;

procedure TPolyPolygonTests.Test_Polyline_countTooLarge_raises;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    raised := False;
    try
      pdf.DrawPolyline(TArray<TPointF>.Create(TPointF.Create(1, 2), TPointF.Create(3, 4)), 3);
    except
      on EPDFError do raised := True;
    end;
    AssertTrue(raised);
  finally
    pdf.Free;
  end;
end;

procedure TPolyPolygonTests.Test_Polyline_penNone_emitsNothing;
var s: string;
begin
  s := ContentOf(Build(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Style := penNone;
    TsmPDF(o).DrawPolyline(TArray<TPointF>.Create(TPointF.Create(1, 2), TPointF.Create(3, 4)));
  end));
  AssertEquals(0, CountSubstring(' m'#10, s));
end;

initialization
  TTestRegistry.RegisterTestCase(TPolyPolygonTests);

end.
