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
    procedure Test_Arial_emitsType0OverCIDFontType2;
    procedure Test_Arial_emitsFontDescriptor;
    procedure Test_Arial_emitsFontFile2WithLength1;
    procedure Test_Arial_baseFontMatchesPostScriptName;
    procedure Test_Arial_WArrayCoversOnlyUsedGlyphs;
    procedure Test_Arial_fontDescriptorIncludesFontBBox;
    procedure Test_Arial_fontDescriptorHasSymbolicFlag;
    procedure Test_UnknownFontName_fallsBackToHelvetica;
    procedure Test_MixedTTFAndStandard14_eachGetOwnFontDict;
    procedure Test_ArialBold_resolvesToBoldFile;
  end;

implementation

uses
  StrUtils, IOUtils, RegularExpressions, Vcl.Graphics, smPDF;

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

procedure TTTFEmitTests.Test_Arial_emitsType0OverCIDFontType2;
var s: string;
begin
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/Subtype /Type0', s);
  AssertContains('/Encoding /Identity-H', s);
  AssertContains('/Subtype /CIDFontType2', s);
  AssertContains('/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0>>', s);
  AssertContains('/CIDToGIDMap /Identity', s);
  AssertContains('/ToUnicode ', s);
  AssertEquals(0, Pos('/Subtype /TrueType', s), 'TrueType fonts are no longer simple fonts');
  AssertEquals(0, Pos('/Widths', s));
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
  // A subset is named TAG+PostScriptName, the tag being six capital letters.
  AssertTrue(TRegEx.IsMatch(s, '/BaseFont /[A-Z]{6}\+ArialMT'),
    '/BaseFont should be the subset tag plus the PostScript name');
end;

procedure TTTFEmitTests.Test_Arial_WArrayCoversOnlyUsedGlyphs;
var
  s, w: string;
  startIdx, endIdx: Integer;
begin
  // "Hello" uses four distinct glyphs: H e l o (Arial gids 43, 72, 79, 82).
  // Widths are Arial's 2048-unit advances in 1/1000 em: H 1479, e/o 1139, l 455.
  s := SavedAsString(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Name := 'Arial';
    TsmPDF(o).DrawText('Hello', 100, 100);
  end);
  AssertContains('/DW 1000', s);
  startIdx := Pos('/W [', s);
  AssertTrue(startIdx > 0, '/W array present');
  endIdx := PosEx(']]', s, startIdx);
  AssertTrue(endIdx > startIdx, 'closing ]] for /W');
  w := Copy(s, startIdx, endIdx - startIdx + 2);
  // Arial advances at 2048 units/em: H 1479, e 1139, l 455, o 1139.
  AssertEquals('/W [43 [722.168] 72 [556.152] 79 [222.168] 82 [556.152]]', w,
    'one gid [width] group per run of consecutive glyph ids');
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

procedure TTTFEmitTests.Test_Arial_fontDescriptorHasSymbolicFlag;
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
  // CID fonts are flagged symbolic (bit 3, value 4), not nonsymbolic.
  AssertTrue((flagsValue and 4) <> 0,
    Format('Symbolic flag (4) should be set in flags=%d', [flagsValue]));
  AssertTrue((flagsValue and 32) = 0,
    Format('Nonsymbolic flag (32) should be clear in flags=%d', [flagsValue]));
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
  AssertFalse(Pos('/Subtype /Type0', s) > 0,
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
  AssertContains('/Subtype /Type1', s);
  AssertContains('/Subtype /Type0', s);
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
