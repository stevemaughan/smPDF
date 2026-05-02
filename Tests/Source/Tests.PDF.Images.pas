unit Tests.PDF.Images;

interface

uses
  SysUtils, Classes, smPDF.TestFramework;

type
  TImageTests = class(TTestCase)
  protected
    function MakePicture(out APicture: TObject; AWidth, AHeight: Integer;
      AGraphicClass: TPersistentClass): TObject;
  published
    // FlateCompress
    procedure Test_Flate_emptyInput_producesValidStream;
    procedure Test_Flate_helloWorldRoundTrip;
    procedure Test_Flate_largeRedundantInput_compressesWell;

    // JPEG frame parser
    procedure Test_ParseJpeg_emptyBytes_returnsFalse;
    procedure Test_ParseJpeg_garbage_returnsFalse;
    procedure Test_ParseJpeg_minimalValidFrame_parsesDimensions;
    procedure Test_ParseJpeg_realJpegFromTJpeg_parsesDimensions;

    // Bitmap extraction
    procedure Test_ExtractFromBitmap_8x4_returnsRgbBytes;
    procedure Test_ExtractFromBitmap_redPixel_isAtIndex0;

    // PNG extraction
    procedure Test_ExtractFromPng_opaque_isOpaqueKind;
    procedure Test_ExtractFromPng_bodyHas3BytesPerPixel;

    // Picture dispatch
    procedure Test_ExtractImageData_nilGraphic_raises;
  end;

implementation

uses
  System.ZLib, Vcl.Graphics, Vcl.Imaging.JPEG, Vcl.Imaging.PngImage,
  smPDF.Images;

function FlateDecompress(const ABytes: TBytes): TBytes;
var
  inStream: TBytesStream;
  zStream: TZDecompressionStream;
  outStream: TBytesStream;
  buf: array[0..4095] of Byte;
  read: Integer;
begin
  inStream := TBytesStream.Create(ABytes);
  outStream := TBytesStream.Create;
  try
    zStream := TZDecompressionStream.Create(inStream);
    try
      repeat
        read := zStream.Read(buf, SizeOf(buf));
        if read > 0 then outStream.WriteBuffer(buf, read);
      until read = 0;
    finally
      zStream.Free;
    end;
    SetLength(Result, outStream.Size);
    if outStream.Size > 0 then
      Move(outStream.Memory^, Result[0], outStream.Size);
  finally
    outStream.Free;
    inStream.Free;
  end;
end;

function TImageTests.MakePicture(out APicture: TObject; AWidth, AHeight: Integer;
  AGraphicClass: TPersistentClass): TObject;
begin
  Result := nil; APicture := nil;
end;

procedure TImageTests.Test_Flate_emptyInput_producesValidStream;
var
  out_: TBytes;
begin
  out_ := FlateCompress(nil);
  // zlib always emits at least the 2-byte header + 4-byte adler checksum
  AssertTrue(Length(out_) >= 6, 'Flate output for empty input should still be a valid zlib stream');
end;

procedure TImageTests.Test_Flate_helloWorldRoundTrip;
var
  input, compressed, restored: TBytes;
  s: AnsiString;
  i: Integer;
begin
  s := 'Hello, world! Hello, world! Hello, world!';
  SetLength(input, Length(s));
  for i := 1 to Length(s) do
    input[i - 1] := Byte(s[i]);
  compressed := FlateCompress(input);
  restored := FlateDecompress(compressed);
  AssertBytesEqual(input, restored, 'Flate round-trip preserves bytes');
end;

procedure TImageTests.Test_Flate_largeRedundantInput_compressesWell;
var
  input, compressed: TBytes;
  i: Integer;
begin
  SetLength(input, 10000);
  for i := 0 to 9999 do
    input[i] := 65;  // all the same byte — should compress to ~30 bytes
  compressed := FlateCompress(input);
  AssertTrue(Length(compressed) < 100,
    Format('10000 identical bytes should compress under 100 bytes; got %d', [Length(compressed)]));
end;

procedure TImageTests.Test_ParseJpeg_emptyBytes_returnsFalse;
var
  w, h, bpc, n: Integer;
begin
  AssertFalse(ParseJpegFrame(nil, w, h, bpc, n));
end;

procedure TImageTests.Test_ParseJpeg_garbage_returnsFalse;
var
  bytes: TBytes;
  w, h, bpc, n: Integer;
begin
  bytes := TBytes.Create($DE, $AD, $BE, $EF, $00, $00);
  AssertFalse(ParseJpegFrame(bytes, w, h, bpc, n));
end;

procedure TImageTests.Test_ParseJpeg_minimalValidFrame_parsesDimensions;
var
  bytes: TBytes;
  w, h, bpc, n: Integer;
begin
  // SOI then SOF0 segment encoding 16x32 image, 8-bit, 3 components
  bytes := TBytes.Create(
    $FF, $D8,                       // SOI
    $FF, $C0,                       // SOF0 marker
    $00, $11,                       // segment length = 17 (incl these 2 bytes)
    $08,                            // bits per component = 8
    $00, $20,                       // height = 32
    $00, $10,                       // width = 16
    $03,                            // 3 components
    $01, $22, $00,                  // component 1
    $02, $11, $01,                  // component 2
    $03, $11, $01                   // component 3
  );
  AssertTrue(ParseJpegFrame(bytes, w, h, bpc, n));
  AssertEquals(16, w);
  AssertEquals(32, h);
  AssertEquals(8,  bpc);
  AssertEquals(3,  n);
