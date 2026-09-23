unit Tests.PDF.Subset;

// TrueType subsetting (W10).

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers, smPDF.TTF;

type
  TSubsetTests = class(TTestCase)
  protected
    function LoadFont(const AFamily: string): TTTFFont;
    function Subset(AFont: TTTFFont; const AText: string): TTTFFont;
    function FontFileOf(const APdf: TBytes; out AStream: TPdfTestStream): Boolean;
  published
    procedure Test_Subset_reparsesWithOwnParser;
    procedure Test_Subset_keepsGlyphCountAndIds;
    procedure Test_Subset_unusedGlyphsAreEmpty;
    procedure Test_Subset_usedGlyphsKeepTheirOutlines;
    procedure Test_Subset_compositeGlyphKeepsComponents;
    procedure Test_Subset_cmapMapsUsedCharacters;
    procedure Test_Subset_dropsLayoutTables;
    procedure Test_Subset_keepsHintingTables;
    procedure Test_SubsetTag_isSixCapitalsAndStable;
    procedure Test_Pdf_baseFontCarriesSubsetTag;
    procedure Test_Pdf_arialPage_fontDataUnder100KB;
  end;

implementation

uses
  RegularExpressions, Vcl.Graphics, smPDF, smPDF.GdiFonts, smPDF.Subset;

function TSubsetTests.LoadFont(const AFamily: string): TTTFFont;
var
  data: TBytes;
  face: string;
begin
  if not GdiLoadFontData(AFamily, False, False, data, face) then
    Skip(AFamily + ' is not installed');
  Result := TTTFFont.CreateFromBytes(data, AFamily);
end;

function TSubsetTests.Subset(AFont: TTTFFont; const AText: string): TTTFFont;
var
  used: TArray<Word>;
  map: TArray<TSubsetCharMapping>;
  i: Integer;
begin
  SetLength(used, Length(AText));
  SetLength(map, Length(AText));
  for i := 1 to Length(AText) do
  begin
    used[i - 1] := AFont.GlyphIndex(Ord(AText[i]));
    map[i - 1].Codepoint := Ord(AText[i]);
    map[i - 1].GlyphId := used[i - 1];
  end;
  Result := TTTFFont.CreateFromBytes(BuildHollowSubset(AFont, used, map, 'ABCDEF+Test'), 'subset');
end;

function TSubsetTests.FontFileOf(const APdf: TBytes; out AStream: TPdfTestStream): Boolean;
var
  st: TPdfTestStream;
begin
  for st in ExtractPdfStreams(APdf) do
    if Pos('/Length1', st.Dict) > 0 then
    begin
      AStream := st;
      Exit(True);
    end;
  Result := False;
end;

procedure TSubsetTests.Test_Subset_reparsesWithOwnParser;
var
  font, sub: TTTFFont;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      AssertEquals('ABCDEF+Test', sub.Metrics.PostScriptName);
      AssertEquals(font.Metrics.UnitsPerEm, sub.Metrics.UnitsPerEm);
      AssertEquals(1, sub.IndexToLocFormat, 'the subset uses long loca offsets');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_keepsGlyphCountAndIds;
var
  font, sub: TTTFFont;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      AssertEquals(font.Metrics.NumGlyphs, sub.Metrics.NumGlyphs);
      AssertEquals(Integer(font.GlyphIndex(Ord('H'))), Integer(sub.GlyphIndex(Ord('H'))));
      AssertEquals(Integer(font.GlyphAdvance(font.GlyphIndex(Ord('H')))),
                   Integer(sub.GlyphAdvance(sub.GlyphIndex(Ord('H')))), 'advance of a used glyph');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_unusedGlyphsAreEmpty;
var
  font, sub: TTTFFont;
  off, len: Cardinal;
begin
  font := LoadFont('Arial');
  try
    AssertTrue(font.GlyphRange(font.GlyphIndex(Ord('Z')), off, len), 'Z has an outline in Arial');
    sub := Subset(font, 'Hello');
    try
      AssertFalse(sub.GlyphRange(font.GlyphIndex(Ord('Z')), off, len), 'unused glyph Z is hollow');
      AssertFalse(sub.GlyphRange(font.GlyphIndex(Ord('a')), off, len), 'unused glyph a is hollow');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_usedGlyphsKeepTheirOutlines;
var
  font, sub: TTTFFont;
  off1, len1, off2, len2: Cardinal;
  gid: Word;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      gid := font.GlyphIndex(Ord('e'));
      AssertTrue(font.GlyphRange(gid, off1, len1));
      AssertTrue(sub.GlyphRange(gid, off2, len2), 'used glyph e keeps its outline');
      AssertTrue((len2 >= len1) and (len2 - len1 < 4), 'same outline, padded to 4 bytes');
      AssertTrue(sub.GlyphRange(0, off2, len2) or not font.GlyphRange(0, off1, len1),
        '.notdef is always kept');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_compositeGlyphKeepsComponents;
