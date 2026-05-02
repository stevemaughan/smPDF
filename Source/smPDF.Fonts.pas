unit smPDF.Fonts;

interface

uses
  SysUtils;

type
  TStandardFont = (
    sfHelvetica,            sfHelveticaBold,
    sfHelveticaOblique,     sfHelveticaBoldOblique,
    sfTimesRoman,           sfTimesBold,
    sfTimesItalic,          sfTimesBoldItalic,
    sfCourier,              sfCourierBold,
    sfCourierOblique,       sfCourierBoldOblique,
    sfSymbol,               sfZapfDingbats
  );

// True if the given user-facing family name maps to one of the 14 built-in
// PDF fonts (without falling back to a default). Phase 4 uses this to decide
// whether to consult Windows for a TTF file or just emit a Type1 font dict.
function IsStandard14FamilyName(const ABaseName: string): Boolean;

// Resolve a user-supplied font family name + bold/italic flags to one of the
// 14 standard fonts. Recognised family names (case-insensitive):
//   'Helvetica', 'Sans', 'SansSerif'   -> Helvetica family
//   'Times', 'Times-Roman', 'Serif'    -> Times family
//   'Courier', 'Mono', 'Monospace'     -> Courier family
//   'Symbol' -> Symbol (bold/italic ignored)
//   'ZapfDingbats', 'Zapf Dingbats' -> ZapfDingbats (bold/italic ignored)
// Anything unrecognised falls back to Helvetica.
//
// NOTE: 'Arial', 'Times New Roman', and 'Courier New' are NOT treated as
// Standard 14 aliases here — Phase 4 prefers to embed the actual TTF for
// those. Use IsStandard14FamilyName to gate this behaviour at call sites.
function ResolveStandardFont(const ABaseName: string; ABold, AItalic: Boolean): TStandardFont;

// Same as ResolveStandardFont but returns False for unrecognised family names
// instead of falling back to Helvetica. Lets callers decide what to do
// (e.g., look up an installed TTF instead).
function TryResolveStandardFont(const ABaseName: string; ABold, AItalic: Boolean;
  out AFont: TStandardFont): Boolean;

// The PostScript name used in the PDF /BaseFont entry (e.g. 'Helvetica-BoldOblique').
function StandardFontPdfName(AFont: TStandardFont): string;

// True for the two single-byte custom-encoding fonts that must NOT carry an
// /Encoding /WinAnsiEncoding entry (they ship with their own built-in encoding).
function StandardFontIsSymbolic(AFont: TStandardFont): Boolean;

// Width of a single byte (after WinAnsi encoding) in 1/1000 em.
function StandardFontCharWidth(AFont: TStandardFont; AByte: Byte): Integer;

// Width of an already-WinAnsi-encoded string at the given size, in PDF points.
function StandardFontTextWidth(AFont: TStandardFont; ASizePoints: Double; const AText: AnsiString): Double;

// Approximate font metrics in PDF points at the given size.
// Ascent is positive (above baseline); descent is positive (magnitude below baseline).
function StandardFontAscent(AFont: TStandardFont; ASizePoints: Double): Double;
function StandardFontDescent(AFont: TStandardFont; ASizePoints: Double): Double;

// Standard line height (top-to-top) in PDF points at the given size.
// Uses a 1.2x size-multiplier convention shared by most renderers.
function StandardFontLineHeight(AFont: TStandardFont; ASizePoints: Double): Double;

// Convert an arbitrary Unicode string to WinAnsi (codepage 1252) bytes.
// Code points not in WinAnsi become the literal '?' (0x3F).
function StringToWinAnsi(const AText: string): AnsiString;

implementation

uses
  Classes;

// ---------------------------------------------------------------------------
// Width tables — Adobe AFM canonical widths for ASCII range 32..126.
// Values for chars outside this range fall back to 500 (a reasonable middle).
// ---------------------------------------------------------------------------

