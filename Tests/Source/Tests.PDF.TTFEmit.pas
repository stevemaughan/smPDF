unit Tests.PDF.TTFEmit;

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework;

type
  TTTFEmitTests = class(TTestCase)
  protected
    function SavedAsString(const ABuild: TProc<TObject>): string;
    function CountOccurrences(const ASubstring, AString: string): Integer;
  published
    procedure Test_Arial_emitsTrueTypeSubtype;
    procedure Test_Arial_emitsFontDescriptor;
    procedure Test_Arial_emitsFontFile2WithLength1;
    procedure Test_Arial_baseFontMatchesPostScriptName;
    procedure Test_Arial_widthsArrayHas224Entries;
    procedure Test_Arial_fontDescriptorIncludesFontBBox;
    procedure Test_Arial_fontDescriptorHasNonsymbolicFlag;
    procedure Test_UnknownFontName_fallsBackToHelvetica;
    procedure Test_MixedTTFAndStandard14_eachGetOwnFontDict;
    procedure Test_ArialBold_resolvesToBoldFile;
  end;

implementation

uses
  StrUtils, IOUtils, Vcl.Graphics, smPDF;

function TTTFEmitTests.SavedAsString(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
  fn: string;
  bytes: TBytes;
  i: Integer;
begin
  fn := TPath.Combine(TPath.GetTempPath, 'smPDF-tests-ttfemit.pdf');
  if TFile.Exists(fn) then TFile.Delete(fn);

  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
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

function TTTFEmitTests.CountOccurrences(const ASubstring, AString: string): Integer;
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

procedure TTTFEmitTests.Test_Arial_emitsTrueTypeSubtype;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/Subtype /TrueType', s);
end;

procedure TTTFEmitTests.Test_Arial_emitsFontDescriptor;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/Type /FontDescriptor', s);
  AssertContains('/FontName /', s);
  AssertContains('/Ascent ',     s);
  AssertContains('/Descent ',    s);
  AssertContains('/CapHeight ',  s);
  AssertContains('/StemV ',      s);
end;

procedure TTTFEmitTests.Test_Arial_emitsFontFile2WithLength1;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/FontFile2',    s);
  AssertContains('/Length1',      s);
end;

procedure TTTFEmitTests.Test_Arial_baseFontMatchesPostScriptName;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  // Arial's PostScript name is 'ArialMT' on most systems. Accept either form.
  AssertTrue(
    (Pos('/BaseFont /ArialMT', s) > 0) or
    (Pos('/BaseFont /Arial',   s) > 0),
    '/BaseFont should be the embedded font''s PostScript name');
end;

procedure TTTFEmitTests.Test_Arial_widthsArrayHas224Entries;
var
  s: string;
  startIdx, endIdx, count, i: Integer;
  widthsBlock: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  startIdx := Pos('/Widths [', s);
  AssertTrue(startIdx > 0, '/Widths array present');
  endIdx := PosEx(']', s, startIdx);
  AssertTrue(endIdx > startIdx, 'closing ] for /Widths');

  widthsBlock := Copy(s, startIdx + Length('/Widths ['), endIdx - (startIdx + Length('/Widths [')));
  // Count whitespace-separated numbers
  count := 0;
  i := 1;
  while i <= Length(widthsBlock) do
  begin
    while (i <= Length(widthsBlock)) and (widthsBlock[i] = ' ') do Inc(i);
    if (i <= Length(widthsBlock)) and CharInSet(widthsBlock[i], ['0'..'9', '-']) then
    begin
      Inc(count);
      while (i <= Length(widthsBlock)) and CharInSet(widthsBlock[i], ['0'..'9', '-']) do Inc(i);
    end
    else
      Inc(i);
  end;
  AssertEquals(255 - 32 + 1, count, 'expected 224 width entries (FirstChar=32 .. LastChar=255)');
end;

procedure TTTFEmitTests.Test_Arial_fontDescriptorIncludesFontBBox;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/FontBBox [', s);
end;

procedure TTTFEmitTests.Test_Arial_fontDescriptorHasNonsymbolicFlag;
var
  s: string;
  startIdx: Integer;
  flagStr: string;
  flagsValue: Integer;
  i: Integer;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  startIdx := Pos('/Flags ', s);
  AssertTrue(startIdx > 0);
  flagStr := '';
  i := startIdx + Length('/Flags ');
  while (i <= Length(s)) and CharInSet(s[i], ['0'..'9']) do
  begin
    flagStr := flagStr + s[i];
    Inc(i);
  end;
  flagsValue := StrToIntDef(flagStr, 0);
  AssertTrue((flagsValue and 32) <> 0,
    Format('Nonsymbolic flag (32) should be set in flags=%d', [flagsValue]));
end;

procedure TTTFEmitTests.Test_UnknownFontName_fallsBackToHelvetica;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'NoSuchFontExistsAnywhere99';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/BaseFont /Helvetica', s);
  AssertFalse(Pos('/Subtype /TrueType', s) > 0,
    'unknown font should not produce a TrueType embed');
end;

procedure TTTFEmitTests.Test_MixedTTFAndStandard14_eachGetOwnFontDict;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Helvetica'; TsmPDF(o).DrawText('Std14', 100, 100);
    TsmPDF(o).Font.Name := 'Arial';     TsmPDF(o).DrawText('TTF',   100, 130);
  end);
  AssertContains('/Subtype /Type1',    s);
  AssertContains('/Subtype /TrueType', s);
end;

procedure TTTFEmitTests.Test_ArialBold_resolvesToBoldFile;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).Font.Bold := True;
    TsmPDF(o).DrawText('Bold!', 100, 100);
  end);
  // Arial Bold PostScript name is typically 'Arial-BoldMT'. Accept variations.
  AssertTrue(
    (Pos('Arial-BoldMT', s) > 0) or
    (Pos('Arial-Bold',   s) > 0) or
    (Pos('ArialBold',    s) > 0),
    '/BaseFont should reference the bold variant');
end;

initialization
  TTestRegistry.RegisterTestCase(TTTFEmitTests);

end.