var
  font, sub: TTTFFont;
  gid, comp: Word;
  comps: TArray<Word>;
  off, len: Cardinal;
  ch: Char;
begin
  font := LoadFont('Arial');
  try
    // Find an accented letter that Arial builds as a composite glyph.
    comps := nil;
    for ch in [#$00E9, #$00C5, #$00F1, #$00FC, #$00E0] do
    begin
      gid := font.GlyphIndex(Ord(ch));
      comps := font.GlyphComponents(gid);
      if Length(comps) > 0 then Break;
    end;
    if Length(comps) = 0 then
      Skip('no composite accented glyph found in this Arial');
    sub := Subset(font, string(ch));
    try
      AssertTrue(sub.GlyphRange(gid, off, len), 'the composite itself is kept');
      for comp in comps do
        AssertTrue(sub.GlyphRange(comp, off, len),
          'component ' + IntToStr(comp) + ' of the composite is kept');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_cmapMapsUsedCharacters;
var
  font, sub: TTTFFont;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      AssertEquals(Integer(font.GlyphIndex(Ord('l'))), Integer(sub.GlyphIndex(Ord('l'))));
      AssertEquals(0, Integer(sub.GlyphIndex(Ord('Z'))), 'unused characters are not mapped');
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_dropsLayoutTables;
var
  font, sub: TTTFFont;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      AssertFalse(sub.HasTable('GSUB'));
      AssertFalse(sub.HasTable('GPOS'));
      AssertFalse(sub.HasTable('kern'));
      AssertFalse(sub.HasTable('DSIG'));
      AssertTrue(sub.HasTable('glyf'));
      AssertTrue(sub.HasTable('OS/2'));
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_Subset_keepsHintingTables;
var
  font, sub: TTTFFont;
begin
  font := LoadFont('Arial');
  try
    sub := Subset(font, 'Hello');
    try
      AssertEquals(font.HasTable('fpgm'), sub.HasTable('fpgm'));
      AssertEquals(font.HasTable('prep'), sub.HasTable('prep'));
      AssertEquals(font.HasTable('cvt '), sub.HasTable('cvt '));
    finally
      sub.Free;
    end;
  finally
    font.Free;
  end;
end;

procedure TSubsetTests.Test_SubsetTag_isSixCapitalsAndStable;
var
  a, b, c: string;
begin
  a := MakeSubsetTag('ArialMT', [3, 4, 5]);
  b := MakeSubsetTag('ArialMT', [3, 4, 5]);
  c := MakeSubsetTag('ArialMT', [3, 4, 6]);
  AssertTrue(TRegEx.IsMatch(a, '^[A-Z]{6}$'), a);
  AssertEquals(a, b, 'the same subset gets the same tag');
  AssertTrue(a <> c, 'a different glyph set gets a different tag');
end;

procedure TSubsetTests.Test_Pdf_baseFontCarriesSubsetTag;
var
  pdf: TsmPDF;
  s: string;
  data: TBytes;
  face: string;
begin
  if not GdiLoadFontData('Arial', False, False, data, face) then
    Skip('Arial is not installed');
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.DrawText('Hello', 10, 10);
    s := PdfBytesToString(pdf.ToBytes);
    AssertTrue(TRegEx.IsMatch(s, '/BaseFont /[A-Z]{6}\+ArialMT'), 'BaseFont');
    AssertTrue(TRegEx.IsMatch(s, '/FontName /[A-Z]{6}\+ArialMT'), 'FontName');
  finally
    pdf.Free;
  end;
end;

procedure TSubsetTests.Test_Pdf_arialPage_fontDataUnder100KB;
var
  pdf: TsmPDF;
  st: TPdfTestStream;
  data: TBytes;
  face: string;
  sub: TTTFFont;
begin
  if not GdiLoadFontData('Arial', False, False, data, face) then
    Skip('Arial is not installed');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.Font.Size := 24;
    pdf.DrawText('Sales Territories 2026 - North East Region', 10, 10);
    AssertTrue(FontFileOf(pdf.ToBytes, st), 'FontFile2 present');
    AssertTrue(Length(st.Raw) < 100 * 1024,
      Format('embedded Arial is %d bytes; expected under 100 KB', [Length(st.Raw)]));
    AssertEquals(Length(st.Data), DictInt(st.Dict, 'Length1'));
    sub := TTTFFont.CreateFromBytes(st.Data, 'embedded');
    try
      AssertTrue(sub.GlyphIndex(Ord('S')) > 0, 'embedded subset maps S');
    finally
      sub.Free;
    end;
  finally
    pdf.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TSubsetTests);

end.
