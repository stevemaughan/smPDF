program smPDF_StressDemo;

// Stress demo shaped like AlignMix's map export: an A0 landscape page at
// 72 DPI in points, about a million polygon vertices with holes, roads, 2,000
// haloed two-line labels, rep icons drawn as outlines, multilingual labels, a
// rounded legend, all clipped to the map frame. Prints time, size and memory.
//
// The GeoJSON is converted once into a compact cache by a child process, so
// the 74 MB JSON parse does not count towards this process's peak memory.

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.IOUtils, System.JSON, System.Diagnostics, System.Generics.Collections,
  Winapi.Windows, Winapi.PsAPI, Vcl.Graphics, smPDF, smPDF.GdiFonts;

const
  PAGE_W = 3370.39;   // A0 landscape, points
  PAGE_H = 2383.94;
  MARGIN = 36;
  TITLE_H = 90;
  CACHE_FILE = 'territories.cache';

type
  TTerritory = record
    Name, Rep: string;
    Sales: Double;
    Fill: TColor;
    Stroke: TColor;
    Counts: TArray<Integer>;
    Points: TArray<TPointF>;   // lon, lat
  end;

var
  GSeed: Cardinal = 20260923;

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

function WorkingSetMB: Double;
var
  pmc: TProcessMemoryCounters;
begin
  pmc.cb := SizeOf(pmc);
  if GetProcessMemoryInfo(GetCurrentProcess, @pmc, SizeOf(pmc)) then
    Result := pmc.WorkingSetSize / (1024 * 1024)
  else
    Result := 0;
end;

function HexToColor(const AHex: string): TColor;
var
  s: string;
begin
  s := AHex;
  if (s <> '') and (s[1] = '#') then Delete(s, 1, 1);
  if Length(s) <> 6 then Exit(clGray);
  Result := TColor(RGB(StrToIntDef('$' + Copy(s, 1, 2), 128),
    StrToIntDef('$' + Copy(s, 3, 2), 128), StrToIntDef('$' + Copy(s, 5, 2), 128)));
end;

function Lighten(AColor: TColor; AAlpha: Double): TColor;
var
  c: Cardinal;
begin
  c := Cardinal(ColorToRGB(AColor));
  Result := TColor(RGB(
    Round(255 * (1 - AAlpha) + (c and $FF) * AAlpha),
    Round(255 * (1 - AAlpha) + ((c shr 8) and $FF) * AAlpha),
    Round(255 * (1 - AAlpha) + ((c shr 16) and $FF) * AAlpha)));
end;

// ---------------------------------------------------------------------------
// Cache: built by "smPDF_StressDemo --build-cache <geojson> <cache>"
// ---------------------------------------------------------------------------

procedure BuildCache(const AGeoJson, ACache: string);
var
  root: TJSONValue;
  features, coords, poly, pt: TJSONArray;
  feature, geom, props: TJSONObject;
  w: TBinaryWriter;
  i, j, k, m: Integer;
  counts: TList<Integer>;
  pts: TList<TPointF>;
  v: TJSONValue;
  gType: string;

  procedure AddRing(ARing: TJSONArray);
  var
    n: Integer;
  begin
    if ARing.Count < 4 then Exit;
    for n := 0 to ARing.Count - 2 do  // the closing vertex repeats the first
    begin
      pt := ARing.Items[n] as TJSONArray;
      pts.Add(TPointF.Create((pt.Items[0] as TJSONNumber).AsDouble, (pt.Items[1] as TJSONNumber).AsDouble));
    end;
    counts.Add(ARing.Count - 1);
  end;

  function Str(const AKey: string): string;
  begin
    v := props.GetValue(AKey);
    if v is TJSONString then Result := TJSONString(v).Value else Result := '';
  end;

