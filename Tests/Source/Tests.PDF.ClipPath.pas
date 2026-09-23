unit Tests.PDF.ClipPath;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TClipPathTests = class(TTestCase)
  protected
    function Build(const ABuild: TProc<TObject>): string;
    function CountLines(const AContent, ALine: string): Integer;
    procedure ExpectError(const AAction: TProc<TObject>; const AMsg: string);
  published
    // W6 clip stack
    procedure Test_PushClipRect_emitsSaveRectangleClip;
    procedure Test_NestedPushPop_balancesSaveRestore;
    procedure Test_UnpoppedClips_closedAtEmit;
    procedure Test_Emit_doesNotChangeThePage;
    procedure Test_PopClip_underflow_raises;
    procedure Test_PopClip_afterNewPage_raises;
    procedure Test_PushClipRect_integerOverload;
    procedure Test_DrawInsideClip_setsOwnState;

    // W7 path API
    procedure Test_Path_fill_operatorSequence;
    procedure Test_Path_stroke_usesPen;
    procedure Test_Path_fillAndStroke_evenOdd;
    procedure Test_Path_fillWithClearBrush_paintsNothing;
    procedure Test_Path_moveToWithoutBeginPath_raises;
    procedure Test_Path_lineToWithoutMoveTo_raises;
    procedure Test_Path_drawWhileOpen_raises;
    procedure Test_Path_newPageWhileOpen_raises;
    procedure Test_Path_beginPathTwice_raises;
    procedure Test_Path_clipWhileOpen_raises;
    procedure Test_Path_saveWhileOpen_raises;
    procedure Test_Path_saveToFileWhileOpen_leavesExistingFile;
    procedure Test_Path_measuringWhileOpen_isAllowed;
    procedure Test_RoundRect_zeroRadius_equalsDrawBox;
    procedure Test_RoundRect_emitsFourCurves;
    procedure Test_RoundRect_radiusClampedToHalfSize;
  end;

implementation

uses
  StrUtils, IOUtils, Vcl.Graphics, smPDF;

function TClipPathTests.Build(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  s: string;
  a, b: Integer;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    ABuild(pdf);
    s := PdfBytesToString(pdf.ToBytes);
  finally
    pdf.Free;
  end;
  // Content of the first stream only.
  a := Pos('stream'#10, s);
  b := PosEx(#10'endstream', s, a);
  Result := Copy(s, a + 7, b - a - 7);
end;

function TClipPathTests.CountLines(const AContent, ALine: string): Integer;
var
  line: string;
begin
  Result := 0;
  for line in AContent.Split([#10]) do
    if line = ALine then Inc(Result);
end;

procedure TClipPathTests.ExpectError(const AAction: TProc<TObject>; const AMsg: string);
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    raised := False;
    try
      AAction(pdf);
    except
      on EPDFError do raised := True;
    end;
    AssertTrue(raised, AMsg);
  finally
    pdf.Free;
  end;
end;

// ===== W6 =====

procedure TClipPathTests.Test_PushClipRect_emitsSaveRectangleClip;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRectF.Create(10, 20, 110, 70));
    TsmPDF(o).PopClip;
  end);
  AssertEquals('q'#10'10 722 100 50 re'#10'W n'#10'Q'#10, s);
end;

procedure TClipPathTests.Test_NestedPushPop_balancesSaveRestore;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRectF.Create(0, 0, 300, 300));
    TsmPDF(o).PushClipRect(TRectF.Create(50, 50, 100, 100));
    TsmPDF(o).DrawLine(0, 0, 200, 200);
    TsmPDF(o).PopClip;
    TsmPDF(o).DrawLine(0, 200, 200, 0);
    TsmPDF(o).PopClip;
  end);
  AssertEquals(2, CountLines(s, 'W n'));
  AssertEquals(CountLines(s, 'q'), CountLines(s, 'Q'), 'q/Q must balance');
  AssertEquals(4, CountLines(s, 'q'));
end;

procedure TClipPathTests.Test_UnpoppedClips_closedAtEmit;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRectF.Create(0, 0, 300, 300));
    TsmPDF(o).PushClipRect(TRectF.Create(50, 50, 100, 100));
    TsmPDF(o).DrawLine(0, 0, 200, 200);
  end);
  AssertEquals(CountLines(s, 'q'), CountLines(s, 'Q'), 'open clips are closed when the page is written');
  AssertTrue(EndsText('Q'#10'Q'#10, s), 'the closing Qs come last');
end;

procedure TClipPathTests.Test_Emit_doesNotChangeThePage;
var
  pdf: TsmPDF;
  first, second: TBytes;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.PushClipRect(TRectF.Create(0, 0, 300, 300));
    first  := pdf.ToBytes;
    second := pdf.ToBytes;
    AssertBytesEqual(first, second, 'saving twice gives the same bytes');
    // The clip is still open on the page, so PopClip must still work.
    pdf.PopClip;
    s := PdfBytesToString(pdf.ToBytes);
    AssertEquals(1, CountSubstring('W n', s));
  finally
    pdf.Free;
  end;
end;

procedure TClipPathTests.Test_PopClip_underflow_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).PopClip;
  end, 'PopClip with nothing pushed must raise EPDFError');
