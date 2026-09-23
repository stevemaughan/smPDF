program smPDF_Tests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  smPDF.TestFramework in 'Source\smPDF.TestFramework.pas',
  Tests.PDF.Helpers in 'Source\Tests.PDF.Helpers.pas',
  Tests.PDF.Geometry in 'Source\Tests.PDF.Geometry.pas',
  Tests.PDF.Writer in 'Source\Tests.PDF.Writer.pas',
  Tests.PDF.Pages in 'Source\Tests.PDF.Pages.pas',
  Tests.PDF.Drawing in 'Source\Tests.PDF.Drawing.pas',
  Tests.PDF.Fonts in 'Source\Tests.PDF.Fonts.pas',
  Tests.PDF.Text in 'Source\Tests.PDF.Text.pas',
  Tests.PDF.TTF in 'Source\Tests.PDF.TTF.pas',
  Tests.PDF.WinFonts in 'Source\Tests.PDF.WinFonts.pas',
  Tests.PDF.TTFEmit in 'Source\Tests.PDF.TTFEmit.pas',
  Tests.PDF.Images in 'Source\Tests.PDF.Images.pas',
  Tests.PDF.PictureEmit in 'Source\Tests.PDF.PictureEmit.pas',
  Tests.PDF.Integration in 'Source\Tests.PDF.Integration.pas',
  Tests.PDF.Compression in 'Source\Tests.PDF.Compression.pas',
  Tests.PDF.FloatCoords in 'Source\Tests.PDF.FloatCoords.pas',
  Tests.PDF.PolyPolygon in 'Source\Tests.PDF.PolyPolygon.pas';

var
  results: TArray<TTestResult>;
  junitPath: string;
  i: Integer;
begin
  try
    junitPath := '';
    i := 1;
    while i <= ParamCount do
    begin
      if (ParamStr(i) = '--junit') and (i < ParamCount) then
      begin
        junitPath := ParamStr(i + 1);
        Inc(i, 2);
      end
      else
        Inc(i);
    end;

    results := TTestRunner.RunAll;
    TTestRunner.WriteConsole(results);
    if junitPath <> '' then
      TTestRunner.WriteJUnit(junitPath, results);

    if TTestRunner.FailureCount(results) > 0 then
      ExitCode := 1
    else
      ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
