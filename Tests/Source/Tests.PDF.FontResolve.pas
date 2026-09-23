unit Tests.PDF.FontResolve;

// Font resolution through GDI (W2). Tests that need a particular installed
// font skip when it is missing, so the suite passes on a clean machine.

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TFontResolveTests = class(TTestCase)
  protected
    function LoadPostScriptName(const AFamily: string; ABold, AItalic: Boolean): string;
    function BuildWith(const AFamily: string; ABold: Boolean = False; AItalic: Boolean = False): string;
  published
    procedure Test_Arial_fourStyles_fourPostScriptNames;
    procedure Test_Cambria_fromCollection_rebuildsValidSfnt;
    procedure Test_RebuiltFont_checksumsAreValid;
    procedure Test_UnknownFamily_fallsBackToHelvetica_withOneWarning;
    procedure Test_Oswald_resolvesToRegular_notDemiBold;
    procedure Test_Oswald_bold_resolvesToBold;
    procedure Test_KnownFamily_noWarnings;
    procedure Test_SyntheticBold_emboldensWithFillColourStroke;
    procedure Test_RealBold_isNotEmboldened;
    procedure Test_EmbeddingRestricted_readsFsType;
    procedure Test_TwoThreads_resolveFontsIndependently;
  end;

implementation

uses
  Winapi.Windows, Vcl.Graphics, smPDF, smPDF.GdiFonts, smPDF.TTF;

function TFontResolveTests.LoadPostScriptName(const AFamily: string; ABold, AItalic: Boolean): string;
var
  data: TBytes;
  face: string;
  ttf: TTTFFont;
begin
  if not GdiLoadFontData(AFamily, ABold, AItalic, data, face) then
    Skip(AFamily + ' is not installed');
  ttf := TTTFFont.CreateFromBytes(data, AFamily);
  try
    Result := ttf.Metrics.PostScriptName;
  finally
    ttf.Free;
  end;
end;

