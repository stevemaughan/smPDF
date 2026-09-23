unit smPDF.Subset;

// TrueType subsetting for embedding. The subset is "hollow": it keeps the
// original glyph count and every glyph id, so hmtx stays valid and glyph ids
// can be used directly as CIDs, but only the glyphs actually drawn (plus the
// components of composite glyphs, and .notdef) carry outline data. Every other
// loca entry is zero-length. Tables a PDF viewer does not need are dropped.

// Checksums and hashes rely on 32-bit wrap-around.
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  SysUtils, Generics.Collections, smPDF.TTF;

type
  TSubsetCharMapping = record
    Codepoint: Cardinal;
    GlyphId:   Word;
  end;

// The glyphs the subset must carry: .notdef, AUsed, and every component of a
// composite glyph among them, recursively. Sorted ascending.
function SubsetGlyphClosure(ATTF: TTTFFont; const AUsed: array of Word): TArray<Word>;

// Build the subset font file. ACharMap becomes the subset's (3,1) cmap (BMP
// code points only); AFontName is written as its PostScript name.
function BuildHollowSubset(ATTF: TTTFFont; const AUsed: array of Word;
  const ACharMap: array of TSubsetCharMapping; const AFontName: string): TBytes;

// Six upper-case letters identifying a subset, derived from the font name and
// the glyph set so the same subset always gets the same tag.
function MakeSubsetTag(const APostScriptName: string; const AGlyphs: array of Word): string;

implementation

uses
  Generics.Defaults;

procedure PutU16(var ABuf: TBytes; AOffset: Integer; AValue: Word);
begin
  ABuf[AOffset]     := Byte(AValue shr 8);
  ABuf[AOffset + 1] := Byte(AValue);
end;

procedure PutU32(var ABuf: TBytes; AOffset: Integer; AValue: Cardinal);
begin
  ABuf[AOffset]     := Byte(AValue shr 24);
  ABuf[AOffset + 1] := Byte(AValue shr 16);
  ABuf[AOffset + 2] := Byte(AValue shr 8);
  ABuf[AOffset + 3] := Byte(AValue);
end;

function SubsetGlyphClosure(ATTF: TTTFFont; const AUsed: array of Word): TArray<Word>;
var
  keep: TDictionary<Word, Boolean>;
  work: TStack<Word>;
  gid, comp: Word;
  list: TList<Word>;
begin
  keep := TDictionary<Word, Boolean>.Create;
  work := TStack<Word>.Create;
  list := TList<Word>.Create;
  try
    work.Push(0);
    for gid in AUsed do
      work.Push(gid);
    while work.Count > 0 do
    begin
      gid := work.Pop;
      if (gid >= ATTF.Metrics.NumGlyphs) or keep.ContainsKey(gid) then Continue;
      keep.Add(gid, True);
      for comp in ATTF.GlyphComponents(gid) do
        work.Push(comp);
    end;
    list.AddRange(keep.Keys);
    list.Sort;
    Result := list.ToArray;
  finally
    list.Free;
    work.Free;
    keep.Free;
  end;
end;

function BuildGlyfAndLoca(ATTF: TTTFFont; const AKeep: TArray<Word>;
  out AGlyf, ALoca: TBytes): Boolean;
var
  src: TBytes;
  glyfStart, glyfLength: Cardinal;
  keep: array of Boolean;
  gid, n: Integer;
  offset, len, glyfSize: Cardinal;
  cur: Cardinal;
begin
  // Read outlines from the font file itself; copying glyf would double the
  // memory for a large CJK font.
  src := ATTF.Bytes;
  ATTF.TableRange('glyf', glyfStart, glyfLength);
  n := ATTF.Metrics.NumGlyphs;
  SetLength(keep, n);
  for gid in AKeep do
    if gid < n then keep[gid] := True;

  glyfSize := 0;
  for gid := 0 to n - 1 do
    if keep[gid] and ATTF.GlyphRange(gid, offset, len) then
      Inc(glyfSize, (len + 3) and not 3);

  SetLength(AGlyf, glyfSize);
  if glyfSize > 0 then FillChar(AGlyf[0], glyfSize, 0);
  SetLength(ALoca, (n + 1) * 4);
  cur := 0;
  for gid := 0 to n - 1 do
  begin
    PutU32(ALoca, gid * 4, cur);
    if keep[gid] and ATTF.GlyphRange(gid, offset, len) then
    begin
      if Int64(offset) + len <= glyfLength then
        Move(src[glyfStart + offset], AGlyf[cur], len);
      Inc(cur, (len + 3) and not 3);
    end;
  end;
  PutU32(ALoca, n * 4, cur);
  Result := True;
end;

// hmtx with advance and side bearing kept only for glyphs in the subset; the
// zeros compress to almost nothing and the widths the PDF uses come from /W.
function BuildHmtx(ATTF: TTTFFont; const AKeep: TArray<Word>): TBytes;
var
  gid: Word;
  keep: array of Boolean;
  src: TBytes;
  numHMetrics, n, i: Integer;
  hhea: TBytes;
