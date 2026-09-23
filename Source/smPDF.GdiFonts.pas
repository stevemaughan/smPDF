unit smPDF.GdiFonts;

// Installed-font access through GDI. Asking GDI for (family, weight, italic)
// gives exactly the face a GDI TextOut would draw, wherever it is installed:
// system or per-user fonts, standalone .ttf files or members of a .ttc
// collection. Each call uses its own memory DC, so separate threads (each
// with its own TsmPDF) can load fonts concurrently.

interface

uses
  SysUtils, Types, Winapi.Windows;

type
  TGlyphOutlineCommand = (gcMoveTo, gcLineTo, gcCurveTo, gcClose);

  // A glyph outline in font units (y up, origin on the baseline at the pen
  // position). gcCurveTo consumes three points: two controls and the end.
  TGlyphOutline = record
    Commands: TArray<TGlyphOutlineCommand>;
    Points:   TArray<TPointF>;
  end;

  // A font selected into a private memory DC. Free releases both.
  TGdiFontContext = class
  strict private
    fDC:      HDC;
    fFont:    HFONT;
    fOldFont: HGDIOBJ;
    fFaceName: string;
  public
    // AEmHeight is the character height in device units (lfHeight = -AEmHeight).
    constructor Create(const AFamily: string; ABold, AItalic: Boolean; AEmHeight: Integer = 2048);
    destructor Destroy; override;

    // True when GDI matched AFamily itself rather than a substitute.
    function MatchesFamily(const AFamily: string): Boolean;
    // One sfnt table, or nil when the font has none.
    function TableData(const ATag: AnsiString): TBytes;
    // Tags listed in the selected font's own table directory.
    function TableTags: TArray<AnsiString>;
    // The unhinted outline of a glyph id, in units of the em height the
    // context was created with. False for glyphs GDI cannot outline.
    function GlyphOutline(AGlyph: Word; out AOutline: TGlyphOutline): Boolean;

    property DC: HDC read fDC;
    property FaceName: string read fFaceName;
  end;

// True when GDI has a TrueType/OpenType family of this name (no data is read).
function GdiFontInstalled(const AFamily: string): Boolean;

// Load the face GDI selects for (AFamily, ABold, AItalic) as a standalone
// TrueType/OpenType file rebuilt from its tables. Returns False when the
// family is not installed (GDI would have substituted another font).
function GdiLoadFontData(const AFamily: string; ABold, AItalic: Boolean;
  out AData: TBytes; out AFaceName: string): Boolean;

implementation

uses
  Generics.Collections, smPDF.TTF;

function TagToDWord(const ATag: AnsiString): DWORD;
begin
  // GetFontData wants the tag bytes in file order read as a little-endian DWORD.
  Result :=  DWORD(Ord(ATag[1]))
         or (DWORD(Ord(ATag[2])) shl 8)
         or (DWORD(Ord(ATag[3])) shl 16)
         or (DWORD(Ord(ATag[4])) shl 24);
end;

{ TGdiFontContext }

constructor TGdiFontContext.Create(const AFamily: string; ABold, AItalic: Boolean;
  AEmHeight: Integer);
var
  lf: TLogFont;
  buf: array[0..LF_FACESIZE] of Char;
  n: Integer;
begin
  inherited Create;
  fDC := CreateCompatibleDC(0);
  if fDC = 0 then
    RaiseLastOSError;

  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -AEmHeight;
  if ABold then lf.lfWeight := FW_BOLD else lf.lfWeight := FW_NORMAL;
  lf.lfItalic := Ord(AItalic);
  lf.lfCharSet := DEFAULT_CHARSET;
  lf.lfOutPrecision := OUT_TT_ONLY_PRECIS;
  lf.lfClipPrecision := CLIP_DEFAULT_PRECIS;
  lf.lfQuality := DEFAULT_QUALITY;
  StrPLCopy(lf.lfFaceName, AFamily, LF_FACESIZE - 1);

  fFont := CreateFontIndirect(lf);
  if fFont = 0 then
    RaiseLastOSError;
  fOldFont := SelectObject(fDC, fFont);

  n := GetTextFace(fDC, Length(buf), @buf[0]);
  if n > 0 then
    fFaceName := string(PChar(@buf[0]))
  else
    fFaceName := '';
end;

destructor TGdiFontContext.Destroy;
begin
  if fDC <> 0 then
  begin
    if fOldFont <> 0 then
      SelectObject(fDC, fOldFont);
    DeleteDC(fDC);
  end;
  if fFont <> 0 then
    DeleteObject(fFont);
  inherited;
