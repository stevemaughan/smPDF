unit Tests.PDF.MapText;

// Text for maps (W8): GDI-compatible metrics, halos, text as outlines.

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TMapTextTests = class(TTestCase)
  protected
    procedure RequireFont(const AFamily: string);
    function Content(const ABuild: TProc<TObject>): string;
    function MoveToXs(const AContent: string): TArray<Double>;
  published
    // W8a metrics
    procedure Test_TypoTop_isTheDefault;
    procedure Test_TypoTop_baselineAtTypoAscender;
    procedure Test_GdiTop_Arial100_baselineAtWinAscent;
    procedure Test_GdiTop_Arial100_textHeightIsGdiCell;
    procedure Test_Baseline_origin_yIsTheBaseline;
    procedure Test_FontMetrics_gdiTop_Arial;
    procedure Test_FontMetrics_typoTop_Helvetica;
    procedure Test_GdiTop_brushBackgroundCoversCell;

    // W8b halos
    procedure Test_UnderFill_strokeFirstThenFill;
    procedure Test_UnderFill_doublesWidthAndRoundsJoins;
    procedure Test_UnderFill_oneTextObjectTwoShows;
    procedure Test_StrokeWidth_overridesStrokeStyle;
    procedure Test_NoHalo_byDefault;

    // W8c outlines
    procedure Test_Outlines_ArialA_isAPathNotText;
    procedure Test_Outlines_AA_advanceIsTwiceA;
    procedure Test_Outlines_Ionicons_F202_hasPath;
    procedure Test_Outlines_CJK_YaHei_hasPath;
    procedure Test_Outlines_underFillHalo_strokeThenFill;
    procedure Test_Outlines_rotation_wrapsInCm;
    procedure Test_Outlines_missingCharacter_warns;
    procedure Test_Outlines_standardFontName_drawsWithGdiEquivalent;
  end;

implementation

uses
  StrUtils, Generics.Collections, Vcl.Graphics, smPDF, smPDF.GdiFonts;

procedure TMapTextTests.RequireFont(const AFamily: string);
begin
  if not GdiFontInstalled(AFamily) then
    Skip(AFamily + ' is not installed');
end;

function TMapTextTests.Content(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  streams: TArray<TPdfTestStream>;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    ABuild(pdf);
    streams := ExtractPdfStreams(pdf.ToBytes);
  finally
    pdf.Free;
  end;
  // Fonts and images are written before the page, so its content comes last.
  if Length(streams) = 0 then
    Result := ''
  else
    Result := PdfBytesToString(streams[High(streams)].Data);
end;

function TMapTextTests.MoveToXs(const AContent: string): TArray<Double>;
var
  line: string;
  xs: TList<Double>;
begin
  xs := TList<Double>.Create;
  try
    for line in AContent.Split([#10]) do
      if EndsText(' m', line) then
        xs.Add(StrToFloat(line.Split([' '])[0], TFormatSettings.Invariant));
    Result := xs.ToArray;
  finally
    xs.Free;
  end;
end;

// ===== W8a =====

procedure TMapTextTests.Test_TypoTop_isTheDefault;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    AssertTrue(pdf.TextOrigin = toTypoTop);
  finally
    pdf.Free;
  end;
end;

procedure TMapTextTests.Test_TypoTop_baselineAtTypoAscender;
var s: string;
begin
  RequireFont('Arial');
  // Arial sTypoAscender 1491 of 2048: baseline 20 + 72.803 = 92.803 -> 792 - 92.803.
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Size := 100;
    TsmPDF(o).DrawText('H', 10, 20);
  end);
  AssertContains('1 0 0 1 10 699.197 Tm', s);
end;

procedure TMapTextTests.Test_GdiTop_Arial100_baselineAtWinAscent;
var s: string;
begin
  RequireFont('Arial');
  // usWinAscent 1854 of 2048 at 100 pt = 90.527; baseline at 20 + 90.527.
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).TextOrigin := toGdiTop;
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Size := 100;
    TsmPDF(o).DrawText('H', 10, 20);
  end);
  AssertContains('1 0 0 1 10 681.473 Tm', s);
end;

procedure TMapTextTests.Test_GdiTop_Arial100_textHeightIsGdiCell;
var
  pdf: TsmPDF;
begin
  RequireFont('Arial');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.Font.Size := 100;
    AssertEquals(120.0, pdf.TextHeightF('Hg'), 1e-9, 'toTypoTop keeps 1.2 x size');
    pdf.TextOrigin := toGdiTop;
    AssertEquals(100 * (1854 + 434) / 2048, pdf.TextHeightF('Hg'), 0.01, 'GDI cell');
    AssertEquals(112, pdf.TextHeight('Hg'));
  finally
    pdf.Free;
  end;
