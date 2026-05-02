unit smPDF.Writer;

interface

uses
  SysUtils, Classes;

type
  TPDFObjectId = type Integer;

  TPDFWriter = class
  strict private
    fStream: TBytesStream;
    fNextId: Integer;
    fOffsets: array of Int64;
    fInDictOrArray: Integer;
    fNeedsSeparator: Boolean;

    procedure WriteRawBytes(const ABytes: array of Byte); overload;
    procedure WriteRawBytes(const ABytes: TBytes); overload;
    procedure WriteAscii(const AStr: string);
    procedure WriteHeader;
    procedure EmitSeparatorIfNeeded;
    procedure RegisterOffset(AObjectId: TPDFObjectId);
  public
    constructor Create;
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

    procedure WriteName(const AName: string);
    procedure WriteInt(AValue: Integer);
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

    function Finalize(ARootObjectId: TPDFObjectId): TBytes;
  end;

implementation

uses
  smPDF.Geometry;

const
  LF: Byte = $0A;
  PDF_HEADER: array[0..8] of Byte =
    (Ord('%'), Ord('P'), Ord('D'), Ord('F'), Ord('-'), Ord('1'), Ord('.'), Ord('4'), $0A);
  // High-bit comment marking the file as binary per PDF spec section 7.5.2
  PDF_BINARY_MARKER: array[0..5] of Byte =
    (Ord('%'), $E2, $E3, $CF, $D3, $0A);

constructor TPDFWriter.Create;
begin
  inherited Create;
  fStream := TBytesStream.Create;
  fNextId := 1;
  fInDictOrArray := 0;
  fNeedsSeparator := False;
  WriteHeader;
end;

destructor TPDFWriter.Destroy;
begin
  fStream.Free;
  inherited;
end;

procedure TPDFWriter.WriteRawBytes(const ABytes: array of Byte);
begin
  if Length(ABytes) > 0 then
    fStream.WriteBuffer(ABytes[0], Length(ABytes));
end;

procedure TPDFWriter.WriteRawBytes(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    fStream.WriteBuffer(ABytes[0], Length(ABytes));
end;

procedure TPDFWriter.WriteAscii(const AStr: string);
var
  bytes: TBytes;
  i: Integer;
begin
  if AStr = '' then Exit;
  SetLength(bytes, Length(AStr));
  for i := 1 to Length(AStr) do
    bytes[i - 1] := Byte(Ord(AStr[i]) and $FF);
  WriteRawBytes(bytes);
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
    SetLength(fOffsets, AObjectId);
  fOffsets[AObjectId - 1] := fStream.Position;
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
    SetLength(fOffsets, Result);
  // Offset stays 0 until BeginReservedObject is called. Finalize() asserts on this.
end;

procedure TPDFWriter.BeginReservedObject(AObjectId: TPDFObjectId);
begin
  if (AObjectId < 1) or (AObjectId >= fNextId) then
    raise EAssertionFailed.CreateFmt('Object id %d not reserved', [AObjectId]);
  if fOffsets[AObjectId - 1] <> 0 then
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
  Result := BeginObject;
    BeginDict;
      if Assigned(AExtraDictEntries) then
        AExtraDictEntries(Self);
      WriteName('Length'); WriteInt(Length(AContent));
    EndDict;
    WriteAscii(#10 + 'stream' + #10);
    if Length(AContent) > 0 then
      WriteRawBytes(AContent);
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

procedure TPDFWriter.WriteInt(AValue: Integer);
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
  WriteAscii(Format('%d 0 R', [AObjectId]));
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
  esc: string;
begin
  EmitSeparatorIfNeeded;
  esc := '';
  for i := 1 to Length(AValue) do
    case AValue[i] of
      '(':  esc := esc + '\(';
      ')':  esc := esc + '\)';
      '\':  esc := esc + '\\';
      #10:  esc := esc + '\n';
      #13:  esc := esc + '\r';
      #9:   esc := esc + '\t';
      #8:   esc := esc + '\b';
      #12:  esc := esc + '\f';
    else
      esc := esc + AValue[i];
    end;
  WriteAscii('(' + esc + ')');
  fNeedsSeparator := True;
end;

procedure TPDFWriter.WriteHexString(const ABytes: TBytes);
var
  sb: TStringBuilder;
  b: Byte;
begin
  EmitSeparatorIfNeeded;
  sb := TStringBuilder.Create;
  try
    sb.Append('<');
    for b in ABytes do
      sb.Append(IntToHex(b, 2));
    sb.Append('>');
    WriteAscii(sb.ToString);
  finally
    sb.Free;
  end;
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
  Result := fStream.Position;
end;

function TPDFWriter.ObjectCount: Integer;
begin
  Result := fNextId - 1;
end;

function TPDFWriter.Finalize(ARootObjectId: TPDFObjectId): TBytes;
var
  xrefOffset: Int64;
  i: Integer;
  count: Integer;
begin
  count := ObjectCount;

  // Defensive: every reserved object must have been written. Otherwise the
  // xref entry would point at offset 0 (the file header) and crash the reader.
  for i := 0 to count - 1 do
    if fOffsets[i] = 0 then
      raise EAssertionFailed.CreateFmt(
        'PDF writer: object %d was reserved but never written', [i + 1]);

  xrefOffset := fStream.Position;

  // xref section
  WriteAscii('xref' + #10);
  WriteAscii(Format('0 %d'#10, [count + 1]));
  // Free entry for object 0 — head of free list, generation 65535
  WriteAscii('0000000000 65535 f '#10);
  for i := 0 to count - 1 do
    WriteAscii(Format('%.10d 00000 n '#10, [fOffsets[i]]));

  // trailer
  WriteAscii('trailer' + #10);
  BeginDict;
  WriteName('Size'); WriteInt(count + 1);
  if ARootObjectId > 0 then
  begin
    WriteName('Root'); WriteRef(ARootObjectId);
  end;
  EndDict;
  WriteAscii(#10);

  WriteAscii('startxref' + #10);
  WriteAscii(IntToStr(xrefOffset) + #10);
  WriteAscii('%%EOF' + #10);

  Result := Copy(fStream.Bytes, 0, fStream.Size);
end;

end.
