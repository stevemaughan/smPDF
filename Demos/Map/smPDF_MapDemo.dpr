program smPDF_MapDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.JSON,
  System.Math,
  Vcl.Graphics,
  Generics.Collections,
  Winapi.Windows,
  smPDF;

const
  // Layout constants in points (1/72 inch). Multiplied by DPI/72 at use.
  MARGIN_LEFT_PT   = 30;
  MARGIN_RIGHT_PT  = 30;
  MARGIN_TOP_PT    = 80;
  MARGIN_BOTTOM_PT = 30;
  TITLE_TOP_PT     = 25;
  TITLE_BOTTOM_PT  = 65;

type
  TBounds = record
    MinLon, MaxLon, MinMercY, MaxMercY: Double;
  end;

  TProjector = record
    OffsetX, OffsetY: Double;
    Scale:            Double;
  end;

function HexToColor(const AHex: string): TColor;
var
  s: string;
  r, g, b: Integer;
begin
  s := AHex;
  if (s <> '') and (s[1] = '#') then Delete(s, 1, 1);
  if Length(s) <> 6 then Exit(clGray);
  r := StrToIntDef('$' + Copy(s, 1, 2), 128);
  g := StrToIntDef('$' + Copy(s, 3, 2), 128);
  b := StrToIntDef('$' + Copy(s, 5, 2), 128);
  Result := TColor(RGB(r, g, b));
end;

function BlendOnWhite(AColor: TColor; AAlpha: Double): TColor;
var
  packed_: Cardinal;
  r, g, b: Byte;
begin
  if AAlpha < 0 then AAlpha := 0;
  if AAlpha > 1 then AAlpha := 1;
  packed_ := Cardinal(ColorToRGB(AColor));
  r := Round(255 * (1 - AAlpha) + ( packed_         and $FF) * AAlpha);
  g := Round(255 * (1 - AAlpha) + ((packed_ shr  8) and $FF) * AAlpha);
  b := Round(255 * (1 - AAlpha) + ((packed_ shr 16) and $FF) * AAlpha);
  Result := TColor(RGB(r, g, b));
end;

function MercatorY(ALatDeg: Double): Double;
begin
  Result := RadToDeg(Ln(Tan(Pi / 4 + DegToRad(ALatDeg) / 2)));
end;

procedure UpdateBoundsForRing(ARing: TJSONArray; var AB: TBounds);
var
  i: Integer;
  pt: TJSONArray;
  lon, lat, my: Double;
begin
  for i := 0 to ARing.Count - 1 do
  begin
    pt  := ARing.Items[i] as TJSONArray;
    lon := (pt.Items[0] as TJSONNumber).AsDouble;
    lat := (pt.Items[1] as TJSONNumber).AsDouble;
    my  := MercatorY(lat);
    if lon < AB.MinLon   then AB.MinLon   := lon;
    if lon > AB.MaxLon   then AB.MaxLon   := lon;
    if my  < AB.MinMercY then AB.MinMercY := my;
    if my  > AB.MaxMercY then AB.MaxMercY := my;
  end;
end;

procedure UpdateBoundsForPolygon(APoly: TJSONArray; var AB: TBounds);
var
  i: Integer;
begin
  for i := 0 to APoly.Count - 1 do
    UpdateBoundsForRing(APoly.Items[i] as TJSONArray, AB);
end;

procedure UpdateBoundsForFeature(AGeom: TJSONObject; var AB: TBounds);
var
  gType: string;
  coords: TJSONArray;
  i: Integer;
begin
  gType  := (AGeom.GetValue('type') as TJSONString).Value;
  coords :=  AGeom.GetValue('coordinates') as TJSONArray;
  if gType = 'Polygon' then
    UpdateBoundsForPolygon(coords, AB)
  else if gType = 'MultiPolygon' then
    for i := 0 to coords.Count - 1 do
      UpdateBoundsForPolygon(coords.Items[i] as TJSONArray, AB);
end;

function MakeProjector(const AB: TBounds; APageW, APageH, ADpi: Integer): TProjector;
var
  marginL, marginR, marginT, marginB, drawW, drawH: Integer;
  spanX, spanY, sx, sy: Double;
