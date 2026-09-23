unit Tests.PDF.Unicode;

// Tier 1 Unicode text through CID fonts (W11). Non-ASCII text is written with
// #$ escapes so the source stays ASCII. Tests that need a particular font, or
// mutool for text extraction, skip when it is missing.

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TUnicodeTests = class(TTestCase)
  protected
    procedure RequireFont(const AFamily: string);
    function Build(const AFamily, AText: string; ACompress: Boolean = False): TBytes;
    function ToUnicodeOf(const APdf: TBytes): string;
    procedure CheckExtracts(const AFamily, AText: string);
  published
    procedure Test_Polish_Arial_type0HexAndToUnicode;
    procedure Test_Polish_Arial_extractsWithMutool;
    procedure Test_Chinese_YaHei_extracts;
    procedure Test_Japanese_YuGothic_extracts;
    procedure Test_Vietnamese_Arial_extracts;
    procedure Test_PlainAscii_TrueType_extracts;
    procedure Test_Multilingual_rendersWithoutMutoolWarnings;
    procedure Test_Ionicons_F202_drawsRealGlyph;
    procedure Test_MissingCharacter_glyphZeroAndOneWarning;
    procedure Test_SurrogatePair_formatTwelveCmap_resolves;
    procedure Test_W_groupsConsecutiveGlyphIds;
    procedure Test_TrueTypeText_isAlwaysHex;
    procedure Test_CJKParagraph_wrapsWithoutSpaces;
    procedure Test_CJKTextWidth_sumsAdvances;
    procedure Test_YaHeiPage_fontDataWellUnder1MB;
    procedure Test_Standard14_nonWinAnsi_questionMarkAndOneWarningEach;
    procedure Test_ToUnicodeCMap_surrogatesAndBlocks;
    procedure Test_TextToCodepoints_combinesSurrogates;
  end;

implementation

uses
  StrUtils, Types, Vcl.Graphics, smPDF, smPDF.GdiFonts, smPDF.TTF, smPDF.FontEmit, smPDF.FontRegistry;

const
  POLISH     = #$0141#$00F3'd'#$017A' Gy'#$0151'r Dvo'#$0159#$00E1'k';
  CHINESE    = #$5317#$4EAC#$5E02;
  JAPANESE   = #$6771#$4EAC#$90FD;
  VIETNAMESE = 'H'#$00E0' N'#$1ED9'i';

procedure TUnicodeTests.RequireFont(const AFamily: string);
begin
  if not GdiFontInstalled(AFamily) then
    Skip(AFamily + ' is not installed');
end;

function TUnicodeTests.Build(const AFamily, AText: string; ACompress: Boolean): TBytes;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := ACompress;
    pdf.NewPage(612, 792);
    pdf.Font.Name := AFamily;
    pdf.Font.Size := 18;
    pdf.DrawText(AText, 20, 20);
    Result := pdf.ToBytes;
    AssertEquals(0, pdf.Warnings.Count, pdf.Warnings.Text);
  finally
    pdf.Free;
  end;
end;

function TUnicodeTests.ToUnicodeOf(const APdf: TBytes): string;
var
  st: TPdfTestStream;
begin
  for st in ExtractPdfStreams(APdf) do
    if Pos('begincmap', PdfBytesToString(st.Data)) > 0 then
      Exit(PdfBytesToString(st.Data));
  Result := '';
end;

procedure TUnicodeTests.CheckExtracts(const AFamily, AText: string);
var
  extracted: string;
begin
  RequireFont(AFamily);
  if not MutoolExtractText(Build(AFamily, AText, True), extracted) then
    Skip('mutool is not on the PATH');
  AssertEquals(AText, extracted, AFamily + ' text extracted by mutool');
end;

procedure TUnicodeTests.Test_Polish_Arial_type0HexAndToUnicode;
var
  pdf: TBytes;
  s, cmap: string;
begin
  RequireFont('Arial');
  pdf := Build('Arial', POLISH);
  s := PdfBytesToString(pdf);
  AssertContains('/Subtype /Type0', s);
  AssertContains('/Encoding /Identity-H', s);
  AssertTrue(Pos('> Tj', s) > 0, 'text is shown as a hex string');
  cmap := ToUnicodeOf(pdf);
  AssertContains('> <0141>', cmap, 'L with stroke');
  AssertContains('> <00F3>', cmap, 'o acute');
  AssertContains('> <017A>', cmap, 'z acute');
  AssertContains('> <0151>', cmap, 'o double acute');
  AssertContains('> <0159>', cmap, 'r caron');
  AssertContains('> <00E1>', cmap, 'a acute');
end;

procedure TUnicodeTests.Test_Polish_Arial_extractsWithMutool;
begin
  CheckExtracts('Arial', POLISH);
end;