end;

procedure TMapTextTests.Test_Baseline_origin_yIsTheBaseline;
var s: string;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).TextOrigin := toBaseline;
    TsmPDF(o).DrawText('Base', 10, 20);
  end);
  AssertContains('1 0 0 1 10 772 Tm', s);
end;

procedure TMapTextTests.Test_FontMetrics_gdiTop_Arial;
var
  pdf: TsmPDF;
  m: TPDFTextMetrics;
begin
  RequireFont('Arial');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.Font.Size := 100;
    pdf.TextOrigin := toGdiTop;
    m := pdf.FontMetrics;
    AssertEquals(100 * 1854 / 2048, m.Ascent, 1e-6);
    AssertEquals(100 * 434 / 2048, m.Descent, 1e-6);
    AssertEquals(100 * 2288 / 2048, m.LineHeight, 1e-6);
    AssertEquals(100 * 1467 / 2048, m.CapHeight, 1e-6);
    AssertEquals(100 * 1062 / 2048, m.XHeight, 1e-6);
  finally
    pdf.Free;
  end;
end;

procedure TMapTextTests.Test_FontMetrics_typoTop_Helvetica;
var
  pdf: TsmPDF;
  m: TPDFTextMetrics;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Size := 10;
    m := pdf.FontMetrics;
    AssertEquals(7.18, m.Ascent, 1e-9);
    AssertEquals(2.07, m.Descent, 1e-9);
    AssertEquals(12.0, m.LineHeight, 1e-9);
  finally
    pdf.Free;
  end;
end;

procedure TMapTextTests.Test_GdiTop_brushBackgroundCoversCell;
var s: string;
begin
  RequireFont('Arial');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).TextOrigin := toGdiTop;
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Size := 100;
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawText('H', 10, 20);
  end);
  // Cell from y = 20 to 20 + 111.719: its bottom edge in PDF is 792 - 131.719.
  AssertContains(' 660.281 ', s);
  AssertContains(' 111.719 re', s);
end;

// ===== W8b =====

procedure TMapTextTests.Test_UnderFill_strokeFirstThenFill;
var
  s: string;
  pStroke, pFill: Integer;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Color := clBlack;
    TsmPDF(o).Font.StrokeColor := clWhite;
    TsmPDF(o).Font.StrokeWidth := 0.6;
    TsmPDF(o).Font.StrokeMode := smUnderFill;
    TsmPDF(o).DrawText('Label', 10, 20);
  end);
  pStroke := Pos('1 Tr', s);
  pFill   := Pos('0 Tr', s);
  AssertTrue(pStroke > 0, 'stroke-only pass (1 Tr)');
  AssertTrue(pFill > pStroke, 'fill pass (0 Tr) comes after the stroke pass');
  AssertContains('1 1 1 RG', s, 'halo in StrokeColor');
  AssertContains('0 0 0 rg', s, 'fill in Font.Color');
end;

procedure TMapTextTests.Test_UnderFill_doublesWidthAndRoundsJoins;
var s: string;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeWidth := 0.6;
    TsmPDF(o).Font.StrokeMode := smUnderFill;
    TsmPDF(o).DrawText('Label', 10, 20);
  end);
  AssertContains('1.2 w', s, 'line width is twice StrokeWidth');
  AssertContains('1 j', s, 'round join');
  AssertContains('1 J', s, 'round cap');
end;

procedure TMapTextTests.Test_UnderFill_oneTextObjectTwoShows;
var s: string;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeWidth := 0.6;
    TsmPDF(o).Font.StrokeMode := smUnderFill;
    TsmPDF(o).DrawText('Label', 10, 20);
  end);
  AssertEquals(1, CountSubstring('BT', s));
  AssertEquals(2, CountSubstring(') Tj', s));
  AssertEquals(2, CountSubstring(' Tm', s), 'both passes start at the same origin');
end;

procedure TMapTextTests.Test_StrokeWidth_overridesStrokeStyle;
var s: string;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.StrokeStyle := ssThick;
    TsmPDF(o).Font.StrokeWidth := 0.8;
    TsmPDF(o).DrawText('Label', 10, 20);
  end);
  AssertContains('0.8 w', s);
  AssertContains('2 Tr', s, 'smOverFill stays text render mode 2');
end;

