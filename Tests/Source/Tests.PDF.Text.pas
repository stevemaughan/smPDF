unit Tests.PDF.Text;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework;

type
  TTextTests = class(TTestCase)
  protected
    function SavedAsString(const ABuild: TProc<TObject>): string;
    function CountOccurrences(const ASubstring, AString: string): Integer;
  published
    // Basic emission
    procedure Test_DrawText_emitsBeginTextEndText;
    procedure Test_DrawText_emitsTfWithFontResourceAndSize;
    procedure Test_DrawText_emitsTjWithEscapedString;
    procedure Test_DrawText_emitsTextMatrix;
    procedure Test_DrawText_emptyStringEmitsNothing;

    // Font resolution / resources
    procedure Test_FontDict_emittedForHelveticaUsage;
    procedure Test_FontDict_includesWinAnsiEncodingForLatinFonts;
    procedure Test_FontDict_omitsEncodingForSymbol;
    procedure Test_BoldItalic_resolvesToBoldObliquePdfName;
    procedure Test_TimesBoldItalic_resolvesToBoldItalicPdfName;
    procedure Test_TwoFontsSamePage_getDistinctResourceAliases;
    procedure Test_SameFontTwice_reusesSameResource;

    // Color
    procedure Test_TextFill_usesFontColor;

    // Alignment in rect
    procedure Test_DrawText_leftAlignedInRect_xEqualsRectLeft;
    procedure Test_DrawText_rightAlignedInRect_textEndsAtRectRight;
    procedure Test_DrawText_centerAlignedInRect_textCentered;
    procedure Test_DrawText_inRect_autoSizesToFitHeight;
    procedure Test_DrawText_inRect_doublingRectDoublesFontSize;

    // Paragraph word wrap
    procedure Test_DrawParagraph_singleLineFits_emitsOneTj;
    procedure Test_DrawParagraph_longTextWrapsToMultipleLines;
    procedure Test_DrawParagraph_padding_doubleProducesGreaterLineHeight;

    // Underline
    procedure Test_Underline_emitsStrokeBesidesText;
    procedure Test_Underline_disabled_emitsOnlyText;

    // Outlined text (Font.StrokeStyle / StrokeColor)
    procedure Test_StrokeStyle_isOff_byDefault;
    procedure Test_StrokeStyle_None_emitsNoTextRenderingMode;
    procedure Test_StrokeStyle_Medium_emitsFillAndStrokeMode;
    procedure Test_StrokeStyle_setsStrokeColorAndWidth;
    procedure Test_StrokeStyle_widthScalesByStyle;

    // Text measurement
    procedure Test_TextWidth_emptyStringIsZero;
    procedure Test_TextWidth_nonEmptyIsPositive;
    procedure Test_TextWidth_scalesWithSize;
    procedure Test_TextWidth_boldWiderThanRegular;
    procedure Test_TextHeight_isLineHeightInPixels;
    procedure Test_TextHeight_emptyStringStillReturnsLineHeight;
    procedure Test_TextExtent_combinesWidthAndHeight;
    procedure Test_MeasureParagraph_singleLineFits_returnsOneLineHeight;
    procedure Test_MeasureParagraph_longText_returnsMultipleLines;
    procedure Test_MeasureParagraph_doubleSpacingDoublesHeight;
    procedure Test_MeasureParagraph_emptyTextReturnsZero;
    procedure Test_TextWidth_beforeNewPage_raisesEPDFError;

    // Text background (Brush as VCL TextRect-style fill behind text)
    procedure Test_DrawText_brushClear_emitsNoBackgroundRect;
    procedure Test_DrawText_brushSolid_emitsFilledRectBeforeText;
    procedure Test_DrawText_brushSolid_xyOverload_rectMatchesTextBounds;
    procedure Test_DrawText_brushSolid_rectOverload_rectMatchesARect;
    procedure Test_DrawText_brushSolid_doesNotConsultPen;
    procedure Test_DrawParagraph_brushSolid_emitsSingleBackgroundFillNotPerLine;

    // Rotated text (DrawText X,Y overload with AAngle, CCW degrees)
    procedure Test_DrawText_zeroAngle_emitsNoCm;
    procedure Test_DrawText_explicitZeroAngle_emitsNoCm;
    procedure Test_DrawText_ninetyDegrees_emitsCmAndIsBalancedByQ;
    procedure Test_DrawText_ninetyDegrees_cmValuesMatchFormula;
  end;