end;

procedure TImageTests.Test_ParseJpeg_realJpegFromTJpeg_parsesDimensions;
var
  bmp: TBitmap;
  jpg: TJPEGImage;
  ms: TMemoryStream;
  bytes: TBytes;
  w, h, bpc, n: Integer;
begin
  bmp := TBitmap.Create;
  jpg := TJPEGImage.Create;
  ms  := TMemoryStream.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(40, 25);
    bmp.Canvas.Brush.Color := clRed;
    bmp.Canvas.FillRect(Rect(0, 0, 40, 25));
    jpg.Assign(bmp);
    jpg.SaveToStream(ms);
    SetLength(bytes, ms.Size);
    if ms.Size > 0 then
      Move(ms.Memory^, bytes[0], ms.Size);

    AssertTrue(ParseJpegFrame(bytes, w, h, bpc, n),
      'parser should recognise a JPEG built by TJPEGImage');
    AssertEquals(40, w);
    AssertEquals(25, h);
    AssertEquals(8,  bpc);
    AssertEquals(3,  n);
  finally
    ms.Free;
    jpg.Free;
    bmp.Free;
  end;
end;

procedure TImageTests.Test_ExtractFromBitmap_8x4_returnsRgbBytes;
var
  pic: TPicture;
  bmp: TBitmap;
  data: TPDFImageData;
begin
  pic := TPicture.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(8, 4);
    bmp.Canvas.Brush.Color := clBlue;
    bmp.Canvas.FillRect(Rect(0, 0, 8, 4));
    pic.Assign(bmp);

    data := ExtractImageData(pic);
    AssertEquals(Ord(ikRgbOpaque), Ord(data.Kind));
    AssertEquals(8,  data.Width);
    AssertEquals(4,  data.Height);
    AssertEquals(8,  data.BitsPerComp);
    AssertEquals(3,  data.NumComps);
    AssertEquals(8 * 4 * 3, Length(data.Body));
  finally
    bmp.Free;
    pic.Free;
  end;
end;

procedure TImageTests.Test_ExtractFromBitmap_redPixel_isAtIndex0;
var
  pic: TPicture;
  bmp: TBitmap;
  data: TPDFImageData;
begin
  pic := TPicture.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(2, 1);
    bmp.Canvas.Pixels[0, 0] := $000000FF;  // bright red (BGR=00 00 FF -> R=255,G=0,B=0)
    bmp.Canvas.Pixels[1, 0] := $0000FF00;  // bright green
    pic.Assign(bmp);

    data := ExtractImageData(pic);
    // Pixel (0,0) RGB = 255, 0, 0
    AssertEquals(255, data.Body[0]);
    AssertEquals(0,   data.Body[1]);
    AssertEquals(0,   data.Body[2]);
    // Pixel (1,0) RGB = 0, 255, 0
    AssertEquals(0,   data.Body[3]);
    AssertEquals(255, data.Body[4]);
    AssertEquals(0,   data.Body[5]);
  finally
    bmp.Free;
    pic.Free;
  end;
end;

procedure TImageTests.Test_ExtractFromPng_opaque_isOpaqueKind;
var
  pic: TPicture;
  bmp: TBitmap;
  png: TPngImage;
  data: TPDFImageData;
begin
  pic := TPicture.Create;
  bmp := TBitmap.Create;
  png := TPngImage.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(4, 4);
    bmp.Canvas.Brush.Color := clYellow;
    bmp.Canvas.FillRect(Rect(0, 0, 4, 4));
    png.Assign(bmp);
    pic.Assign(png);

    data := ExtractImageData(pic);
    AssertEquals(Ord(ikRgbOpaque), Ord(data.Kind));
    AssertEquals(4, data.Width);
    AssertEquals(4, data.Height);
    AssertEquals(0, Length(data.AlphaMask));
  finally
    png.Free;
    bmp.Free;
    pic.Free;
  end;
end;

procedure TImageTests.Test_ExtractFromPng_bodyHas3BytesPerPixel;
var
  pic: TPicture;
  bmp: TBitmap;
  png: TPngImage;
  data: TPDFImageData;
begin
  pic := TPicture.Create;
  bmp := TBitmap.Create;
  png := TPngImage.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(10, 5);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(Rect(0, 0, 10, 5));
    png.Assign(bmp);
    pic.Assign(png);

    data := ExtractImageData(pic);
    AssertEquals(10 * 5 * 3, Length(data.Body));
  finally
    png.Free;
    bmp.Free;
    pic.Free;
  end;
end;

procedure TImageTests.Test_ExtractImageData_nilGraphic_raises;
var
  pic: TPicture;
  raised: Boolean;
begin
  pic := TPicture.Create;
  try
    raised := False;
    try
      ExtractImageData(pic);
    except
      on E: EPDFImageError do raised := True;
    end;
    AssertTrue(raised, 'TPicture without graphic should raise EPDFImageError');
  finally
    pic.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TImageTests);

end.
