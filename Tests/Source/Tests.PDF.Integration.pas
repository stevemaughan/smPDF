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
  try
    pdf.NewPage(psLetter, poPortrait, 72);
    pdf.Save(fileName);
  finally
    pdf.Free;
  end;
  s := BytesToLatin1(ReadAllBytes(fileName));
  AssertContains('/MediaBox [0 0 612 792]', s);
end;

initialization
  TTestRegistry.RegisterTestCase(TIntegrationTests);

end.
