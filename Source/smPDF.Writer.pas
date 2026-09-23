unit smPDF.Writer;

interface

uses
  SysUtils, Classes;

type
  TPDFObjectId = type Integer;

  TPDFWriter = class
  strict private
    fStream: TStream;
    fOwnsStream: Boolean;
    fPosition: Int64;      // bytes written so far; xref offsets are relative to the %PDF header
    fNextId: Integer;
    fOffsets: array of Int64;
    fWritten: array of Boolean;
    fInDictOrArray: Integer;
    fNeedsSeparator: Boolean;

    procedure WriteRawBytes(const ABytes: array of Byte); overload;
    procedure WriteRawBytes(AData: Pointer; ACount: NativeInt); overload;
    procedure WriteAscii(const AStr: string);
    procedure WriteHeader;
    procedure EmitSeparatorIfNeeded;
    procedure RegisterOffset(AObjectId: TPDFObjectId);
  public
    // Writes into an internal memory stream; Finalize returns the bytes.
    constructor Create; overload;
    // Writes straight into AStream at its current position; the caller owns it.
    constructor Create(AStream: TStream); overload;
    destructor Destroy; override;

    function BeginObject: TPDFObjectId;
    procedure EndObject;

    // Reserve an object ID without emitting it. Use BeginReservedObject(id)
    // later to actually write the object body. Lets you emit forward references
    // (e.g., a dictionary that references an object whose contents you'll write later).
    function ReserveObjectId: TPDFObjectId;
    procedure BeginReservedObject(AObjectId: TPDFObjectId);

    // Emit a complete stream object: << /Length N >> stream <bytes> endstream.
    // Returns the object id. Compression is the caller's responsibility.
    function EmitStreamObject(const AContent: TBytes): TPDFObjectId; overload;
    // Variant that lets the caller write additional dict entries (e.g. /Length1
    // for embedded font files) before /Length is appended.
    function EmitStreamObject(const AContent: TBytes;
      const AExtraDictEntries: TProc<TPDFWriter>): TPDFObjectId; overload;
    function EmitStreamObject(AData: Pointer; ACount: NativeInt;
      const AExtraDictEntries: TProc<TPDFWriter>): TPDFObjectId; overload;

    procedure WriteName(const AName: string);
    procedure WriteInt(AValue: Int64);
    procedure WriteNumber(AValue: Double);
    procedure WriteRef(AObjectId: TPDFObjectId);
    procedure WriteBool(AValue: Boolean);
    procedure WriteNull;
    procedure WriteLiteralString(const AValue: string);
    procedure WriteHexString(const ABytes: TBytes);

    procedure BeginDict;
    procedure EndDict;

    procedure BeginArray;
    procedure EndArray;

    function CurrentOffset: Int64;
    function ObjectCount: Integer;

    // Writes the xref table and trailer. AInfoObjectId = 0 omits /Info.
    procedure Finish(ARootObjectId: TPDFObjectId; AInfoObjectId: TPDFObjectId = 0);
    // Finish, then return everything written. Only for the parameterless constructor.
    function Finalize(ARootObjectId: TPDFObjectId): TBytes;
  end;

implementation

uses
  smPDF.Geometry;

const
  PDF_HEADER: array[0..8] of Byte =
    (Ord('%'), Ord('P'), Ord('D'), Ord('F'), Ord('-'), Ord('1'), Ord('.'), Ord('4'), $0A);
  // High-bit comment marking the file as binary per PDF spec section 7.5.2
  PDF_BINARY_MARKER: array[0..5] of Byte =
    (Ord('%'), $E2, $E3, $CF, $D3, $0A);

constructor TPDFWriter.Create;
begin
  Create(TBytesStream.Create);
  fOwnsStream := True;
end;

constructor TPDFWriter.Create(AStream: TStream);
begin
  inherited Create;
  fStream := AStream;
  fOwnsStream := False;
  fPosition := 0;
  fNextId := 1;
  fInDictOrArray := 0;
  fNeedsSeparator := False;
  WriteHeader;
end;

destructor TPDFWriter.Destroy;
begin
  if fOwnsStream then
    fStream.Free;
  inherited;
end;

procedure TPDFWriter.WriteRawBytes(const ABytes: array of Byte);
begin
  if Length(ABytes) > 0 then
    WriteRawBytes(@ABytes[0], Length(ABytes));
end;

procedure TPDFWriter.WriteRawBytes(AData: Pointer; ACount: NativeInt);
begin
  if ACount <= 0 then Exit;
  fStream.WriteBuffer(AData^, ACount);
  Inc(fPosition, ACount);
