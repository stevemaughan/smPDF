unit smPDF.Geometry;

interface

uses
  smPDF.Types;

const
  POINTS_PER_INCH = 72.0;

  // Longest text PdfNumberToChars can produce: sign, 19 digits, dot, 3 decimals.
  PDF_NUMBER_MAX_CHARS = 24;

type
  TPdfNumberChars = array[0..PDF_NUMBER_MAX_CHARS - 1] of AnsiChar;

function PixelsToPoints(APixels: Double; ADpi: Integer): Double; inline;
function PointsToPixels(APoints: Double; ADpi: Integer): Integer; inline;

function FlipYPixels(AYPixels, APageHeightPixels: Integer): Integer; inline;

function PixelToPdfPoint(AXPixels, AYPixels: Integer; ADpi: Integer;
  APageHeightPixels: Integer): TPDFPointF;

// A PDF number rounded to three decimals, trailing zeros and dot removed,
// never "-0". Written straight into ABuf; returns the character count.
function PdfNumberToChars(AValue: Double; var ABuf: TPdfNumberChars): Integer;

function FormatPdfNumber(AValue: Double): string;

implementation

uses
  SysUtils, Math;

var
  GPdfFormatSettings: TFormatSettings;

function PixelsToPoints(APixels: Double; ADpi: Integer): Double;
begin
  Result := APixels * POINTS_PER_INCH / ADpi;
end;

function PointsToPixels(APoints: Double; ADpi: Integer): Integer;
begin
  Result := Round(APoints * ADpi / POINTS_PER_INCH);
end;

function FlipYPixels(AYPixels, APageHeightPixels: Integer): Integer;
begin
  Result := APageHeightPixels - AYPixels;
end;

function PixelToPdfPoint(AXPixels, AYPixels: Integer; ADpi: Integer;
  APageHeightPixels: Integer): TPDFPointF;
begin
  Result.X := PixelsToPoints(AXPixels, ADpi);
  Result.Y := PixelsToPoints(FlipYPixels(AYPixels, APageHeightPixels), ADpi);
end;

// The general-purpose formatter, kept for values too large for the Int64
// fast path. The fast path must stay byte-identical to it.
function FormatPdfNumberSlow(AValue: Double): string;
var
  rounded: Double;
begin
  if SameValue(AValue, 0.0, 1e-9) then
    Exit('0');

  rounded := RoundTo(AValue, -3);
  if Frac(rounded) = 0 then
    Result := IntToStr(Trunc(rounded))
  else
  begin
    Result := Format('%.3f', [rounded], GPdfFormatSettings);
    while (Length(Result) > 0) and (Result[Length(Result)] = '0') do
      SetLength(Result, Length(Result) - 1);
    if (Length(Result) > 0) and (Result[Length(Result)] = '.') then
      SetLength(Result, Length(Result) - 1);
  end;
end;

const
  FAST_PATH_LIMIT = 1e9;

function PdfNumberToChars(AValue: Double; var ABuf: TPdfNumberChars): Integer;
var
  q, intPart: Int64;
  frac, i, n: Integer;
  digits: array[0..19] of AnsiChar;
  slow: string;
begin
  if not ((AValue > -FAST_PATH_LIMIT) and (AValue < FAST_PATH_LIMIT)) then
  begin
    slow := FormatPdfNumberSlow(AValue);
    Result := Length(slow);
    if Result > PDF_NUMBER_MAX_CHARS then Result := PDF_NUMBER_MAX_CHARS;
    for i := 0 to Result - 1 do
      ABuf[i] := AnsiChar(slow[i + 1]);
    Exit;
  end;

  // Same arithmetic as RoundTo(AValue, -3): multiply, then round half to
  // even. On Win32 the product stays in x87 extended precision, as in RoundTo.
  q := Round(AValue * 1000.0);
  if q = 0 then
  begin
    ABuf[0] := '0';
    Exit(1);
  end;

  Result := 0;
  if q < 0 then
  begin
    ABuf[0] := '-';
    Result := 1;
    q := -q;
  end;

  intPart := q div 1000;
  frac    := Integer(q mod 1000);

  n := 0;
  repeat
    digits[n] := AnsiChar(Ord('0') + intPart mod 10);
    intPart := intPart div 10;
    Inc(n);
  until intPart = 0;
  for i := n - 1 downto 0 do
  begin
    ABuf[Result] := digits[i];
    Inc(Result);
  end;

  if frac <> 0 then
  begin
    ABuf[Result] := '.';
    ABuf[Result + 1] := AnsiChar(Ord('0') + frac div 100);
    ABuf[Result + 2] := AnsiChar(Ord('0') + (frac div 10) mod 10);
    ABuf[Result + 3] := AnsiChar(Ord('0') + frac mod 10);
    Inc(Result, 4);
    while ABuf[Result - 1] = '0' do
      Dec(Result);
  end;
end;

function FormatPdfNumber(AValue: Double): string;
var
  buf: TPdfNumberChars;
  n, i: Integer;
begin
  n := PdfNumberToChars(AValue, buf);
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i + 1] := Char(buf[i]);
end;

initialization
  GPdfFormatSettings := TFormatSettings.Invariant;

end.