const
  HELVETICA_WIDTHS: array[32..126] of Integer = (
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
   1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    222, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584
  );

  HELVETICA_BOLD_WIDTHS: array[32..126] of Integer = (
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584
  );

  TIMES_WIDTHS: array[32..126] of Integer = (
    250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444,
    921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722,
    556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500,
    333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500,
    500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541
  );

  TIMES_BOLD_WIDTHS: array[32..126] of Integer = (
    250, 333, 555, 500, 500,1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
    930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778,
    611, 778, 722, 556, 667, 722, 722,1000, 722, 722, 667, 333, 278, 333, 581, 500,
    333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500,
    556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520
  );

function IsStandard14FamilyName(const ABaseName: string): Boolean;
var
  fam: string;
begin
  fam := LowerCase(Trim(ABaseName));
  Result :=
    (fam = 'helvetica') or (fam = 'sans') or (fam = 'sansserif') or (fam = 'sans-serif') or
    (fam = 'times') or (fam = 'times-roman') or (fam = 'serif') or
    (fam = 'courier') or (fam = 'mono') or (fam = 'monospace') or
    (fam = 'symbol') or
    (fam = 'zapfdingbats') or (fam = 'zapf dingbats') or (fam = 'dingbats');
end;

function TryResolveStandardFont(const ABaseName: string; ABold, AItalic: Boolean;
  out AFont: TStandardFont): Boolean;
var
  fam: string;
begin
  fam := LowerCase(Trim(ABaseName));
  Result := True;
  if fam = 'symbol' then
    AFont := sfSymbol
  else if (fam = 'zapfdingbats') or (fam = 'zapf dingbats') or (fam = 'dingbats') then
    AFont := sfZapfDingbats
  else if (fam = 'times') or (fam = 'times-roman') or (fam = 'serif') then
  begin
    if      ABold and AItalic then AFont := sfTimesBoldItalic
    else if ABold             then AFont := sfTimesBold
    else if AItalic           then AFont := sfTimesItalic
    else                           AFont := sfTimesRoman;
  end
  else if (fam = 'courier') or (fam = 'mono') or (fam = 'monospace') then
  begin
    if      ABold and AItalic then AFont := sfCourierBoldOblique
    else if ABold             then AFont := sfCourierBold
    else if AItalic           then AFont := sfCourierOblique
    else                           AFont := sfCourier;
  end
  else if (fam = 'helvetica') or (fam = 'sans') or (fam = 'sansserif') or (fam = 'sans-serif') then
  begin
    if      ABold and AItalic then AFont := sfHelveticaBoldOblique
    else if ABold             then AFont := sfHelveticaBold
    else if AItalic           then AFont := sfHelveticaOblique
    else                           AFont := sfHelvetica;
  end
  else
  begin
    AFont  := sfHelvetica;  // unused; caller checks Result
    Result := False;
  end;
end;

function ResolveStandardFont(const ABaseName: string; ABold, AItalic: Boolean): TStandardFont;
begin
  if not TryResolveStandardFont(ABaseName, ABold, AItalic, Result) then
  begin
    // Fall back to the Helvetica variant matching bold/italic.
    if      ABold and AItalic then Result := sfHelveticaBoldOblique
    else if ABold             then Result := sfHelveticaBold
    else if AItalic           then Result := sfHelveticaOblique
    else                           Result := sfHelvetica;
  end;
end;

function StandardFontPdfName(AFont: TStandardFont): string;
begin
  case AFont of
    sfHelvetica:            Result := 'Helvetica';
    sfHelveticaBold:        Result := 'Helvetica-Bold';
    sfHelveticaOblique:     Result := 'Helvetica-Oblique';
    sfHelveticaBoldOblique: Result := 'Helvetica-BoldOblique';
    sfTimesRoman:           Result := 'Times-Roman';
    sfTimesBold:            Result := 'Times-Bold';
    sfTimesItalic:          Result := 'Times-Italic';
    sfTimesBoldItalic:      Result := 'Times-BoldItalic';
    sfCourier:              Result := 'Courier';
    sfCourierBold:          Result := 'Courier-Bold';
    sfCourierOblique:       Result := 'Courier-Oblique';
    sfCourierBoldOblique:   Result := 'Courier-BoldOblique';
    sfSymbol:               Result := 'Symbol';
    sfZapfDingbats:         Result := 'ZapfDingbats';
  end;
