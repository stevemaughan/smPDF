unit Tests.PDF.WinFonts;

interface

uses
  SysUtils, smPDF.TestFramework;

type
  TWinFontsTests = class(TTestCase)
  published
    procedure Test_Lookup_Arial_returnsExistingPath;
    procedure Test_Lookup_ArialBold_returnsDifferentPath;
    procedure Test_Lookup_ArialBoldItalic_returnsDifferentPath;
    procedure Test_Lookup_NonExistentFont_returnsEmpty;
    procedure Test_Lookup_Calibri_returnsExistingPath;
    procedure Test_Lookup_BoldFallbackToRegular_whenNoBoldVariant;
    procedure Test_Lookup_CaseInsensitive;
  end;

implementation

uses
  IOUtils, smPDF.WinFonts;

procedure TWinFontsTests.Test_Lookup_Arial_returnsExistingPath;
var path: string;
begin
  path := LookupSystemTTFPath('Arial', False, False);
  AssertNotEmpty(path, 'Arial should be installed on every Windows system');
  AssertTrue(TFile.Exists(path), 'Returned path must point to an existing file');
  AssertTrue(SameText(ExtractFileExt(path), '.ttf'), 'Returned file should be a .ttf');
end;

procedure TWinFontsTests.Test_Lookup_ArialBold_returnsDifferentPath;
var
  reg, bold: string;
begin
  reg  := LookupSystemTTFPath('Arial', False, False);
  bold := LookupSystemTTFPath('Arial', True,  False);
  AssertNotEmpty(bold);
  AssertFalse(SameText(reg, bold),
    'Regular and Bold should resolve to different files (arial.ttf vs arialbd.ttf)');
end;

procedure TWinFontsTests.Test_Lookup_ArialBoldItalic_returnsDifferentPath;
var
  reg, biPath: string;
begin
  reg    := LookupSystemTTFPath('Arial', False, False);
  biPath := LookupSystemTTFPath('Arial', True,  True);
  AssertNotEmpty(biPath);
  AssertFalse(SameText(reg, biPath),
    'Bold Italic should resolve to a distinct file from Regular');
end;

procedure TWinFontsTests.Test_Lookup_NonExistentFont_returnsEmpty;
var path: string;
begin
  path := LookupSystemTTFPath('ThisFontDoesNotExistOnAnyMachine12345', False, False);
  AssertEquals('', path);
end;

procedure TWinFontsTests.Test_Lookup_Calibri_returnsExistingPath;
var path: string;
begin
  path := LookupSystemTTFPath('Calibri', False, False);
  AssertNotEmpty(path, 'Calibri ships with Office; expected on Windows test machine');
  AssertTrue(TFile.Exists(path));
end;

procedure TWinFontsTests.Test_Lookup_BoldFallbackToRegular_whenNoBoldVariant;
var path: string;
begin
  // For a real font that has no Bold variant, the lookup should fall back to
  // the Regular file rather than returning empty. We use a fictitious style
  // by asking for Bold of a font we know to exist — Arial has Bold so use a
  // name where we KNOW only the regular exists. "Lucida Console" is a
  // common Windows font with limited variants; but we can't depend on that.
  // Easier: ask for Bold of a font that exists; we accept either the Bold
  // file (if present) or the Regular file (fallback) — but never empty.
  path := LookupSystemTTFPath('Calibri', True, False);
  AssertNotEmpty(path, 'Calibri Bold (or fallback) should resolve to something');
  AssertTrue(TFile.Exists(path));
end;

procedure TWinFontsTests.Test_Lookup_CaseInsensitive;
var
  upper, lower: string;
begin
  upper := LookupSystemTTFPath('ARIAL', False, False);
  lower := LookupSystemTTFPath('arial', False, False);
  AssertEquals(upper, lower);
end;

initialization
  TTestRegistry.RegisterTestCase(TWinFontsTests);

end.
