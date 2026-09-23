unit smPDF.Images;

interface

uses
  SysUtils, Classes, Vcl.Graphics;

type
  EPDFImageError = class(Exception);

  TPDFImageKind = (ikJpeg, ikRgbOpaque, ikRgbWithAlpha);

  TPDFImageData = record
    Kind:        TPDFImageKind;
    Width:       Integer;
    Height:      Integer;
    BitsPerComp: Integer;
    NumComps:    Integer;        // 1=gray, 3=RGB, 4=CMYK (only RGB/Gray emitted in Phase 5)
    Body:        TBytes;         // ikJpeg: original JPEG; ikRgb*: raw RGB triples (NOT compressed)
    AlphaMask:   TBytes;         // ikRgbWithAlpha: one byte per pixel, row-major
  end;

// Inspect a TPicture and extract image data ready for PDF embedding.
function ExtractImageData(APicture: TPicture): TPDFImageData;

// Compress raw bytes with zlib's FlateDecode. Returned slice is exactly the
// compressed data (no extra padding).
function FlateCompress(const ABytes: TBytes): TBytes; overload;
function FlateCompress(AData: Pointer; ACount: NativeInt): TBytes; overload;

// Find a JPEG SOFx (start-of-frame) marker and return width/height/comps.
// Used by ExtractImageData but exposed for testability.
function ParseJpegFrame(const ABytes: TBytes; out AWidth, AHeight, ABitsPerComp,
  ANumComps: Integer): Boolean;

implementation

uses
  System.ZLib, Vcl.Imaging.JPEG, Vcl.Imaging.PngImage;

const
  // zlib level 4 is the first with lazy matching: on map content it runs about
  // four times faster than the default level 6 for roughly 10% more bytes.
  FLATE_LEVEL = 4;

function FlateCompress(const ABytes: TBytes): TBytes;
begin
  if Length(ABytes) = 0 then
    Result := FlateCompress(nil, 0)
  else
    Result := FlateCompress(@ABytes[0], Length(ABytes));
end;

function FlateCompress(AData: Pointer; ACount: NativeInt): TBytes;
var
  strm: z_stream;
  rc: Integer;
  used: NativeInt;
begin
  // Deflate straight into a growing buffer: no intermediate stream, and the
  // buffer starts well below the input size because content compresses ~4:1.
  SetLength(Result, 4096 + ACount div 4);
  FillChar(strm, SizeOf(strm), 0);
  if deflateInit(strm, FLATE_LEVEL) <> Z_OK then
    raise EPDFImageError.Create('zlib deflateInit failed');
  try
    strm.next_in  := AData;
    strm.avail_in := ACount;
    used := 0;
    repeat
      if used = Length(Result) then
        SetLength(Result, Length(Result) * 2);
      strm.next_out  := @Result[used];
      strm.avail_out := Length(Result) - used;
      rc := deflate(strm, Z_FINISH);
      used := Length(Result) - NativeInt(strm.avail_out);
      if (rc <> Z_OK) and (rc <> Z_BUF_ERROR) and (rc <> Z_STREAM_END) then
        raise EPDFImageError.CreateFmt('zlib deflate failed (%d)', [rc]);
    until rc = Z_STREAM_END;
  finally
    deflateEnd(strm);
  end;
  SetLength(Result, used);
end;

function ParseJpegFrame(const ABytes: TBytes; out AWidth, AHeight, ABitsPerComp,
  ANumComps: Integer): Boolean;
var
  i, segLen: Integer;
  marker: Byte;
begin
  Result := False;
  AWidth := 0; AHeight := 0; ABitsPerComp := 0; ANumComps := 0;

  // JPEG must begin with SOI (FF D8)
  if (Length(ABytes) < 4) or (ABytes[0] <> $FF) or (ABytes[1] <> $D8) then Exit;

  i := 2;
  while i < Length(ABytes) - 8 do
  begin
    if ABytes[i] <> $FF then begin Inc(i); Continue; end;
    // Skip fill bytes (FF FF ...)
    while (i < Length(ABytes)) and (ABytes[i] = $FF) do Inc(i);
    if i >= Length(ABytes) then Exit;
    marker := ABytes[i];
    Inc(i);

    case marker of
      $D8, $D9, $00:                                  // SOI/EOI/literal-zero — no length
        Continue;
      $C0, $C1, $C2, $C3,
      $C5, $C6, $C7,
      $C9, $CA, $CB,
      $CD, $CE, $CF:                                   // SOF0..15 (excluding C4=DHT, C8=JPG, CC=DAC)
        begin
          // segment-length skipped (2 bytes), then precision/H/W/comps
          if i + 8 > Length(ABytes) then Exit;
          // segLen at i, i+1
          segLen        := (Integer(ABytes[i]) shl 8) or ABytes[i + 1];
          ABitsPerComp  := ABytes[i + 2];
          AHeight       := (Integer(ABytes[i + 3]) shl 8) or ABytes[i + 4];
          AWidth        := (Integer(ABytes[i + 5]) shl 8) or ABytes[i + 6];
          ANumComps     := ABytes[i + 7];
          Result        := (AWidth > 0) and (AHeight > 0);
          // Suppress "segLen never used" — leaves the assignment as documentation
          if segLen = 0 then;
          Exit;
        end;
    else
      // Generic segment: 2-byte length follows
      if i + 1 >= Length(ABytes) then Exit;
      segLen := (Integer(ABytes[i]) shl 8) or ABytes[i + 1];
      Inc(i, segLen);
    end;
  end;