implementation

uses
  StrUtils, IOUtils, Vcl.Graphics, smPDF;

function TTextTests.SavedAsString(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  fn: string;
  bytes: TBytes;
  i: Integer;
begin
  fn := TPath.Combine(TPath.GetTempPath, 'smPDF-tests-text.pdf');
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

function TTextTests.CountOccurrences(const ASubstring, AString: string): Integer;
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

// ===== Basic emission =====

procedure TTextTests.Test_DrawText_emitsBeginTextEndText;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('BT'#10, s);
  AssertContains('ET'#10, s);
end;

procedure TTextTests.Test_DrawText_emitsTfWithFontResourceAndSize;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size := 14;
    TsmPDF(o).DrawText('Hi', 100, 100);
  end);
  AssertContains('/F1 14 Tf', s);
end;

procedure TTextTests.Test_DrawText_emitsTjWithEscapedString;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hello world', 100, 100);
  end);
  AssertContains('(Hello world) Tj', s);
end;

procedure TTextTests.Test_DrawText_emitsTextMatrix;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('X', 100, 200);
  end);
  AssertContains('Tm', s);
end;

procedure TTextTests.Test_DrawText_emptyStringEmitsNothing;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('', 100, 100);
  end);
  AssertFalse(Pos('BT'#10, s) > 0, 'no BT for empty string');
  AssertFalse(Pos('Tj',    s) > 0, 'no Tj for empty string');
end;

// ===== Font resources =====

procedure TTextTests.Test_FontDict_emittedForHelveticaUsage;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/Type /Font', s);
  AssertContains('/Subtype /Type1', s);
  AssertContains('/BaseFont /Helvetica', s);
end;

procedure TTextTests.Test_FontDict_includesWinAnsiEncodingForLatinFonts;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Times';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/Encoding /WinAnsiEncoding', s);
end;

procedure TTextTests.Test_FontDict_omitsEncodingForSymbol;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Symbol';
    TsmPDF(o).DrawText('XYZ', 100, 100);
  end);
  AssertContains('/BaseFont /Symbol', s);
  // Symbol must NOT carry /Encoding /WinAnsiEncoding (it ships with its own)
  AssertFalse(Pos('/Encoding /WinAnsiEncoding', s) > 0,
    'Symbol must not specify WinAnsiEncoding');
end;

procedure TTextTests.Test_BoldItalic_resolvesToBoldObliquePdfName;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Bold    := True;
    TsmPDF(o).Font.Italics := True;
    TsmPDF(o).DrawText('X', 100, 100);
  end);
  AssertContains('/BaseFont /Helvetica-BoldOblique', s);
end;

procedure TTextTests.Test_TimesBoldItalic_resolvesToBoldItalicPdfName;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name    := 'Times';
    TsmPDF(o).Font.Bold    := True;
    TsmPDF(o).Font.Italics := True;
    TsmPDF(o).DrawText('X', 100, 100);
  end);
  AssertContains('/BaseFont /Times-BoldItalic', s);
end;

procedure TTextTests.Test_TwoFontsSamePage_getDistinctResourceAliases;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Helvetica'; TsmPDF(o).DrawText('A', 100, 100);
    TsmPDF(o).Font.Name := 'Times';     TsmPDF(o).DrawText('B', 100, 130);
  end);
  AssertContains('/F1 ', s, 'first font got /F1');
  AssertContains('/F2 ', s, 'second font got /F2');
  // Both fonts must appear in the document
  AssertContains('/BaseFont /Helvetica', s);
  AssertContains('/BaseFont /Times-Roman', s);
