unit Tests.PDF.Info;

// Document information dictionary (W9a).

interface

uses
  SysUtils, Classes, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TInfoTests = class(TTestCase)
  protected
    function Build(const ASetup: TProc<TObject>): string;
  published
    procedure Test_Trailer_referencesInfo;
    procedure Test_Producer_defaultsToLibraryVersion;
    procedure Test_SetFields_areWritten;
    procedure Test_EmptyFields_areOmitted;
    procedure Test_NonAscii_isUtf16HexWithBom;
    procedure Test_Parentheses_areEscaped;
    procedure Test_CreationDate_format;
    procedure Test_CreationDate_defaultsToCreateTime;
    procedure Test_SavingTwice_givesIdenticalBytes;
  end;

implementation

uses
  DateUtils, RegularExpressions, smPDF;

function TInfoTests.Build(const ASetup: TProc<TObject>): string;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    if Assigned(ASetup) then ASetup(pdf);
    Result := PdfBytesToString(pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

procedure TInfoTests.Test_Trailer_referencesInfo;
var
  s, trailer: string;
  m: TMatch;
begin
  s := Build(nil);
  trailer := Copy(s, Pos('trailer', s), MaxInt);
  m := TRegEx.Match(trailer, '/Info (\d+) 0 R');
  AssertTrue(m.Success, 'trailer has /Info');
  AssertContains(m.Groups[1].Value + ' 0 obj'#10'<< /Producer', s, 'the referenced object is the info dict');
end;

procedure TInfoTests.Test_Producer_defaultsToLibraryVersion;
begin
  AssertContains('/Producer (smPDF ' + SMPDF_VERSION + ')', Build(nil));
end;

procedure TInfoTests.Test_SetFields_areWritten;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Title   := 'District Map';
    TsmPDF(o).Author  := 'AlignMix';
    TsmPDF(o).Subject := 'Territories';
    TsmPDF(o).Creator := 'AlignMix 2026';
    TsmPDF(o).Producer := 'Custom';
  end);
  AssertContains('/Title (District Map)', s);
  AssertContains('/Author (AlignMix)', s);
  AssertContains('/Subject (Territories)', s);
  AssertContains('/Creator (AlignMix 2026)', s);
  AssertContains('/Producer (Custom)', s);
end;

procedure TInfoTests.Test_EmptyFields_areOmitted;
var s: string;
begin
  s := Build(nil);
  AssertEquals(0, Pos('/Title', s));
  AssertEquals(0, Pos('/Author', s));
end;

procedure TInfoTests.Test_NonAscii_isUtf16HexWithBom;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Title := #$0141#$00F3'd'#$017A;
  end);
  AssertContains('/Title <FEFF014100F30064017A>', s);
end;

procedure TInfoTests.Test_Parentheses_areEscaped;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Title := 'a(b)c\d';
  end);
  AssertContains('/Title (a\(b\)c\\d)', s);
end;

procedure TInfoTests.Test_CreationDate_format;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).CreationDate := EncodeDateTime(2026, 9, 23, 14, 30, 5, 0);
  end);
  AssertTrue(TRegEx.IsMatch(s, '/CreationDate \(D:20260923143005[+-]\d\d''\d\d''\)'),
    'D:YYYYMMDDHHmmSS+hh''mm''');
end;

procedure TInfoTests.Test_CreationDate_defaultsToCreateTime;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    AssertTrue(Abs(MinutesBetween(Now, pdf.CreationDate)) < 5);
  finally
    pdf.Free;
  end;
end;

procedure TInfoTests.Test_SavingTwice_givesIdenticalBytes;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.DrawText('x', 10, 10);
    AssertBytesEqual(pdf.ToBytes, pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

initialization
  TTestRegistry.RegisterTestCase(TInfoTests);

end.
