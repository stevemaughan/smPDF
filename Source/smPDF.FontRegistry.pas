unit smPDF.FontRegistry;

// Per-document font resolution. Maps (family, bold, italic) to a face that can
// be written into the PDF: one of the 14 standard fonts, or an installed
// TrueType font loaded through GDI. Everything is cached per TsmPDF instance,
// so documents on different threads never share state.

interface

uses
  SysUtils, Classes, Generics.Collections, smPDF.Fonts, smPDF.TTF, smPDF.GdiFonts;

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
    fUsedGlyphs:  TDictionary<Word, Cardinal>;  // glyph id -> first code point drawn with it
    fOutlines:    TDictionary<Cardinal, TGlyphOutline>;  // glyph id + style bits -> outline
  public
    constructor CreateStandard(AFont: TStandardFont);
    // Takes ownership of ATTF.
    constructor CreateTrueType(ATTF: TTTFFont; const AKey, AGdiFamily: string;
      AGdiBold, AGdiItalic: Boolean);
    destructor Destroy; override;

    // Note that AGlyph was drawn for ACodepoint. The first code point seen for
    // a glyph is the one text extraction will report.
    procedure RecordGlyph(AGlyph: Word; ACodepoint: Cardinal);
    // Glyph ids drawn so far, ascending.
    function UsedGlyphs: TArray<Word>;
    function UsedGlyphCodepoint(AGlyph: Word): Cardinal;
    function HasUsedGlyphs: Boolean;

    // Glyph outlines fetched from GDI for DrawTextOutlines, in font units,
    // per requested style: when a family has no bold or italic face GDI
    // simulates it in the outline, so the same glyph differs by style.
    function TryGetOutline(AGlyph: Word; ABold, AItalic: Boolean; out AOutline: TGlyphOutline): Boolean;
    procedure AddOutline(AGlyph: Word; ABold, AItalic: Boolean; const AOutline: TGlyphOutline);

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

  // A stretch of text drawn in one font.
  TPDFGlyphRun = record
    Resolution: TPDFFontResolution;
    // Glyph ids for TrueType faces, WinAnsi bytes for the standard fonts.
    Codes:      TArray<Word>;
    AdvanceEm:  Double;          // total advance, in ems
  end;
  TPDFGlyphRuns = TArray<TPDFGlyphRun>;

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

    // Encode ACount code points starting at AStart in the resolved face. With
    // ARecord (drawing, not measuring) the glyphs are recorded for embedding
    // and each character the face cannot show adds one warning.
    function EncodeRun(const AResolution: TPDFFontResolution; const ACodepoints: TArray<Cardinal>;
      AStart, ACount: Integer; ARecord: Boolean): TPDFGlyphRun;
    // True when AFace can show ACodepoint with a real glyph.
    function FaceHasGlyph(AFace: TPDFFontFace; ACodepoint: Cardinal): Boolean;
  end;

// Code points of a Delphi string: surrogate pairs combined, lone surrogates
// replaced by U+FFFD, control characters by a space.
function TextToCodepoints(const AText: string): TArray<Cardinal>;

// Characters that can be broken between when wrapping (CJK ideographs, kana,
// Hangul and their punctuation), since those scripts do not use spaces.
function IsCJKCodepoint(ACodepoint: Cardinal): Boolean;

function CodepointToString(ACodepoint: Cardinal): string;

implementation

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
  fOutlines.Free;
  fUsedGlyphs.Free;
  fTTF.Free;
  inherited;
end;

procedure TPDFFontFace.RecordGlyph(AGlyph: Word; ACodepoint: Cardinal);
begin
  if fUsedGlyphs = nil then
    fUsedGlyphs := TDictionary<Word, Cardinal>.Create;
  if not fUsedGlyphs.ContainsKey(AGlyph) then
    fUsedGlyphs.Add(AGlyph, ACodepoint);
end;

function TPDFFontFace.UsedGlyphs: TArray<Word>;
begin
  if fUsedGlyphs = nil then Exit(nil);
  Result := fUsedGlyphs.Keys.ToArray;
  TArray.Sort<Word>(Result);
end;

function TPDFFontFace.UsedGlyphCodepoint(AGlyph: Word): Cardinal;
begin
  if (fUsedGlyphs = nil) or not fUsedGlyphs.TryGetValue(AGlyph, Result) then
    Result := 0;
end;

function TPDFFontFace.HasUsedGlyphs: Boolean;
begin
  Result := (fUsedGlyphs <> nil) and (fUsedGlyphs.Count > 0);
end;

function OutlineKey(AGlyph: Word; ABold, AItalic: Boolean): Cardinal;
begin
  Result := AGlyph or (Cardinal(Ord(ABold)) shl 16) or (Cardinal(Ord(AItalic)) shl 17);
end;

function TPDFFontFace.TryGetOutline(AGlyph: Word; ABold, AItalic: Boolean;
  out AOutline: TGlyphOutline): Boolean;
begin
  Result := (fOutlines <> nil) and fOutlines.TryGetValue(OutlineKey(AGlyph, ABold, AItalic), AOutline);