end;

function StandardFontIsSymbolic(AFont: TStandardFont): Boolean;
begin
  Result := AFont in [sfSymbol, sfZapfDingbats];
end;

function StandardFontCharWidth(AFont: TStandardFont; AByte: Byte): Integer;
begin
  if (AByte < 32) or (AByte > 126) then
    Exit(500);  // Latin-1 supplement and unmapped: phase-3 approximation

  case AFont of
    sfHelvetica, sfHelveticaOblique:
      Result := HELVETICA_WIDTHS[AByte];
    sfHelveticaBold, sfHelveticaBoldOblique:
      Result := HELVETICA_BOLD_WIDTHS[AByte];
    sfTimesRoman, sfTimesItalic:
      Result := TIMES_WIDTHS[AByte];
    sfTimesBold, sfTimesBoldItalic:
      Result := TIMES_BOLD_WIDTHS[AByte];
    sfCourier, sfCourierBold, sfCourierOblique, sfCourierBoldOblique:
      Result := 600;
    sfSymbol, sfZapfDingbats:
      Result := 500;  // approximation; Phase 4+ can refine
  else
    Result := 500;
  end;
end;

function StandardFontTextWidth(AFont: TStandardFont; ASizePoints: Double; const AText: AnsiString): Double;
var
  total: Integer;
  i: Integer;
begin
  total := 0;
  for i := 1 to Length(AText) do
    total := total + StandardFontCharWidth(AFont, Byte(AText[i]));
  Result := total * ASizePoints / 1000.0;
end;

function StandardFontAscent(AFont: TStandardFont; ASizePoints: Double): Double;
var
  emRatio: Double;
begin
  case AFont of
    sfHelvetica, sfHelveticaBold, sfHelveticaOblique, sfHelveticaBoldOblique:
      emRatio := 0.718;
    sfTimesRoman, sfTimesBold, sfTimesItalic, sfTimesBoldItalic:
      emRatio := 0.683;
    sfCourier, sfCourierBold, sfCourierOblique, sfCourierBoldOblique:
      emRatio := 0.629;
  else
    emRatio := 0.700;  // Symbol/Dingbats approximation
  end;
  Result := emRatio * ASizePoints;
end;

function StandardFontDescent(AFont: TStandardFont; ASizePoints: Double): Double;
var
  emRatio: Double;
begin
  case AFont of
    sfHelvetica, sfHelveticaBold, sfHelveticaOblique, sfHelveticaBoldOblique:
      emRatio := 0.207;
    sfTimesRoman, sfTimesBold, sfTimesItalic, sfTimesBoldItalic:
      emRatio := 0.217;
    sfCourier, sfCourierBold, sfCourierOblique, sfCourierBoldOblique:
      emRatio := 0.157;
  else
    emRatio := 0.200;
  end;
  Result := emRatio * ASizePoints;
end;

function StandardFontLineHeight(AFont: TStandardFont; ASizePoints: Double): Double;
begin
  Result := 1.2 * ASizePoints;
end;

function StringToWinAnsi(const AText: string): AnsiString;
var
  enc: TEncoding;
  bytes: TBytes;
  i: Integer;
begin
  if AText = '' then
    Exit('');
  enc := TEncoding.GetEncoding(1252);
  try
    bytes := enc.GetBytes(AText);
    SetLength(Result, Length(bytes));
    for i := 0 to High(bytes) do
      Result[i + 1] := AnsiChar(bytes[i]);
  finally
    enc.Free;
  end;
end;

end.
