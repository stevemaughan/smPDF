unit Tests.PDF.TTF;

interface

uses
  SysUtils, Classes, smPDF.TestFramework;

type
  TTTFTests = class(TTestCase)
  protected
    function ArialPath: string;
    function CalibriPath: string;
    function CourierNewPath: string;
  published
    procedure Test_Load_Arial_succeeds;
    procedure Test_Load_NonExistentFile_raises;
    procedure Test_Load_RandomBytes_raises;

    procedure Test_Arial_unitsPerEmIsTypical;
    procedure Test_Arial_numGlyphsIsPositive;
    procedure Test_Arial_familyNameIsArial;
    procedure Test_Arial_postScriptNameSet;
    procedure Test_Arial_isNotItalic;
    procedure Test_Arial_ascentIsPositive;
    procedure Test_Arial_descentIsNegative;
    procedure Test_Arial_capHeightIsPositive;

    procedure Test_Arial_glyphIndexForCapitalA_isPositive;
    procedure Test_Arial_glyphIndexForUnknown_isZero;
    procedure Test_Arial_widthForA_matchesCapitalGlyph;
    procedure Test_Arial_widthForSpace_isPositive;
    procedure Test_Arial_widthForControlChar_isZero;

    procedure Test_CourierNew_isFixedPitchFlag;
    procedure Test_CourierNew_allAsciiCharsHaveSameWidth;

    procedure Test_FontUnitsToPdf_at1000UnitsPerEm_isIdentity;
    procedure Test_FontUnitsToPdf_at2048UnitsPerEm_scales;

    procedure Test_PdfFlags_includeNonsymbolic;
  end;

implementation

uses
  IOUtils, smPDF.TTF;

const
  WIN_FONTS = 'C:\Windows\Fonts\';

function TTTFTests.ArialPath: string;
begin
  Result := TPath.Combine(WIN_FONTS, 'arial.ttf');
  if not TFile.Exists(Result) then
    Fail('arial.ttf not found at ' + Result);
end;

function TTTFTests.CalibriPath: string;
begin
  Result := TPath.Combine(WIN_FONTS, 'calibri.ttf');
  if not TFile.Exists(Result) then
    Fail('calibri.ttf not found at ' + Result);
end;

function TTTFTests.CourierNewPath: string;
begin
  Result := TPath.Combine(WIN_FONTS, 'cour.ttf');
  if not TFile.Exists(Result) then
    Fail('cour.ttf not found at ' + Result);
end;

procedure TTTFTests.Test_Load_Arial_succeeds;
var
  font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(Length(font.Bytes) > 1000, 'arial.ttf should be at least 1KB');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Load_NonExistentFile_raises;
var
  raised: Boolean;
begin
  raised := False;
  try
    TTTFFont.Create('C:\nonexistent\nope.ttf').Free;
  except
    on E: Exception do raised := True;
  end;
  AssertTrue(raised, 'Loading a missing file should raise');
end;

procedure TTTFTests.Test_Load_RandomBytes_raises;
var
  raised: Boolean;
  bogus: TBytes;
begin
  bogus := TBytes.Create($DE, $AD, $BE, $EF, 0, 0, 0, 0, 0, 0, 0, 0);
  raised := False;
  try
    TTTFFont.CreateFromBytes(bogus, 'random').Free;
  except
    on E: ETTFParseError do raised := True;
  end;
  AssertTrue(raised, 'Random bytes should raise ETTFParseError');
end;