begin
  marginL := Round(MARGIN_LEFT_PT   * ADpi / 72);
  marginR := Round(MARGIN_RIGHT_PT  * ADpi / 72);
  marginT := Round(MARGIN_TOP_PT    * ADpi / 72);
  marginB := Round(MARGIN_BOTTOM_PT * ADpi / 72);
  drawW := APageW - marginL - marginR;
  drawH := APageH - marginT - marginB;
  spanX := AB.MaxLon   - AB.MinLon;
  spanY := AB.MaxMercY - AB.MinMercY;
  sx    := drawW / spanX;
  sy    := drawH / spanY;
  Result.Scale   := Min(sx, sy);
  Result.OffsetX := marginL + (drawW - spanX * Result.Scale) / 2 - AB.MinLon   * Result.Scale;
  Result.OffsetY := marginT + (drawH - spanY * Result.Scale) / 2 + AB.MaxMercY * Result.Scale;
end;

function ProjectPoint(const P: TProjector; ALon, ALat: Double): TPointF;
begin
  Result.X := P.OffsetX + ALon            * P.Scale;
  Result.Y := P.OffsetY - MercatorY(ALat) * P.Scale;
end;

// Append one GeoJSON ring as an explicit part of a poly-polygon. The closing
// vertex (a repeat of the first) is dropped; DrawPolyPolygon closes each part.
procedure AppendRing(ring: TJSONArray; const P: TProjector;
  pts: TList<TPointF>; counts: TList<Integer>);
var
  i, n: Integer;
  pt: TJSONArray;
begin
  n := ring.Count;
  if n < 4 then Exit;
  for i := 0 to n - 2 do
  begin
    pt := ring.Items[i] as TJSONArray;
    pts.Add(ProjectPoint(P, (pt.Items[0] as TJSONNumber).AsDouble,
                            (pt.Items[1] as TJSONNumber).AsDouble));
  end;
  counts.Add(n - 1);
end;

procedure DrawFeature(pdf: TsmPDF; feature: TJSONObject; const P: TProjector);
var
  geom, props: TJSONObject;
  gType, fillStr, strokeStr: string;
  fillAlpha: Double;
  fillColor, strokeColor: TColor;
  coords, poly: TJSONArray;
  i, j: Integer;
  pts: TList<TPointF>;
  counts: TList<Integer>;
  v: TJSONValue;
begin
  geom  := feature.GetValue('geometry')   as TJSONObject;
  props := feature.GetValue('properties') as TJSONObject;

  fillStr   := '#CCCCCC';
  fillAlpha := 0.4;
  strokeStr := '#888888';

  v := props.GetValue('fill');
  if v is TJSONString then fillStr   := TJSONString(v).Value;
  v := props.GetValue('fill-opacity');
  if v is TJSONNumber then fillAlpha := TJSONNumber(v).AsDouble;
  v := props.GetValue('stroke');
  if v is TJSONString then strokeStr := TJSONString(v).Value;

  fillColor   := BlendOnWhite(HexToColor(fillStr), fillAlpha);
  strokeColor := HexToColor(strokeStr);

  pdf.Brush.Style := brushSolid;
  pdf.Brush.Color := fillColor;
  pdf.Pen.Style   := penSolid;
  pdf.Pen.Color   := strokeColor;
  pdf.Pen.Width   := 0.3;

  gType  := (geom.GetValue('type')        as TJSONString).Value;
  coords :=  geom.GetValue('coordinates') as TJSONArray;

  pts    := TList<TPointF>.Create;
  counts := TList<Integer>.Create;
  try
    if gType = 'Polygon' then
    begin
      for i := 0 to coords.Count - 1 do
        AppendRing(coords.Items[i] as TJSONArray, P, pts, counts);
    end
    else if gType = 'MultiPolygon' then
    begin
      for i := 0 to coords.Count - 1 do
      begin
        poly := coords.Items[i] as TJSONArray;
        for j := 0 to poly.Count - 1 do
          AppendRing(poly.Items[j] as TJSONArray, P, pts, counts);
      end;
    end;

    if counts.Count > 0 then
      pdf.DrawPolyPolygon(pts.ToArray, counts.ToArray, frEvenOdd);
  finally
    counts.Free;
    pts.Free;
  end;
end;

procedure DrawTitle(pdf: TsmPDF; APageW, ADpi: Integer);
var
  topPx, bottomPx: Integer;