begin
  root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AGeoJson, TEncoding.UTF8));
  if root = nil then raise Exception.Create('Cannot parse ' + AGeoJson);
  counts := TList<Integer>.Create;
  pts := TList<TPointF>.Create;
  w := TBinaryWriter.Create(ACache, False);
  try
    features := (root as TJSONObject).GetValue('features') as TJSONArray;
    w.Write(Integer(features.Count));
    for i := 0 to features.Count - 1 do
    begin
      feature := features.Items[i] as TJSONObject;
      geom := feature.GetValue('geometry') as TJSONObject;
      props := feature.GetValue('properties') as TJSONObject;
      counts.Clear;
      pts.Clear;
      gType := (geom.GetValue('type') as TJSONString).Value;
      coords := geom.GetValue('coordinates') as TJSONArray;
      if gType = 'Polygon' then
        for j := 0 to coords.Count - 1 do
          AddRing(coords.Items[j] as TJSONArray)
      else
        for j := 0 to coords.Count - 1 do
        begin
          poly := coords.Items[j] as TJSONArray;
          for k := 0 to poly.Count - 1 do
            AddRing(poly.Items[k] as TJSONArray);
        end;
      w.Write(Str('Territory Name'));
      w.Write(Str('Sales Rep Name'));
      v := props.GetValue('Total Sales');
      if v is TJSONNumber then w.Write(TJSONNumber(v).AsDouble) else w.Write(Double(0));
      w.Write(Integer(HexToColor(Str('fill'))));
      w.Write(Integer(HexToColor(Str('stroke'))));
      w.Write(Integer(counts.Count));
      for m := 0 to counts.Count - 1 do w.Write(counts[m]);
      w.Write(Integer(pts.Count));
      for m := 0 to pts.Count - 1 do
      begin
        w.Write(Double(pts[m].X));
        w.Write(Double(pts[m].Y));
      end;
    end;
  finally
    w.Free;
    pts.Free;
    counts.Free;
    root.Free;
  end;
end;

function LoadCache(const ACache: string): TArray<TTerritory>;
var
  r: TBinaryReader;
  n, i, m: Integer;
begin
  r := TBinaryReader.Create(ACache);
  try
    n := r.ReadInteger;
    SetLength(Result, n);
    for i := 0 to n - 1 do
    begin
      Result[i].Name   := r.ReadString;
      Result[i].Rep    := r.ReadString;
      Result[i].Sales  := r.ReadDouble;
      Result[i].Fill   := TColor(r.ReadInteger);
      Result[i].Stroke := TColor(r.ReadInteger);
      SetLength(Result[i].Counts, r.ReadInteger);
      for m := 0 to High(Result[i].Counts) do
        Result[i].Counts[m] := r.ReadInteger;
      SetLength(Result[i].Points, r.ReadInteger);
      for m := 0 to High(Result[i].Points) do
      begin
        Result[i].Points[m].X := r.ReadDouble;
        Result[i].Points[m].Y := r.ReadDouble;
      end;
    end;
  finally
    r.Free;
  end;
end;

procedure EnsureCache(const AGeoJson, ACache: string);
var
  si: TStartupInfo;
  pi: TProcessInformation;
  cmd: string;
  code: Cardinal;
