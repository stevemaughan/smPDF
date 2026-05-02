unit Tests.PDF.Geometry;

interface

uses
  smPDF.TestFramework;

type
  TGeometryTests = class(TTestCase)
  published
    procedure Test_PixelsToPoints_72dpi_isIdentity;
    procedure Test_PixelsToPoints_300dpi_oneInch;
    procedure Test_PixelsToPoints_96dpi_arbitrary;

    procedure Test_PointsToPixels_72dpi_isIdentity;
    procedure Test_PointsToPixels_300dpi_oneInch;
    procedure Test_PointsToPixels_roundTrip;

    procedure Test_FlipY_topRow_becomesBottomRow;
    procedure Test_FlipY_bottomRow_becomesTopRow;
    procedure Test_FlipY_middle_unchanged;

    procedure Test_PixelToPdfPoint_topLeft_becomesTopOfPage;
    procedure Test_PixelToPdfPoint_bottomLeft_becomesOrigin;
    procedure Test_PixelToPdfPoint_300dpi_LetterPage;

    procedure Test_FormatPdfNumber_integer_noDecimals;
    procedure Test_FormatPdfNumber_fractional_threeDecimals;
    procedure Test_FormatPdfNumber_negativeZero_normalised;
    procedure Test_FormatPdfNumber_culture_independent;
  end;

implementation

uses
  SysUtils, smPDF.Types, smPDF.Geometry;

procedure TGeometryTests.Test_PixelsToPoints_72dpi_isIdentity;
begin
  AssertEquals(100.0, PixelsToPoints(100, 72), 1e-9, '72dpi: 1 pixel == 1 point');
end;

procedure TGeometryTests.Test_PixelsToPoints_300dpi_oneInch;
begin
  // 300 px at 300 DPI = 1 inch = 72 points
  AssertEquals(72.0, PixelsToPoints(300, 300), 1e-9);
end;

procedure TGeometryTests.Test_PixelsToPoints_96dpi_arbitrary;
begin
  // 192 px at 96 DPI = 2 inches = 144 points
  AssertEquals(144.0, PixelsToPoints(192, 96), 1e-9);
end;

procedure TGeometryTests.Test_PointsToPixels_72dpi_isIdentity;
begin
  AssertEquals(100, PointsToPixels(100, 72));
end;

procedure TGeometryTests.Test_PointsToPixels_300dpi_oneInch;
begin
  // 72 points = 1 inch = 300 pixels at 300 DPI
  AssertEquals(300, PointsToPixels(72, 300));
end;

procedure TGeometryTests.Test_PointsToPixels_roundTrip;
var
  pts: Double;
begin
  pts := PixelsToPoints(450, 300);
  AssertEquals(450, PointsToPixels(pts, 300), 'round trip 450 px @ 300 dpi');
end;

procedure TGeometryTests.Test_FlipY_topRow_becomesBottomRow;
begin
  AssertEquals(2999, FlipYPixels(0, 3000), 'y=0 in 3000-tall page becomes 2999');
end;

procedure TGeometryTests.Test_FlipY_bottomRow_becomesTopRow;
begin
  AssertEquals(0, FlipYPixels(2999, 3000));
end;

procedure TGeometryTests.Test_FlipY_middle_unchanged;
begin
  // for an odd-sized page the middle row is symmetric about (h-1)/2
  // 100-tall page: y=49.5 is the centre line; y=49 flips to y=50
  AssertEquals(50, FlipYPixels(49, 100));
end;

procedure TGeometryTests.Test_PixelToPdfPoint_topLeft_becomesTopOfPage;
var
  p: TPDFPointF;
begin
  // Letter page at 72 DPI: 612x792 pixels = 612x792 points.
  // Top-left in user coords (0,0) becomes (0, 791) in PDF (just below top edge).
  p := PixelToPdfPoint(0, 0, 72, 792);
  AssertEquals(0.0, p.X, 1e-9);
  AssertEquals(791.0, p.Y, 1e-9, 'top row in 792-pixel page maps to y=791 in PDF coords');
end;

procedure TGeometryTests.Test_PixelToPdfPoint_bottomLeft_becomesOrigin;
var
  p: TPDFPointF;
begin
  // Bottom-left pixel (0, 791) maps to PDF origin (0, 0)
  p := PixelToPdfPoint(0, 791, 72, 792);
  AssertEquals(0.0, p.X, 1e-9);
  AssertEquals(0.0, p.Y, 1e-9);
end;

procedure TGeometryTests.Test_PixelToPdfPoint_300dpi_LetterPage;
var
  p: TPDFPointF;
begin
  // Letter @ 300 DPI: 2550x3300 pixels.
  // Pixel (300, 300) = (1in, 1in from top-left) = (72pt, height-72pt) in PDF
  // height in points = 3300 * 72/300 = 792
  // expected PDF y = 792 - 72 = 720, but using FlipYPixels then convert:
  // flippedY = 3299 - 300 = 2999, in points: 2999 * 72/300 = 719.76
  p := PixelToPdfPoint(300, 300, 300, 3300);
  AssertEquals(72.0, p.X, 1e-9);
  AssertEquals(719.76, p.Y, 1e-3);
end;

procedure TGeometryTests.Test_FormatPdfNumber_integer_noDecimals;
begin
  AssertEquals('612', FormatPdfNumber(612.0));
  AssertEquals('-100', FormatPdfNumber(-100.0));
  AssertEquals('0', FormatPdfNumber(0.0));
end;

procedure TGeometryTests.Test_FormatPdfNumber_fractional_threeDecimals;
begin
  // PDF spec recommends max 5 decimal places; we use 3 for compactness
  AssertEquals('1.5', FormatPdfNumber(1.5));
  AssertEquals('72.123', FormatPdfNumber(72.1234567));
  AssertEquals('0.001', FormatPdfNumber(0.001));
end;

procedure TGeometryTests.Test_FormatPdfNumber_negativeZero_normalised;
begin
  // -0.0 should render as "0", not "-0"
  AssertEquals('0', FormatPdfNumber(-0.0));
end;

procedure TGeometryTests.Test_FormatPdfNumber_culture_independent;
var
  oldDecimal: Char;
  saved: TFormatSettings;
begin
  // PDF requires '.' as decimal separator regardless of locale
  saved := FormatSettings;
  oldDecimal := FormatSettings.DecimalSeparator;
  try
    FormatSettings.DecimalSeparator := ',';
    AssertEquals('1.5', FormatPdfNumber(1.5));
  finally
    FormatSettings := saved;
    FormatSettings.DecimalSeparator := oldDecimal;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TGeometryTests);

end.
