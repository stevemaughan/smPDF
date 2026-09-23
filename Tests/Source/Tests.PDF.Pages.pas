unit Tests.PDF.Pages;

interface

uses
  SysUtils, smPDF.TestFramework;

type
  TPageTests = class(TTestCase)
  protected
    function BytesToLatin1(const ABytes: TBytes): string;
  published
    procedure Test_Page_dimensionsInPixels;
    procedure Test_Page_dimensionsInPoints_72dpi;
    procedure Test_Page_dimensionsInPoints_300dpi;
    procedure Test_Page_Emit_writesPageObject;
    procedure Test_Page_Emit_referencesParent;
    procedure Test_Page_Emit_emitsMediaBoxInPoints;
    procedure Test_Page_Emit_returnsObjectId;
    procedure Test_Page_Emit_includesContentsRef;
    procedure Test_Page_Emit_emptyPageHasZeroLengthStream;

    // Graphics state
    procedure Test_SaveState_emitsLowerQ;
    procedure Test_RestoreState_emitsUpperQ;
    procedure Test_SetStrokeRGB_emitsRG;
    procedure Test_SetFillRGB_emitsLowerRg;
    procedure Test_SetLineWidthPt_emitsW;
    procedure Test_SetDashPattern_emitsDArrayAndPhase;
    procedure Test_SetLineCap_emitsJ;
    procedure Test_SetLineJoin_emitsLowerJ;

    // Path construction (user pixel coords)
    procedure Test_UserMoveTo_emitsM_withConvertedPoint;
    procedure Test_UserLineTo_emitsL_withConvertedPoint;
    procedure Test_UserRectanglePath_emitsRe_withConvertedDimensions;
    procedure Test_UserOvalPath_emitsFourCubicCurves;
    procedure Test_ClosePath_emitsH;

    // Painting
    procedure Test_Stroke_emitsUpperS;
    procedure Test_FillEvenOdd_emitsFstar;
    procedure Test_FillAndStrokeEvenOdd_emitsBstar;
    procedure Test_DiscardPath_emitsN;

    // Clipping
    procedure Test_SetClipRect_emitsRectThenWstarN;

    // Font registry
    procedure Test_UseFont_firstReturnsF1;
    procedure Test_UseFont_secondReturnsF2;
    procedure Test_UseFont_isIdempotent;
    procedure Test_UsedFontNames_returnsInsertionOrder;

    // Text operators
    procedure Test_BeginText_emitsBT;
    procedure Test_EndText_emitsET;
    procedure Test_SetTextFont_emitsTfWithResourceAndSize;
    procedure Test_SetTextMatrixUserBaseline_emitsFlippedY;
    procedure Test_ShowTextAnsi_emitsParensAndTj;
    procedure Test_ShowTextAnsi_escapesParens;
    procedure Test_ShowTextAnsi_escapesBackslash;
    procedure Test_ShowTextAnsi_passesHighBitBytesUnchanged;

    // Font resource dict in Emit
    procedure Test_Emit_withoutFontMap_omitsFontResourceDict;
    procedure Test_Emit_withFontIdsAndUsedFonts_emitsFontDict;
  end;

implementation

uses
  Generics.Collections, smPDF.Page, smPDF.Writer;

function TPageTests.BytesToLatin1(const ABytes: TBytes): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

procedure TPageTests.Test_Page_dimensionsInPixels;
var
  page: TPDFPage;
begin
  page := TPDFPage.Create(2550, 3300, 300);
  try
    AssertEquals(2550, page.WidthPixels);
    AssertEquals(3300, page.HeightPixels);
    AssertEquals(300, page.Dpi);
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_Page_dimensionsInPoints_72dpi;
var
  page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    AssertEquals(612.0, page.WidthPoints, 1e-9);
    AssertEquals(792.0, page.HeightPoints, 1e-9);
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_Page_dimensionsInPoints_300dpi;
var
  page: TPDFPage;
begin
  // Letter at 300 dpi: 2550x3300 px == 612x792 pt
  page := TPDFPage.Create(2550, 3300, 300);
  try
    AssertEquals(612.0, page.WidthPoints, 1e-6);
    AssertEquals(792.0, page.HeightPoints, 1e-6);
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_writesPageObject;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    page.Emit(w, 99);
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Type /Page', s);
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_referencesParent;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    page.Emit(w, 42);
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Parent 42 0 R', s);
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_emitsMediaBoxInPoints;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  // Letter at 300 DPI: 2550x3300 px -> 612x792 pt
  page := TPDFPage.Create(2550, 3300, 300);
  try
    page.Emit(w, 1);
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/MediaBox [0 0 612 792]', s);
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_returnsObjectId;
var
  w: TPDFWriter;
  page: TPDFPage;
  id: Integer;