procedure TMapTextTests.Test_NoHalo_byDefault;
var s: string;
begin
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).DrawText('Label', 10, 20);
  end);
  AssertEquals(0, Pos(' Tr', s));
  AssertEquals(0, Pos(' w'#10, s));
end;

// ===== W8c =====

procedure TMapTextTests.Test_Outlines_ArialA_isAPathNotText;
var s: string;
begin
  RequireFont('Arial');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Size := 24;
    TsmPDF(o).DrawTextOutlines('A', 10, 20);
  end);
  AssertTrue(Pos(' m'#10, s) > 0, 'moveto');
  AssertTrue((Pos(' l'#10, s) > 0) or (Pos(' c'#10, s) > 0), 'lineto or curveto');
  AssertContains(#10'f'#10, s, 'non-zero fill');
  AssertEquals(0, Pos('Tj', s), 'no text operators');
  AssertEquals(0, Pos('BT', s));
end;

procedure TMapTextTests.Test_Outlines_AA_advanceIsTwiceA;
var
  pdf: TsmPDF;
  xs: TArray<Double>;
  advance: Double;
  s: string;
begin
  RequireFont('Arial');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Size := 24;
    TsmPDF(o).DrawTextOutlines('AA', 10, 20);
  end);
  xs := MoveToXs(s);
  AssertTrue((Length(xs) >= 2) and not Odd(Length(xs)), 'the same contours for both glyphs');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.Font.Size := 24;
    advance := pdf.TextWidthF('A');
    AssertEquals(2 * advance, pdf.TextWidthF('AA'), 1e-9);
  finally
    pdf.Free;
  end;
  // The second A starts exactly one advance to the right of the first.
  AssertEquals(advance, xs[Length(xs) div 2] - xs[0], 0.002);
end;

procedure TMapTextTests.Test_Outlines_Ionicons_F202_hasPath;
var s: string;
begin
  RequireFont('Ionicons');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Ionicons';
    TsmPDF(o).Font.Size := 16;
    TsmPDF(o).DrawTextOutlines(#$F202, 10, 20);
  end);
  AssertTrue(CountSubstring(' m'#10, s) > 0, 'U+F202 has an outline');
  AssertContains(#10'f'#10, s);
end;

procedure TMapTextTests.Test_Outlines_CJK_YaHei_hasPath;
var s: string;
begin
  RequireFont('Microsoft YaHei');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Microsoft YaHei';
    TsmPDF(o).Font.Size := 16;
    TsmPDF(o).DrawTextOutlines(#$5317, 10, 20);
  end);
  AssertTrue(CountSubstring(' m'#10, s) > 0, 'U+5317 has an outline');
end;

procedure TMapTextTests.Test_Outlines_underFillHalo_strokeThenFill;
var
  s: string;
begin
  RequireFont('Arial');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.StrokeWidth := 0.5;
    TsmPDF(o).Font.StrokeMode := smUnderFill;
    TsmPDF(o).DrawTextOutlines('A', 10, 20);
  end);
  AssertContains('1 w', s, 'twice StrokeWidth');
  AssertContains('1 j', s);
  AssertTrue(Pos(#10'S'#10, s) > 0, 'stroke pass');
  AssertTrue(Pos(#10'f'#10, s) > Pos(#10'S'#10, s), 'fill after stroke');
end;

procedure TMapTextTests.Test_Outlines_rotation_wrapsInCm;
var s: string;
begin
  RequireFont('Arial');
  s := Content(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawTextOutlines('A', 100, 100, 90);
  end);
  AssertContains('0 1 -1 0 792 592 cm', s);
end;

procedure TMapTextTests.Test_Outlines_missingCharacter_warns;
var
  pdf: TsmPDF;
begin
  RequireFont('Arial');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.DrawTextOutlines('A'#$5317, 10, 20);
    AssertEquals(1, pdf.Warnings.Count, pdf.Warnings.Text);
    AssertContains('U+5317', pdf.Warnings[0]);
  finally
    pdf.Free;
  end;
end;

procedure TMapTextTests.Test_Outlines_standardFontName_drawsWithGdiEquivalent;
var
  pdf: TsmPDF;
  s: string;
begin
  RequireFont('Arial');
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Helvetica';
    pdf.DrawTextOutlines('A', 10, 20);
    s := PdfBytesToString(pdf.ToBytes);
    AssertTrue(Pos(' m'#10, s) > 0, 'drawn as a path');
    AssertEquals(0, pdf.Warnings.Count, pdf.Warnings.Text);
  finally
    pdf.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TMapTextTests);

end.
