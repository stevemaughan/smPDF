program smPDF_Bench;

// Throughput benchmark: ~1,000,000 polygon vertices plus 2,000 outlined labels
// on an A0 landscape page at 72 DPI. Uses only API that exists in smPDF 1.0 so
// the same workload can be timed before and after the 2.0 changes.

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Types, System.Diagnostics,
  Winapi.Windows, Winapi.PsAPI, Vcl.Graphics, smPDF;

const
  PAGE_W        = 3370;   // A0 landscape at 72 DPI, whole points
  PAGE_H        = 2384;
  POLY_COUNT    = 4000;
  OUTER_VERTS   = 200;
  HOLE_VERTS    = 50;
  LABEL_COUNT   = 2000;

var
  GSeed: Cardinal = 12345;

function NextRandom: Double;
begin
  GSeed := GSeed * 1103515245 + 12345;
  Result := ((GSeed shr 8) and $FFFFFF) / 16777216.0;
end;

function PeakWorkingSetMB: Double;
var
  pmc: TProcessMemoryCounters;
begin
  pmc.cb := SizeOf(pmc);
  if GetProcessMemoryInfo(GetCurrentProcess, @pmc, SizeOf(pmc)) then
    Result := pmc.PeakWorkingSetSize / (1024 * 1024)
  else
    Result := 0;
end;

procedure AddRing(AList: TPDFPointList; CX, CY, ARadius: Double; ACount: Integer);
var
  i: Integer;
  a, r: Double;
  first: TPoint;
begin
  for i := 0 to ACount - 1 do
  begin
    a := 2 * Pi * i / ACount;
    r := ARadius * (0.75 + 0.25 * NextRandom);
    if i = 0 then
    begin
      first := Point(Round(CX + r * Cos(a)), Round(CY + r * Sin(a)));
      AList.Add(first);
    end
    else
      AList.Add(Point(Round(CX + r * Cos(a)), Round(CY + r * Sin(a))));
  end;
  AList.Add(first);
end;

var
  pdf: TsmPDF;
  pts: TPDFPointList;
  i, vertices: Integer;
  cx, cy, radius: Double;
  swTotal, swDraw, swSave: TStopwatch;
  outFile: string;
  bytes: Int64;
begin
  try
    outFile := ExtractFilePath(ParamStr(0)) + 'bench.pdf';
    swTotal := TStopwatch.StartNew;
    vertices := 0;

    pdf := TsmPDF.Create;
    pts := TPDFPointList.Create;
    try
      swDraw := TStopwatch.StartNew;
      pdf.NewPage(psCustom, poPortrait, 72, clWhite, PAGE_W, PAGE_H);

      pdf.Pen.Color := $00404040;
      pdf.Pen.Width := 0.5;
      pdf.Brush.Style := brushSolid;
      for i := 0 to POLY_COUNT - 1 do
      begin
        pts.Clear;
        cx := 40 + NextRandom * (PAGE_W - 80);
        cy := 40 + NextRandom * (PAGE_H - 80);
        radius := 15 + NextRandom * 25;
        AddRing(pts, cx, cy, radius, OUTER_VERTS);
        AddRing(pts, cx, cy, radius * 0.3, HOLE_VERTS);
        Inc(vertices, pts.Count);
        pdf.Brush.Color := RGB(100 + i mod 150, 150 + i mod 100, 200 - i mod 120);
        pdf.DrawPolygon(pts);
      end;

      pdf.Brush.Style := brushClear;
      pdf.Font.Name := 'Arial';
      pdf.Font.Size := 9;
      pdf.Font.Color := clBlack;
      pdf.Font.StrokeColor := clWhite;
      pdf.Font.StrokeStyle := ssThin;
      for i := 0 to LABEL_COUNT - 1 do
        pdf.DrawText('Territory ' + IntToStr(i),
          Round(20 + NextRandom * (PAGE_W - 120)), Round(20 + NextRandom * (PAGE_H - 40)));
      swDraw.Stop;

      swSave := TStopwatch.StartNew;
      bytes := pdf.Save(outFile);
      swSave.Stop;
    finally
      pts.Free;
      pdf.Free;
    end;
    swTotal.Stop;

    Writeln(Format('Vertices:        %d', [vertices]));
    Writeln(Format('Labels:          %d', [LABEL_COUNT]));
    Writeln(Format('Draw time:       %d ms', [swDraw.ElapsedMilliseconds]));
    Writeln(Format('Save time:       %d ms', [swSave.ElapsedMilliseconds]));
    Writeln(Format('Total time:      %d ms', [swTotal.ElapsedMilliseconds]));
    Writeln(Format('Output size:     %.2f MB (%d bytes)', [bytes / (1024 * 1024), bytes]));
    Writeln(Format('Peak working set %.1f MB', [PeakWorkingSetMB]));
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
