unit Tests.PDF.Compression;

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TCompressionTests = class(TTestCase)
  protected
    function Build(ACompress: Boolean; AWithArial: Boolean = False): TBytes;
    function FindContentStream(const AStreams: TArray<TPdfTestStream>; out AStream: TPdfTestStream): Boolean;
    function FindFontFile(const AStreams: TArray<TPdfTestStream>; out AStream: TPdfTestStream): Boolean;
  published
    procedure Test_CompressStreams_defaultsToTrue;
    procedure Test_CompressTrue_contentHasFlateFilter;
    procedure Test_CompressFalse_contentHasNoFilter;
    procedure Test_Compressed_inflatesToExactRawContent;
    procedure Test_Compressed_isSmallerForRepetitiveContent;
    procedure Test_FontFile2_compressed_hasFilterAndUncompressedLength1;
    procedure Test_FontFile2_uncompressed_hasNoFilter;
  end;

implementation

uses
  Vcl.Graphics, smPDF;

function TCompressionTests.Build(ACompress: Boolean; AWithArial: Boolean): TBytes;
var
  pdf: TsmPDF;
  i: Integer;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := ACompress;
    pdf.NewPage(psA4, poPortrait, 72);
    for i := 0 to 199 do
      pdf.DrawLine(10, 10 + i, 500, 10 + i);
    if AWithArial then
    begin
      pdf.Font.Name := 'Arial';
      pdf.DrawText('Hello', 100, 100);
    end;
    Result := pdf.ToBytes;
  finally
    pdf.Free;
  end;
end;

function TCompressionTests.FindContentStream(const AStreams: TArray<TPdfTestStream>;
  out AStream: TPdfTestStream): Boolean;
var
  st: TPdfTestStream;
begin
  for st in AStreams do
    if (Pos('/Length1', st.Dict) = 0) and (Pos('/Subtype', st.Dict) = 0)
      and (Pos(' l'#10, PdfBytesToString(st.Data)) > 0) then
    begin
      AStream := st;
      Exit(True);
    end;
  Result := False;
end;

function TCompressionTests.FindFontFile(const AStreams: TArray<TPdfTestStream>;
  out AStream: TPdfTestStream): Boolean;
var
  st: TPdfTestStream;
begin
  for st in AStreams do
    if Pos('/Length1', st.Dict) > 0 then
    begin
      AStream := st;
      Exit(True);
    end;
  Result := False;
end;

procedure TCompressionTests.Test_CompressStreams_defaultsToTrue;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    AssertTrue(pdf.CompressStreams, 'CompressStreams should default to True');
  finally
    pdf.Free;
  end;
end;

procedure TCompressionTests.Test_CompressTrue_contentHasFlateFilter;
var
  st: TPdfTestStream;
begin
  AssertTrue(FindContentStream(ExtractPdfStreams(Build(True)), st), 'content stream not found');
  AssertContains('/Filter /FlateDecode', st.Dict);
end;

procedure TCompressionTests.Test_CompressFalse_contentHasNoFilter;
var
  st: TPdfTestStream;
begin
  AssertTrue(FindContentStream(ExtractPdfStreams(Build(False)), st), 'content stream not found');
  AssertEquals(0, Pos('/Filter', st.Dict), 'uncompressed content must not carry /Filter');
end;

procedure TCompressionTests.Test_Compressed_inflatesToExactRawContent;
var
  packed_, plain: TPdfTestStream;
begin
  AssertTrue(FindContentStream(ExtractPdfStreams(Build(True)), packed_), 'compressed content not found');
  AssertTrue(FindContentStream(ExtractPdfStreams(Build(False)), plain), 'plain content not found');
  AssertBytesEqual(plain.Raw, packed_.Data, 'inflated content must equal the raw content');
end;

procedure TCompressionTests.Test_Compressed_isSmallerForRepetitiveContent;
begin
  AssertTrue(Length(Build(True)) < Length(Build(False)) div 2,
    'compressed PDF should be well under half the uncompressed size');
end;

procedure TCompressionTests.Test_FontFile2_compressed_hasFilterAndUncompressedLength1;
var
  st: TPdfTestStream;
begin
  if not FindFontFile(ExtractPdfStreams(Build(True, True)), st) then
    Skip('Arial is not installed; no /FontFile2 to inspect');
  AssertContains('/Filter /FlateDecode', st.Dict);
  AssertEquals(Length(st.Data), DictInt(st.Dict, 'Length1'), '/Length1 must be the uncompressed length');
  AssertTrue(Length(st.Raw) < Length(st.Data), 'compressed font should be smaller than the raw font');
end;

procedure TCompressionTests.Test_FontFile2_uncompressed_hasNoFilter;
var
  st: TPdfTestStream;
begin
  if not FindFontFile(ExtractPdfStreams(Build(False, True)), st) then
    Skip('Arial is not installed; no /FontFile2 to inspect');
  AssertEquals(0, Pos('/Filter', st.Dict), 'uncompressed font must not carry /Filter');
  AssertEquals(Length(st.Raw), DictInt(st.Dict, 'Length1'));
end;

initialization
  TTestRegistry.RegisterTestCase(TCompressionTests);

end.