begin
  // Emit allocates two objects: content stream (id 1) then the page (id 2).
  // The returned value is the page object id, which is what the parent /Pages dict references.
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    id := page.Emit(w, 1);
    AssertEquals(2, id, 'page object id follows its content stream id');
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_includesContentsRef;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    page.Emit(w, 99);
    s := BytesToLatin1(w.Finalize(0));
    // Content stream gets id 1, page gets id 2; page dict references content via /Contents 1 0 R
    AssertContains('/Contents 1 0 R', s);
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Page_Emit_emptyPageHasZeroLengthStream;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    page.Emit(w, 99);
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Length 0', s);
  finally
    page.Free;
    w.Free;
  end;
end;

// ---- Helper to round-trip a page through the writer and inspect bytes ----

function PageBytes(APage: TPDFPage): string;
var
  w: TPDFWriter;
  i: Integer;
  raw: TBytes;
begin
  w := TPDFWriter.Create;
  try
    APage.Emit(w, 1);
    raw := w.Finalize(0);
    SetLength(Result, Length(raw));
    for i := 0 to High(raw) do
      Result[i + 1] := Char(raw[i]);
  finally
    w.Free;
  end;
end;

procedure TPageTests.Test_SaveState_emitsLowerQ;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SaveState;
    AssertContains('q'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_RestoreState_emitsUpperQ;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.RestoreState;
    AssertContains('Q'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetStrokeRGB_emitsRG;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetStrokeRGB(1.0, 0.5, 0.0);
    AssertContains('1 0.5 0 RG', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetFillRGB_emitsLowerRg;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetFillRGB(0.0, 0.0, 1.0);
    AssertContains('0 0 1 rg', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetLineWidthPt_emitsW;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetLineWidthPt(2.5);
    AssertContains('2.5 w', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetDashPattern_emitsDArrayAndPhase;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetDashPattern([3.0, 2.0], 0.0);
    AssertContains('[3 2] 0 d', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetLineCap_emitsJ;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetLineCap(1);
    AssertContains('1 J', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetLineJoin_emitsLowerJ;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetLineJoin(2);
    AssertContains('2 j', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UserMoveTo_emitsM_withConvertedPoint;
var page: TPDFPage;
begin
  // 612x792 page at 72 dpi -> 1 px = 1 pt. (10, 20) in user coords (top-left, Y down)
  // becomes (10, 792-20) = (10, 772) in PDF coords (bottom-left, Y up).
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UserMoveTo(10, 20);
    AssertContains('10 772 m', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UserLineTo_emitsL_withConvertedPoint;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UserLineTo(100, 200);
    AssertContains('100 592 l', PageBytes(page));   // 792 - 200 = 592
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UserRectanglePath_emitsRe_withConvertedDimensions;
var page: TPDFPage;
begin
  // user (10,20)..(110,120) at 72dpi/72dpi: PDF lower-left = (10, 792-120) = (10, 672)
  // width 100, height 100
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UserRectanglePath(10, 20, 110, 120);
    AssertContains('10 672 100 100 re', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UserOvalPath_emitsFourCubicCurves;
var
  page: TPDFPage;
  s: string;
  cCount: Integer;
  i: Integer;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UserOvalPath(0, 0, 200, 200);
    s := PageBytes(page);
    AssertContains('m', s, 'oval starts with a moveto');
    AssertContains('h', s, 'oval closes its path');
    cCount := 0;
    for i := 1 to Length(s) do
      if (i + 1 <= Length(s)) and (s[i] = 'c') and (s[i + 1] = #10) then
        Inc(cCount);
    AssertEquals(4, cCount, 'oval should emit exactly four cubic-bezier (c) operators');
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_ClosePath_emitsH;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.ClosePath;
    AssertContains('h'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_Stroke_emitsUpperS;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.Stroke;
    AssertContains('S'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_FillEvenOdd_emitsFstar;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.FillEvenOdd;
    AssertContains('f*'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_FillAndStrokeEvenOdd_emitsBstar;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.FillAndStrokeEvenOdd;
    AssertContains('B*'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_DiscardPath_emitsN;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.DiscardPath;
    AssertContains('n'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetClipRect_emitsRectThenWstarN;
var
  page: TPDFPage;
  s: string;
  posRe, posW, posN: Integer;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetClipRect(10, 20, 110, 120);
    s := PageBytes(page);
    posRe := Pos('re'#10, s);
    posW  := Pos('W*'#10, s);
    posN  := Pos('n'#10, s);
    AssertTrue(posRe > 0, 're operator emitted');
    AssertTrue(posW  > 0, 'W* operator emitted');
    AssertTrue(posN  > 0, 'n operator emitted');
    AssertTrue((posRe < posW) and (posW < posN), 'order must be re W* n for clipping');
  finally
    page.Free;
  end;
end;

// ---- Font registry ----

procedure TPageTests.Test_UseFont_firstReturnsF1;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    AssertEquals('F1', page.UseFont('Helvetica'));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UseFont_secondReturnsF2;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UseFont('Helvetica');
    AssertEquals('F2', page.UseFont('Times-Roman'));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UseFont_isIdempotent;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    AssertEquals('F1', page.UseFont('Helvetica'));
    AssertEquals('F1', page.UseFont('Helvetica'));
    AssertEquals('F2', page.UseFont('Courier'));
    AssertEquals('F1', page.UseFont('Helvetica'));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_UsedFontNames_returnsInsertionOrder;
var
  page: TPDFPage;
  names: TArray<string>;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UseFont('Helvetica');
    page.UseFont('Times-Bold');
    page.UseFont('Courier-Oblique');
    names := page.UsedFontNames;
    AssertEquals(3, Length(names));
    AssertEquals('Helvetica',         names[0]);
    AssertEquals('Times-Bold',        names[1]);
    AssertEquals('Courier-Oblique',   names[2]);
  finally
    page.Free;
  end;
end;

// ---- Text operators ----

procedure TPageTests.Test_BeginText_emitsBT;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.BeginText;
    AssertContains('BT'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_EndText_emitsET;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.EndText;
    AssertContains('ET'#10, PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetTextFont_emitsTfWithResourceAndSize;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetTextFont('F1', 12.0);
    AssertContains('/F1 12 Tf', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_SetTextMatrixUserBaseline_emitsFlippedY;
var page: TPDFPage;
begin
  // 612x792 page at 72 dpi -> 1 px = 1 pt. Baseline at user (50, 100) -> PDF (50, 692)
  // because 792 - 100 = 692.
  page := TPDFPage.Create(612, 792, 72);
  try
    page.SetTextMatrixUserBaseline(50, 100);
    AssertContains('1 0 0 1 50 692 Tm', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_ShowTextAnsi_emitsParensAndTj;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.ShowTextAnsi(AnsiString('Hello'));
    AssertContains('(Hello) Tj', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_ShowTextAnsi_escapesParens;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.ShowTextAnsi(AnsiString('a(b)c'));
    AssertContains('(a\(b\)c) Tj', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_ShowTextAnsi_escapesBackslash;
var page: TPDFPage;
begin
  page := TPDFPage.Create(612, 792, 72);
  try
    page.ShowTextAnsi(AnsiString('a\b'));
    AssertContains('(a\\b) Tj', PageBytes(page));
  finally
    page.Free;
  end;
end;

procedure TPageTests.Test_ShowTextAnsi_passesHighBitBytesUnchanged;
var
  page: TPDFPage;
  s: AnsiString;
  rawByte: AnsiChar;
begin
  // 0xC9 = WinAnsi 'É'. Should pass through verbatim into the (...) literal.
  rawByte := AnsiChar(#$C9);
  s := AnsiString('A') + rawByte + AnsiString('B');
  page := TPDFPage.Create(612, 792, 72);
  try
    page.ShowTextAnsi(s);
    AssertContains('(A' + AnsiString(#$C9) + 'B) Tj', PageBytes(page));
  finally
    page.Free;
  end;
end;

// ---- Font resource dict in Emit ----

procedure TPageTests.Test_Emit_withoutFontMap_omitsFontResourceDict;
var
  w: TPDFWriter;
  page: TPDFPage;
  s: string;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  try
    page.UseFont('Helvetica');  // page knows it, but no document-wide id map provided
    page.Emit(w, 99, nil);
    s := BytesToLatin1(w.Finalize(0));
    AssertFalse(Pos('/Font', s) > 0, 'No /Font resource entry when no font id map provided');
  finally
    page.Free;
    w.Free;
  end;
end;

procedure TPageTests.Test_Emit_withFontIdsAndUsedFonts_emitsFontDict;
var
  w: TPDFWriter;
  page: TPDFPage;
  fontIds: TDictionary<string, TPDFObjectId>;
  s: string;
  helvId, timesId: TPDFObjectId;
begin
  w := TPDFWriter.Create;
  page := TPDFPage.Create(612, 792, 72);
  fontIds := TDictionary<string, TPDFObjectId>.Create;
  try
    page.UseFont('Helvetica');
    page.UseFont('Times-Roman');
    helvId  := w.ReserveObjectId;
    timesId := w.ReserveObjectId;
    fontIds.Add('Helvetica',   helvId);
    fontIds.Add('Times-Roman', timesId);
    page.Emit(w, 99, fontIds);
    // fill in the reserved font objects so Finalize doesn't refuse
    w.BeginReservedObject(helvId);  w.BeginDict; w.EndDict; w.EndObject;
    w.BeginReservedObject(timesId); w.BeginDict; w.EndDict; w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Font',       s);
    AssertContains('/F1 ' + IntToStr(helvId)  + ' 0 R', s);
    AssertContains('/F2 ' + IntToStr(timesId) + ' 0 R', s);
  finally
    fontIds.Free;
    page.Free;
    w.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TPageTests);

end.
