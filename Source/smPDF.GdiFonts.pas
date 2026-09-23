unit smPDF.GdiFonts;

// Installed-font access through GDI. Asking GDI for (family, weight, italic)
// gives exactly the face a GDI TextOut would draw, wherever it is installed:
// system or per-user fonts, standalone .ttf files or members of a .ttc
// collection. Each call uses its own memory DC, so separate threads (each
// with its own TsmPDF) can load fonts concurrently.

interface

uses
  SysUtils, Winapi.Windows;

type
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

    property DC: HDC read fDC;
    property FaceName: string read fFaceName;
  end;

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

function GdiLoadFontData(const AFamily: string; ABold, AItalic: Boolean;
  out AData: TBytes; out AFaceName: string): Boolean;
var
  ctx: TGdiFontContext;
  tags: TArray<AnsiString>;
  tables: TList<TSfntTable>;
  tag: AnsiString;
  data: TBytes;
begin
  AData := nil;
  AFaceName := '';
  Result := False;
  if Trim(AFamily) = '' then Exit;

  ctx := TGdiFontContext.Create(AFamily, ABold, AItalic);
  try
    AFaceName := ctx.FaceName;
    if not ctx.MatchesFamily(AFamily) then Exit;

    tags := ctx.TableTags;
    if Length(tags) = 0 then Exit;

    tables := TList<TSfntTable>.Create;
    try
      for tag in tags do
      begin
        // The digital signature no longer matches a rebuilt file.
        if tag = 'DSIG' then Continue;
        data := ctx.TableData(tag);
        if data <> nil then
          tables.Add(TSfntTable.Create(tag, data));
      end;
      if tables.Count = 0 then Exit;
      AData := BuildSfnt(tables.ToArray);
      Result := True;
    finally
      tables.Free;
    end;
  finally
    ctx.Free;
  end;
end;

end.
