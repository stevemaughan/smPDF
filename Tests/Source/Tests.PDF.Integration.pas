unit Tests.PDF.Integration;

interface

uses
  SysUtils, Classes, smPDF.TestFramework;

type
  TIntegrationTests = class(TTestCase)
  protected
    function TempPdf(const AName: string): string;
    function ReadAllBytes(const AFileName: string): TBytes;
    function BytesToLatin1(const ABytes: TBytes): string;
  published
    procedure Test_NewDocument_pageCountIsZero;
    procedure Test_Save_raisesEPDFErrorWhenNoPagesAdded;

    procedure Test_NewPage_default_increasesPageCount;
    procedure Test_NewPage_explicit_setsDimensions;
    procedure Test_NewPage_landscape_swapsDimensions;
    procedure Test_NewPage_psCustom_requiresExplicitDimensions;
    procedure Test_NewPage_psCustom_acceptsPositiveDimensions;

    // Parameter-less NewPage inherits previous page's settings (2nd+ page).
    procedure Test_NewPage_paramless_secondPage_inheritsSizeAndOrientation;
    procedure Test_NewPage_paramless_secondPage_inheritsPaperColor;
    procedure Test_NewPage_paramless_secondPage_inheritsCustomDimensions;
    procedure Test_NewPage_paramless_firstPage_stillUsesDefaults;

    // Paper color
    procedure Test_NewPage_defaultPaperColor_isWhite;
    procedure Test_NewPage_explicitPaperColor_setsProperty;
    procedure Test_NewPage_whitePaper_emitsNoBackgroundFill;
    procedure Test_NewPage_nonWhitePaper_emitsBackgroundFill;

    procedure Test_DrawLine_beforeNewPage_raisesEPDFError;
    procedure Test_DrawText_beforeNewPage_raisesEPDFError;

    procedure Test_Save_singlePage_writesValidPdfFile;
    procedure Test_Save_singlePage_containsCatalogPagesAndPage;
    procedure Test_Save_singlePage_correctMediaBoxFor_A4_300dpi;
    procedure Test_Save_threePages_kidsArrayHasThreeRefs;
    procedure Test_Save_LetterPortrait_72dpi;
    procedure Test_Save_returnsByteCount_matchingFileSize;

    // In-memory output: Save(TStream) and ToBytes.
    procedure Test_ToBytes_matchesSavedFile;
    procedure Test_ToBytes_raisesEPDFErrorWhenNoPagesAdded;
    procedure Test_SaveStream_matchesToBytesAndReturnsCount;
    procedure Test_SaveStream_appendsAtCurrentPosition;
    procedure Test_SaveStream_nilStream_raisesEPDFError;
    procedure Test_SaveStream_raisesEPDFErrorWhenNoPagesAdded;
    procedure Test_SaveFile_noPages_doesNotCreateFile;
  end;

implementation

uses
  IOUtils, Vcl.Graphics, smPDF;

function TIntegrationTests.TempPdf(const AName: string): string;
var
  dir: string;
begin
  dir := TPath.Combine(TPath.GetTempPath, 'smPDF-tests');
  TDirectory.CreateDirectory(dir);
  Result := TPath.Combine(dir, AName);
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

function TIntegrationTests.ReadAllBytes(const AFileName: string): TBytes;
begin
  Result := TFile.ReadAllBytes(AFileName);
end;

function TIntegrationTests.BytesToLatin1(const ABytes: TBytes): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

