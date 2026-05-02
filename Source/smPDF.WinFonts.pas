unit smPDF.WinFonts;

interface

// Find an installed Windows TrueType font by family + bold/italic.
// Returns the full path to a .ttf file, or '' if no match.
// Phase 4 deliberately rejects .otf (CFF-flavour OpenType) and .ttc (collections);
// they would need separate parsing paths.
function LookupSystemTTFPath(const AFamily: string; ABold, AItalic: Boolean): string;

// Force a re-scan of the registry on the next lookup. Mainly for tests.
procedure ResetSystemFontCache;

implementation

uses
  SysUtils, Classes, Generics.Collections, StrUtils, IOUtils,
  Winapi.Windows, System.Win.Registry;

type
  TFontMap = TDictionary<string, string>;  // lower-cased "family suffix" -> full path

var
  GFontMap:   TFontMap;
  GFontsDir:  string;

function ResolveFontsDir: string;
var
  buf: array[0..MAX_PATH] of WideChar;
  n: Cardinal;
begin
  n := GetWindowsDirectoryW(@buf[0], Length(buf));
  if (n > 0) and (n < Cardinal(Length(buf))) then
    Result := IncludeTrailingPathDelimiter(string(PWideChar(@buf[0]))) + 'Fonts\'
  else
    Result := 'C:\Windows\Fonts\';
end;

procedure EnsureLoaded;
var
  reg: TRegistry;
  values: TStringList;
  i: Integer;
  rawKey, rawValue, normalised, ext, fullPath: string;
begin
  if Assigned(GFontMap) then Exit;
  GFontMap  := TFontMap.Create;
  GFontsDir := ResolveFontsDir;

  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;
    if not reg.OpenKeyReadOnly(
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') then
      Exit;
    values := TStringList.Create;
    try
      reg.GetValueNames(values);
      for i := 0 to values.Count - 1 do
      begin
        rawKey   := values[i];
        rawValue := reg.ReadString(rawKey);
        if rawValue = '' then Continue;

        ext := LowerCase(ExtractFileExt(rawValue));
        if (ext = '.ttc') or (ext = '.otf') then Continue;
        if (ext <> '.ttf') then Continue;

        // Strip trailing " (TrueType)" / " (OpenType)" suffix the registry uses.
        normalised := rawKey;
        if EndsText(' (TrueType)', normalised) then
          normalised := Copy(normalised, 1, Length(normalised) - Length(' (TrueType)'))
        else if EndsText(' (OpenType)', normalised) then
          normalised := Copy(normalised, 1, Length(normalised) - Length(' (OpenType)'));

        if TPath.IsPathRooted(rawValue) then
          fullPath := rawValue
        else
          fullPath := GFontsDir + rawValue;

        GFontMap.AddOrSetValue(LowerCase(Trim(normalised)), fullPath);
      end;
    finally
      values.Free;
    end;
    reg.CloseKey;
  finally
    reg.Free;
  end;
end;

function TryGet(const AKey: string; out APath: string): Boolean;
begin
  Result := GFontMap.TryGetValue(LowerCase(Trim(AKey)), APath);
  if Result and not TFile.Exists(APath) then
    Result := False;
end;

function LookupSystemTTFPath(const AFamily: string; ABold, AItalic: Boolean): string;
begin
  EnsureLoaded;
  Result := '';

  if ABold and AItalic then
  begin
    if TryGet(AFamily + ' Bold Italic',  Result) then Exit;
    if TryGet(AFamily + ' Bold Oblique', Result) then Exit;
    if TryGet(AFamily + ' BoldItalic',   Result) then Exit;
  end
  else if ABold then
  begin
    if TryGet(AFamily + ' Bold',         Result) then Exit;
  end
  else if AItalic then
  begin
    if TryGet(AFamily + ' Italic',       Result) then Exit;
    if TryGet(AFamily + ' Oblique',      Result) then Exit;
  end;

  // Fall through to plain family name regardless of style request.
  if TryGet(AFamily,                Result) then Exit;
  if TryGet(AFamily + ' Regular',   Result) then Exit;

  Result := '';
end;

procedure ResetSystemFontCache;
begin
  FreeAndNil(GFontMap);
end;

initialization

finalization
  FreeAndNil(GFontMap);

end.