begin
  topPx    := Round(TITLE_TOP_PT    * ADpi / 72);
  bottomPx := Round(TITLE_BOTTOM_PT * ADpi / 72);
  pdf.Font.Name    := 'Helvetica';
  pdf.Font.Bold    := True;
  pdf.Font.Italics := False;
  pdf.Font.Size    := 28;
  pdf.Font.Color   := $00404040;
  pdf.DrawText('Sales Territories',
    TRect.Create(0, topPx, APageW, bottomPx), taCenter);
end;

procedure RenderMap(pdf: TsmPDF; root: TJSONObject; APageW, APageH, ADpi: Integer);
var
  features: TJSONArray;
  feature:  TJSONObject;
  bounds:   TBounds;
  proj:     TProjector;
  i:        Integer;
begin
  features := root.GetValue('features') as TJSONArray;

  bounds.MinLon   :=  MaxDouble;
  bounds.MaxLon   := -MaxDouble;
  bounds.MinMercY :=  MaxDouble;
  bounds.MaxMercY := -MaxDouble;

  for i := 0 to features.Count - 1 do
  begin
    feature := features.Items[i] as TJSONObject;
    UpdateBoundsForFeature(feature.GetValue('geometry') as TJSONObject, bounds);
  end;

  proj := MakeProjector(bounds, APageW, APageH, ADpi);

  for i := 0 to features.Count - 1 do
  begin
    feature := features.Items[i] as TJSONObject;
    DrawFeature(pdf, feature, proj);
  end;
end;

function FindGeoJson(const AExeDir: string): string;
var
  candidates: array[0..2] of string;
  i: Integer;
begin
  candidates[0] := TPath.Combine(AExeDir, 'Sales-Territories.geojson');
  candidates[1] := TPath.Combine(TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(AExeDir)),
                                 'Sales-Territories.geojson');
  candidates[2] := TPath.Combine(AExeDir, '..\Sales-Territories.geojson');
  for i := Low(candidates) to High(candidates) do
    if FileExists(candidates[i]) then Exit(candidates[i]);
  Result := '';
end;

var
  pdf:        TsmPDF;
  exeDir:     string;
  geoPath:    string;
  outFile:    string;
  jsonText:   string;
  root:       TJSONValue;
  pageW:      Integer;
  pageH:      Integer;
  t0, t1:     TDateTime;
  nBytes:     Int64;
begin
  try
    exeDir  := ExtractFilePath(ParamStr(0));
    geoPath := FindGeoJson(exeDir);
    if geoPath = '' then
      raise Exception.CreateFmt('GeoJSON not found near %s', [exeDir]);
    outFile := TPath.Combine(exeDir, 'sales-territories.pdf');

    Writeln('Reading ', geoPath);
    t0 := Now;
    jsonText := TFile.ReadAllText(geoPath, TEncoding.UTF8);
    Writeln(Format('  %d chars in %.1fs', [Length(jsonText), (Now - t0) * 86400]));

    Writeln('Parsing JSON');
    t0 := Now;
    root := TJSONObject.ParseJSONValue(jsonText);
    if root = nil then raise Exception.Create('Failed to parse GeoJSON');
    SetLength(jsonText, 0);
    Writeln(Format('  parsed in %.1fs', [(Now - t0) * 86400]));

    try
      pdf := TsmPDF.Create;
      try
        pdf.NewPage(psA3, poLandscape, 300);
        pageW := pdf.Width;
        pageH := pdf.Height;
        Writeln(Format('Page: %d x %d', [pageW, pageH]));

        DrawTitle(pdf, pageW, pdf.DPI);

        Writeln('Rendering map');
        t0 := Now;
        RenderMap(pdf, root as TJSONObject, pageW, pageH, pdf.DPI);
        Writeln(Format('  rendered in %.1fs', [(Now - t0) * 86400]));

        Writeln('Saving PDF');
        t0 := Now;
        nBytes := pdf.Save(outFile);
        t1 := Now;
        Writeln(Format('  saved in %.1fs', [(t1 - t0) * 86400]));
      finally
        pdf.Free;
      end;
    finally
      root.Free;
    end;

    Writeln('OK: wrote ', outFile);
    Writeln('     bytes: ', nBytes);
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