function TFontResolveTests.BuildWith(const AFamily: string; ABold, AItalic: Boolean): string;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := AFamily;
    pdf.Font.Bold := ABold;
    pdf.Font.Italics := AItalic;
    pdf.DrawText('Hello', 10, 10);
    Result := PdfBytesToString(pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

procedure TFontResolveTests.Test_Arial_fourStyles_fourPostScriptNames;
var
  names: TStringList;
begin
  names := TStringList.Create;
  try
    names.Sorted := True;
    names.Duplicates := dupIgnore;
    names.Add(LoadPostScriptName('Arial', False, False));
    names.Add(LoadPostScriptName('Arial', True,  False));
    names.Add(LoadPostScriptName('Arial', False, True));
    names.Add(LoadPostScriptName('Arial', True,  True));
    AssertEquals(4, names.Count, 'distinct PostScript names: ' + names.CommaText);
    AssertTrue(names.IndexOf('ArialMT') >= 0, names.CommaText);
    AssertTrue(names.IndexOf('Arial-BoldItalicMT') >= 0, names.CommaText);
  finally
    names.Free;
  end;
end;

procedure TFontResolveTests.Test_Cambria_fromCollection_rebuildsValidSfnt;
var
  data: TBytes;
  face: string;
  ttf: TTTFFont;
begin
  if not GdiLoadFontData('Cambria', False, False, data, face) then
    Skip('Cambria is not installed');
  ttf := TTTFFont.CreateFromBytes(data, 'Cambria');
  try
    AssertEquals('Cambria', ttf.Metrics.PostScriptName);
    AssertTrue(ttf.HasTrueTypeOutlines, 'Cambria has glyf outlines');
    AssertTrue(ttf.GlyphIndex(Ord('A')) > 0, 'cmap maps "A"');
  finally
    ttf.Free;
  end;
end;

procedure TFontResolveTests.Test_RebuiltFont_checksumsAreValid;
var
  data: TBytes;
  face: string;
  numTables, i, off, len: Integer;
  stored, actual: Cardinal;
  tag: string;
  headOff: Integer;
  saved: array[0..3] of Byte;
  function U16(p: Integer): Integer; begin Result := (data[p] shl 8) or data[p + 1]; end;
  function U32(p: Integer): Cardinal;
  begin
    Result := (Cardinal(data[p]) shl 24) or (Cardinal(data[p + 1]) shl 16) or
              (Cardinal(data[p + 2]) shl 8) or data[p + 3];
  end;
begin
  if not GdiLoadFontData('Cambria', False, False, data, face) then
    Skip('Cambria is not installed');
  AssertEquals($B1B0AFBA, Int64(SfntChecksum(data, 0, Length(data))), 'whole-font checksum');

  numTables := U16(4);
  headOff := -1;
  for i := 0 to numTables - 1 do
  begin
    tag := Char(data[12 + i * 16]) + Char(data[13 + i * 16]) + Char(data[14 + i * 16]) + Char(data[15 + i * 16]);
    stored := U32(12 + i * 16 + 4);
    off    := U32(12 + i * 16 + 8);
    len    := U32(12 + i * 16 + 12);
    AssertEquals(0, off mod 4, tag + ' is 4-byte aligned');
    if tag = 'head' then
    begin
      headOff := off;
      Move(data[off + 8], saved[0], 4);
      FillChar(data[off + 8], 4, 0);
    end;
    actual := SfntChecksum(data, off, len);
    if tag = 'head' then
      Move(saved[0], data[off + 8], 4);
    AssertEquals(Int64(stored), Int64(actual), tag + ' checksum');
  end;
  AssertTrue(headOff > 0, 'head table present');
end;

procedure TFontResolveTests.Test_UnknownFamily_fallsBackToHelvetica_withOneWarning;
var
  pdf: TsmPDF;
  s: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'No Such Font Family 42';
    pdf.DrawText('one', 10, 10);
    pdf.DrawText('two', 10, 30);
    pdf.Font.Size := 20;
    pdf.DrawText('three', 10, 50);
    s := PdfBytesToString(pdf.ToBytes);
    AssertContains('/BaseFont /Helvetica', s);
    AssertEquals(1, pdf.Warnings.Count, pdf.Warnings.Text);
    AssertContains('No Such Font Family 42', pdf.Warnings[0]);
    AssertContains('Helvetica', pdf.Warnings[0]);
  finally
    pdf.Free;
  end;
end;

procedure TFontResolveTests.Test_Oswald_resolvesToRegular_notDemiBold;
begin
  AssertEquals('Oswald-Regular', LoadPostScriptName('Oswald', False, False));
end;

procedure TFontResolveTests.Test_Oswald_bold_resolvesToBold;
begin
  AssertEquals('Oswald-Bold', LoadPostScriptName('Oswald', True, False));
end;

procedure TFontResolveTests.Test_KnownFamily_noWarnings;
var
  pdf: TsmPDF;
  data: TBytes;
  face: string;
begin
  if not GdiLoadFontData('Arial', False, False, data, face) then
    Skip('Arial is not installed');
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Arial';
    pdf.DrawText('Hello', 10, 10);
    pdf.ToBytes;
    AssertEquals(0, pdf.Warnings.Count, pdf.Warnings.Text);
  finally
    pdf.Free;
  end;
end;

procedure TFontResolveTests.Test_SyntheticBold_emboldensWithFillColourStroke;
var
  s: string;
  data: TBytes;
  face: string;
begin
  // Calibri Light has no bold face, so GDI would embolden it.
  if not GdiLoadFontData('Calibri Light', False, False, data, face) then
    Skip('Calibri Light is not installed');
  s := BuildWith('Calibri Light', True);
  AssertContains('+Calibri-Light', s);
  AssertContains('0 0 0 RG', s, 'stroke in the fill colour');
  AssertContains('0.36 w', s, '0.03 em at 12 pt');
  AssertContains('2 Tr', s);
end;

procedure TFontResolveTests.Test_RealBold_isNotEmboldened;
var
  s: string;
  data: TBytes;
  face: string;
begin
  if not GdiLoadFontData('Arial', True, False, data, face) then
    Skip('Arial is not installed');
  s := BuildWith('Arial', True);
  AssertContains('+Arial-BoldMT', s);
  AssertEquals(0, Pos(' Tr', s), 'a real bold face needs no emboldening');
end;

procedure TFontResolveTests.Test_EmbeddingRestricted_readsFsType;
var
  data: TBytes;
  face: string;
  ttf: TTTFFont;
  os2: Integer;
  i, numTables: Integer;
begin
  if not GdiLoadFontData('Arial', False, False, data, face) then
    Skip('Arial is not installed');
  // Patch OS/2.fsType to 2 (restricted licence) in a copy of the file.
  numTables := (data[4] shl 8) or data[5];
  os2 := -1;
  for i := 0 to numTables - 1 do
    if (Char(data[12 + i * 16]) = 'O') and (Char(data[13 + i * 16]) = 'S') then
      os2 := (data[12 + i * 16 + 8] shl 24) or (data[12 + i * 16 + 9] shl 16) or
             (data[12 + i * 16 + 10] shl 8) or data[12 + i * 16 + 11];
  AssertTrue(os2 > 0, 'OS/2 table found');
  data[os2 + 8] := 0;
  data[os2 + 9] := 2;
  ttf := TTTFFont.CreateFromBytes(data, 'patched');
  try
    AssertTrue(ttf.EmbeddingRestricted);
  finally
    ttf.Free;
  end;
end;

function BuildMultiFontDoc: TBytes;
const
  FAMILIES: array[0..3] of string = ('Arial', 'Calibri', 'Oswald', 'Cambria');
var
  pdf: TsmPDF;
  i, j: Integer;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    for j := 0 to 3 do
      for i := 0 to High(FAMILIES) do
      begin
        pdf.Font.Name := FAMILIES[i];
        pdf.Font.Bold := Odd(j);
        pdf.Font.Italics := j >= 2;
        pdf.DrawText(FAMILIES[i] + ' sample', 10, 10 + 20 * (i + 4 * j));
      end;
    Result := pdf.ToBytes;
  finally
    pdf.Free;
  end;
end;

type
  TFontWorker = class(TThread)
  protected
    procedure Execute; override;
  public
    Output: TBytes;
    Error:  string;
  end;

procedure TFontWorker.Execute;
begin
  try
    Output := BuildMultiFontDoc;
  except
    on E: Exception do Error := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TFontResolveTests.Test_TwoThreads_resolveFontsIndependently;
var
  expected: TBytes;
  workers: array[0..1] of TFontWorker;
  i: Integer;
begin
  expected := BuildMultiFontDoc;
  for i := 0 to 1 do
    workers[i] := TFontWorker.Create(True);
  try
    for i := 0 to 1 do workers[i].Start;
    for i := 0 to 1 do workers[i].WaitFor;
    for i := 0 to 1 do
    begin
      AssertEquals('', workers[i].Error, 'thread ' + IntToStr(i));
      AssertBytesEqual(expected, workers[i].Output, 'thread ' + IntToStr(i) + ' output');
    end;
  finally
    for i := 0 to 1 do workers[i].Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TFontResolveTests);

end.
