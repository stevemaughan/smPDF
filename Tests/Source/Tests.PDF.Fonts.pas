unit Tests.PDF.Fonts;

interface

uses
  SysUtils, smPDF.TestFramework;

type
  TFontTests = class(TTestCase)
  published
    // Resolver
    procedure Test_Resolve_HelveticaPlain;
    procedure Test_Resolve_HelveticaBold;
    procedure Test_Resolve_HelveticaItalic;
    procedure Test_Resolve_HelveticaBoldItalic;
    procedure Test_Resolve_ArialAliasesToHelvetica;
    procedure Test_Resolve_TimesPlain;
    procedure Test_Resolve_TimesBoldUsesTimesBoldNotOblique;
    procedure Test_Resolve_TimesItalicUsesItalicNotOblique;
    procedure Test_Resolve_CourierAllVariants;
    procedure Test_Resolve_SymbolIgnoresBoldItalic;
    procedure Test_Resolve_UnknownFallsBackToHelvetica;
    procedure Test_Resolve_CaseInsensitive;

    // PDF base font names
    procedure Test_PdfName_HelveticaBold_isHyphenated;
    procedure Test_PdfName_TimesRoman_includesRomanSuffix;

    // Symbolic font flag
    procedure Test_IsSymbolic_trueForSymbolAndDingbats;
    procedure Test_IsSymbolic_falseForOthers;

    // Width tables
    procedure Test_CharWidth_HelveticaCapitalA;
    procedure Test_CharWidth_HelveticaSpace;
    procedure Test_CharWidth_HelveticaBold_widerThanRegular;
    procedure Test_CharWidth_TimesCapitalM;
    procedure Test_CharWidth_CourierAllChars_isMonospace;
    procedure Test_CharWidth_outOfRangeFallsBackTo500;

    // Text width
    procedure Test_TextWidth_HelveticaHello;
    procedure Test_TextWidth_emptyStringIsZero;
    procedure Test_TextWidth_scalesWithSize;

    // Metrics
    procedure Test_Ascent_HelveticaAt12pt;
    procedure Test_Descent_TimesAt10pt;
    procedure Test_LineHeight_isOnePointTwoOfSize;

    // WinAnsi encoding
    procedure Test_StringToWinAnsi_pureAscii;
    procedure Test_StringToWinAnsi_latin1Supplement;
    procedure Test_StringToWinAnsi_unmappedBecomesQuestionMark;
    procedure Test_StringToWinAnsi_emptyString;
  end;

implementation

uses
  smPDF.Fonts;

procedure TFontTests.Test_Resolve_HelveticaPlain;
begin
  AssertEquals(Ord(sfHelvetica), Ord(ResolveStandardFont('Helvetica', False, False)));
end;

procedure TFontTests.Test_Resolve_HelveticaBold;
begin
  AssertEquals(Ord(sfHelveticaBold), Ord(ResolveStandardFont('Helvetica', True, False)));
end;

procedure TFontTests.Test_Resolve_HelveticaItalic;
begin
  AssertEquals(Ord(sfHelveticaOblique), Ord(ResolveStandardFont('Helvetica', False, True)));
end;

procedure TFontTests.Test_Resolve_HelveticaBoldItalic;
begin
  AssertEquals(Ord(sfHelveticaBoldOblique), Ord(ResolveStandardFont('Helvetica', True, True)));
end;

procedure TFontTests.Test_Resolve_ArialAliasesToHelvetica;
begin
  AssertEquals(Ord(sfHelvetica),     Ord(ResolveStandardFont('Arial', False, False)));
  AssertEquals(Ord(sfHelveticaBold), Ord(ResolveStandardFont('Arial', True,  False)));
end;

procedure TFontTests.Test_Resolve_TimesPlain;
begin
  AssertEquals(Ord(sfTimesRoman), Ord(ResolveStandardFont('Times', False, False)));
end;

procedure TFontTests.Test_Resolve_TimesBoldUsesTimesBoldNotOblique;
begin
  // Times has Italic variants, NOT Oblique like Helvetica
  AssertEquals(Ord(sfTimesBold), Ord(ResolveStandardFont('Times', True, False)));