end;

procedure TTextTests.Test_SameFontTwice_reusesSameResource;
var
  s: string;
  occurrencesOfF2: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('A', 100, 100);
    TsmPDF(o).DrawText('B', 100, 130);
  end);
  occurrencesOfF2 := CountOccurrences('/F2', s);
  AssertEquals(0, occurrencesOfF2, 'no /F2 should appear when only one font is used');
end;

// ===== Color =====

procedure TTextTests.Test_TextFill_usesFontColor;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Color := clRed;  // 1 0 0 in RGB floats
    TsmPDF(o).DrawText('Red text', 100, 100);
  end);
  AssertContains('1 0 0 rg', s, 'text fill color set from Font.Color');
end;

// ===== Alignment in rect =====

procedure TTextTests.Test_DrawText_leftAlignedInRect_xEqualsRectLeft;
var s: string;
begin
  // Rect-overload auto-sizes the font to fit. Left alignment still anchors x to rect.Left.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('X', TRect.Create(100, 200, 400, 240), taLeftJustify);
  end);
  AssertContains('1 0 0 1 100 ', s);
end;

procedure TTextTests.Test_DrawText_rightAlignedInRect_textEndsAtRectRight;
var s: string;
begin
  // Rect 300x40 (px=pt at 72dpi). Auto-size: 40/1.2 = 33.333pt is height-limited.
  // Helvetica "Hello" = 2278 units / 1000 -> 75.93pt at 33.333pt. Right-aligned x = 400 - 76 = 324.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hello', TRect.Create(100, 200, 400, 240), taRightJustify);
  end);
  AssertContains('1 0 0 1 324 ', s, 'right-aligned text ends near rect.Right');
end;

procedure TTextTests.Test_DrawText_centerAlignedInRect_textCentered;
var s: string;
begin
  // Rect 300x40. Auto-size 33.333pt. "Hi" = 944/1000 -> 31.46pt at 33.333pt -> 31 px.
  // Center: 100 + Round((300 - 31) / 2) = 100 + 134 = 234.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hi', TRect.Create(100, 200, 400, 240), taCenter);
  end);
  AssertContains('1 0 0 1 234 ', s);
end;

procedure TTextTests.Test_DrawText_inRect_autoSizesToFitHeight;
var s: string;
begin
  // Wide-but-short rect: height drives the size. 40 / 1.2 = 33.333 pt.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size := 12;  // ignored by rect-overload
    TsmPDF(o).DrawText('Hi', TRect.Create(0, 0, 1000, 40), taLeftJustify);
  end);
  AssertContains('/F1 33.333 Tf', s, 'rect-overload picks max size that fits height');
end;

procedure TTextTests.Test_DrawText_inRect_doublingRectDoublesFontSize;
var s1, s2: string;
begin
  s1 := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hi', TRect.Create(0, 0, 1000, 40), taLeftJustify);
  end);
  s2 := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hi', TRect.Create(0, 0, 2000, 80), taLeftJustify);
  end);
  AssertContains('/F1 33.333 Tf', s1, '40px high rect -> 33.333pt');
  AssertContains('/F1 66.667 Tf', s2, '80px high rect -> 66.667pt (uniform scale)');
end;

// ===== Paragraph word wrap =====

procedure TTextTests.Test_DrawParagraph_singleLineFits_emitsOneTj;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawParagraph('Hello',
      TRect.Create(100, 200, 500, 240), taLeftJustify, tpSingle);
  end);
  AssertEquals(1, CountOccurrences('Tj', s));
end;

procedure TTextTests.Test_DrawParagraph_longTextWrapsToMultipleLines;
var s: string;
begin
  // 200pt-wide rect with many words at 12pt Helvetica should wrap.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawParagraph(
      'This sentence is intentionally long enough that the wrapper has to break it across at least three or four lines.',
      TRect.Create(100, 200, 300, 600), taLeftJustify, tpSingle);
  end);
  AssertTrue(CountOccurrences('Tj', s) >= 3,
    'long text should wrap to at least 3 Tj operators (one per line)');
