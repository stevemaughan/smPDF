unit Tests.PDF.Writer;

interface

uses
  SysUtils, smPDF.TestFramework;

type
  TWriterTests = class(TTestCase)
  protected
    function BytesToLatin1(const ABytes: array of Byte): string; overload;
    function BytesToLatin1(const ABytes: TBytes): string; overload;
  published
    procedure Test_NewWriter_emitsPdfHeader;
    procedure Test_NewWriter_emitsBinaryComment;

    procedure Test_BeginObject_returnsSequentialIdsStartingAtOne;
    procedure Test_BeginObject_writesObjMarker;
    procedure Test_EndObject_writesEndobjMarker;

    procedure Test_WriteName_simple;
    procedure Test_WriteInt_emitsDigits;
    procedure Test_WriteNumber_usesPdfFormatting;
    procedure Test_WriteRef_emitsObjNumberR;
    procedure Test_WriteBool;
    procedure Test_WriteNull;

    procedure Test_Dict_emitsAngleBrackets;
    procedure Test_Dict_keyValueSpacing;
    procedure Test_Array_emitsSquareBrackets;

    procedure Test_LiteralString_simpleAscii;
    procedure Test_LiteralString_escapesParens;
    procedure Test_LiteralString_escapesBackslash;
    procedure Test_HexString_emitsAngleBrackets;

    procedure Test_Finalize_includesXrefSection;
    procedure Test_Finalize_includesTrailer;
    procedure Test_Finalize_endsWithStartxrefAndEOF;
    procedure Test_Finalize_xrefHasCorrectOffsetForObject1;

    procedure Test_Finalize_minimalCatalogIsWellFormed;

    procedure Test_ReserveObjectId_assignsSequentialIdsAfterBeginObject;
    procedure Test_ReserveObjectId_canBeFilledLaterByBeginReservedObject;
    procedure Test_ReserveObjectId_supportsForwardReferenceFromEarlierObject;
    procedure Test_Finalize_unfilledReservedObjectRaises;

    procedure Test_EmitStreamObject_writesLengthAndStreamMarkers;
    procedure Test_EmitStreamObject_emptyContent;
    procedure Test_EmitStreamObject_returnsObjectId;
    procedure Test_EmitStreamObject_contentBytesAreVerbatim;
  end;

implementation

uses
  Classes, smPDF.Writer;

{ TWriterTests }

function TWriterTests.BytesToLatin1(const ABytes: array of Byte): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

function TWriterTests.BytesToLatin1(const ABytes: TBytes): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