end;

procedure TFontTests.Test_Resolve_TimesItalicUsesItalicNotOblique;
begin
  AssertEquals(Ord(sfTimesItalic), Ord(ResolveStandardFont('Times', False, True)));
  AssertEquals('Times-Italic', StandardFontPdfName(sfTimesItalic));
end;

procedure TFontTests.Test_Resolve_CourierAllVariants;
begin
  AssertEquals(Ord(sfCourier),             Ord(ResolveStandardFont('Courier', False, False)));
  AssertEquals(Ord(sfCourierBold),         Ord(ResolveStandardFont('Courier', True,  False)));
  AssertEquals(Ord(sfCourierOblique),      Ord(ResolveStandardFont('Courier', False, True)));
  AssertEquals(Ord(sfCourierBoldOblique),  Ord(ResolveStandardFont('Courier', True,  True)));
end;

procedure TFontTests.Test_Resolve_SymbolIgnoresBoldItalic;
begin
  AssertEquals(Ord(sfSymbol), Ord(ResolveStandardFont('Symbol', False, False)));
  AssertEquals(Ord(sfSymbol), Ord(ResolveStandardFont('Symbol', True,  True)));
end;

procedure TFontTests.Test_Resolve_UnknownFallsBackToHelvetica;
begin
  AssertEquals(Ord(sfHelvetica),     Ord(ResolveStandardFont('SomeRandomThing', False, False)));
  AssertEquals(Ord(sfHelveticaBold), Ord(ResolveStandardFont('SomeRandomThing', True,  False)));
end;

procedure TFontTests.Test_Resolve_CaseInsensitive;
begin
  AssertEquals(Ord(sfHelvetica), Ord(ResolveStandardFont('HELVETICA', False, False)));
  AssertEquals(Ord(sfTimesBold), Ord(ResolveStandardFont('times',     True,  False)));
end;

procedure TFontTests.Test_PdfName_HelveticaBold_isHyphenated;
begin
  AssertEquals('Helvetica-Bold',         StandardFontPdfName(sfHelveticaBold));
  AssertEquals('Helvetica-BoldOblique',  StandardFontPdfName(sfHelveticaBoldOblique));
end;

procedure TFontTests.Test_PdfName_TimesRoman_includesRomanSuffix;
begin
  AssertEquals('Times-Roman',     StandardFontPdfName(sfTimesRoman));
  AssertEquals('Times-BoldItalic', StandardFontPdfName(sfTimesBoldItalic));
end;

procedure TFontTests.Test_IsSymbolic_trueForSymbolAndDingbats;
begin
  AssertTrue(StandardFontIsSymbolic(sfSymbol));
  AssertTrue(StandardFontIsSymbolic(sfZapfDingbats));
end;

procedure TFontTests.Test_IsSymbolic_falseForOthers;
begin
  AssertFalse(StandardFontIsSymbolic(sfHelvetica));
  AssertFalse(StandardFontIsSymbolic(sfTimesRoman));
  AssertFalse(StandardFontIsSymbolic(sfCourier));
end;

procedure TFontTests.Test_CharWidth_HelveticaCapitalA;
begin
  AssertEquals(667, StandardFontCharWidth(sfHelvetica, Ord('A')));
end;

procedure TFontTests.Test_CharWidth_HelveticaSpace;
begin
  AssertEquals(278, StandardFontCharWidth(sfHelvetica, Ord(' ')));
end;

procedure TFontTests.Test_CharWidth_HelveticaBold_widerThanRegular;
begin
  // Bold Helvetica is wider than regular for many chars; for 'a' we know:
  // regular = 556, bold = 556 (same here actually) — pick a char where they differ:
  // 'B': regular 667, bold 722
  AssertTrue(StandardFontCharWidth(sfHelveticaBold, Ord('B'))
           > StandardFontCharWidth(sfHelvetica,     Ord('B')));
end;

procedure TFontTests.Test_CharWidth_TimesCapitalM;
begin
  AssertEquals(889, StandardFontCharWidth(sfTimesRoman, Ord('M')));
