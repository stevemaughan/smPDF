unit smPDF.FontRegistry;

// Per-document font resolution. Maps (family, bold, italic) to a face that can
// be written into the PDF: one of the 14 standard fonts, or an installed
// TrueType font loaded through GDI. Everything is cached per TsmPDF instance,
// so documents on different threads never share state.

interface

uses
  SysUtils, Classes, Generics.Collections, smPDF.Fonts, smPDF.TTF;

type
  TPDFFontFace = class
  strict private
    fKey:         string;
    fIsStandard:  Boolean;
    fStdFont:     TStandardFont;
    fTTF:         TTTFFont;
    fGdiFamily:   string;
    fGdiBold:     Boolean;
    fGdiItalic:   Boolean;
  public
    constructor CreateStandard(AFont: TStandardFont);
    // Takes ownership of ATTF.
    constructor CreateTrueType(ATTF: TTTFFont; const AKey, AGdiFamily: string;
      AGdiBold, AGdiItalic: Boolean);
    destructor Destroy; override;

    // Unique within a document; used as the page resource key.
    property Key:        string        read fKey;
    property IsStandard: Boolean       read fIsStandard;
    property StdFont:    TStandardFont read fStdFont;
    property TTF:        TTTFFont      read fTTF;
    // The GDI request that produced this face (for glyph outlines).
    property GdiFamily:  string        read fGdiFamily;
    property GdiBold:    Boolean       read fGdiBold;
    property GdiItalic:  Boolean       read fGdiItalic;
  end;

  TPDFFontResolution = record
    Face:            TPDFFontFace;
    // GDI would synthesise these styles because the family has no such face.
    SyntheticBold:   Boolean;
    SyntheticItalic: Boolean;
  end;

  TPDFFontRegistry = class
  strict private
    fWarnings:     TStrings;
    fFaces:        TObjectList<TPDFFontFace>;
    fByKey:        TDictionary<string, TPDFFontFace>;
    fCache:        TDictionary<string, TPDFFontResolution>;
    fOutlineCache: TDictionary<string, TPDFFontResolution>;
    fProblems:     TDictionary<string, string>;  // cache key -> why the family could not be loaded

    function StandardFace(AFont: TStandardFont): TPDFFontFace;
    function Fallback(ABold, AItalic: Boolean): TPDFFontResolution;
    function LoadTrueType(const AFamily: string; ABold, AItalic: Boolean;
      out AResolution: TPDFFontResolution; out AProblem: string): Boolean;
  public
    constructor Create(AWarnings: TStrings);
    destructor Destroy; override;

    // The face to embed for text. Unknown, non-TrueType or restricted fonts
    // resolve to Helvetica and add one warning each.
    function Resolve(const AFamily: string; ABold, AItalic: Boolean): TPDFFontResolution;
    // Like Resolve, but keeps an installed font even when it cannot be
    // embedded, because drawing its outlines is still allowed. Face is nil
    // when the family is not installed at all.
    function ResolveForOutlines(const AFamily: string; ABold, AItalic: Boolean): TPDFFontResolution;
    function FindFace(const AKey: string; out AFace: TPDFFontFace): Boolean;
    function Faces: TArray<TPDFFontFace>;

    // Adds AMessage to the warnings unless it is already there.
    procedure Warn(const AMessage: string);
  end;

implementation

uses
  smPDF.GdiFonts;

{ TPDFFontFace }

constructor TPDFFontFace.CreateStandard(AFont: TStandardFont);
begin
  inherited Create;
  fIsStandard := True;
  fStdFont    := AFont;
  fKey        := StandardFontPdfName(AFont);
end;

constructor TPDFFontFace.CreateTrueType(ATTF: TTTFFont; const AKey, AGdiFamily: string;
  AGdiBold, AGdiItalic: Boolean);
begin
  inherited Create;
  fIsStandard := False;
  fStdFont    := sfHelvetica;
  fTTF        := ATTF;
  fKey        := AKey;
  fGdiFamily  := AGdiFamily;
  fGdiBold    := AGdiBold;
  fGdiItalic  := AGdiItalic;
end;

destructor TPDFFontFace.Destroy;
begin
  fTTF.Free;
  inherited;
end;

{ TPDFFontRegistry }

constructor TPDFFontRegistry.Create(AWarnings: TStrings);
begin
  inherited Create;
  fWarnings     := AWarnings;
  fFaces        := TObjectList<TPDFFontFace>.Create(True);
  fByKey        := TDictionary<string, TPDFFontFace>.Create;
  fCache        := TDictionary<string, TPDFFontResolution>.Create;
  fOutlineCache := TDictionary<string, TPDFFontResolution>.Create;
  fProblems     := TDictionary<string, string>.Create;
end;

destructor TPDFFontRegistry.Destroy;
begin
  fProblems.Free;
  fOutlineCache.Free;
  fCache.Free;
  fByKey.Free;
  fFaces.Free;
  inherited;
end;

procedure TPDFFontRegistry.Warn(const AMessage: string);
begin
  if (fWarnings <> nil) and (fWarnings.IndexOf(AMessage) < 0) then
    fWarnings.Add(AMessage);