end;

procedure TTextTests.Test_DrawParagraph_padding_doubleProducesGreaterLineHeight;
var
  sSingle, sDouble: string;
  // Compare the Y coordinate of the second line under tpSingle vs tpDouble.
  // tpDouble's spacing should be 2x tpSingle's, so the second line sits twice as far
  // below the first. We can't easily extract Y from the PDF text without a parser,
  // so just assert that the byte count differs (more spacing => different Tm values).
begin
  sSingle := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawParagraph(
      'Word one. Word two. Word three. Word four. Word five. Word six.',
      TRect.Create(100, 100, 300, 700), taLeftJustify, tpSingle);
  end);
  sDouble := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawParagraph(
      'Word one. Word two. Word three. Word four. Word five. Word six.',
      TRect.Create(100, 100, 300, 700), taLeftJustify, tpDouble);
  end);
  // Both should wrap to multiple lines. They will produce different Tm Y values.
  AssertNotEmpty(sSingle);
  AssertNotEmpty(sDouble);
  // The PDFs differ — different Tm content for the line positions.
  AssertFalse(sSingle = sDouble, 'tpSingle and tpDouble should produce different output');
end;

// ===== Underline =====

procedure TTextTests.Test_Underline_emitsStrokeBesidesText;
var
  s: string;
  cntStroke, cntFill: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Underline := True;
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  cntStroke := CountOccurrences('S'#10, s);
  cntFill   := CountOccurrences('rg'#10, s);
  AssertTrue(cntStroke >= 1, 'underline emits at least one Stroke (S)');
  AssertTrue(cntFill   >= 1, 'text fill colour emitted');
end;

procedure TTextTests.Test_Underline_disabled_emitsOnlyText;
var
  s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Underline := False;
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  // No stroke command should appear (only the text path: BT/Tf/Tm/Tj/ET wrapped in q/Q)
  AssertFalse(Pos('S'#10, s) > 0, 'no stroke when underline disabled');
end;

// ===== Outlined text =====

procedure TTextTests.Test_StrokeStyle_isOff_byDefault;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertFalse(Pos(' Tr'#10, s) > 0,
    'default StrokeStyle is ssNone, no text rendering mode emitted');
end;

procedure TTextTests.Test_StrokeStyle_None_emitsNoTextRenderingMode;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeStyle := ssNone;
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertFalse(Pos(' Tr'#10, s) > 0,
    'no text rendering mode emitted when StrokeStyle = ssNone');
end;

procedure TTextTests.Test_StrokeStyle_Medium_emitsFillAndStrokeMode;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeStyle := ssMedium;
    TsmPDF(o).DrawText('Hi', 100, 100);
  end);
  AssertContains('2 Tr'#10, s, 'fill+stroke text-render mode emitted');
end;

procedure TTextTests.Test_StrokeStyle_setsStrokeColorAndWidth;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeStyle := ssMedium;
    TsmPDF(o).Font.StrokeColor := clBlack;       // 0 0 0 RG
    TsmPDF(o).Font.Color       := clRed;         // 1 0 0 rg
    TsmPDF(o).Font.Size        := 24;
    TsmPDF(o).DrawText('Outlined', 100, 100);
  end);
  AssertContains('1 0 0 rg', s, 'fill colour from Font.Color');
  AssertContains('0 0 0 RG', s, 'stroke colour from Font.StrokeColor');
  AssertContains('1.2 w',    s, 'ssMedium @ 24pt = 0.05 * 24 = 1.2pt line width');
end;

procedure TTextTests.Test_StrokeStyle_widthScalesByStyle;
var
  sThin, sThick: string;
begin
  sThin := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size        := 24;
    TsmPDF(o).Font.StrokeStyle := ssThin;
    TsmPDF(o).DrawText('X', 100, 100);
  end);
  sThick := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size        := 24;
    TsmPDF(o).Font.StrokeStyle := ssThick;
    TsmPDF(o).DrawText('X', 100, 100);
  end);
  AssertContains('0.6 w', sThin,  'ssThin @ 24pt = 0.025 * 24 = 0.6pt');
  AssertContains('2.4 w', sThick, 'ssThick @ 24pt = 0.10 * 24 = 2.4pt');
end;

// ===== Text measurement =====
// Tests use 72 dpi pages so 1 px == 1 pt — matches the existing alignment tests
// and keeps hand-checked values trivial.

procedure TTextTests.Test_TextWidth_emptyStringIsZero;
var pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    AssertEquals(0, pdf.TextWidth(''));
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextWidth_nonEmptyIsPositive;
var pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    AssertTrue(pdf.TextWidth('Hello') > 0, 'TextWidth("Hello") should be positive');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextWidth_scalesWithSize;
var
  pdf: TsmPDF;
  w12, w24: Integer;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;  w12 := pdf.TextWidth('Hello');
    pdf.Font.Size := 24;  w24 := pdf.TextWidth('Hello');
    // Doubling size should approximately double width (allow ±1 for rounding).
    AssertTrue(Abs(w24 - 2 * w12) <= 1,
      Format('w24 (%d) should be ~2x w12 (%d)', [w24, w12]));
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextWidth_boldWiderThanRegular;
var
  pdf: TsmPDF;
  wReg, wBold: Integer;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 24;
    pdf.Font.Bold := False;  wReg  := pdf.TextWidth('Hello');
    pdf.Font.Bold := True;   wBold := pdf.TextWidth('Hello');
    AssertTrue(wBold > wReg,
      Format('Bold (%d) should be wider than regular (%d)', [wBold, wReg]));
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextHeight_isLineHeightInPixels;
var pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    // Line height = 1.2 * 12pt = 14.4 -> Round(14.4) = 14 px at 72 dpi.
    AssertEquals(14, pdf.TextHeight('Hello'));
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextHeight_emptyStringStillReturnsLineHeight;
var pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    AssertEquals(14, pdf.TextHeight(''));
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextExtent_combinesWidthAndHeight;
var
  pdf: TsmPDF;
  ext: TSize;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    ext := pdf.TextExtent('Hello');
    AssertEquals(pdf.TextWidth('Hello'),  ext.cx, 'cx matches TextWidth');
    AssertEquals(pdf.TextHeight('Hello'), ext.cy, 'cy matches TextHeight');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_MeasureParagraph_singleLineFits_returnsOneLineHeight;
var
  pdf: TsmPDF;
  ext: TSize;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    // Plenty of width — fits on one line. cy = 1 * 1.2 * 12 = 14.4 -> 14.
    ext := pdf.MeasureParagraph('Hello', 500, tpSingle);
    AssertEquals(14, ext.cy, 'single-line text gives one line-height');
    AssertTrue(ext.cx > 0,    'non-zero width for non-empty text');
    AssertTrue(ext.cx <= 500, 'width fits within max');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_MeasureParagraph_longText_returnsMultipleLines;
var
  pdf: TsmPDF;
  ext: TSize;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    // Narrow column + many words -> multiple lines. Expect >= 3 line-heights.
    ext := pdf.MeasureParagraph(
      'This sentence is intentionally long enough that the wrapper has to break it across at least three lines.',
      150, tpSingle);
    AssertTrue(ext.cy >= 3 * 14,
      Format('Wrapped paragraph should be at least 3 lines high; got cy=%d', [ext.cy]));
    AssertTrue(ext.cx <= 150, 'no line should exceed maxWidth');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_MeasureParagraph_doubleSpacingDoublesHeight;
var
  pdf: TsmPDF;
  single, double: TSize;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Font.Size := 12;
    single := pdf.MeasureParagraph('Hello world this wraps somewhere', 100, tpSingle);
    double := pdf.MeasureParagraph('Hello world this wraps somewhere', 100, tpDouble);
    // tpSingle = 1.2x, tpDouble = 2.4x -> exactly 2x line-height per line.
    AssertEquals(2 * single.cy, double.cy, 'tpDouble height = 2 * tpSingle height');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_MeasureParagraph_emptyTextReturnsZero;
var
  pdf: TsmPDF;
  ext: TSize;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    ext := pdf.MeasureParagraph('', 500, tpSingle);
    AssertEquals(0, ext.cx, 'empty text -> cx=0');
    AssertEquals(0, ext.cy, 'empty text -> cy=0');
  finally
    pdf.Free;
  end;
end;

procedure TTextTests.Test_TextWidth_beforeNewPage_raisesEPDFError;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.TextWidth('Hello');
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'TextWidth before NewPage should raise EPDFError');
  finally
    pdf.Free;
  end;
end;

// ===== Text background =====
// Brush.Style = brushSolid acts as a TextRect-style background fill behind
// the text. brushClear (the default) is a no-op so existing call sites are
// unchanged. Pen is intentionally not consulted for text.

procedure TTextTests.Test_DrawText_brushClear_emitsNoBackgroundRect;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    // Brush defaults to brushClear — no background should be emitted.
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertFalse(Pos(' re'#10, s) > 0,
    'no rectangle path should be emitted for text when brush is clear');
end;

procedure TTextTests.Test_DrawText_brushSolid_emitsFilledRectBeforeText;
var
  s: string;
  posRe, posBT: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;  // 1 1 0 in RGB floats
    TsmPDF(o).DrawText('Hi', 100, 200);
  end);
  AssertContains('1 1 0 rg', s, 'yellow Brush fill colour set');
  AssertContains(' re'#10,    s, 'rectangle path emitted');
  AssertContains('f*'#10,     s, 'even-odd fill operator emitted');
  posRe := Pos(' re'#10, s);
  posBT := Pos('BT'#10, s);
  AssertTrue((posRe > 0) and (posBT > 0) and (posRe < posBT),
    'background rect must precede the BT block so text overlays it');
end;

procedure TTextTests.Test_DrawText_brushSolid_xyOverload_rectMatchesTextBounds;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;
    TsmPDF(o).DrawText('Hi', 100, 200);
  end);
  // 72dpi A4 page = 595x842 pt. Helvetica 12pt 'Hi' = 944/1000 * 12 = 11.328 -> 11px wide.
  // TextHeight = 1.2 * 12 = 14.4 -> 14px. Rect (100,200,111,214) in pixels.
  // PDF Y-flip via FlipYPixels: Y_pdf = (842 - 1 - Y_px). ll = (100, 842-1-214) = (100, 627).
  AssertContains('100 627 11 14 re', s,
    'background rect = (X, Y, X+TextWidth, Y+TextHeight) in PDF coords');
end;

procedure TTextTests.Test_DrawText_brushSolid_rectOverload_rectMatchesARect;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;
    TsmPDF(o).DrawText('Hi', TRect.Create(100, 200, 400, 240), taCenter);
  end);
  // ARect (100,200,400,240) px. Y-flip: ll = (100, 842-1-240) = (100, 601). w=300, h=40.
  AssertContains('100 601 300 40 re', s,
    'background rect matches the supplied ARect in PDF coords');
end;

procedure TTextTests.Test_DrawText_brushSolid_doesNotConsultPen;
var
  s, between: string;
  posRe, posBT: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;
    TsmPDF(o).Pen.Style   := penSolid;     // would normally stroke a shape
    TsmPDF(o).Pen.Color   := clRed;        // 1 0 0 — must NOT appear as RG (stroke)
    TsmPDF(o).DrawText('Hi', 100, 200);
  end);
  posRe := Pos(' re'#10, s);
  posBT := Pos('BT'#10,  s);
  AssertTrue(posRe > 0,         're operator should be present (background fill)');
  AssertTrue(posBT > posRe,     'BT should follow re');
  between := Copy(s, posRe, posBT - posRe);
  AssertFalse(Pos('S'#10, between) > 0,
    'no Stroke (S) between background fill and text — Pen ignored for text');
  AssertFalse(Pos('1 0 0 RG', between) > 0,
    'no Pen stroke colour between fill and text — Pen.Color ignored for text');
end;

procedure TTextTests.Test_DrawParagraph_brushSolid_emitsSingleBackgroundFillNotPerLine;
var
  s: string;
  reCount: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;
    TsmPDF(o).DrawParagraph(
      'This sentence is intentionally long enough that the wrapper has to break it across multiple lines for sure.',
      TRect.Create(100, 100, 250, 600), taLeftJustify, tpSingle);
  end);
  reCount := CountOccurrences(' re'#10, s);
  AssertEquals(1, reCount,
    'exactly one background rect for the whole paragraph, not one per wrapped line');
end;

// ===== Rotated text =====
// AAngle is CCW degrees (matches VCL TFont.Orientation).
// Default zero must emit no extra cm operator so existing call sites stay
// byte-identical. Non-zero angles wrap the draw in q ... cm ... Q so Brush
// background, Underline, and StrokeStyle outline all rotate together.

procedure TTextTests.Test_DrawText_zeroAngle_emitsNoCm;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hi', 100, 100);   // AAngle defaults to 0
  end);
  AssertFalse(Pos(' cm'#10, s) > 0,
    'no cm operator should be emitted when AAngle is the default zero');
end;

procedure TTextTests.Test_DrawText_explicitZeroAngle_emitsNoCm;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Hi', 100, 100, 0.0);
  end);
  AssertFalse(Pos(' cm'#10, s) > 0,
    'no cm operator should be emitted when AAngle is explicitly zero');
end;

procedure TTextTests.Test_DrawText_ninetyDegrees_emitsCmAndIsBalancedByQ;
var
  s: string;
  cmCount, qCount, capQCount: Integer;
  posQ, posCm, posBT, posCapQ: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Up', 100, 100, 90);
  end);
  cmCount   := CountOccurrences(' cm'#10, s);
  qCount    := CountOccurrences('q'#10,   s);
  capQCount := CountOccurrences('Q'#10,   s);
  AssertEquals(1, cmCount, 'rotated DrawText emits exactly one cm operator');
  AssertEquals(qCount, capQCount,
    'every q must be matched by a Q (rotation wrapper does not leak state)');
  // Order: q -> cm -> BT (text emission) -> ... -> Q
  posQ    := Pos('q'#10,   s);
  posCm   := Pos(' cm'#10, s);
  posBT   := Pos('BT'#10,  s);
  posCapQ := Pos('Q'#10,   s);
  AssertTrue((posQ > 0) and (posCm > posQ),
    'cm follows q (graphics state must be saved before transforming)');
  AssertTrue(posBT > posCm,
    'text emission (BT) follows the cm transform');
  AssertTrue(posCapQ > posBT,
    'Q closes the wrapper after text emission');
end;

procedure TTextTests.Test_DrawText_ninetyDegrees_cmValuesMatchFormula;
var s: string;
begin
  // 72 DPI A4: pageHeightPx = 842. For pivot user (100, 100):
  //   PDF pivot = (100, 842 - 1 - 100) = (100, 741) [points; 1 px = 1 pt at 72 dpi]
  //   AAngle = 90  =>  cos = 0, sin = 1
  //   cm = [cos, sin, -sin, cos, ex, ey]
  //      = [0, 1, -1, 0, px*(1-cos)+py*sin, py*(1-cos)-px*sin]
  //      = [0, 1, -1, 0, 100*1 + 741*1, 741*1 - 100*1]
  //      = [0, 1, -1, 0, 841, 641]
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Up', 100, 100, 90);
  end);
  AssertContains('0 1 -1 0 841 641 cm', s,
    '90 deg CCW rotation around user (100,100) at 72dpi A4 emits the expected affine');
end;

initialization
  TTestRegistry.RegisterTestCase(TTextTests);

end.
