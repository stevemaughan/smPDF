unit Tests.PDF.Opacity;

// Transparency through ExtGState (W12).

interface

uses
  SysUtils, Classes, Types, smPDF.TestFramework, Tests.PDF.Helpers;

type
  TOpacityTests = class(TTestCase)
  protected
    function Build(const ABuild: TProc<TObject>): string;
  published
    procedure Test_Defaults_areOpaque;
    procedure Test_Opaque_writesNoExtGState;
    procedure Test_BrushOpacity_setsFillAlpha;
    procedure Test_PenOpacity_setsStrokeAlpha;
    procedure Test_FontOpacity_setsBothAlphas;
    procedure Test_PageResources_listExtGState;
    procedure Test_SameAlpha_sharesOneObjectAcrossPages;
    procedure Test_Opacity_isClamped;
    procedure Test_TextBackground_usesBrushOpacity;
    procedure Test_Translucent_rendersWithoutMutoolWarnings;
  end;

implementation

uses
  RegularExpressions, Vcl.Graphics, smPDF;

function TOpacityTests.Build(const ABuild: TProc<TObject>): string;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    pdf.CompressStreams := False;
    pdf.NewPage(612, 792);
    ABuild(pdf);
    Result := PdfBytesToString(pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

procedure TOpacityTests.Test_Defaults_areOpaque;
var
  pdf: TsmPDF;
begin
  pdf := TsmPDF.Create;
  try
    AssertEquals(1.0, pdf.Pen.Opacity);
    AssertEquals(1.0, pdf.Brush.Opacity);
    AssertEquals(1.0, pdf.Font.Opacity);
  finally
    pdf.Free;
  end;
end;

procedure TOpacityTests.Test_Opaque_writesNoExtGState;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
    TsmPDF(o).DrawText('Opaque', 10, 120);
  end);
  AssertEquals(0, Pos('ExtGState', s));
  AssertEquals(0, Pos(' gs'#10, s));
end;

procedure TOpacityTests.Test_BrushOpacity_setsFillAlpha;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Opacity := 0.5;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertContains('q'#10'/GS1 gs'#10, s, 'the alpha is selected inside the draw''s q');
  AssertContains('<< /Type /ExtGState /CA 1 /ca 0.5>>', s);
end;

procedure TOpacityTests.Test_PenOpacity_setsStrokeAlpha;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Pen.Opacity := 0.25;
    TsmPDF(o).DrawLine(10, 10, 100, 100);
  end);
  AssertContains('/CA 0.25 /ca 1', s);
end;

procedure TOpacityTests.Test_FontOpacity_setsBothAlphas;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Font.Size := 60;
    TsmPDF(o).Font.Color := clRed;
    TsmPDF(o).Font.Opacity := 0.3;
    TsmPDF(o).DrawText('TRIAL', 100, 300, 45);
  end);
  AssertContains('/CA 0.3 /ca 0.3', s);
  AssertTrue(Pos('/GS1 gs', s) < Pos('BT', s), 'alpha is set before the text object');
end;

procedure TOpacityTests.Test_PageResources_listExtGState;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Opacity := 0.5;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertTrue(TRegEx.IsMatch(s, '/ExtGState << /GS1 \d+ 0 R>>'), 'page resources name GS1');
end;

procedure TOpacityTests.Test_SameAlpha_sharesOneObjectAcrossPages;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Opacity := 0.5;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
    TsmPDF(o).DrawOval(10, 10, 100, 100);
    TsmPDF(o).NewPage;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
    TsmPDF(o).Brush.Opacity := 0.75;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertEquals(2, CountSubstring('/Type /ExtGState', s), 'one object per distinct alpha pair');
  AssertEquals(3, CountSubstring('/GS1 gs', s));
  AssertEquals(1, CountSubstring('/GS2 gs', s));
end;

procedure TOpacityTests.Test_Opacity_isClamped;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Opacity := 1.5;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
    TsmPDF(o).Brush.Opacity := -1;
    TsmPDF(o).DrawBox(10, 10, 100, 100);
  end);
  AssertEquals(1, CountSubstring('/Type /ExtGState', s), 'above 1 is opaque, below 0 is 0');
  AssertContains('/CA 1 /ca 0>>', s);
end;

procedure TOpacityTests.Test_TextBackground_usesBrushOpacity;
var s: string;
begin
  s := Build(procedure(o: TObject)
  begin
    TsmPDF(o).Brush.Style := brushSolid;
    TsmPDF(o).Brush.Color := clYellow;
    TsmPDF(o).Brush.Opacity := 0.4;
    TsmPDF(o).DrawText('Highlighted', 10, 10);
  end);
  AssertContains('/CA 1 /ca 0.4', s);
end;

procedure TOpacityTests.Test_Translucent_rendersWithoutMutoolWarnings;
var
  pdf: TsmPDF;
  bytes: TBytes;
  warnings: string;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Brush.Style := brushSolid;
    pdf.Brush.Color := clBlue;
    pdf.Brush.Opacity := 0.35;
    pdf.DrawOval(50, 50, 300, 300);
    pdf.Font.Size := 72;
    pdf.Font.Opacity := 0.2;
    pdf.DrawText('TRIAL', 100, 400, 30);
    bytes := pdf.ToBytes;
  finally
    pdf.Free;
  end;
  if not MutoolRenderWarnings(bytes, warnings) then
    Skip('mutool is not on the PATH');
  AssertEquals('', warnings);
end;

initialization
  TTestRegistry.RegisterTestCase(TOpacityTests);

end.