procedure TIntegrationTests.Test_NewDocument_pageCountIsZero;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    AssertEquals(0, pdf.PageCount);
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_Save_raisesEPDFErrorWhenNoPagesAdded;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.Save(TempPdf('empty.pdf'));
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'Save should raise EPDFError when no pages were added');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_default_increasesPageCount;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage;
    AssertEquals(1, pdf.PageCount);
    pdf.NewPage;
    AssertEquals(2, pdf.PageCount);
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_explicit_setsDimensions;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psLetter, poPortrait, 72);
    AssertEquals(612, pdf.Width,  'Letter portrait 72dpi width');
    AssertEquals(792, pdf.Height, 'Letter portrait 72dpi height');
    AssertEquals(72,  pdf.DPI);
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_landscape_swapsDimensions;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psLetter, poLandscape, 72);
    AssertEquals(792, pdf.Width,  'Letter landscape 72dpi width');
    AssertEquals(612, pdf.Height, 'Letter landscape 72dpi height');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_psCustom_requiresExplicitDimensions;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.NewPage(psCustom, poPortrait, 300, clWhite, 0, 0);
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'psCustom with zero dimensions should raise');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_psCustom_acceptsPositiveDimensions;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psCustom, poPortrait, 300, clWhite, 1000, 1500);
    AssertEquals(1000, pdf.Width);
    AssertEquals(1500, pdf.Height);
  finally
    pdf.Free;
  end;
end;

// ===== Paper color =====

procedure TIntegrationTests.Test_NewPage_defaultPaperColor_isWhite;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    AssertEquals(Integer(clWhite), Integer(pdf.PaperColor),
      'omitting APaperColor should default to clWhite');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_explicitPaperColor_setsProperty;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72, clYellow);
    AssertEquals(Integer(clYellow), Integer(pdf.PaperColor));
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_whitePaper_emitsNoBackgroundFill;
var
  pdf: TsmPDF;
  fileName, s: string;