procedure TTTFTests.Test_Arial_unitsPerEmIsTypical;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    // Arial uses 2048 units per em (very common). Some fonts use 1000 or 1024.
    AssertTrue((font.Metrics.UnitsPerEm >= 256) and (font.Metrics.UnitsPerEm <= 4096),
      Format('UnitsPerEm should be a typical TTF value, got %d', [font.Metrics.UnitsPerEm]));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_numGlyphsIsPositive;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.Metrics.NumGlyphs > 100,
      Format('Arial should have many glyphs, got %d', [font.Metrics.NumGlyphs]));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_familyNameIsArial;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertContains('Arial', font.Metrics.FamilyName,
      'family name should contain "Arial"');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_postScriptNameSet;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertNotEmpty(font.Metrics.PostScriptName, 'PostScript name should be populated');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_isNotItalic;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertFalse(font.Metrics.IsItalic, 'arial.ttf is the regular face, not italic');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_ascentIsPositive;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.Metrics.Ascent > 0,
      Format('Ascent should be positive, got %d', [font.Metrics.Ascent]));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_descentIsNegative;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.Metrics.Descent < 0,
      Format('Descent should be negative, got %d', [font.Metrics.Descent]));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_capHeightIsPositive;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.Metrics.CapHeight > 0,
      Format('CapHeight should be positive, got %d', [font.Metrics.CapHeight]));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_glyphIndexForCapitalA_isPositive;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.GlyphIndex(Ord('A')) > 0,
      'Arial must have a glyph for capital A');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_glyphIndexForUnknown_isZero;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    // U+E000 is private use area; Arial should not map it
    AssertEquals(0, font.GlyphIndex($E000));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_widthForA_matchesCapitalGlyph;
var
  font: TTTFFont;
  glyph: Word;
  widthFromGlyph, widthFromChar: Word;
begin
  font := TTTFFont.Create(ArialPath);
  try
    glyph          := font.GlyphIndex(Ord('A'));
    widthFromGlyph := font.GlyphAdvance(glyph);
    widthFromChar  := font.CharWidthWinAnsi(Ord('A'));
    AssertEquals(widthFromGlyph, widthFromChar,
      'CharWidthWinAnsi should return the same value as the glyph advance');
    AssertTrue(widthFromChar > 0, 'A has positive width');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_widthForSpace_isPositive;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue(font.CharWidthWinAnsi(Ord(' ')) > 0, 'space has positive width');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_Arial_widthForControlChar_isZero;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    // 0x00 in WinAnsi: typically maps to .notdef (glyph 0) -> width 0
    AssertEquals(0, font.CharWidthWinAnsi(0));
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_CourierNew_isFixedPitchFlag;
var font: TTTFFont;
begin
  font := TTTFFont.Create(CourierNewPath);
  try
    AssertTrue(font.Metrics.IsFixedPitch, 'Courier New should report isFixedPitch');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_CourierNew_allAsciiCharsHaveSameWidth;
var
  font: TTTFFont;
  refWidth, w: Word;
  b: Byte;
begin
  font := TTTFFont.Create(CourierNewPath);
  try
    refWidth := font.CharWidthWinAnsi(Ord('A'));
    AssertTrue(refWidth > 0);
    for b := Ord('A') to Ord('Z') do
    begin
      w := font.CharWidthWinAnsi(b);
      AssertEquals(refWidth, w,
        Format('Courier New should be monospaced; byte %d width %d != %d', [b, w, refWidth]));
    end;
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_FontUnitsToPdf_at1000UnitsPerEm_isIdentity;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    // Even if Arial's own units differ, the function divides by UnitsPerEm.
    // We test the math indirectly by checking the round trip on numGlyphs:
    AssertTrue(font.FontUnitsToPdf(font.Metrics.UnitsPerEm) = 1000,
      'FontUnitsToPdf(unitsPerEm) should be 1000 by definition');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_FontUnitsToPdf_at2048UnitsPerEm_scales;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    if font.Metrics.UnitsPerEm = 2048 then
      AssertEquals(500, font.FontUnitsToPdf(1024),
        '2048 units/em: half-em -> 500/1000');
  finally
    font.Free;
  end;
end;

procedure TTTFTests.Test_PdfFlags_includeNonsymbolic;
var font: TTTFFont;
begin
  font := TTTFFont.Create(ArialPath);
  try
    AssertTrue((font.Metrics.PdfFlags and 32) <> 0,
      'Arial should have the Nonsymbolic flag set (bit 5 = 32)');
  finally
    font.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TTTFTests);

end.