end;

function TGdiFontContext.MatchesFamily(const AFamily: string): Boolean;
begin
  Result := SameText(Trim(fFaceName), Trim(AFamily));
end;

function TGdiFontContext.TableData(const ATag: AnsiString): TBytes;
var
  size: DWORD;
begin
  Result := nil;
  size := GetFontData(fDC, TagToDWord(ATag), 0, nil, 0);
  if (size = GDI_ERROR) or (size = 0) then Exit;
  SetLength(Result, size);
  if GetFontData(fDC, TagToDWord(ATag), 0, @Result[0], size) <> size then
    Result := nil;
end;

function TGdiFontContext.TableTags: TArray<AnsiString>;
var
  header: array[0..11] of Byte;
  numTables, i: Integer;
  dir: TBytes;
  tag: AnsiString;
begin
  Result := nil;
  // Offset 0 is the start of the selected font's own offset table, even inside
  // a collection. The offsets it lists are collection-relative, so only the tags are used.
  if GetFontData(fDC, 0, 0, @header[0], SizeOf(header)) <> SizeOf(header) then Exit;
  numTables := (header[4] shl 8) or header[5];
  if numTables = 0 then Exit;
  SetLength(dir, numTables * 16);
  if GetFontData(fDC, 0, 12, @dir[0], Length(dir)) <> DWORD(Length(dir)) then Exit;
  SetLength(Result, numTables);
  for i := 0 to numTables - 1 do
  begin
    SetLength(tag, 4);
    tag[1] := AnsiChar(dir[i * 16]);
    tag[2] := AnsiChar(dir[i * 16 + 1]);
    tag[3] := AnsiChar(dir[i * 16 + 2]);
    tag[4] := AnsiChar(dir[i * 16 + 3]);
    Result[i] := tag;
  end;
end;

function FixedToDouble(const AValue: TFixed): Double;
begin
  Result := AValue.value + AValue.fract / 65536.0;
end;

function TGdiFontContext.GlyphOutline(AGlyph: Word; out AOutline: TGlyphOutline): Boolean;
const
  GGO_UNHINTED_    = $0100;
  TT_PRIM_CSPLINE_ = 3;  // cubic Bezier segments (CFF outlines); missing from Winapi.Windows
var
  gm: TGlyphMetrics;
  mat: TMat2;
  size: DWORD;
  buf: TBytes;
  p, polyEnd, recEnd: NativeInt;
  header: PTTPolygonHeader;
  curve: PTTPolyCurve;
  cmds: TList<TGlyphOutlineCommand>;
  pts: TList<TPointF>;
  cur, q0, q1, mid: TPointF;
  i, n: Integer;
  apfx: PPointFX;

  function PF(const AFx: TPointFX): TPointF;
  begin
    Result := TPointF.Create(FixedToDouble(AFx.x), FixedToDouble(AFx.y));
  end;

  function At(AIndex: Integer): TPointF;
  begin
    Result := PF(PPointFX(NativeInt(apfx) + AIndex * SizeOf(TPointFX))^);
  end;

  procedure Cubic(const C1, C2, E: TPointF);
  begin
    cmds.Add(gcCurveTo);
    pts.Add(C1);
    pts.Add(C2);
    pts.Add(E);
    cur := E;
  end;

  // A quadratic Bezier (P0, C, P2) is the cubic with controls two thirds of
  // the way from each end towards C.
  procedure Quad(const C, E: TPointF);
  begin
    Cubic(TPointF.Create(cur.X + 2 / 3 * (C.X - cur.X), cur.Y + 2 / 3 * (C.Y - cur.Y)),
          TPointF.Create(E.X + 2 / 3 * (C.X - E.X), E.Y + 2 / 3 * (C.Y - E.Y)), E);
  end;