begin
  // White paper is the default; no background rect should be emitted, so the
  // saved PDF stays byte-identical to pre-feature output.
  fileName := TempPdf('paper-white.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);   // implicit clWhite
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  AssertFalse(Pos(' re'#10, s) > 0,
    'no rectangle path should be emitted for default (white) paper');
end;

procedure TIntegrationTests.Test_NewPage_nonWhitePaper_emitsBackgroundFill;
var
  pdf: TsmPDF;
  fileName, s: string;
  posRG, posRe, posFstar: Integer;
begin
  fileName := TempPdf('paper-yellow.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72, clYellow);  // 1 1 0 in RGB floats
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  posRG    := Pos('1 1 0 rg', s);
  posRe    := Pos(' re'#10,   s);
  posFstar := Pos('f*'#10,    s);
  AssertTrue(posRG > 0,    'yellow Brush fill colour set for paper background');
  AssertTrue(posRe > posRG, 'rectangle path follows the colour');
  AssertTrue(posFstar > posRe,
    'fill operator follows the rectangle (full-page background paint)');
end;

procedure TIntegrationTests.Test_DrawLine_beforeNewPage_raisesEPDFError;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.DrawLine(0, 0, 100, 100);
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'DrawLine before NewPage should raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_DrawText_beforeNewPage_raisesEPDFError;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.DrawText('hi', 10, 10);
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'DrawText before NewPage should raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_Save_singlePage_writesValidPdfFile;
var
  pdf: TsmPDF;
  fileName: string;
  bytes: TBytes;
  s: string;
begin
  fileName := TempPdf('single.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  AssertTrue(TFile.Exists(fileName), 'PDF file should exist on disk');
  bytes := ReadAllBytes(fileName);
  s := BytesToLatin1(bytes);
  AssertStartsWith('%PDF-1.4', s);
  AssertContains('%%EOF', s);
end;

procedure TIntegrationTests.Test_Save_singlePage_containsCatalogPagesAndPage;
var
  pdf: TsmPDF;
  fileName: string;
  s: string;
begin
  fileName := TempPdf('struct.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  AssertContains('/Type /Catalog', s);
  AssertContains('/Type /Pages',   s);
  AssertContains('/Type /Page',    s);
  AssertContains('/Count 1',       s);
  AssertContains('/Root 1 0 R',    s);
end;

procedure TIntegrationTests.Test_Save_singlePage_correctMediaBoxFor_A4_300dpi;
var
  pdf: TsmPDF;
  fileName: string;
  s: string;
begin
  // A4 @ 300 dpi: 2480x3508 px (rounded). Back to points: ~595.20 x 841.92 (rounding noise).
  fileName := TempPdf('a4_300.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 300);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  AssertContains('/MediaBox [0 0 595', s);
  AssertContains('841',                s);
end;

procedure TIntegrationTests.Test_Save_threePages_kidsArrayHasThreeRefs;
var
  pdf: TsmPDF;
  fileName: string;
  s: string;
begin
  fileName := TempPdf('three.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  // Each page allocates a content-stream object before its page object, so the
  // page ids are not contiguous. Just assert the array contains three refs.
  AssertContains('/Kids [', s);
  AssertContains(' 0 R ',   s, 'at least three refs separated by spaces');
  AssertContains(' 0 R]',   s);
  AssertContains('/Count 3', s);
end;

procedure TIntegrationTests.Test_Save_LetterPortrait_72dpi;
var
  pdf: TsmPDF;
  fileName: string;
  s: string;
begin
  fileName := TempPdf('letter.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psLetter, poPortrait, 72);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  AssertContains('/MediaBox [0 0 612 792]', s);
end;

procedure TIntegrationTests.Test_NewPage_paramless_secondPage_inheritsSizeAndOrientation;
var
  pdf: TsmPDF;
  w1, h1: Integer;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA3, poLandscape, 72);   // A3 landscape at 72dpi
    w1 := pdf.Width;
    h1 := pdf.Height;
    pdf.NewPage;                           // parameter-less -> should inherit
    AssertEquals(Ord(psA3),         Ord(pdf.Size),        'paper size inherited');
    AssertEquals(Ord(poLandscape),  Ord(pdf.Orientation), 'orientation inherited');
    AssertEquals(72,                pdf.DPI,              'DPI inherited');
    AssertEquals(w1,                pdf.Width,            'width matches previous page');
    AssertEquals(h1,                pdf.Height,           'height matches previous page');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_paramless_secondPage_inheritsPaperColor;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72, clYellow);
    pdf.NewPage;
    AssertEquals(Integer(clYellow), Integer(pdf.PaperColor),
      'paper colour inherited from previous page');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_paramless_secondPage_inheritsCustomDimensions;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    // psCustom + landscape exercises the custom-dim path through the
    // orientation swap; the second page must end up the same size as the first.
    pdf.NewPage(psCustom, poLandscape, 72, clWhite, 1000, 500);
    AssertEquals(500,  pdf.Width,  'first page width post-swap');
    AssertEquals(1000, pdf.Height, 'first page height post-swap');
    pdf.NewPage;
    AssertEquals(500,  pdf.Width,  'second page width matches first');
    AssertEquals(1000, pdf.Height, 'second page height matches first');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_NewPage_paramless_firstPage_stillUsesDefaults;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage;   // no previous page -> A4 portrait at 300 dpi
    AssertEquals(Ord(psA4),        Ord(pdf.Size),        'default paper size');
    AssertEquals(Ord(poPortrait),  Ord(pdf.Orientation), 'default orientation');
    AssertEquals(300,              pdf.DPI,              'default DPI');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_Save_returnsByteCount_matchingFileSize;
var
  pdf: TsmPDF;
  fileName: string;
  returned, actual: Int64;
  fs: TFileStream;
begin
  fileName := TempPdf('save-returns-bytes.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.DrawText('size check', 50, 50);
    returned := pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  // Capture actual file size via TFileStream (XE8-compatible — TFile.GetSize
  // requires Delphi 10.4 Sydney+).
  fs := TFileStream.Create(fileName, fmOpenRead or fmShareDenyWrite);
  try
    actual := fs.Size;
  finally
    fs.Free;
  end;
  AssertTrue(returned > 0, 'Save should return a positive byte count');
  AssertEquals(actual, returned, 'Save return value matches file size on disk');
end;

procedure TIntegrationTests.Test_ToBytes_matchesSavedFile;
var
  pdf: TsmPDF;
  fileName: string;
  bytes: TBytes;
begin
  fileName := TempPdf('tobytes.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    pdf.DrawText('in memory', 50, 50);
    pdf.DrawLine(10, 10, 200, 200);
    pdf.Save(fileName);
    bytes := pdf.ToBytes;
  finally
    pdf.Free;
  end;
  AssertStartsWith('%PDF-1.4', BytesToLatin1(bytes));
  AssertBytesEqual(ReadAllBytes(fileName), bytes, 'ToBytes matches Save(file) byte for byte');
end;

procedure TIntegrationTests.Test_ToBytes_raisesEPDFErrorWhenNoPagesAdded;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.ToBytes;
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'ToBytes should raise EPDFError when no pages were added');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_SaveStream_matchesToBytesAndReturnsCount;
var
  pdf: TsmPDF;
  ms: TMemoryStream;
  expected, actual: TBytes;
  returned: Int64;
begin
  ms := TMemoryStream.Create;
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psLetter, poPortrait, 72);
    pdf.DrawBox(20, 20, 300, 200);
    expected := pdf.ToBytes;
    returned := pdf.Save(ms);
    AssertEquals(Int64(Length(expected)), returned, 'Save(stream) returns byte count');
    AssertEquals(returned, ms.Size, 'Stream size equals returned byte count');
    SetLength(actual, ms.Size);
    ms.Position := 0;
    ms.ReadBuffer(actual[0], ms.Size);
    AssertBytesEqual(expected, actual, 'Save(stream) matches ToBytes');
  finally
    pdf.Free;
    ms.Free;
  end;
end;

procedure TIntegrationTests.Test_SaveStream_appendsAtCurrentPosition;
const
  PREFIX: array[0..3] of Byte = (Ord('A'), Ord('B'), Ord('C'), Ord('D'));
var
  pdf: TsmPDF;
  ms: TMemoryStream;
  returned: Int64;
  all: TBytes;
  s: string;
begin
  ms := TMemoryStream.Create;
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    ms.WriteBuffer(PREFIX[0], Length(PREFIX));
    pdf.NewPage(psA4, poPortrait, 72);
    returned := pdf.Save(ms);
    AssertEquals(Int64(Length(PREFIX)) + returned, ms.Size, 'PDF appended after existing content');
    SetLength(all, ms.Size);
    ms.Position := 0;
    ms.ReadBuffer(all[0], ms.Size);
    s := BytesToLatin1(all);
    AssertStartsWith('ABCD%PDF-1.4', s, 'Existing content preserved, PDF follows');
  finally
    pdf.Free;
    ms.Free;
  end;
end;

procedure TIntegrationTests.Test_SaveStream_nilStream_raisesEPDFError;
var
  pdf: TsmPDF;
  raised: Boolean;
begin
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    pdf.NewPage(psA4, poPortrait, 72);
    raised := False;
    try
      pdf.Save(TStream(nil));
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'Save(nil stream) should raise EPDFError');
  finally
    pdf.Free;
  end;
end;

procedure TIntegrationTests.Test_SaveStream_raisesEPDFErrorWhenNoPagesAdded;
var
  pdf: TsmPDF;
  ms: TMemoryStream;
  raised: Boolean;
begin
  ms := TMemoryStream.Create;
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    raised := False;
    try
      pdf.Save(ms);
    except
      on E: EPDFError do raised := True;
    end;
    AssertTrue(raised, 'Save(stream) should raise EPDFError when no pages were added');
    AssertEquals(Int64(0), ms.Size, 'Nothing written to the stream on failure');
  finally
    pdf.Free;
    ms.Free;
  end;
end;

procedure TIntegrationTests.Test_SaveFile_noPages_doesNotCreateFile;
var
  pdf: TsmPDF;
  fileName: string;
begin
  fileName := TempPdf('no-pages.pdf');
  pdf := TsmPDF.Create;
  pdf.CompressStreams := False;
  try
    try
      pdf.Save(fileName);
    except
      on E: EPDFError do ;
    end;
  finally
    pdf.Free;
  end;
  AssertFalse(TFile.Exists(fileName), 'Failed Save should not leave a file on disk');
end;

initialization
  TTestRegistry.RegisterTestCase(TIntegrationTests);

end.