end;

function ExtractFromJPEG(AJpeg: TJPEGImage): TPDFImageData;
var
  ms: TMemoryStream;
  parsed: Boolean;
begin
  ms := TMemoryStream.Create;
  try
    AJpeg.SaveToStream(ms);
    SetLength(Result.Body, ms.Size);
    if ms.Size > 0 then
      Move(ms.Memory^, Result.Body[0], ms.Size);
  finally
    ms.Free;
  end;

  parsed := ParseJpegFrame(Result.Body,
    Result.Width, Result.Height, Result.BitsPerComp, Result.NumComps);
  if not parsed then
  begin
    // Fall back to TJPEGImage's reported dimensions
    Result.Width       := AJpeg.Width;
    Result.Height      := AJpeg.Height;
    Result.BitsPerComp := 8;
    if AJpeg.Grayscale then Result.NumComps := 1 else Result.NumComps := 3;
  end;

  // Phase 5 emits DeviceRGB or DeviceGray. CMYK JPEGs would need /DeviceCMYK
  // and inverted decode array — out of scope.
  if Result.NumComps = 4 then
    raise EPDFImageError.Create('CMYK JPEGs are not supported in Phase 5');

  Result.Kind := ikJpeg;
end;

procedure ExtractRGBAndAlpha(APng: TPngImage; out ARgb, AAlpha: TBytes;
  out AHasAlpha: Boolean);
var
  x, y: Integer;
  c: TColor;
  alphaRow: PByteArray;
  i: Integer;
  hasAlphaChannel: Boolean;
begin
  AHasAlpha := False;
  hasAlphaChannel := APng.TransparencyMode in [ptmPartial];

  SetLength(ARgb, APng.Width * APng.Height * 3);
  if hasAlphaChannel then
    SetLength(AAlpha, APng.Width * APng.Height)
  else
    SetLength(AAlpha, 0);

  i := 0;
  for y := 0 to APng.Height - 1 do
  begin
    if hasAlphaChannel then
      alphaRow := APng.AlphaScanline[y]
    else
      alphaRow := nil;

    for x := 0 to APng.Width - 1 do
    begin
      c := APng.Pixels[x, y];
      // TColor on Windows is $00BBGGRR
      ARgb[i * 3 + 0] := Byte( c        and $FF);  // R
      ARgb[i * 3 + 1] := Byte((c shr 8) and $FF);  // G
      ARgb[i * 3 + 2] := Byte((c shr 16) and $FF); // B
      if alphaRow <> nil then
      begin
        AAlpha[i] := alphaRow^[x];
        if alphaRow^[x] <> 255 then
          AHasAlpha := True;
      end;
      Inc(i);
    end;
  end;

  if not AHasAlpha then
    SetLength(AAlpha, 0);
end;

function ExtractFromPNG(APng: TPngImage): TPDFImageData;
var
  rgb, alpha: TBytes;
  hasAlpha: Boolean;
begin
  ExtractRGBAndAlpha(APng, rgb, alpha, hasAlpha);

  Result.Width       := APng.Width;
  Result.Height      := APng.Height;
  Result.BitsPerComp := 8;
  Result.NumComps    := 3;
  Result.Body        := rgb;
  if hasAlpha then
  begin
    Result.Kind      := ikRgbWithAlpha;
    Result.AlphaMask := alpha;
  end
  else
  begin
    Result.Kind      := ikRgbOpaque;
    Result.AlphaMask := nil;
  end;
end;

function ExtractFromBitmap(ABmp: TBitmap): TPDFImageData;
var
  y, x: Integer;
  row: PByte;
  outIdx: Integer;
  rgb: TBytes;
begin
  ABmp.PixelFormat := pf24bit;
  SetLength(rgb, ABmp.Width * ABmp.Height * 3);
  outIdx := 0;
  for y := 0 to ABmp.Height - 1 do
  begin
    row := PByte(ABmp.ScanLine[y]);
    for x := 0 to ABmp.Width - 1 do
    begin
      // pf24bit memory layout is BGR
      rgb[outIdx + 0] := PByte(row + x * 3 + 2)^;  // R
      rgb[outIdx + 1] := PByte(row + x * 3 + 1)^;  // G
      rgb[outIdx + 2] := PByte(row + x * 3 + 0)^;  // B
      Inc(outIdx, 3);
    end;
  end;

  Result.Kind        := ikRgbOpaque;
  Result.Width       := ABmp.Width;
  Result.Height      := ABmp.Height;
  Result.BitsPerComp := 8;
  Result.NumComps    := 3;
  Result.Body        := rgb;
  Result.AlphaMask   := nil;
end;

function ExtractImageData(APicture: TPicture): TPDFImageData;
var
  graphic: TGraphic;
  bmp: TBitmap;
begin
  if (APicture = nil) or (APicture.Graphic = nil) then
    raise EPDFImageError.Create('DrawPicture: TPicture has no graphic');

  graphic := APicture.Graphic;

  if graphic is TJPEGImage then
    Exit(ExtractFromJPEG(TJPEGImage(graphic)));
  if graphic is TPngImage then
    Exit(ExtractFromPNG(TPngImage(graphic)));
  if graphic is TBitmap then
    Exit(ExtractFromBitmap(TBitmap(graphic)));

  // Fallback: convert any other graphic kind to a TBitmap and extract from there.
  bmp := TBitmap.Create;
  try
    bmp.Assign(graphic);
    Result := ExtractFromBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

end.