end;

procedure TClipPathTests.Test_PopClip_afterNewPage_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRectF.Create(0, 0, 10, 10));
    TsmPDF(o).NewPage;
    TsmPDF(o).PopClip;
  end, 'clips belong to their page');
end;

procedure TClipPathTests.Test_PushClipRect_integerOverload;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRect.Create(10, 20, 110, 70));
  end);
  AssertContains('10 722 100 50 re'#10'W n', s);
end;

procedure TClipPathTests.Test_DrawInsideClip_setsOwnState;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).PushClipRect(TRectF.Create(0, 0, 100, 100));
    TsmPDF(o).Pen.Color := clRed;
    TsmPDF(o).DrawLine(0, 0, 50, 50);
    TsmPDF(o).PopClip;
  end);
  AssertContains('W n'#10'q'#10'1 0 0 RG', s, 'the draw wraps itself in q and sets its colour');
end;

// ===== W7 =====

procedure TClipPathTests.Test_Path_fill_operatorSequence;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clRed;
    TsmPDF(o).BeginPath;
    TsmPDF(o).MoveTo(10, 10);
    TsmPDF(o).LineTo(100, 10);
    TsmPDF(o).CurveTo(110, 20, 110, 40, 100, 50);
    TsmPDF(o).ClosePath;
    TsmPDF(o).FillPath;
  end);
  AssertEquals('q'#10'1 0 0 rg'#10'10 782 m'#10'100 782 l'#10'110 772 110 752 100 742 c'#10 +
    'h'#10'f'#10'Q'#10, s);
end;

procedure TClipPathTests.Test_Path_stroke_usesPen;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Width := 2.5;
    TsmPDF(o).BeginPath;
    TsmPDF(o).MoveTo(0, 0);
    TsmPDF(o).LineTo(10, 10);
    TsmPDF(o).StrokePath;
  end);
  AssertContains('2.5 w', s);
  AssertContains('10 782 l'#10'S'#10'Q', s);
end;

procedure TClipPathTests.Test_Path_fillAndStroke_evenOdd;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).BeginPath;
    TsmPDF(o).MoveTo(0, 0);
    TsmPDF(o).LineTo(10, 10);
    TsmPDF(o).LineTo(0, 10);
    TsmPDF(o).ClosePath;
    TsmPDF(o).FillAndStrokePath(frEvenOdd);
  end);
  AssertContains('h'#10'B*'#10'Q', s);
end;

procedure TClipPathTests.Test_Path_fillWithClearBrush_paintsNothing;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).MoveTo(0, 0);
    TsmPDF(o).LineTo(10, 10);
    TsmPDF(o).FillPath;
  end);
  AssertEquals('', s);