end;

procedure TPDFFontFace.AddOutline(AGlyph: Word; ABold, AItalic: Boolean;
  const AOutline: TGlyphOutline);
begin
  if fOutlines = nil then
    fOutlines := TDictionary<Cardinal, TGlyphOutline>.Create;
  fOutlines.AddOrSetValue(OutlineKey(AGlyph, ABold, AItalic), AOutline);
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

function TextToCodepoints(const AText: string): TArray<Cardinal>;
var
  i, n: Integer;
  c: Char;
begin
  SetLength(Result, Length(AText));
  n := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    c := AText[i];
    if (c >= #$D800) and (c <= #$DBFF) and (i < Length(AText)) and
       (AText[i + 1] >= #$DC00) and (AText[i + 1] <= #$DFFF) then
    begin
      Result[n] := $10000 + ((Cardinal(Ord(c)) - $D800) shl 10) + (Cardinal(Ord(AText[i + 1])) - $DC00);
      Inc(i, 2);
    end
    else
    begin
      if (c >= #$D800) and (c <= #$DFFF) then
        Result[n] := $FFFD
      else if c < ' ' then
        Result[n] := $20
      else
        Result[n] := Ord(c);
      Inc(i);
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function IsCJKCodepoint(ACodepoint: Cardinal): Boolean;
begin
  case ACodepoint of
    $1100..$11FF,    // Hangul Jamo
    $2E80..$2FDF,    // CJK radicals, Kangxi radicals
    $3000..$303F,    // CJK symbols and punctuation
    $3040..$30FF,    // Hiragana, Katakana
    $3100..$31FF,    // Bopomofo, Hangul compatibility Jamo, Katakana extensions
    $3200..$33FF,    // Enclosed CJK, CJK compatibility
    $3400..$4DBF,    // CJK extension A
    $4E00..$9FFF,    // CJK unified ideographs
    $A960..$A97F,    // Hangul Jamo extended A
    $AC00..$D7AF,    // Hangul syllables
    $F900..$FAFF,    // CJK compatibility ideographs
    $FF00..$FFEF,    // Halfwidth and fullwidth forms
    $20000..$3FFFF:  // CJK extensions B onwards
      Result := True;
  else
    Result := False;
  end;
end;

function CodepointToString(ACodepoint: Cardinal): string;
begin
  if ACodepoint > $FFFF then
    Result := Char($D800 + ((ACodepoint - $10000) shr 10)) + Char($DC00 + ((ACodepoint - $10000) and $3FF))
  else
    Result := Char(ACodepoint);
end;

function FaceDisplayName(AFace: TPDFFontFace): string;
begin
  if AFace.IsStandard then
    Result := StandardFontPdfName(AFace.StdFont)
  else if AFace.GdiFamily <> '' then
    Result := AFace.GdiFamily
  else
    Result := AFace.TTF.Metrics.PostScriptName;
end;

function TPDFFontRegistry.FaceHasGlyph(AFace: TPDFFontFace; ACodepoint: Cardinal): Boolean;
var
  b: Byte;
begin
  if AFace.IsStandard then
    Result := UnicodeToWinAnsi(ACodepoint, b)
  else
    Result := AFace.TTF.GlyphIndex(ACodepoint) <> 0;
end;

function TPDFFontRegistry.EncodeRun(const AResolution: TPDFFontResolution;
  const ACodepoints: TArray<Cardinal>; AStart, ACount: Integer; ARecord: Boolean): TPDFGlyphRun;
var
  face: TPDFFontFace;
  i: Integer;
  cp: Cardinal;
  b: Byte;
  gid: Word;
  units: Int64;
begin
  face := AResolution.Face;
  Result.Resolution := AResolution;
  SetLength(Result.Codes, ACount);
  units := 0;
  for i := 0 to ACount - 1 do
  begin
    cp := ACodepoints[AStart + i];
    if face.IsStandard then
    begin
      if not UnicodeToWinAnsi(cp, b) and ARecord then
        Warn(Format('%s cannot show U+%.4X (%s): the 14 standard PDF fonts are WinAnsi only, ' +
          'so it was drawn as "?". Use a TrueType font such as Arial.',
          [FaceDisplayName(face), cp, CodepointToString(cp)]));
      Result.Codes[i] := b;
      Inc(units, StandardFontCharWidth(face.StdFont, b));
    end
    else
    begin
      gid := face.TTF.GlyphIndex(cp);
      if (gid = 0) and ARecord then
        Warn(Format('Font "%s" has no glyph for U+%.4X (%s); it was drawn as the font''s missing-glyph box.',
          [FaceDisplayName(face), cp, CodepointToString(cp)]));
      Result.Codes[i] := gid;
      Inc(units, face.TTF.GlyphAdvance(gid));
      if ARecord then
        face.RecordGlyph(gid, cp);
    end;
  end;
  if face.IsStandard then
    Result.AdvanceEm := units / 1000.0
  else
    Result.AdvanceEm := units / face.TTF.Metrics.UnitsPerEm;
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
