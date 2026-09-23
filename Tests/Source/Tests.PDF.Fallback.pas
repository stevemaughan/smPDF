unit Tests.PDF.Fallback;

// Fallback fonts (W13). Needs Oswald and Microsoft YaHei; skips without them.

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TFallbackTests = class(TTestCase)
  protected
    procedure RequireFonts;
  published
    procedure Test_NoFallback_keepsOldBehaviour;
    procedure Test_Fallback_embedsBothFonts_withoutWarnings;
    procedure Test_Fallback_widthIsSumOfRuns;
    procedure Test_Fallback_runsShareOneTextObject;
    procedure Test_Fallback_characterNoFontHas_usesPrimaryAndWarns;
    procedure Test_Fallback_notInstalled_isSkippedWithWarning;
    procedure Test_Fallback_textExtractsWithMutool;
    procedure Test_SystemFallbackFonts_withoutLink_isDefaultList;
    procedure Test_SystemFallbackFonts_excludesTheFamilyItself;
  end;

implementation

uses
  StrUtils, RegularExpressions, smPDF, smPDF.GdiFonts;

const
  MIXED = 'Beijing '#$5317#$4EAC;

procedure TFallbackTests.RequireFonts;
begin
  if not GdiFontInstalled('Oswald') then Skip('Oswald is not installed');
  if not GdiFontInstalled('Microsoft YaHei') then Skip('Microsoft YaHei is not installed');
end;

function BuildMixed(const AFallbacks: string; out AWarnings: string; ACompress: Boolean = False): TBytes;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := ACompress;
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Oswald';
    pdf.Font.Size := 16;
    pdf.Font.FallbackFonts := AFallbacks;
    pdf.DrawText(MIXED, 20, 20);
    Result := pdf.ToBytes;
    AWarnings := pdf.Warnings.Text;
  finally
    pdf.Free;
  end;
end;

procedure TFallbackTests.Test_NoFallback_keepsOldBehaviour;
var
  s, warnings: string;
begin
  RequireFonts;
  s := PdfBytesToString(BuildMixed('', warnings));
  AssertEquals(1, CountSubstring('/Subtype /Type0', s), 'only Oswald is embedded');
  AssertContains('U+5317', warnings);
  AssertContains('U+4EAC', warnings);
end;

procedure TFallbackTests.Test_Fallback_embedsBothFonts_withoutWarnings;
var
  s, warnings: string;
begin
  RequireFonts;
  s := PdfBytesToString(BuildMixed('Microsoft YaHei', warnings));
  AssertEquals(2, CountSubstring('/Subtype /Type0', s));
  AssertTrue(TRegEx.IsMatch(s, '/BaseFont /[A-Z]{6}\+Oswald-Regular'), 'Oswald subset');
  AssertTrue(TRegEx.IsMatch(s, '/BaseFont /[A-Z]{6}\+MicrosoftYaHei'), 'YaHei subset');
  AssertEquals('', warnings);
end;

procedure TFallbackTests.Test_Fallback_widthIsSumOfRuns;
var
  pdf: TsmPDF;
  latin, cjk, combined: Double;
begin
  RequireFonts;
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Size := 16;
    pdf.Font.Name := 'Oswald';
    latin := pdf.TextWidthF('Beijing ');
    pdf.Font.Name := 'Microsoft YaHei';
    cjk := pdf.TextWidthF(#$5317#$4EAC);
    pdf.Font.Name := 'Oswald';
    pdf.Font.FallbackFonts := 'Microsoft YaHei';
    combined := pdf.TextWidthF(MIXED);
    AssertEquals(latin + cjk, combined, 1e-9);
  finally
    pdf.Free;
  end;
end;

procedure TFallbackTests.Test_Fallback_runsShareOneTextObject;
var
  s, warnings: string;
  content: string;
  st: TPdfTestStream;
begin
  RequireFonts;
  content := '';
  for st in ExtractPdfStreams(BuildMixed('Microsoft YaHei', warnings)) do
    content := PdfBytesToString(st.Data);   // the page content is the last stream
  s := content;
  AssertEquals(1, CountSubstring('BT', s));
  AssertContains('/F1 16 Tf', s);
  AssertContains('/F2 16 Tf', s);
  AssertEquals(2, CountSubstring(' Tm', s), 'each run starts at its own pen position');
end;

procedure TFallbackTests.Test_Fallback_characterNoFontHas_usesPrimaryAndWarns;
var
  pdf: TsmPDF;
begin
  RequireFonts;
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Oswald';
    pdf.Font.FallbackFonts := 'Microsoft YaHei';
    pdf.DrawText('A'#$E000, 20, 20);   // a private-use code point neither font maps
    AssertEquals(1, pdf.Warnings.Count, pdf.Warnings.Text);
    AssertContains('Oswald', pdf.Warnings[0]);
    AssertContains('U+E000', pdf.Warnings[0]);
  finally
    pdf.Free;
  end;
end;

procedure TFallbackTests.Test_Fallback_notInstalled_isSkippedWithWarning;
var
  s, warnings: string;
begin
  RequireFonts;
  s := PdfBytesToString(BuildMixed('No Such Font 7;Microsoft YaHei', warnings));
  AssertContains('Fallback font "No Such Font 7" is not installed', warnings);
  AssertTrue(TRegEx.IsMatch(s, '\+MicrosoftYaHei'), 'the next fallback is still used');
  AssertEquals(0, Pos('U+5317', warnings));
end;

procedure TFallbackTests.Test_Fallback_textExtractsWithMutool;
var
  warnings, extracted: string;
begin
  RequireFonts;
  if not MutoolExtractText(BuildMixed('Microsoft YaHei', warnings, True), extracted) then
    Skip('mutool is not on the PATH');
  AssertEquals(MIXED, extracted);
end;

procedure TFallbackTests.Test_SystemFallbackFonts_withoutLink_isDefaultList;
begin
  // No FontLink entry exists for a made-up family, so the defaults are returned.
  AssertEquals('Segoe UI;Microsoft YaHei;Yu Gothic;Malgun Gothic;Nirmala UI',
    SystemFallbackFonts('No Such Family 42'));
end;

procedure TFallbackTests.Test_SystemFallbackFonts_excludesTheFamilyItself;
var
  list: string;
begin
  list := SystemFallbackFonts('Segoe UI');
  AssertFalse(ContainsText(';' + list + ';', ';Segoe UI;'), list);
  AssertContains('Microsoft YaHei', list);
end;

initialization
  TTestRegistry.RegisterTestCase(TFallbackTests);

end.
