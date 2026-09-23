program smPDF_FallbackBench;

// Cost of fallback fonts per PDF (W15): a Letter page with 300 short Oswald
// labels, with no fallback list, with SystemFallbackFonts('Oswald') on English
// text, and with the same list plus one Chinese label.

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Diagnostics, Vcl.Graphics, smPDF;

const
  LABEL_COUNT = 300;
  RUNS        = 10;

function BuildOne(const AFallbacks: string; AChinese: Boolean): Integer;
var
  pdf: TsmPDF;
  i: Integer;
begin
  pdf := TsmPDF.Create;
  try
    pdf.NewPage(612, 792);
    pdf.Font.Name := 'Oswald';
    pdf.Font.Size := 8.5;
    pdf.Font.Color := clBlack;
    pdf.Font.FallbackFonts := AFallbacks;
    for i := 0 to LABEL_COUNT - 1 do
      pdf.DrawText('Territory ' + IntToStr(i), 20 + (i mod 6) * 95.5, 20 + (i div 6) * 15.0);
    if AChinese then
      pdf.DrawText(#$5317#$4EAC#$5E02, 20, 770);
    Result := Length(pdf.ToBytes);
  finally
    pdf.Free;
  end;
end;

procedure Measure(const ACaption, AFallbacks: string; AChinese: Boolean);
var
  sw: TStopwatch;
  i, size: Integer;
begin
  BuildOne(AFallbacks, AChinese);   // warm up GDI's font cache
  sw := TStopwatch.StartNew;
  for i := 1 to RUNS do
    size := BuildOne(AFallbacks, AChinese);
  sw.Stop;
  Writeln(Format('%-44s %7.1f ms per PDF  %8d bytes',
    [ACaption, sw.Elapsed.TotalMilliseconds / RUNS, size]));
end;

var
  fallbacks: string;
begin
  try
    fallbacks := SystemFallbackFonts('Oswald');
    Writeln('Fallback list: ', fallbacks);
    Measure('No fallback list', '', False);
    Measure('SystemFallbackFonts, English only', fallbacks, False);
    Measure('SystemFallbackFonts, plus one Chinese label', fallbacks, True);
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