end;

procedure TPDFWriter.WriteAscii(const AStr: string);
var
  buf: array[0..255] of Byte;
  i, n, start: Integer;
begin
  start := 1;
  while start <= Length(AStr) do
  begin
    n := Length(AStr) - start + 1;
    if n > Length(buf) then n := Length(buf);
    for i := 0 to n - 1 do
      buf[i] := Byte(Ord(AStr[start + i]) and $FF);
    WriteRawBytes(@buf[0], n);
    Inc(start, n);
  end;
end;

procedure TPDFWriter.WriteHeader;
begin
  WriteRawBytes(PDF_HEADER);
  WriteRawBytes(PDF_BINARY_MARKER);
end;

procedure TPDFWriter.EmitSeparatorIfNeeded;
begin
  if fNeedsSeparator then
  begin
    WriteRawBytes([Ord(' ')]);
    fNeedsSeparator := False;
  end;
end;

procedure TPDFWriter.RegisterOffset(AObjectId: TPDFObjectId);
begin
  if Length(fOffsets) < AObjectId then
  begin
    SetLength(fOffsets, AObjectId);
    SetLength(fWritten, AObjectId);
  end;
  fOffsets[AObjectId - 1] := fPosition;
  fWritten[AObjectId - 1] := True;
end;

function TPDFWriter.BeginObject: TPDFObjectId;
begin
  Result := fNextId;
  Inc(fNextId);
  RegisterOffset(Result);
  WriteAscii(IntToStr(Result) + ' 0 obj' + #10);
  fNeedsSeparator := False;
end;

function TPDFWriter.ReserveObjectId: TPDFObjectId;
begin
  Result := fNextId;
  Inc(fNextId);
  if Length(fOffsets) < Result then
  begin
    SetLength(fOffsets, Result);
    SetLength(fWritten, Result);
  end;
  // Stays unwritten until BeginReservedObject is called. Finish() asserts on this.
end;

procedure TPDFWriter.BeginReservedObject(AObjectId: TPDFObjectId);
begin
  if (AObjectId < 1) or (AObjectId >= fNextId) then
    raise EAssertionFailed.CreateFmt('Object id %d not reserved', [AObjectId]);
  if fWritten[AObjectId - 1] then
    raise EAssertionFailed.CreateFmt('Object id %d already written', [AObjectId]);
  RegisterOffset(AObjectId);
  WriteAscii(IntToStr(AObjectId) + ' 0 obj' + #10);
  fNeedsSeparator := False;
end;

function TPDFWriter.EmitStreamObject(const AContent: TBytes): TPDFObjectId;
begin
  Result := EmitStreamObject(AContent, nil);
end;

function TPDFWriter.EmitStreamObject(const AContent: TBytes;
  const AExtraDictEntries: TProc<TPDFWriter>): TPDFObjectId;
begin
  if Length(AContent) = 0 then
    Result := EmitStreamObject(nil, 0, AExtraDictEntries)
  else
    Result := EmitStreamObject(@AContent[0], Length(AContent), AExtraDictEntries);
end;

function TPDFWriter.EmitStreamObject(AData: Pointer; ACount: NativeInt;
  const AExtraDictEntries: TProc<TPDFWriter>): TPDFObjectId;
begin
  Result := BeginObject;
    BeginDict;
      if Assigned(AExtraDictEntries) then
        AExtraDictEntries(Self);
      WriteName('Length'); WriteInt(ACount);
    EndDict;
    WriteAscii(#10 + 'stream' + #10);
    WriteRawBytes(AData, ACount);
    WriteAscii(#10 + 'endstream');
  EndObject;
end;

procedure TPDFWriter.EndObject;
begin
  WriteAscii(#10 + 'endobj' + #10);
  fNeedsSeparator := False;
end;

procedure TPDFWriter.WriteName(const AName: string);
begin
  EmitSeparatorIfNeeded;
  WriteAscii('/' + AName);
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteInt(AValue: Int64);
begin
  EmitSeparatorIfNeeded;
  WriteAscii(IntToStr(AValue));
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteNumber(AValue: Double);
begin
  EmitSeparatorIfNeeded;
  WriteAscii(FormatPdfNumber(AValue));
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteRef(AObjectId: TPDFObjectId);
begin
  EmitSeparatorIfNeeded;
  WriteAscii(IntToStr(AObjectId) + ' 0 R');
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteBool(AValue: Boolean);
begin
  EmitSeparatorIfNeeded;
  if AValue then WriteAscii('true') else WriteAscii('false');
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteNull;
begin
  EmitSeparatorIfNeeded;
  WriteAscii('null');
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteLiteralString(const AValue: string);
var
  i: Integer;
  esc: TStringBuilder;
begin
  EmitSeparatorIfNeeded;
  esc := TStringBuilder.Create(Length(AValue) + 2);
  try
    esc.Append('(');
    for i := 1 to Length(AValue) do
      case AValue[i] of
        '(':  esc.Append('\(');
        ')':  esc.Append('\)');
        '\':  esc.Append('\\');
        #10:  esc.Append('\n');
        #13:  esc.Append('\r');
        #9:   esc.Append('\t');
        #8:   esc.Append('\b');
        #12:  esc.Append('\f');
      else
        esc.Append(AValue[i]);
      end;
    esc.Append(')');
    WriteAscii(esc.ToString);
  finally
    esc.Free;
  end;
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteHexString(const ABytes: TBytes);
const
  HEX: array[0..15] of Char = '0123456789ABCDEF';
var
  s: string;
  i: Integer;
begin
  EmitSeparatorIfNeeded;
  SetLength(s, Length(ABytes) * 2 + 2);
  s[1] := '<';
  for i := 0 to High(ABytes) do
  begin
    s[2 + i * 2]     := HEX[ABytes[i] shr 4];
    s[2 + i * 2 + 1] := HEX[ABytes[i] and $F];
  end;
  s[Length(s)] := '>';
  WriteAscii(s);
  fNeedsSeparator := True;
end;

procedure TPDFWriter.BeginDict;
begin
  EmitSeparatorIfNeeded;
  WriteAscii('<<');
  Inc(fInDictOrArray);
  fNeedsSeparator := True;
end;

procedure TPDFWriter.EndDict;
begin
  WriteAscii('>>');
  Dec(fInDictOrArray);
  fNeedsSeparator := True;
end;

procedure TPDFWriter.BeginArray;
begin
  EmitSeparatorIfNeeded;
  WriteAscii('[');
  Inc(fInDictOrArray);
  fNeedsSeparator := False;  // first element follows '[' with no space
end;

procedure TPDFWriter.EndArray;
begin
  WriteAscii(']');
  Dec(fInDictOrArray);
  fNeedsSeparator := True;
end;

function TPDFWriter.CurrentOffset: Int64;
begin
  Result := fPosition;
end;

function TPDFWriter.ObjectCount: Integer;
begin
  Result := fNextId - 1;
end;

procedure TPDFWriter.Finish(ARootObjectId: TPDFObjectId; AInfoObjectId: TPDFObjectId);
var
  xrefOffset: Int64;
  i: Integer;
  count: Integer;
begin
  count := ObjectCount;

  // Defensive: every reserved object must have been written. Otherwise the
  // xref entry would point at offset 0 (the file header) and crash the reader.
  for i := 0 to count - 1 do
    if not fWritten[i] then
      raise EAssertionFailed.CreateFmt(
        'PDF writer: object %d was reserved but never written', [i + 1]);

  xrefOffset := fPosition;

  WriteAscii('xref' + #10);
  WriteAscii('0 ' + IntToStr(count + 1) + #10);
  // Free entry for object 0 — head of free list, generation 65535
  WriteAscii('0000000000 65535 f '#10);
  for i := 0 to count - 1 do
    WriteAscii(Format('%.10d 00000 n '#10, [fOffsets[i]]));

  WriteAscii('trailer' + #10);
  BeginDict;
  WriteName('Size'); WriteInt(count + 1);
  if ARootObjectId > 0 then
  begin
    WriteName('Root'); WriteRef(ARootObjectId);
  end;
  if AInfoObjectId > 0 then
  begin
    WriteName('Info'); WriteRef(AInfoObjectId);
  end;
  EndDict;
  WriteAscii(#10);

  WriteAscii('startxref' + #10);
  WriteAscii(IntToStr(xrefOffset) + #10);
  WriteAscii('%%EOF' + #10);
end;

function TPDFWriter.Finalize(ARootObjectId: TPDFObjectId): TBytes;
begin
  if not fOwnsStream then
    raise EAssertionFailed.Create('PDF writer: Finalize needs the internal stream; use Finish');
  Finish(ARootObjectId);
  Result := Copy(TBytesStream(fStream).Bytes, 0, fStream.Size);
end;

end.