end;

function TPDFFontRegistry.StandardFace(AFont: TStandardFont): TPDFFontFace;
var
  key: string;
begin
  key := StandardFontPdfName(AFont);
  if fByKey.TryGetValue(key, Result) then Exit;
  Result := TPDFFontFace.CreateStandard(AFont);
  fFaces.Add(Result);
  fByKey.Add(key, Result);
end;

function TPDFFontRegistry.Fallback(ABold, AItalic: Boolean): TPDFFontResolution;
begin
  Result.Face := StandardFace(ResolveStandardFont('Helvetica', ABold, AItalic));
  Result.SyntheticBold   := False;
  Result.SyntheticItalic := False;
end;

function TPDFFontRegistry.LoadTrueType(const AFamily: string; ABold, AItalic: Boolean;
  out AResolution: TPDFFontResolution; out AProblem: string): Boolean;
var
  data: TBytes;
  faceName, key: string;
  ttf: TTTFFont;
  face: TPDFFontFace;
begin
  AResolution.Face := nil;
  AResolution.SyntheticBold := False;
  AResolution.SyntheticItalic := False;
  AProblem := '';

  if not GdiLoadFontData(AFamily, ABold, AItalic, data, faceName) then
  begin
    AProblem := 'is not installed';
    Exit(False);
  end;

  try
    ttf := TTTFFont.CreateFromBytes(data, AFamily);
  except
    on E: Exception do
    begin
      AProblem := 'could not be read (' + E.Message + ')';
      Exit(False);
    end;
  end;

  key := ttf.Metrics.PostScriptName;
  if key = '' then key := StringReplace(AFamily, ' ', '', [rfReplaceAll]);
  if fByKey.TryGetValue(key, face) and (face.IsStandard or (face.TTF.Metrics.NumGlyphs <> ttf.Metrics.NumGlyphs)) then
    key := 'TT' + IntToStr(fFaces.Count) + '+' + key;

  if fByKey.TryGetValue(key, face) then
    ttf.Free
  else
  begin
    face := TPDFFontFace.CreateTrueType(ttf, key, AFamily, ABold, AItalic);
    fFaces.Add(face);
    fByKey.Add(key, face);
  end;

  AResolution.Face := face;
  AResolution.SyntheticBold   := ABold and (face.TTF.Metrics.UsWeightClass < 600);
  AResolution.SyntheticItalic := AItalic and not face.TTF.Metrics.IsItalic;
  Result := True;
end;

function CacheKey(const AFamily: string; ABold, AItalic: Boolean): string;
begin
  Result := LowerCase(Trim(AFamily)) + '|' + BoolToStr(ABold, True) + '|' + BoolToStr(AItalic, True);
end;

function TPDFFontRegistry.ResolveForOutlines(const AFamily: string; ABold, AItalic: Boolean): TPDFFontResolution;
var
  key, problem: string;
begin
  key := CacheKey(AFamily, ABold, AItalic);
  if fOutlineCache.TryGetValue(key, Result) then Exit;
  if not LoadTrueType(AFamily, ABold, AItalic, Result, problem) then
  begin
    Result.Face := nil;
    fProblems.AddOrSetValue(key, problem);
  end;
  fOutlineCache.Add(key, Result);
end;

function TPDFFontRegistry.Resolve(const AFamily: string; ABold, AItalic: Boolean): TPDFFontResolution;
var
  key, problem: string;
  std: TStandardFont;
begin
  key := CacheKey(AFamily, ABold, AItalic);
  if fCache.TryGetValue(key, Result) then Exit;

  if TryResolveStandardFont(AFamily, ABold, AItalic, std) then
  begin
    Result.Face := StandardFace(std);
    Result.SyntheticBold   := False;
    Result.SyntheticItalic := False;
  end
  else
  begin
    Result := ResolveForOutlines(AFamily, ABold, AItalic);
    if Result.Face = nil then
    begin
      if not fProblems.TryGetValue(key, problem) then problem := 'is not installed';
      Warn(Format('Font "%s" %s; used Helvetica.', [AFamily, problem]));
      Result := Fallback(ABold, AItalic);
    end
    else if not Result.Face.TTF.HasTrueTypeOutlines then
    begin
      Warn(Format('Font "%s" has PostScript (CFF) outlines, which cannot be embedded; used Helvetica.',
        [AFamily]));
      Result := Fallback(ABold, AItalic);
    end
    else if Result.Face.TTF.EmbeddingRestricted then
    begin
      Warn(Format('Font "%s" does not permit embedding (restricted licence); used Helvetica.',
        [AFamily]));
      Result := Fallback(ABold, AItalic);
    end;
  end;
  fCache.Add(key, Result);
end;

function TPDFFontRegistry.FindFace(const AKey: string; out AFace: TPDFFontFace): Boolean;
begin
  Result := fByKey.TryGetValue(AKey, AFace);
end;

function TPDFFontRegistry.Faces: TArray<TPDFFontFace>;
begin
  Result := fFaces.ToArray;
end;

end.