begin
  src := ATTF.TableData('hmtx');
  hhea := ATTF.TableData('hhea');
  numHMetrics := (hhea[34] shl 8) or hhea[35];
  n := ATTF.Metrics.NumGlyphs;
  SetLength(keep, n);
  for gid in AKeep do
    if gid < n then keep[gid] := True;

  SetLength(Result, Length(src));
  if Length(src) > 0 then FillChar(Result[0], Length(src), 0);
  for i := 0 to n - 1 do
  begin
    if not keep[i] then Continue;
    if i < numHMetrics then
    begin
      if i * 4 + 4 <= Length(src) then
        Move(src[i * 4], Result[i * 4], 4);
    end
    else
    begin
      // lsb-only entries follow the long metrics
      if numHMetrics * 4 + (i - numHMetrics) * 2 + 2 <= Length(src) then
        Move(src[numHMetrics * 4 + (i - numHMetrics) * 2],
             Result[numHMetrics * 4 + (i - numHMetrics) * 2], 2);
    end;
  end;
  // The last long metric's advance applies to every lsb-only glyph, so keep it.
  if (numHMetrics > 0) and (numHMetrics * 4 <= Length(src)) then
    Move(src[(numHMetrics - 1) * 4], Result[(numHMetrics - 1) * 4], 2);
end;

function BuildCmapFormat4(const ACharMap: array of TSubsetCharMapping): TBytes;
type
  TSeg = record StartCode, EndCode: Word; Delta: Word; end;
var
  pairs: TList<TSubsetCharMapping>;
  segs: TList<TSeg>;
  m: TSubsetCharMapping;
  seg: TSeg;
  i, segCount, searchRange, entrySelector, subLen, p: Integer;
  lastCp: Integer;
begin
  pairs := TList<TSubsetCharMapping>.Create;
  segs  := TList<TSeg>.Create;
  try
    for m in ACharMap do
      if (m.Codepoint <= $FFFE) and (m.GlyphId <> 0) then
        pairs.Add(m);
    pairs.Sort(TComparer<TSubsetCharMapping>.Construct(
      function(const A, B: TSubsetCharMapping): Integer
      begin
        if A.Codepoint < B.Codepoint then Result := -1
        else if A.Codepoint > B.Codepoint then Result := 1
        else Result := 0;
      end));

    lastCp := -1;
    for m in pairs do
    begin
      if Integer(m.Codepoint) = lastCp then Continue;  // duplicate code point
      if (segs.Count > 0) and (Integer(m.Codepoint) = segs.Last.EndCode + 1) and
         (Word(m.GlyphId - m.Codepoint) = segs.Last.Delta) then
      begin
        seg := segs.Last;
        seg.EndCode := m.Codepoint;
        segs[segs.Count - 1] := seg;
      end
      else
      begin
        seg.StartCode := m.Codepoint;
        seg.EndCode   := m.Codepoint;
        seg.Delta     := Word(m.GlyphId - m.Codepoint);
        segs.Add(seg);
      end;
      lastCp := m.Codepoint;
    end;
    // Lengths are 16-bit: beyond this many segments write an empty map.
    // Glyphs are addressed by id through /CIDToGIDMap, and the text
    // mapping lives in /ToUnicode, so the embedded cmap is not needed.
    if segs.Count > 8000 then
      segs.Clear;
    seg.StartCode := $FFFF;
    seg.EndCode   := $FFFF;
    seg.Delta     := 1;
    segs.Add(seg);

    segCount := segs.Count;
    searchRange := 1;
    entrySelector := 0;
    while searchRange * 2 <= segCount do
    begin
      searchRange := searchRange * 2;
      Inc(entrySelector);
    end;
    searchRange := searchRange * 2;

    subLen := 16 + segCount * 8;
    SetLength(Result, 4 + 8 + subLen);
    FillChar(Result[0], Length(Result), 0);
    PutU16(Result, 0, 0);       // version
    PutU16(Result, 2, 1);       // one encoding record
    PutU16(Result, 4, 3);       // Windows
    PutU16(Result, 6, 1);       // Unicode BMP
    PutU32(Result, 8, 12);      // subtable offset
    p := 12;
    PutU16(Result, p, 4);
    PutU16(Result, p + 2, subLen);
    PutU16(Result, p + 4, 0);
    PutU16(Result, p + 6, segCount * 2);
    PutU16(Result, p + 8, searchRange);
    PutU16(Result, p + 10, entrySelector);
    PutU16(Result, p + 12, segCount * 2 - searchRange);
    for i := 0 to segCount - 1 do
    begin
      PutU16(Result, p + 14 + i * 2, segs[i].EndCode);
      PutU16(Result, p + 16 + segCount * 2 + i * 2, segs[i].StartCode);
      PutU16(Result, p + 16 + segCount * 4 + i * 2, segs[i].Delta);
      PutU16(Result, p + 16 + segCount * 6 + i * 2, 0);
    end;
  finally
    segs.Free;
    pairs.Free;
  end;