end;

procedure TFontTests.Test_CharWidth_CourierAllChars_isMonospace;
var
  b: Byte;
begin
  for b := 32 to 126 do
    AssertEquals(600, StandardFontCharWidth(sfCourier, b),
      Format('Courier byte %d should be 600', [b]));
end;

procedure TFontTests.Test_CharWidth_outOfRangeFallsBackTo500;
begin
  AssertEquals(500, StandardFontCharWidth(sfHelvetica, 0));
  AssertEquals(500, StandardFontCharWidth(sfHelvetica, 200));
end;

procedure TFontTests.Test_TextWidth_HelveticaHello;
var
  expected: Double;
begin
  // Helvetica widths: H=722, e=556, l=222, l=222, o=556 -> sum = 2278 / 1000 em
  // At 12pt: width = 2278 * 12 / 1000 = 27.336 pt
  expected := (722 + 556 + 222 + 222 + 556) * 12.0 / 1000.0;
  AssertEquals(expected,
    StandardFontTextWidth(sfHelvetica, 12, 'Hello'),
    1e-9);
end;

procedure TFontTests.Test_TextWidth_emptyStringIsZero;
begin
  AssertEquals(0.0, StandardFontTextWidth(sfHelvetica, 12, ''), 1e-9);
end;

procedure TFontTests.Test_TextWidth_scalesWithSize;
var
  w12, w24: Double;
begin
  w12 := StandardFontTextWidth(sfHelvetica, 12, 'AB');
  w24 := StandardFontTextWidth(sfHelvetica, 24, 'AB');
  AssertEquals(2.0 * w12, w24, 1e-9);
end;

procedure TFontTests.Test_Ascent_HelveticaAt12pt;
begin
  // Approximation: 0.718 * 12 = 8.616 pt
  AssertEquals(8.616, StandardFontAscent(sfHelvetica, 12), 1e-3);
end;

procedure TFontTests.Test_Descent_TimesAt10pt;
begin
  // 0.217 * 10 = 2.17 pt (positive magnitude)
  AssertEquals(2.17, StandardFontDescent(sfTimesRoman, 10), 1e-3);
end;

procedure TFontTests.Test_LineHeight_isOnePointTwoOfSize;
begin
  AssertEquals(14.4, StandardFontLineHeight(sfHelvetica, 12), 1e-9);
  AssertEquals(12.0, StandardFontLineHeight(sfHelvetica, 10), 1e-9);
end;

procedure TFontTests.Test_StringToWinAnsi_pureAscii;
var
  ans: AnsiString;
begin
  ans := StringToWinAnsi('Hello');
  AssertEquals(5, Length(ans));
  AssertEquals(Ord('H'), Byte(ans[1]));
  AssertEquals(Ord('o'), Byte(ans[5]));
end;

procedure TFontTests.Test_StringToWinAnsi_latin1Supplement;
var
  ans: AnsiString;
begin
  // U+00C9 (Latin Capital Letter E with Acute, 'E acute') -> 0xC9 in WinAnsi.
  // Use Pascal's hex-char escape so the source encoding doesn't matter.
  ans := StringToWinAnsi(#$00C9);
  AssertEquals(1, Length(ans));
  AssertEquals($C9, Byte(ans[1]));
end;

procedure TFontTests.Test_StringToWinAnsi_unmappedBecomesQuestionMark;
var
  ans: AnsiString;
begin
  // U+1F600 (😀) is not representable in WinAnsi -> '?'
  // In Delphi UTF-16 string, that's a surrogate pair.
  ans := StringToWinAnsi(#$D83D#$DE00);
  AssertTrue(Length(ans) >= 1, 'should produce at least one byte');
  // First byte should be 0x3F ('?'). Some encoders emit two question marks for the surrogate pair.
  AssertEquals(Ord('?'), Byte(ans[1]));
end;

procedure TFontTests.Test_StringToWinAnsi_emptyString;
begin
  AssertEquals(0, Length(StringToWinAnsi('')));
end;

initialization
  TTestRegistry.RegisterTestCase(TFontTests);

end.
