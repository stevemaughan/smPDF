unit Tests.PDF.PictureEmit;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework;

type
  TPictureEmitTests = class(TTestCase)
  protected
    function SavedAsString(const ABuild: TProc<TObject>): string;
    function CountOccurrences(const ASubstring, AString: string): Integer;
  published
    procedure Test_DrawPicture_bitmap_emitsImageXObject;
    procedure Test_DrawPicture_bitmap_emitsFlateDecode;
    procedure Test_DrawPicture_bitmap_includesWidthAndHeightInDict;
    procedure Test_DrawPicture_bitmap_emitsCmAndDoOperators;
    procedure Test_DrawPicture_bitmap_emitsXObjectResourceEntry;

    procedure Test_DrawPicture_pngOpaque_emitsImageXObject;
    procedure Test_DrawPicture_pngWithAlpha_emitsSMaskRef;
    procedure Test_DrawPicture_pngWithAlpha_emitsTwoImageObjects;

    procedure Test_DrawPicture_jpeg_emitsDCTDecodeFilter;

    procedure Test_DrawPicture_samePictureTwice_dedupsToSingleXObject;
    procedure Test_DrawPicture_beforeNewPage_doesNotRaise;  // current behaviour: raises EPDFError
  end;

implementation

uses
  StrUtils, Math, IOUtils, Winapi.Windows, Vcl.Graphics, Vcl.Imaging.JPEG,
  Vcl.Imaging.PngImage, smPDF;

function MakeRGBBitmap(AWidth, AHeight: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

function MakeRGBAPng(AWidth, AHeight: Integer): TPngImage;
var
  x, y: Integer;
  alphaRow: PByteArray;
begin
  Result := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, AWidth, AHeight);
  for y := 0 to AHeight - 1 do
  begin
    alphaRow := Result.AlphaScanline[y];
    for x := 0 to AWidth - 1 do
    begin
      Result.Pixels[x, y] := RGB(255, 0, 0);
      // Diagonal alpha gradient: opaque at top-left, transparent at bottom-right
      alphaRow^[x] := 255 - Byte(((x + y) * 255) div Max(AWidth + AHeight - 2, 1));
    end;
  end;
end;

function TPictureEmitTests.SavedAsString(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  fn: string;
  bytes: TBytes;
  i: Integer;
begin
  fn := TPath.Combine(TPath.GetTempPath, 'smPDF-tests-pictureemit.pdf');
  if TFile.Exists(fn) then TFile.Delete(fn);

  pdf := TsmPDF.Create;
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

function TPictureEmitTests.CountOccurrences(const ASubstring, AString: string): Integer;
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

// ---- Bitmap path ----

procedure TPictureEmitTests.Test_DrawPicture_bitmap_emitsImageXObject;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(32, 16, clRed);
    try
      pic.Assign(bmp);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/Type /XObject', s);
  AssertContains('/Subtype /Image', s);
end;

procedure TPictureEmitTests.Test_DrawPicture_bitmap_emitsFlateDecode;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(8, 8, clBlue);
    try
      pic.Assign(bmp);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/Filter /FlateDecode', s);
end;

procedure TPictureEmitTests.Test_DrawPicture_bitmap_includesWidthAndHeightInDict;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(32, 16, clBlack);
    try
      pic.Assign(bmp);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/Width 32',  s);
  AssertContains('/Height 16', s);
  AssertContains('/ColorSpace /DeviceRGB', s);
  AssertContains('/BitsPerComponent 8',    s);
end;

procedure TPictureEmitTests.Test_DrawPicture_bitmap_emitsCmAndDoOperators;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(10, 10, clBlack);
    try
      pic.Assign(bmp);
      TsmPDF(o).DrawPicture(pic, 100, 200);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains(' cm'#10, s);
  AssertContains('/Im1 Do'#10, s);
end;

procedure TPictureEmitTests.Test_DrawPicture_bitmap_emitsXObjectResourceEntry;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(10, 10, clBlack);
    try
      pic.Assign(bmp);
      TsmPDF(o).DrawPicture(pic, 100, 200);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/XObject', s);
  AssertContains('/Im1 ',    s);
end;

// ---- PNG path ----

procedure TPictureEmitTests.Test_DrawPicture_pngOpaque_emitsImageXObject;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
    png: TPngImage;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(16, 16, clYellow);
    png := TPngImage.Create;
    try
      png.Assign(bmp);
      pic.Assign(png);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      png.Free;
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/Subtype /Image', s);
  AssertContains('/ColorSpace /DeviceRGB', s);
end;

procedure TPictureEmitTests.Test_DrawPicture_pngWithAlpha_emitsSMaskRef;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    png: TPngImage;
  begin
    pic := TPicture.Create;
    png := MakeRGBAPng(8, 8);
    try
      pic.Assign(png);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      png.Free;
      pic.Free;
    end;
  end);
  AssertContains('/SMask ', s);
end;

procedure TPictureEmitTests.Test_DrawPicture_pngWithAlpha_emitsTwoImageObjects;
var
  s: string;
  occurrencesOfSubtypeImage: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    png: TPngImage;
  begin
    pic := TPicture.Create;
    png := MakeRGBAPng(8, 8);
    try
      pic.Assign(png);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      png.Free;
      pic.Free;
    end;
  end);
  occurrencesOfSubtypeImage := CountOccurrences('/Subtype /Image', s);
  AssertEquals(2, occurrencesOfSubtypeImage,
    'PNG with alpha should produce two Image XObjects (main + SMask)');
end;

// ---- JPEG path ----

procedure TPictureEmitTests.Test_DrawPicture_jpeg_emitsDCTDecodeFilter;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
    jpg: TJPEGImage;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(40, 25, clGreen);
    jpg := TJPEGImage.Create;
    try
      jpg.Assign(bmp);
      pic.Assign(jpg);
      TsmPDF(o).DrawPicture(pic, 100, 100);
    finally
      jpg.Free;
      bmp.Free;
      pic.Free;
    end;
  end);
  AssertContains('/Filter /DCTDecode', s);
end;

procedure TPictureEmitTests.Test_DrawPicture_samePictureTwice_dedupsToSingleXObject;
var
  s: string;
  occurrencesOfSubtypeImage: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  var
    pic: TPicture;
    bmp: TBitmap;
  begin
    pic := TPicture.Create;
    bmp := MakeRGBBitmap(16, 16, clBlue);
    try
      pic.Assign(bmp);
      // Same TPicture instance drawn twice -> one XObject in the PDF
      TsmPDF(o).DrawPicture(pic, 100, 100);
      TsmPDF(o).DrawPicture(pic, 200, 100);
    finally
      bmp.Free;
      pic.Free;
    end;
  end);
  occurrencesOfSubtypeImage := CountOccurrences('/Subtype /Image', s);
  AssertEquals(1, occurrencesOfSubtypeImage, 'duplicate TPicture instance must be deduplicated');
end;

procedure TPictureEmitTests.Test_DrawPicture_beforeNewPage_doesNotRaise;
var
  pdf: TsmPDF;
  pic: TPicture;
  bmp: TBitmap;
  raised: Boolean;
begin
  // Existing invariant: any Draw* before NewPage raises EPDFError.
  pdf := TsmPDF.Create;
  pic := TPicture.Create;
  bmp := MakeRGBBitmap(8, 8, clBlack);
  try
    pic.Assign(bmp);
    raised := False;
    try
      pdf.DrawPicture(pic, 0, 0);
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'DrawPicture before NewPage must raise EPDFError');
  finally
    bmp.Free;
    pic.Free;
    pdf.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TPictureEmitTests);

end.