end;

function BuildNameTable(const AFamily, ASubfamily, APostScriptName: string): TBytes;
var
  names: array[0..4] of string;
  ids: array[0..4] of Word;
  i, count, strOff, cur, k: Integer;
  total: Integer;
begin
  names[0] := AFamily;                ids[0] := 1;
  names[1] := ASubfamily;             ids[1] := 2;
  names[2] := APostScriptName;        ids[2] := 3;
  names[3] := AFamily + ' ' + ASubfamily; ids[3] := 4;
  names[4] := APostScriptName;        ids[4] := 6;
  count := Length(names);
  strOff := 6 + count * 12;
  total := strOff;
  for i := 0 to count - 1 do
    Inc(total, Length(names[i]) * 2);
  SetLength(Result, total);
  FillChar(Result[0], total, 0);
  PutU16(Result, 0, 0);
  PutU16(Result, 2, count);
  PutU16(Result, 4, strOff);
  cur := 0;
  for i := 0 to count - 1 do
  begin
    PutU16(Result, 6 + i * 12,     3);
    PutU16(Result, 6 + i * 12 + 2, 1);
    PutU16(Result, 6 + i * 12 + 4, $0409);
    PutU16(Result, 6 + i * 12 + 6, ids[i]);
    PutU16(Result, 6 + i * 12 + 8, Length(names[i]) * 2);
    PutU16(Result, 6 + i * 12 + 10, cur);
    for k := 1 to Length(names[i]) do
      PutU16(Result, strOff + cur + (k - 1) * 2, Ord(names[i][k]));
    Inc(cur, Length(names[i]) * 2);
  end;
end;

function BuildPostFormat3(ATTF: TTTFFont): TBytes;
var
  src: TBytes;
begin
  SetLength(Result, 32);
  FillChar(Result[0], 32, 0);
  src := ATTF.TableData('post');
  if Length(src) >= 32 then
    Move(src[0], Result[0], 32);
  PutU32(Result, 0, $00030000);  // no glyph names
end;

function BuildHollowSubset(ATTF: TTTFFont; const AUsed: array of Word;
  const ACharMap: array of TSubsetCharMapping; const AFontName: string): TBytes;
const
  // Hinting and rasterising tables are kept for on-screen quality.
  COPIED: array[0..5] of AnsiString = ('hhea', 'maxp', 'OS/2', 'cvt ', 'fpgm', 'prep');
var
  keep: TArray<Word>;
  tables: TList<TSfntTable>;
  glyf, loca, head: TBytes;
  tag: AnsiString;
  data: TBytes;
begin
  if not ATTF.HasTrueTypeOutlines then
    raise ETTFParseError.Create('Only TrueType (glyf) fonts can be subset');

  keep := SubsetGlyphClosure(ATTF, AUsed);
  BuildGlyfAndLoca(ATTF, keep, glyf, loca);

  head := ATTF.TableData('head');
  PutU16(head, 50, 1);  // indexToLocFormat: long offsets

  tables := TList<TSfntTable>.Create;
  try
    tables.Add(TSfntTable.Create('head', head));
    tables.Add(TSfntTable.Create('glyf', glyf));
    tables.Add(TSfntTable.Create('loca', loca));
    tables.Add(TSfntTable.Create('hmtx', BuildHmtx(ATTF, keep)));
    tables.Add(TSfntTable.Create('cmap', BuildCmapFormat4(ACharMap)));
    tables.Add(TSfntTable.Create('name', BuildNameTable(ATTF.Metrics.FamilyName,
      ATTF.Metrics.SubfamilyName, AFontName)));
    tables.Add(TSfntTable.Create('post', BuildPostFormat3(ATTF)));
    for tag in COPIED do
    begin
      data := ATTF.TableData(tag);
      if data <> nil then
        tables.Add(TSfntTable.Create(tag, data));
    end;
    Result := BuildSfnt(tables.ToArray);
  finally
    tables.Free;
  end;
end;

function MakeSubsetTag(const APostScriptName: string; const AGlyphs: array of Word): string;
var
  h: Cardinal;
  i: Integer;
  g: Word;

  procedure Mix(AByte: Byte);
  begin
    h := (h xor AByte) * 16777619;
  end;

begin
  // FNV-1a over the name and the glyph list.
  h := 2166136261;
  for i := 1 to Length(APostScriptName) do
  begin
    Mix(Byte(Ord(APostScriptName[i])));
    Mix(Byte(Ord(APostScriptName[i]) shr 8));
  end;
  for g in AGlyphs do
  begin
    Mix(Byte(g));
    Mix(Byte(g shr 8));
  end;
  SetLength(Result, 6);
  for i := 1 to 6 do
  begin
    Result[i] := Char(Ord('A') + h mod 26);
    h := h div 26;
  end;
end;

end.