begin
  AOutline.Commands := nil;
  AOutline.Points := nil;
  FillChar(mat, SizeOf(mat), 0);
  mat.eM11.value := 1;
  mat.eM22.value := 1;
  size := GetGlyphOutlineW(fDC, AGlyph, GGO_NATIVE or GGO_UNHINTED_ or GGO_GLYPH_INDEX, gm, 0, nil, mat);
  if size = GDI_ERROR then Exit(False);
  if size = 0 then Exit(True);  // a blank glyph such as space
  SetLength(buf, size);
  if GetGlyphOutlineW(fDC, AGlyph, GGO_NATIVE or GGO_UNHINTED_ or GGO_GLYPH_INDEX, gm, size,
    @buf[0], mat) = GDI_ERROR then Exit(False);

  cmds := TList<TGlyphOutlineCommand>.Create;
  pts := TList<TPointF>.Create;
  try
    p := 0;
    while p + SizeOf(TTTPolygonHeader) <= Integer(size) do
    begin
      header := PTTPolygonHeader(@buf[p]);
      polyEnd := p + NativeInt(header.cb);
      cur := PF(header.pfxStart);
      cmds.Add(gcMoveTo);
      pts.Add(cur);
      recEnd := p + SizeOf(TTTPolygonHeader);
      while recEnd < polyEnd do
      begin
        curve := PTTPolyCurve(@buf[recEnd]);
        n := curve.cpfx;
        apfx := @curve.apfx[0];
        case curve.wType of
          TT_PRIM_LINE:
            for i := 0 to n - 1 do
            begin
              cmds.Add(gcLineTo);
              cur := At(i);
              pts.Add(cur);
            end;
          TT_PRIM_QSPLINE:
            // B-spline: between consecutive off-curve controls the on-curve
            // point is implied at their midpoint; the last point is on-curve.
            for i := 0 to n - 2 do
            begin
              q0 := At(i);
              if i < n - 2 then
              begin
                q1 := At(i + 1);
                mid := TPointF.Create((q0.X + q1.X) / 2, (q0.Y + q1.Y) / 2);
                Quad(q0, mid);
              end
              else
                Quad(q0, At(n - 1));
            end;
          TT_PRIM_CSPLINE_:
            begin
              i := 0;
              while i + 2 < n do
              begin
                Cubic(At(i), At(i + 1), At(i + 2));
                Inc(i, 3);
              end;
            end;
        end;
        recEnd := recEnd + 4 + n * SizeOf(TPointFX);
      end;
      cmds.Add(gcClose);
      p := polyEnd;
    end;
    AOutline.Commands := cmds.ToArray;
    AOutline.Points := pts.ToArray;
    Result := True;
  finally
    pts.Free;
    cmds.Free;
  end;
end;

function GdiFontInstalled(const AFamily: string): Boolean;
var
  ctx: TGdiFontContext;
begin
  if Trim(AFamily) = '' then Exit(False);
  ctx := TGdiFontContext.Create(AFamily, False, False, 16);
  try
    Result := ctx.MatchesFamily(AFamily);
  finally
    ctx.Free;
  end;
end;

function GdiLoadFontData(const AFamily: string; ABold, AItalic: Boolean;
  out AData: TBytes; out AFaceName: string): Boolean;
var
  ctx: TGdiFontContext;
  allTags, tags: TArray<AnsiString>;
  lengths, offsets: TArray<Cardinal>;
  size, total: Cardinal;
  i, n: Integer;
begin
  AData := nil;
  AFaceName := '';
  Result := False;
  if Trim(AFamily) = '' then Exit;

  ctx := TGdiFontContext.Create(AFamily, ABold, AItalic);
  try
    AFaceName := ctx.FaceName;
    if not ctx.MatchesFamily(AFamily) then Exit;

    allTags := ctx.TableTags;
    SetLength(tags, Length(allTags));
    SetLength(lengths, Length(allTags));
    n := 0;
    for i := 0 to High(allTags) do
    begin
      // The digital signature no longer matches a rebuilt file.
      if allTags[i] = 'DSIG' then Continue;
      size := GetFontData(ctx.DC, TagToDWord(allTags[i]), 0, nil, 0);
      if (size = GDI_ERROR) or (size = 0) then Continue;
      tags[n] := allTags[i];
      lengths[n] := size;
      Inc(n);
    end;
    if n = 0 then Exit;
    SetLength(tags, n);
    SetLength(lengths, n);

    // Each table is read straight into its place in the rebuilt file, so a
    // large font is never held twice.
    total := SfntLayout(tags, lengths, offsets);
    SetLength(AData, total);
    FillChar(AData[0], total, 0);
    for i := 0 to n - 1 do
      if GetFontData(ctx.DC, TagToDWord(tags[i]), 0, @AData[offsets[i]], lengths[i]) <> lengths[i] then
      begin
        AData := nil;
        Exit;
      end;
    SfntFinish(AData, tags, offsets, lengths);
    Result := True;
  finally
    ctx.Free;
  end;
end;

end.