end;

procedure TClipPathTests.Test_Path_moveToWithoutBeginPath_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).MoveTo(1, 1);
  end, 'MoveTo needs BeginPath');
end;

procedure TClipPathTests.Test_Path_lineToWithoutMoveTo_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).LineTo(1, 1);
  end, 'LineTo needs a current point');
end;

procedure TClipPathTests.Test_Path_drawWhileOpen_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).DrawLine(0, 0, 1, 1);
  end, 'Draw* while a path is open');
end;

procedure TClipPathTests.Test_Path_newPageWhileOpen_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).NewPage;
  end, 'NewPage while a path is open');
end;

procedure TClipPathTests.Test_Path_beginPathTwice_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).BeginPath;
  end, 'BeginPath while a path is open');
end;

procedure TClipPathTests.Test_Path_clipWhileOpen_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).PushClipRect(TRectF.Create(0, 0, 1, 1));
  end, 'PushClipRect while a path is open');
end;

procedure TClipPathTests.Test_Path_saveWhileOpen_raises;
begin
  ExpectError(procedure(o: TObject)
  begin
    TsmPDF(o).BeginPath;
    TsmPDF(o).MoveTo(0, 0);
    TsmPDF(o).ToBytes;
  end, 'saving with an unfinished path');
end;

procedure TClipPathTests.Test_Path_saveToFileWhileOpen_leavesExistingFile;
var
  pdf: TsmPDF;
  fileName: string;
  raised: Boolean;
begin
  fileName := TPath.Combine(TPath.GetTempPath, 'smPDF-open-path.pdf');
  TFile.WriteAllText(fileName, 'keep me');
  try
    pdf := TsmPDF.Create;
    try
      pdf.NewPage(612, 792);
      pdf.BeginPath;
      raised := False;
      try
        pdf.Save(fileName);
      except
        on EPDFError do raised := True;
      end;
      AssertTrue(raised, 'Save with an open path raises');
      AssertTrue(TFile.Exists(fileName), 'the existing file is not deleted');
      AssertEquals('keep me', TFile.ReadAllText(fileName), 'nor overwritten');
    finally
      pdf.Free;
    end;
  finally
    if TFile.Exists(fileName) then TFile.Delete(fileName);
  end;
end;

procedure TClipPathTests.Test_Path_measuringWhileOpen_isAllowed;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.BeginPath;
    AssertTrue(pdf.TextWidthF('abc') > 0);
    pdf.StrokePath;
  finally
    pdf.Free;
  end;
end;

procedure TClipPathTests.Test_RoundRect_zeroRadius_equalsDrawBox;
var a, b: string;
begin
  a := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawRoundRect(TRectF.Create(10.5, 20, 110, 70.25), 0, 0);
  end);
  b := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawBox(10.5, 20, 110, 70.25);
  end);
  AssertEquals(b, a);
end;

procedure TClipPathTests.Test_RoundRect_emitsFourCurves;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawRoundRect(TRectF.Create(10, 20, 110, 70), 8, 8);
  end);
  AssertEquals(1, CountSubstring(' m'#10, s));
  AssertEquals(4, CountSubstring(' l'#10, s));
  AssertEquals(4, CountSubstring(' c'#10, s));
  AssertContains('18 772 m', s, 'path starts after the top-left corner');
  AssertContains(#10'h'#10'S'#10, s);
end;

procedure TClipPathTests.Test_RoundRect_radiusClampedToHalfSize;
var s: string;
begin
  // A 40 x 20 rect with radius 50 becomes a stadium: radii 20 x 10.
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).DrawRoundRect(TRectF.Create(0, 0, 40, 20), 50, 50);
  end);
  AssertContains('20 792 m', s);
  AssertContains('20 792 l', s, 'the straight top edge has zero length');
end;

initialization
  TTestRegistry.RegisterTestCase(TClipPathTests);

end.