procedure TWriterTests.Test_NewWriter_emitsPdfHeader;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    s := BytesToLatin1(w.Finalize(0));
    AssertStartsWith('%PDF-1.4'#10, s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_NewWriter_emitsBinaryComment;
var
  w: TPDFWriter;
  s: string;
begin
  // PDF spec recommends a comment line with 4 high-bit bytes immediately
  // after the header so transports treat the file as binary.
  w := TPDFWriter.Create;
  try
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('%'#$E2#$E3#$CF#$D3#10, s, 'binary marker comment present');
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_BeginObject_returnsSequentialIdsStartingAtOne;
var
  w: TPDFWriter;
  id1, id2, id3: Integer;
begin
  w := TPDFWriter.Create;
  try
    id1 := w.BeginObject;  w.BeginDict; w.EndDict; w.EndObject;
    id2 := w.BeginObject;  w.BeginDict; w.EndDict; w.EndObject;
    id3 := w.BeginObject;  w.BeginDict; w.EndDict; w.EndObject;
    AssertEquals(1, id1);
    AssertEquals(2, id2);
    AssertEquals(3, id3);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_BeginObject_writesObjMarker;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict; w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('1 0 obj', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_EndObject_writesEndobjMarker;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict; w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('endobj', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteName_simple;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict;
    w.WriteName('Type');
    w.WriteName('Catalog');
    w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Type', s);
    AssertContains('/Catalog', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteInt_emitsDigits;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginArray;
    w.WriteInt(42);
    w.WriteInt(-7);
    w.EndArray;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('42', s);
    AssertContains('-7', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteNumber_usesPdfFormatting;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginArray;
    w.WriteNumber(1.5);
    w.WriteNumber(72.0);
    w.EndArray;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('1.5', s);
    AssertContains('72', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteRef_emitsObjNumberR;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict;
    w.WriteName('Pages');
    w.WriteRef(7);
    w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('7 0 R', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteBool;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginArray;
    w.WriteBool(True);
    w.WriteBool(False);
    w.EndArray;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('true', s);
    AssertContains('false', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_WriteNull;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.WriteNull;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('null', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Dict_emitsAngleBrackets;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict;
    w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('<<', s);
    AssertContains('>>', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Dict_keyValueSpacing;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginDict;
    w.WriteName('Type');
    w.WriteName('Catalog');
    w.WriteName('Pages');
    w.WriteRef(2);
    w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Type /Catalog', s);
    AssertContains('/Pages 2 0 R', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Array_emitsSquareBrackets;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.BeginArray;
    w.WriteInt(0); w.WriteInt(0); w.WriteInt(612); w.WriteInt(792);
    w.EndArray;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('[0 0 612 792]', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_LiteralString_simpleAscii;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.WriteLiteralString('Hello PDF');
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('(Hello PDF)', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_LiteralString_escapesParens;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.WriteLiteralString('a(b)c');
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('(a\(b\)c)', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_LiteralString_escapesBackslash;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.WriteLiteralString('back\slash');
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('(back\\slash)', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_HexString_emitsAngleBrackets;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject;
    w.WriteHexString(TBytes.Create($DE, $AD, $BE, $EF));
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('<DEADBEEF>', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_includesXrefSection;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    s := BytesToLatin1(w.Finalize(1));
    AssertContains('xref', s);
    AssertContains('0000000000 65535 f', s, 'free entry for object 0');
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_includesTrailer;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    s := BytesToLatin1(w.Finalize(1));
    AssertContains('trailer', s);
    AssertContains('/Size 2', s);
    AssertContains('/Root 1 0 R', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_endsWithStartxrefAndEOF;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    s := BytesToLatin1(w.Finalize(1));
    AssertContains('startxref', s);
    AssertContains('%%EOF', s);
    // EOF must be the very last token (followed only by an optional newline)
    AssertTrue(Pos('%%EOF', s) > Pos('startxref', s),
      'startxref appears before %%EOF');
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_xrefHasCorrectOffsetForObject1;
var
  w: TPDFWriter;
  bytes: TBytes;
  s: string;
  obj1Pos: Integer;
  expected: string;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    bytes := w.Finalize(1);
    s := BytesToLatin1(bytes);
    obj1Pos := Pos('1 0 obj', s) - 1;  // 0-based offset
    expected := Format('%.10d 00000 n', [obj1Pos]);
    AssertContains(expected, s,
      Format('xref entry for object 1 should reference offset %d', [obj1Pos]));
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_minimalCatalogIsWellFormed;
var
  w: TPDFWriter;
  s: string;
  catalogId, pagesId, pageId: Integer;
begin
  // Build a minimal but legal 1-page document (no content stream).
  w := TPDFWriter.Create;
  try
    catalogId := w.BeginObject;
      w.BeginDict;
        w.WriteName('Type');  w.WriteName('Catalog');
        w.WriteName('Pages'); w.WriteRef(2);  // forward ref
      w.EndDict;
    w.EndObject;

    pagesId := w.BeginObject;
      w.BeginDict;
        w.WriteName('Type');  w.WriteName('Pages');
        w.WriteName('Kids');  w.BeginArray; w.WriteRef(3); w.EndArray;
        w.WriteName('Count'); w.WriteInt(1);
      w.EndDict;
    w.EndObject;

    pageId := w.BeginObject;
      w.BeginDict;
        w.WriteName('Type');     w.WriteName('Page');
        w.WriteName('Parent');   w.WriteRef(2);
        w.WriteName('MediaBox'); w.BeginArray;
          w.WriteInt(0); w.WriteInt(0); w.WriteInt(612); w.WriteInt(792);
        w.EndArray;
        w.WriteName('Resources'); w.BeginDict; w.EndDict;
      w.EndDict;
    w.EndObject;

    AssertEquals(1, catalogId);
    AssertEquals(2, pagesId);
    AssertEquals(3, pageId);

    s := BytesToLatin1(w.Finalize(catalogId));
    AssertStartsWith('%PDF-1.4', s);
    AssertContains('/Type /Catalog', s);
    AssertContains('/Type /Pages', s);
    AssertContains('/Type /Page', s);
    AssertContains('/Kids [3 0 R]', s);
    AssertContains('/MediaBox [0 0 612 792]', s);
    AssertContains('/Size 4', s);
    AssertContains('/Root 1 0 R', s);
    AssertContains('%%EOF', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_ReserveObjectId_assignsSequentialIdsAfterBeginObject;
var
  w: TPDFWriter;
  id1, reserved, id3: Integer;
begin
  w := TPDFWriter.Create;
  try
    id1      := w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    reserved := w.ReserveObjectId;
    id3      := w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    AssertEquals(1, id1);
    AssertEquals(2, reserved);
    AssertEquals(3, id3);

    // Now fill in the reserved object so Finalize doesn't refuse.
    w.BeginReservedObject(reserved);
      w.BeginDict; w.EndDict;
    w.EndObject;

    BytesToLatin1(w.Finalize(0));
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_ReserveObjectId_canBeFilledLaterByBeginReservedObject;
var
  w: TPDFWriter;
  reservedId: Integer;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    reservedId := w.ReserveObjectId;        // id 1
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;  // id 2
    w.BeginReservedObject(reservedId);
      w.BeginDict;
        w.WriteName('FilledLater'); w.WriteBool(True);
      w.EndDict;
    w.EndObject;
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('1 0 obj', s);
    AssertContains('/FilledLater true', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_ReserveObjectId_supportsForwardReferenceFromEarlierObject;
var
  w: TPDFWriter;
  catalogId, pagesRootId: Integer;
  s: string;
begin
  // Mirrors how TsmPDF.Save now wires the catalog -> reserved pages-root forward ref.
  w := TPDFWriter.Create;
  try
    catalogId    := w.BeginObject;
      w.BeginDict;
        w.WriteName('Type');  w.WriteName('Catalog');
        w.WriteName('Pages'); w.WriteRef(2);  // forward ref to pages root
      w.EndDict;
    w.EndObject;

    pagesRootId  := w.ReserveObjectId;       // id 2

    // Some unrelated object that bumps the id counter
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;  // id 3

    w.BeginReservedObject(pagesRootId);
      w.BeginDict;
        w.WriteName('Type'); w.WriteName('Pages');
      w.EndDict;
    w.EndObject;

    AssertEquals(1, catalogId);
    AssertEquals(2, pagesRootId);
    s := BytesToLatin1(w.Finalize(catalogId));
    AssertContains('/Pages 2 0 R', s);
    AssertContains('/Type /Pages', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_Finalize_unfilledReservedObjectRaises;
var
  w: TPDFWriter;
  raised: Boolean;
begin
  w := TPDFWriter.Create;
  try
    w.BeginObject; w.BeginDict; w.EndDict; w.EndObject;
    w.ReserveObjectId;  // never filled in
    raised := False;
    try
      w.Finalize(1);
    except
      on E: EAssertionFailed do raised := True;
    end;
    AssertTrue(raised, 'Finalize should refuse to emit an xref for an unfilled reservation');
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_EmitStreamObject_writesLengthAndStreamMarkers;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.EmitStreamObject(TBytes.Create(Ord('h'), Ord('i')));
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Length 2', s);
    AssertContains('stream',    s);
    AssertContains('endstream', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_EmitStreamObject_emptyContent;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.EmitStreamObject(nil);
    s := BytesToLatin1(w.Finalize(0));
    AssertContains('/Length 0', s);
    AssertContains('stream',    s);
    AssertContains('endstream', s);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_EmitStreamObject_returnsObjectId;
var
  w: TPDFWriter;
  id: Integer;
begin
  w := TPDFWriter.Create;
  try
    id := w.EmitStreamObject(TBytes.Create(Ord('x')));
    AssertEquals(1, id);
  finally
    w.Free;
  end;
end;

procedure TWriterTests.Test_EmitStreamObject_contentBytesAreVerbatim;
var
  w: TPDFWriter;
  s: string;
begin
  w := TPDFWriter.Create;
  try
    w.EmitStreamObject(TBytes.Create(Ord('A'), Ord('B'), Ord('C'), Ord('D')));
    s := BytesToLatin1(w.Finalize(0));
    // The four content bytes should appear inside the stream segment in order.
    AssertContains('stream'#10'ABCD'#10'endstream', s);
  finally
    w.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TWriterTests);

end.