procedure TUnicodeTests.Test_Chinese_YaHei_extracts;
begin
  CheckExtracts('Microsoft YaHei', CHINESE);
end;

procedure TUnicodeTests.Test_Japanese_YuGothic_extracts;
begin
  CheckExtracts('Yu Gothic', JAPANESE);
end;

procedure TUnicodeTests.Test_Vietnamese_Arial_extracts;
begin
  CheckExtracts('Arial', VIETNAMESE);
end;

procedure TUnicodeTests.Test_PlainAscii_TrueType_extracts;
begin
  CheckExtracts('Arial', 'Hello World (ASCII) 123');
end;

procedure TUnicodeTests.Test_Multilingual_rendersWithoutMutoolWarnings;
var
  pdf: TsmPDF;
  warnings: string;
  bytes: TBytes;
begin
  RequireFont('Arial');
  RequireFont('Microsoft YaHei');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.DrawText(POLISH, 20, 20);
    pdf.DrawText(VIETNAMESE, 20, 50);
    pdf.Font.Name := 'Microsoft YaHei';
    pdf.DrawText(CHINESE, 20, 80);
    bytes := pdf.ToBytes;
  finally
    pdf.Free;
  end;
  if not MutoolRenderWarnings(bytes, warnings) then
    Skip('mutool is not on the PATH');
  AssertEquals('', warnings, 'mutool render output');
end;

procedure TUnicodeTests.Test_Ionicons_F202_drawsRealGlyph;
var
  s: string;