begin
  if TFile.Exists(ACache) and (TFile.GetLastWriteTime(ACache) > TFile.GetLastWriteTime(AGeoJson)) then
    Exit;
  Writeln('Building geometry cache from ', ExtractFileName(AGeoJson), ' (child process)...');
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  cmd := Format('"%s" --build-cache "%s" "%s"', [ParamStr(0), AGeoJson, ACache]);
  UniqueString(cmd);
  if not CreateProcess(nil, PChar(cmd), nil, nil, False, 0, nil, nil, si, pi) then
    RaiseLastOSError;
  WaitForSingleObject(pi.hProcess, INFINITE);
  GetExitCodeProcess(pi.hProcess, code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  if code <> 0 then
    raise Exception.Create('Cache build failed');
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

type
  TProjection = record
    OffsetX, OffsetY, Scale: Double;
    function Apply(const ALonLat: TPointF): TPointF;
  end;

function MercatorY(ALat: Double): Double;
begin
  Result := RadToDeg(Ln(Tan(Pi / 4 + DegToRad(ALat) / 2)));
end;

function TProjection.Apply(const ALonLat: TPointF): TPointF;
begin
  Result.X := OffsetX + ALonLat.X * Scale;
  Result.Y := OffsetY - MercatorY(ALonLat.Y) * Scale;
end;

function FitProjection(const ATerritories: TArray<TTerritory>; const AFrame: TRectF): TProjection;
var
  minX, maxX, minY, maxY, my, sx, sy: Double;
  t: TTerritory;
  p: TPointF;
begin
  minX := MaxDouble; maxX := -MaxDouble; minY := MaxDouble; maxY := -MaxDouble;
  for t in ATerritories do
    for p in t.Points do
    begin
      my := MercatorY(p.Y);
      minX := Min(minX, p.X); maxX := Max(maxX, p.X);
      minY := Min(minY, my);  maxY := Max(maxY, my);
    end;
  sx := AFrame.Width / (maxX - minX);
  sy := AFrame.Height / (maxY - minY);
  Result.Scale := Min(sx, sy) * 0.96;
  Result.OffsetX := AFrame.Left + (AFrame.Width - (maxX - minX) * Result.Scale) / 2 - minX * Result.Scale;
  Result.OffsetY := AFrame.Top + (AFrame.Height - (maxY - minY) * Result.Scale) / 2 + maxY * Result.Scale;
end;

function Centroid(const APts: TArray<TPointF>; ACount: Integer): TPointF;
var
  i: Integer;
begin
  Result := TPointF.Create(0, 0);
  for i := 0 to ACount - 1 do
  begin
    Result.X := Result.X + APts[i].X;
    Result.Y := Result.Y + APts[i].Y;
  end;
  if ACount > 0 then
  begin
    Result.X := Result.X / ACount;
    Result.Y := Result.Y / ACount;
  end;
end;

function FontAvailable(const AFamily: string): Boolean;
begin
  Result := GdiFontInstalled(AFamily);
end;

var
  GLabelFont: string;
  GLabelCount: Integer;

// A two-line label stack centred on (CX, CY), placed with GDI metrics.
procedure DrawLabelStack(pdf: TsmPDF; const ALine1, ALine2: string; CX, CY, ASize: Double);
var
  h1, h2, y: Double;
begin
  pdf.Font.Size := ASize;
  pdf.Font.Bold := True;
  h1 := pdf.TextHeightF(ALine1);
  pdf.Font.Size := ASize * 0.8;
  pdf.Font.Bold := False;
  h2 := pdf.TextHeightF(ALine2);
  y := CY - (h1 + h2) / 2;

  pdf.Font.Size := ASize;
  pdf.Font.Bold := True;
  pdf.DrawText(ALine1, CX - pdf.TextWidthF(ALine1) / 2, y);
  pdf.Font.Size := ASize * 0.8;
  pdf.Font.Bold := False;
  pdf.DrawText(ALine2, CX - pdf.TextWidthF(ALine2) / 2, y + h1);
  Inc(GLabelCount);
end;

procedure DrawMap(pdf: TsmPDF; const ATerritories: TArray<TTerritory>; const AFrame: TRectF;
  var AVertices: Integer; ALabels: TList<TPointF>);
var
  proj: TProjection;
  t: TTerritory;
  pts: TArray<TPointF>;
  i: Integer;
  c: TPointF;
begin
  proj := FitProjection(ATerritories, AFrame);
  pdf.Pen.Style := penSolid;
  pdf.Pen.Width := 0.4;
  pdf.Pen.LineJoin := ljRound;
  pdf.Brush.Style := brushSolid;
  for t in ATerritories do
  begin
    SetLength(pts, Length(t.Points));
    for i := 0 to High(t.Points) do
      pts[i] := proj.Apply(t.Points[i]);
    pdf.Brush.Color := Lighten(t.Fill, 0.45);
    pdf.Pen.Color := t.Stroke;
    pdf.DrawPolyPolygon(pts, t.Counts, frEvenOdd);
    Inc(AVertices, Length(pts));
    if Length(t.Counts) > 0 then
    begin
      c := Centroid(pts, t.Counts[0]);
      ALabels.Add(c);
    end;
  end;
end;

procedure DrawRoads(pdf: TsmPDF; const AFrame: TRectF; ACount, AVerts: Integer; var AVertices: Integer);
var
  i, j: Integer;
  pts: TArray<TPointF>;
  angle: Double;
begin
  pdf.Pen.Style := penSolid;
  pdf.Pen.LineJoin := ljRound;
  pdf.Pen.LineCap := lcRound;
  SetLength(pts, AVerts);
  for i := 0 to ACount - 1 do
  begin
    pts[0] := TPointF.Create(AFrame.Left + NextRandom * AFrame.Width, AFrame.Top + NextRandom * AFrame.Height);
    angle := NextRandom * 2 * Pi;
    for j := 1 to AVerts - 1 do
    begin
      angle := angle + (NextRandom - 0.5) * 0.6;
      pts[j] := TPointF.Create(pts[j - 1].X + 6 * Cos(angle), pts[j - 1].Y + 6 * Sin(angle));
    end;
    if i mod 5 = 0 then
    begin
      pdf.Pen.Color := $00306CC0;
      pdf.Pen.Width := 1.2;
    end
    else
    begin
      pdf.Pen.Color := $00909090;
      pdf.Pen.Width := 0.6;
    end;
    pdf.DrawPolyline(pts);
    Inc(AVertices, AVerts);
  end;
end;

const
  CHINESE: array[0..19] of string = ('北京', '上海', '广州', '深圳', '成都', '重庆', '天津', '武汉',
    '西安', '南京', '杭州', '苏州', '长沙', '郑州', '沈阳', '青岛', '宁波', '东莞', '无锡', '厦门');
  JAPANESE: array[0..19] of string = ('東京都', '大阪府', '京都府', '札幌市', '横浜市', '名古屋市',
    '神戸市', '福岡市', '広島市', '仙台市', '川崎市', 'さいたま市', '千葉市', '北九州市', '堺市',
    '新潟市', '浜松市', '熊本市', '相模原市', '岡山市');
  VIETNAMESE: array[0..14] of string = ('Hà Nội', 'Hồ Chí Minh', 'Đà Nẵng', 'Hải Phòng', 'Cần Thơ',
    'Nha Trang', 'Huế', 'Vũng Tàu', 'Biên Hòa', 'Buôn Ma Thuột', 'Quy Nhơn', 'Thái Nguyên',
    'Nam Định', 'Việt Trì', 'Hạ Long');
  POLISH: array[0..14] of string = ('Łódź', 'Kraków', 'Wrocław', 'Gdańsk', 'Poznań', 'Szczecin',
    'Białystok', 'Częstochowa', 'Rzeszów', 'Toruń', 'Kielce', 'Gliwice', 'Zabrze', 'Győr', 'Dvořák');

procedure DrawMultilingual(pdf: TsmPDF; const AFrame: TRectF; const AFamily: string;
  const ANames: array of string; ACount: Integer; AColor: TColor);
var
  i: Integer;
begin
  if not FontAvailable(AFamily) then
  begin
    Writeln('  skipped: ', AFamily, ' is not installed');
    Exit;
  end;
  pdf.Font.Name := AFamily;
  pdf.Font.Bold := False;
  pdf.Font.Color := AColor;
  for i := 0 to ACount - 1 do
  begin
    pdf.Font.Size := 8 + NextRandom * 4;
    pdf.DrawText(ANames[i mod Length(ANames)] + ' ' + IntToStr(i div Length(ANames) + 1),
      AFrame.Left + NextRandom * (AFrame.Width - 80), AFrame.Top + NextRandom * (AFrame.Height - 20));
    Inc(GLabelCount);
  end;
  Writeln(Format('  %d labels in %s', [ACount, AFamily]));
end;

procedure DrawLegend(pdf: TsmPDF; const ATerritories: TArray<TTerritory>);
var
  box: TRectF;
  i: Integer;
  y: Double;
begin
  box := TRectF.Create(PAGE_W - MARGIN - 330, MARGIN + TITLE_H + 20, PAGE_W - MARGIN - 20, MARGIN + TITLE_H + 250);
  pdf.Pen.Style := penSolid;
  pdf.Pen.Color := $00606060;
  pdf.Pen.Width := 1;
  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := clWhite;
  pdf.DrawRoundRect(box, 14, 14);
  pdf.Font.Name := GLabelFont;
  pdf.Font.StrokeWidth := 0;
  pdf.Font.Color := clBlack;
  pdf.Font.Bold := True;
  pdf.Font.Size := 20;
  pdf.Brush.Style := brushClear;
  pdf.DrawText('Legend', box.Left + 18, box.Top + 12);
  pdf.Font.Bold := False;
  pdf.Font.Size := 13.5;
  y := box.Top + 52;
  for i := 0 to 5 do
  begin
    pdf.Brush.Style := brushSolid;
    pdf.Brush.Color := Lighten(ATerritories[i * 7].Fill, 0.45);
    pdf.Pen.Color := ATerritories[i * 7].Stroke;
    pdf.DrawRoundRect(TRectF.Create(box.Left + 18, y, box.Left + 48, y + 20), 4, 4);
    pdf.Brush.Style := brushClear;
    pdf.DrawText(ATerritories[i * 7].Name + ' - ' + ATerritories[i * 7].Rep, box.Left + 60, y);
    y := y + 30;
  end;
end;

var
  pdf: TsmPDF;
  territories: TArray<TTerritory>;
  exeDir, geo, cache, outFile, ionicons: string;
  frame, left, right: TRectF;
  labels: TList<TPointF>;
  i, vertices, roadVertices, icons: Integer;
  swDraw, swSave: TStopwatch;
  bytes: Int64;
  c: TPointF;
  precision: Integer;
begin
  try
    if (ParamCount = 3) and (ParamStr(1) = '--build-cache') then
    begin
      BuildCache(ParamStr(2), ParamStr(3));
      Exit;
    end;

    exeDir := ExtractFilePath(ParamStr(0));
    geo := TPath.GetFullPath(TPath.Combine(exeDir, '..\..\Map\Sales-Territories.geojson'));
    if not TFile.Exists(geo) then
      raise Exception.Create('GeoJSON not found at ' + geo);
    cache := TPath.Combine(exeDir, CACHE_FILE);
    EnsureCache(geo, cache);
    territories := LoadCache(cache);
    outFile := TPath.Combine(exeDir, 'stress.pdf');

    // --precision N: decimals for path coordinates (default 1, i.e. 0.1 pt).
    precision := 1;
    if (ParamCount = 2) and (ParamStr(1) = '--precision') then
      precision := StrToInt(ParamStr(2));

    if FontAvailable('Oswald') then GLabelFont := 'Oswald' else GLabelFont := 'Arial';
    Writeln('Label font: ', GLabelFont);

    labels := TList<TPointF>.Create;
    pdf := TsmPDF.Create;
    try
      swDraw := TStopwatch.StartNew;
      pdf.Title := 'smPDF stress demo - sales territories';
      pdf.Author := 'smPDF';
      pdf.Creator := 'smPDF_StressDemo';
      pdf.CoordinatePrecision := precision;
      pdf.NewPage(PAGE_W, PAGE_H);
      pdf.TextOrigin := toGdiTop;

      pdf.Font.Name := GLabelFont;
      pdf.Font.Size := 40;
      pdf.Font.Bold := True;
      pdf.Font.Color := $00303030;
      pdf.DrawText('US Sales Territories - AlignMix-style stress test', MARGIN, MARGIN);

      frame := TRectF.Create(MARGIN, MARGIN + TITLE_H, PAGE_W - MARGIN, PAGE_H - MARGIN);
      left := TRectF.Create(frame.Left, frame.Top, frame.CenterPoint.X, frame.Bottom);
      right := TRectF.Create(frame.CenterPoint.X, frame.Top, frame.Right, frame.Bottom);

      pdf.PushClipRect(frame);
      vertices := 0;
      DrawMap(pdf, territories, left, vertices, labels);
      DrawMap(pdf, territories, right, vertices, labels);
      roadVertices := 0;
      DrawRoads(pdf, frame, 300, 120, roadVertices);

      // 2,000 haloed two-line label stacks: every territory in both maps,
      // then synthetic place labels.
      pdf.Font.Name := GLabelFont;
      pdf.Font.Color := $00202020;
      pdf.Font.StrokeColor := clWhite;
      pdf.Font.StrokeWidth := 0.6;
      pdf.Font.StrokeMode := smUnderFill;
      pdf.Brush.Style := brushClear;
      GLabelCount := 0;
      for i := 0 to labels.Count - 1 do
        DrawLabelStack(pdf, territories[i mod Length(territories)].Name,
          FormatFloat('$#,##0', territories[i mod Length(territories)].Sales),
          labels[i].X, labels[i].Y, 9.5 + 4.5 * NextRandom);
      while GLabelCount < 2000 do
        DrawLabelStack(pdf, 'Place ' + IntToStr(GLabelCount), 'Pop. ' + FormatFloat('#,##0', 1000 + NextRandom * 90000),
          frame.Left + 40 + NextRandom * (frame.Width - 80), frame.Top + 20 + NextRandom * (frame.Height - 40),
          6.5 + NextRandom * 3);

      // Multilingual labels.
      pdf.Font.StrokeWidth := 0.6;
      DrawMultilingual(pdf, frame, 'Microsoft YaHei', CHINESE, 50, $00202080);
      DrawMultilingual(pdf, frame, 'Yu Gothic', JAPANESE, 50, $00206020);
      DrawMultilingual(pdf, frame, 'Arial', VIETNAMESE, 50, $00602020);
      DrawMultilingual(pdf, frame, 'Arial', POLISH, 50, $00404040);

      // Rep icons from Ionicons, drawn as outlines.
      icons := 0;
      if FontAvailable('Ionicons') then
      begin
        pdf.Font.Name := 'Ionicons';
        pdf.Font.Bold := False;
        pdf.Font.Size := 14;
        pdf.Font.Color := $000030C0;
        pdf.Font.StrokeWidth := 0.8;
        for i := 0 to 199 do
        begin
          c := labels[i mod labels.Count];
          if Odd(i) then ionicons := #$F202 else ionicons := #$F25D;
          pdf.DrawTextOutlines(ionicons, c.X + 18 + NextRandom * 20, c.Y - 30 - NextRandom * 20);
          Inc(icons);
        end;
      end
      else
        Writeln('  skipped: Ionicons is not installed');
      pdf.PopClip;

      pdf.Pen.Style := penSolid;
      pdf.Pen.Color := $00404040;
      pdf.Pen.Width := 1.5;
      pdf.Brush.Style := brushClear;
      pdf.DrawBox(frame.Left, frame.Top, frame.Right, frame.Bottom);
      DrawLegend(pdf, territories);
      swDraw.Stop;

      Writeln(Format('Working set before Save: %.1f MB', [WorkingSetMB]));
      swSave := TStopwatch.StartNew;
      bytes := pdf.Save(outFile);
      swSave.Stop;

      Writeln(Format('Coord. precision: %d decimal(s)', [precision]));
      Writeln(Format('Polygon vertices: %d (%d territories x 2)', [vertices, Length(territories)]));
      Writeln(Format('Road vertices:    %d', [roadVertices]));
      Writeln(Format('Labels:           %d (label stacks and multilingual labels)', [GLabelCount]));
      Writeln(Format('Rep icons:        %d', [icons]));
      Writeln(Format('Draw time:        %d ms', [swDraw.ElapsedMilliseconds]));
      Writeln(Format('Save time:        %d ms', [swSave.ElapsedMilliseconds]));
      Writeln(Format('Total time:       %d ms', [swDraw.ElapsedMilliseconds + swSave.ElapsedMilliseconds]));
      Writeln(Format('Output size:      %.2f MB (%d bytes)', [bytes / (1024 * 1024), bytes]));
      Writeln(Format('Peak working set: %.1f MB', [PeakWorkingSetMB]));
      Writeln(Format('Warnings:         %d', [pdf.Warnings.Count]));
      for i := 0 to pdf.Warnings.Count - 1 do
        Writeln('  ', pdf.Warnings[i]);
      Writeln('Wrote ', outFile);
    finally
      pdf.Free;
      labels.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
