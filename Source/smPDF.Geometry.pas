unit smPDF.Geometry;

interface

uses
  smPDF.Types;

const
  POINTS_PER_INCH = 72.0;

function PixelsToPoints(APixels: Double; ADpi: Integer): Double; inline;
function PointsToPixels(APoints: Double; ADpi: Integer): Integer; inline;

function FlipYPixels(AYPixels, APageHeightPixels: Integer): Integer; inline;

function PixelToPdfPoint(AXPixels, AYPixels: Integer; ADpi: Integer;
  APageHeightPixels: Integer): TPDFPointF;

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
  Result := (APageHeightPixels - 1) - AYPixels;
end;

function PixelToPdfPoint(AXPixels, AYPixels: Integer; ADpi: Integer;
  APageHeightPixels: Integer): TPDFPointF;
begin
  Result.X := PixelsToPoints(AXPixels, ADpi);
  Result.Y := PixelsToPoints(FlipYPixels(AYPixels, APageHeightPixels), ADpi);
end;

function FormatPdfNumber(AValue: Double): string;
var
  rounded: Double;
begin
  // Snap tiny magnitudes to 0 to avoid "-0" output for values like -0.0
  if SameValue(AValue, 0.0, 1e-9) then
    Exit('0');

  rounded := RoundTo(AValue, -3);
  if Frac(rounded) = 0 then
    Result := IntToStr(Trunc(rounded))
  else
  begin
    Result := Format('%.3f', [rounded], GPdfFormatSettings);
    // strip trailing zeros and a trailing dot
    while (Length(Result) > 0) and (Result[Length(Result)] = '0') do
      SetLength(Result, Length(Result) - 1);
    if (Length(Result) > 0) and (Result[Length(Result)] = '.') then
      SetLength(Result, Length(Result) - 1);
  end;
end;

initialization
  GPdfFormatSettings := TFormatSettings.Invariant;

end.
