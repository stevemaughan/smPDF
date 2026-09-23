unit smPDF.Buffer;

// Growable byte buffer for content streams. Operators are appended directly,
// without building intermediate strings, because a map page can carry millions
// of path operators.

interface

uses
  SysUtils;

type
  TPDFByteBuffer = class
  strict private
    fData: TBytes;
    fSize: NativeInt;
    procedure Grow(AMinCapacity: NativeInt);
  public
    constructor Create(AInitialCapacity: NativeInt = 4096);

    procedure Clear;
    // Shrink back to ASize bytes (ASize <= Size); capacity is kept.
    procedure Truncate(ASize: NativeInt);
    procedure AppendByte(AByte: Byte); inline;
    procedure AppendBytes(AData: Pointer; ACount: NativeInt);
    // Characters must be < 256 (content streams are 8-bit).
    procedure AppendAscii(const AStr: string);
    procedure AppendAnsi(const AStr: AnsiString);
    procedure AppendNumber(AValue: Double);
    procedure AppendInt(AValue: Int64);
    // "x y <op>\n" — the hot path for m and l.
    procedure AppendPointOp(AX, AY: Double; AOp: AnsiChar; ADecimals: Integer = 3);
    procedure AppendCoord(AValue: Double; ADecimals: Integer);
    procedure AppendBuffer(ASource: TPDFByteBuffer);

    function Memory: Pointer;
    function ToBytes: TBytes;

    property Size: NativeInt read fSize;
  end;

implementation

uses
  smPDF.Geometry;

constructor TPDFByteBuffer.Create(AInitialCapacity: NativeInt);
begin
  inherited Create;
  if AInitialCapacity < 16 then AInitialCapacity := 16;
  SetLength(fData, AInitialCapacity);
  fSize := 0;
end;

procedure TPDFByteBuffer.Clear;
begin
  fSize := 0;
end;

procedure TPDFByteBuffer.Truncate(ASize: NativeInt);
begin
  if (ASize >= 0) and (ASize < fSize) then
    fSize := ASize;
end;

procedure TPDFByteBuffer.Grow(AMinCapacity: NativeInt);
var
  newCap: NativeInt;
begin
  newCap := Length(fData);
  if newCap < 16 then newCap := 16;
  while newCap < AMinCapacity do
    newCap := newCap * 2;
  SetLength(fData, newCap);
end;

procedure TPDFByteBuffer.AppendByte(AByte: Byte);
begin
  if fSize >= Length(fData) then Grow(fSize + 1);
  fData[fSize] := AByte;
  Inc(fSize);
end;

procedure TPDFByteBuffer.AppendBytes(AData: Pointer; ACount: NativeInt);
begin
  if ACount <= 0 then Exit;
  if fSize + ACount > Length(fData) then Grow(fSize + ACount);
  Move(AData^, fData[fSize], ACount);
  Inc(fSize, ACount);
end;

procedure TPDFByteBuffer.AppendAscii(const AStr: string);
var
  i, n: Integer;
  p: PByte;
begin
  n := Length(AStr);
  if n = 0 then Exit;
  if fSize + n > Length(fData) then Grow(fSize + n);
  p := @fData[fSize];
  for i := 1 to n do
  begin
    p^ := Byte(Ord(AStr[i]) and $FF);
    Inc(p);
  end;
  Inc(fSize, n);
end;

procedure TPDFByteBuffer.AppendAnsi(const AStr: AnsiString);
begin
  if AStr <> '' then
    AppendBytes(@AStr[1], Length(AStr));
end;

procedure TPDFByteBuffer.AppendNumber(AValue: Double);
var
  chars: TPdfNumberChars;
  n: Integer;
begin
  n := PdfNumberToChars(AValue, chars);
  if fSize + n > Length(fData) then Grow(fSize + n);
  Move(chars[0], fData[fSize], n);
  Inc(fSize, n);
end;

procedure TPDFByteBuffer.AppendInt(AValue: Int64);
var
  digits: array[0..20] of Byte;
  n, i: Integer;
  neg: Boolean;
  v: UInt64;
begin
  neg := AValue < 0;
  if neg then v := UInt64(-AValue) else v := UInt64(AValue);
  n := 0;
  repeat
    digits[n] := Ord('0') + v mod 10;
    v := v div 10;
    Inc(n);
  until v = 0;
  if fSize + n + 1 > Length(fData) then Grow(fSize + n + 1);
  if neg then
  begin
    fData[fSize] := Ord('-');
    Inc(fSize);
  end;
  for i := n - 1 downto 0 do
  begin
    fData[fSize] := digits[i];
    Inc(fSize);
  end;
end;

procedure TPDFByteBuffer.AppendCoord(AValue: Double; ADecimals: Integer);
var
  chars: TPdfNumberChars;
  n: Integer;
begin
  n := PdfNumberToCharsPrec(AValue, ADecimals, chars);
  if fSize + n > Length(fData) then Grow(fSize + n);
  Move(chars[0], fData[fSize], n);
  Inc(fSize, n);
end;

procedure TPDFByteBuffer.AppendPointOp(AX, AY: Double; AOp: AnsiChar; ADecimals: Integer);
var
  chars: TPdfNumberChars;
  n: Integer;
begin
  if fSize + 2 * PDF_NUMBER_MAX_CHARS + 4 > Length(fData) then
    Grow(fSize + 2 * PDF_NUMBER_MAX_CHARS + 4);
  n := PdfNumberToCharsPrec(AX, ADecimals, chars);
  Move(chars[0], fData[fSize], n);
  Inc(fSize, n);
  fData[fSize] := Ord(' ');
  Inc(fSize);
  n := PdfNumberToCharsPrec(AY, ADecimals, chars);
  Move(chars[0], fData[fSize], n);
  Inc(fSize, n);
  fData[fSize] := Ord(' ');
  fData[fSize + 1] := Ord(AOp);
  fData[fSize + 2] := 10;
  Inc(fSize, 3);
end;

procedure TPDFByteBuffer.AppendBuffer(ASource: TPDFByteBuffer);
begin
  if (ASource <> nil) and (ASource.Size > 0) then
    AppendBytes(ASource.Memory, ASource.Size);
end;

function TPDFByteBuffer.Memory: Pointer;
begin
  if Length(fData) = 0 then
    Result := nil
  else
    Result := @fData[0];
end;

function TPDFByteBuffer.ToBytes: TBytes;
begin
  Result := Copy(fData, 0, fSize);
end;

end.