begin
  RequireFont('Ionicons');
  s := PdfBytesToString(Build('Ionicons', #$F202));
  AssertFalse(Pos('<0000> Tj', s) > 0, 'U+F202 must not be .notdef');
  AssertTrue(Pos('> Tj', s) > 0);
end;

procedure TUnicodeTests.Test_MissingCharacter_glyphZeroAndOneWarning;
var
  pdf: TsmPDF;
  s: string;
begin
  RequireFont('Arial');
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.DrawText('A' + CHINESE[1], 20, 20);
    pdf.DrawText(CHINESE[1] + 'B', 20, 40);
    s := PdfBytesToString(pdf.ToBytes);
    AssertContains('0000', s);
    AssertEquals(1, pdf.Warnings.Count, pdf.Warnings.Text);
    AssertContains('U+5317', pdf.Warnings[0]);
    AssertContains('Arial', pdf.Warnings[0]);
  finally
    pdf.Free;
  end;
end;

procedure TUnicodeTests.Test_SurrogatePair_formatTwelveCmap_resolves;
var
  pdf: TBytes;
  s: string;
begin
  // U+20000, the first CJK Extension B ideograph, needs the format 12 cmap.
  RequireFont('SimSun-ExtB');
  pdf := Build('SimSun-ExtB', #$D840#$DC00);
  s := PdfBytesToString(pdf);
  AssertFalse(Pos('<0000> Tj', s) > 0, 'U+20000 must resolve to a real glyph');
  AssertContains('> <D840DC00>', ToUnicodeOf(pdf), 'ToUnicode uses a surrogate pair');
end;

procedure TUnicodeTests.Test_W_groupsConsecutiveGlyphIds;
var
  s: string;
begin
  RequireFont('Arial');
  // a, b, c are glyphs 68, 69, 70 in Arial: one group. Advances 1139, 1139, 1024 of 2048.
  s := PdfBytesToString(Build('Arial', 'abc'));
  AssertContains('/W [68 [556.152 556.152 500]]', s);
end;

procedure TUnicodeTests.Test_TrueTypeText_isAlwaysHex;
var
  s: string;
begin
  RequireFont('Arial');
  s := PdfBytesToString(Build('Arial', 'plain ascii'));
  AssertContains('<', s);
  AssertFalse(Pos(') Tj', s) > 0, 'TrueType text never uses literal strings');
end;

procedure TUnicodeTests.Test_CJKParagraph_wrapsWithoutSpaces;
var
  pdf: TsmPDF;
  s, text: string;
  ext: TSize;
  i: Integer;
begin
  RequireFont('Microsoft YaHei');
  text := '';
  for i := 1 to 4 do
    text := text + CHINESE + JAPANESE;   // 24 ideographs, no spaces
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Microsoft YaHei';
    pdf.Font.Size := 10;
    // Room for about five 10 pt ideographs per line.
    pdf.DrawParagraph(text, TRect.Create(20, 20, 72, 400), taLeftJustify, tpSingle);
    ext := pdf.MeasureParagraph(text, 52);
    s := PdfBytesToString(pdf.ToBytes);
    AssertTrue(CountSubstring('> Tj', s) >= 4,
      Format('expected several wrapped lines, got %d', [CountSubstring('> Tj', s)]));
    AssertTrue(ext.cx <= 52, Format('widest line %d exceeds 52 px', [ext.cx]));
    AssertTrue(ext.cy >= 4 * 12, 'several lines tall');
    AssertEquals(0, pdf.Warnings.Count, pdf.Warnings.Text);
  finally
    pdf.Free;
  end;
end;

procedure TUnicodeTests.Test_CJKTextWidth_sumsAdvances;
var
  pdf: TsmPDF;
  data: TBytes;
  face: string;
  ttf: TTTFFont;
  expected: Double;
  i: Integer;
begin
  if not GdiLoadFontData('Microsoft YaHei', False, False, data, face) then
    Skip('Microsoft YaHei is not installed');
  ttf := TTTFFont.CreateFromBytes(data, 'yahei');
  pdf := TsmPDF.Create;
  try
    expected := 0;
    for i := 1 to Length(CHINESE) do
      expected := expected + ttf.GlyphAdvance(ttf.GlyphIndex(Ord(CHINESE[i])));
    expected := expected * 20 / ttf.Metrics.UnitsPerEm;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Microsoft YaHei';
    pdf.Font.Size := 20;
    AssertEquals(expected, pdf.TextWidthF(CHINESE), 1e-9);
  finally
    pdf.Free;
    ttf.Free;
  end;
end;

procedure TUnicodeTests.Test_YaHeiPage_fontDataWellUnder1MB;
var
  pdf: TsmPDF;
  st: TPdfTestStream;
  i, row: Integer;
  line: string;
  fontBytes: Integer;
begin
  RequireFont('Microsoft YaHei');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Microsoft YaHei';
    pdf.Font.Size := 9;
    // 200 labels of 5 different common ideographs each: 1,000 distinct glyphs.
    for row := 0 to 199 do
    begin
      line := '';
      for i := 0 to 4 do
        line := line + Char($4E00 + row * 5 + i);
      pdf.DrawText(line, 10 + (row mod 8) * 70, 10 + (row div 8) * 30);
    end;
    fontBytes := 0;
    for st in ExtractPdfStreams(pdf.ToBytes) do
      if Pos('/Length1', st.Dict) > 0 then
        Inc(fontBytes, Length(st.Raw));
    AssertTrue(fontBytes > 0, 'FontFile2 present');
    AssertTrue(fontBytes < 1024 * 1024,
      Format('YaHei subset is %d bytes for 1,000 glyphs; expected well under 1 MB', [fontBytes]));
  finally
    pdf.Free;
  end;
end;

procedure TUnicodeTests.Test_Standard14_nonWinAnsi_questionMarkAndOneWarningEach;
var
  pdf: TsmPDF;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Helvetica';
    pdf.DrawText(#$0141#$00F3'd'#$017A, 20, 20);
    pdf.DrawText(#$0141'odz', 20, 40);
    s := PdfBytesToString(pdf.ToBytes);
    AssertContains('(?'#$F3'd?) Tj', s, 'o acute is WinAnsi; L-stroke and z-acute are not');
    AssertEquals(2, pdf.Warnings.Count, pdf.Warnings.Text);
    AssertContains('U+0141', pdf.Warnings.Text);
    AssertContains('U+017A', pdf.Warnings.Text);
  finally
    pdf.Free;
  end;
end;

procedure TUnicodeTests.Test_ToUnicodeCMap_surrogatesAndBlocks;
var
  glyphs: TArray<Word>;
  cps: TArray<Cardinal>;
  i: Integer;
  cmap: string;
begin
  SetLength(glyphs, 150);
  SetLength(cps, 150);
  for i := 0 to 149 do
  begin
    glyphs[i] := 10 + i;
    cps[i] := $41 + i;
  end;
  cps[0] := $1F600;
  cmap := string(BuildToUnicodeCMap(glyphs, cps));
  AssertContains('<000A> <D83DDE00>', cmap);
  AssertContains('100 beginbfchar', cmap);
  AssertContains('50 beginbfchar', cmap);
  AssertContains('<0000> <FFFF>', cmap, 'two-byte code space');
end;

procedure TUnicodeTests.Test_TextToCodepoints_combinesSurrogates;
var
  cps: TArray<Cardinal>;
begin
  cps := TextToCodepoints('A'#$D83D#$DE00'B'#$D800#9);
  AssertEquals(5, Length(cps));
  AssertEquals(Int64($41), Int64(cps[0]));
  AssertEquals(Int64($1F600), Int64(cps[1]));
  AssertEquals(Int64($42), Int64(cps[2]));
  AssertEquals(Int64($FFFD), Int64(cps[3]), 'lone surrogate');
  AssertEquals(Int64($20), Int64(cps[4]), 'tab becomes a space');
end;

initialization
  TTestRegistry.RegisterTestCase(TUnicodeTests);

end.
