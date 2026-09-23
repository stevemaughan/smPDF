unit smPDF.TTF;

// Checksums and hashes rely on 32-bit wrap-around.
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  ETTFParseError = class(Exception);

  TTTFTableEntry = record
    Tag:      AnsiString;  // 4 chars
    Checksum: Cardinal;
    Offset:   Cardinal;
    Length:   Cardinal;
  end;

  TTTFFontMetrics = record
    UnitsPerEm:     Integer;
    NumGlyphs:      Integer;

    // Bounding box in font units (FUnits)
    XMin, YMin, XMax, YMax: SmallInt;

    // Vertical metrics used for text placement (positive ascent, negative
    // descent): OS/2 typo values when the font has an OS/2 table, else hhea.
    Ascent:         SmallInt;
    Descent:        SmallInt;
    LineGap:        SmallInt;

    // GDI's cell: tmAscent = usWinAscent, tmDescent = usWinDescent (both positive).
    WinAscent:      Word;
    WinDescent:     Word;

    // From OS/2 (preferred over hhea where available)
    CapHeight:      SmallInt;
    XHeight:        SmallInt;

    // Style
    ItalicAngle:    Double;     // signed degrees, negative = forward slant
    IsBold:         Boolean;
    IsItalic:       Boolean;
    IsFixedPitch:   Boolean;
    UsWeightClass:  Word;       // OS/2 usWeightClass; 400 = regular, 700 = bold

    // OS/2 fsType embedding permissions (0 = installable).
    FsType:         Word;

    // Approximated stem thickness for PDF descriptor — TTF doesn't carry this directly.
    StemV:          Word;

    // PDF /Flags bitfield for the font descriptor
    PdfFlags:       Cardinal;

    // Names from the `name` table (already decoded to Unicode)
    PostScriptName: string;
    FamilyName:     string;
    SubfamilyName:  string;
  end;

  TTTFFont = class
  strict private
    fSourceLabel:    string;
    fBytes:          TBytes;
    fTables:         TDictionary<AnsiString, TTTFTableEntry>;
    fMetrics:        TTTFFontMetrics;
    fNumberOfHMetrics: Integer;
    fIndexToLocFormat: Integer;
    fIsCFF:          Boolean;
    fGlyphAdvances:  array of Word;   // per glyph index, in font units
    fLoca:           array of Cardinal;          // glyf offsets, NumGlyphs + 1 entries
    fCmap:           TDictionary<Cardinal, Word>; // codepoint -> glyph index
    fSymbolCmap:     Boolean;                     // cmap came from the (3,0) symbol subtable

    function ReadU16(AOffset: Integer): Word;
    function ReadI16(AOffset: Integer): SmallInt;
    function ReadU32(AOffset: Integer): Cardinal;
    function ReadFixed(AOffset: Integer): Double;
    function ReadAnsi(AOffset, ALen: Integer): AnsiString;
    function TableOffset(const ATag: AnsiString): Integer;

    procedure ParseAll;
    procedure ParseTableDirectory;
    procedure ParseHead;
    procedure ParseHhea;
    procedure ParseMaxp;
    procedure ParseHmtx;
    procedure ParseOS2;
    procedure ParsePost;
    procedure ParseCmap;
    procedure ParseCmapFormat4(ASubtableOffset: Integer);
    procedure ParseCmapFormat12(ASubtableOffset: Integer);
    procedure ParseName;
    procedure ParseLoca;
    procedure ComputeFlagsAndStemV;
  public
    constructor Create(const AFilePath: string);
    constructor CreateFromBytes(const ABytes: TBytes; const ASourceLabel: string = '<bytes>');
    destructor Destroy; override;

    function HasTable(const ATag: AnsiString): Boolean;
    function TableData(const ATag: AnsiString): TBytes;
    function TableTags: TArray<AnsiString>;

    function GlyphIndex(ACodepoint: Cardinal): Word;  // 0 if missing
    function GlyphAdvance(AGlyphIndex: Word): Word;   // font units

    // Byte range of a glyph inside the glyf table; False for an empty glyph.
    function GlyphRange(AGlyphIndex: Word; out AOffset, ALength: Cardinal): Boolean;
    // Glyph ids referenced by a composite glyph (empty for simple glyphs).
    function GlyphComponents(AGlyphIndex: Word): TArray<Word>;

    // Convert a font-unit value to PDF 1/1000-em units.
    function FontUnitsToPdf(AValue: Integer): Integer;

    // True when the font has TrueType (glyf) outlines, which /FontFile2 needs.
    function HasTrueTypeOutlines: Boolean;
    // OS/2 fsType bit 1: restricted licence, must not be embedded.
    function EmbeddingRestricted: Boolean;
    // OS/2 fsType bit 8: the font may only be embedded whole.
    function SubsettingForbidden: Boolean;

    property Bytes:           TBytes           read fBytes;
    property Metrics:         TTTFFontMetrics  read fMetrics;
    property SourceLabel:     string           read fSourceLabel;
    property IsCFF:           Boolean          read fIsCFF;
    property IndexToLocFormat: Integer         read fIndexToLocFormat;
    property SymbolCmap:      Boolean          read fSymbolCmap;
    // codepoint -> glyph id for every character the font maps
    property CharacterMap:    TDictionary<Cardinal, Word> read fCmap;
  end;

  TSfntTable = record
    Tag:  AnsiString;
    Data: TBytes;
    constructor Create(const ATag: AnsiString; const AData: TBytes);
  end;

// Assemble a standalone TrueType file from tables: sorted directory, 4-byte
// padding, per-table checksums and head.checkSumAdjustment.
function BuildSfnt(const ATables: array of TSfntTable): TBytes;

// The sfnt checksum: sum of big-endian 32-bit words, zero-padded.
function SfntChecksum(const AData: TBytes; AOffset, ALength: Integer): Cardinal;

implementation

uses
  IOUtils, Generics.Defaults;

const
  TTF_MAGIC_NUMBER = $5F0F3CF5;
  TTF_VERSION_TRUE = $00010000;
  SFNT_OTTO        = $4F54544F;  // 'OTTO' - CFF-flavoured OpenType
  PDF_FLAG_FIXEDPITCH  = 1;
  PDF_FLAG_SERIF       = 2;
  PDF_FLAG_SYMBOLIC    = 4;
  PDF_FLAG_SCRIPT      = 8;
  PDF_FLAG_NONSYMBOLIC = 32;
  PDF_FLAG_ITALIC      = 64;
  PDF_FLAG_FORCEBOLD   = 262144;

constructor TSfntTable.Create(const ATag: AnsiString; const AData: TBytes);
begin
  Tag  := ATag;
  Data := AData;
end;

constructor TTTFFont.Create(const AFilePath: string);
begin
  CreateFromBytes(TFile.ReadAllBytes(AFilePath), AFilePath);
end;

constructor TTTFFont.CreateFromBytes(const ABytes: TBytes; const ASourceLabel: string);
begin
  inherited Create;
  fSourceLabel := ASourceLabel;
  fBytes       := ABytes;
  fTables      := TDictionary<AnsiString, TTTFTableEntry>.Create;
  fCmap        := TDictionary<Cardinal, Word>.Create;
  ParseAll;
end;

destructor TTTFFont.Destroy;
begin
  fCmap.Free;
  fTables.Free;
  inherited;
end;

function TTTFFont.ReadU16(AOffset: Integer): Word;
begin
  if (AOffset < 0) or (AOffset + 2 > Length(fBytes)) then
    raise ETTFParseError.CreateFmt('U16 read past EOF at %d (size %d) in %s',
      [AOffset, Length(fBytes), fSourceLabel]);
  Result := (Word(fBytes[AOffset]) shl 8) or Word(fBytes[AOffset + 1]);
end;

function TTTFFont.ReadI16(AOffset: Integer): SmallInt;
begin
  Result := SmallInt(ReadU16(AOffset));
end;

function TTTFFont.ReadU32(AOffset: Integer): Cardinal;
begin
  if (AOffset < 0) or (AOffset + 4 > Length(fBytes)) then
    raise ETTFParseError.CreateFmt('U32 read past EOF at %d (size %d) in %s',
      [AOffset, Length(fBytes), fSourceLabel]);
  Result :=  (Cardinal(fBytes[AOffset    ]) shl 24)
          or (Cardinal(fBytes[AOffset + 1]) shl 16)
          or (Cardinal(fBytes[AOffset + 2]) shl  8)
          or  Cardinal(fBytes[AOffset + 3]);
end;

function TTTFFont.ReadFixed(AOffset: Integer): Double;
var
  raw: Integer;
begin
  raw    := Integer(ReadU32(AOffset));   // signed
  Result := raw / 65536.0;
end;

function TTTFFont.ReadAnsi(AOffset, ALen: Integer): AnsiString;
var
  i: Integer;
begin
  if (AOffset < 0) or (AOffset + ALen > Length(fBytes)) then
    raise ETTFParseError.CreateFmt('Ansi read past EOF at %d len %d in %s',
      [AOffset, ALen, fSourceLabel]);
  SetLength(Result, ALen);
  for i := 0 to ALen - 1 do
    Result[i + 1] := AnsiChar(fBytes[AOffset + i]);
end;

function TTTFFont.TableOffset(const ATag: AnsiString): Integer;
var
  e: TTTFTableEntry;
begin
  if not fTables.TryGetValue(ATag, e) then
    raise ETTFParseError.CreateFmt('Table "%s" not present in %s',
      [string(ATag), fSourceLabel]);
  Result := Integer(e.Offset);
end;

function TTTFFont.HasTable(const ATag: AnsiString): Boolean;
begin
  Result := fTables.ContainsKey(ATag);
end;

function TTTFFont.TableData(const ATag: AnsiString): TBytes;
var
  e: TTTFTableEntry;
begin
  if not fTables.TryGetValue(ATag, e) then
    Exit(nil);
  if Int64(e.Offset) + e.Length > Length(fBytes) then
    raise ETTFParseError.CreateFmt('Table "%s" runs past EOF in %s', [string(ATag), fSourceLabel]);
  Result := Copy(fBytes, e.Offset, e.Length);
end;

function TTTFFont.TableTags: TArray<AnsiString>;
begin
  Result := fTables.Keys.ToArray;
end;

procedure TTTFFont.ParseAll;
begin
  ParseTableDirectory;
  ParseHead;
  ParseHhea;
  ParseMaxp;
  ParseHmtx;
  if HasTable('OS/2') then ParseOS2;
  if HasTable('post') then ParsePost;
  ParseCmap;
  if HasTable('name') then ParseName;
  if HasTrueTypeOutlines then ParseLoca;
  ComputeFlagsAndStemV;
end;

procedure TTTFFont.ParseTableDirectory;
var
  sfntVersion: Cardinal;
  numTables: Word;
  i, recOff: Integer;
  e: TTTFTableEntry;
begin
  if Length(fBytes) < 12 then
    raise ETTFParseError.CreateFmt('File too small (%d bytes) to be a TTF', [Length(fBytes)]);

  sfntVersion := ReadU32(0);
  if sfntVersion = $74746366 then  // 'ttcf'
    raise ETTFParseError.Create('TrueType Collections (.ttc) must be loaded through GDI, not as a file');
  fIsCFF := sfntVersion = SFNT_OTTO;
  if (sfntVersion <> TTF_VERSION_TRUE) and (sfntVersion <> $74727565) and not fIsCFF then  // 'true'
    raise ETTFParseError.CreateFmt('Unsupported sfnt version $%.8x in %s',
      [sfntVersion, fSourceLabel]);

  numTables := ReadU16(4);
  for i := 0 to numTables - 1 do
  begin
    recOff   := 12 + i * 16;
    e.Tag    := ReadAnsi(recOff, 4);
    e.Checksum := ReadU32(recOff +  4);
    e.Offset   := ReadU32(recOff +  8);
    e.Length   := ReadU32(recOff + 12);
    fTables.AddOrSetValue(e.Tag, e);
  end;
end;

procedure TTTFFont.ParseHead;
var
  off: Integer;
  magic: Cardinal;
  macStyle: Word;
begin
  off := TableOffset('head');
  magic := ReadU32(off + 12);
  if magic <> TTF_MAGIC_NUMBER then
    raise ETTFParseError.CreateFmt('Bad head.magicNumber $%.8x in %s', [magic, fSourceLabel]);

  fMetrics.UnitsPerEm := ReadU16(off + 18);
  if fMetrics.UnitsPerEm = 0 then
    raise ETTFParseError.CreateFmt('head.unitsPerEm is zero in %s', [fSourceLabel]);
  fMetrics.XMin := ReadI16(off + 36);
  fMetrics.YMin := ReadI16(off + 38);
  fMetrics.XMax := ReadI16(off + 40);
  fMetrics.YMax := ReadI16(off + 42);

  macStyle := ReadU16(off + 44);
  fMetrics.IsBold   := (macStyle and $1) <> 0;
  fMetrics.IsItalic := (macStyle and $2) <> 0;

  fIndexToLocFormat := ReadI16(off + 50);
end;

procedure TTTFFont.ParseHhea;
var
  off: Integer;
begin
  off := TableOffset('hhea');
  fMetrics.Ascent  := ReadI16(off + 4);
  fMetrics.Descent := ReadI16(off + 6);
  fMetrics.LineGap := ReadI16(off + 8);
  fNumberOfHMetrics := ReadU16(off + 34);
  // Fallback for fonts without OS/2; ParseOS2 overwrites both.
  fMetrics.WinAscent  := Word(Abs(fMetrics.Ascent));
  fMetrics.WinDescent := Word(Abs(fMetrics.Descent));
end;

procedure TTTFFont.ParseMaxp;
var
  off: Integer;
begin
  off := TableOffset('maxp');
  fMetrics.NumGlyphs := ReadU16(off + 4);
end;

procedure TTTFFont.ParseHmtx;
var
  off, i: Integer;
  lastAdvance: Word;
begin
  off := TableOffset('hmtx');
  SetLength(fGlyphAdvances, fMetrics.NumGlyphs);
  lastAdvance := 0;
  // First numberOfHMetrics entries each carry (advance, lsb)
  for i := 0 to fNumberOfHMetrics - 1 do
  begin
    if i >= fMetrics.NumGlyphs then Break;
    fGlyphAdvances[i] := ReadU16(off + i * 4);
    lastAdvance := fGlyphAdvances[i];
  end;
  // Remaining glyphs reuse the last advance, only their lsb is stored
  for i := fNumberOfHMetrics to fMetrics.NumGlyphs - 1 do
    fGlyphAdvances[i] := lastAdvance;
end;

procedure TTTFFont.ParseOS2;
var
  off: Integer;
  version: Word;
  fsSelection: Word;
  e: TTTFTableEntry;
begin
  off := TableOffset('OS/2');
  e := fTables['OS/2'];
  version := ReadU16(off);
  fMetrics.UsWeightClass := ReadU16(off + 4);
  fMetrics.FsType := ReadU16(off + 8);
  fsSelection := ReadU16(off + 62);
  if (fsSelection and $1) <> 0 then
    fMetrics.IsItalic := True;
  // sTypoAscender/Descender (signed, in font units)
  fMetrics.Ascent  := ReadI16(off + 68);
  fMetrics.Descent := ReadI16(off + 70);
  fMetrics.LineGap := ReadI16(off + 72);
  if e.Length >= 78 then
  begin
    fMetrics.WinAscent  := ReadU16(off + 74);
    fMetrics.WinDescent := ReadU16(off + 76);
  end;
  if (version >= 2) and (e.Length >= 90) then
  begin
    fMetrics.XHeight   := ReadI16(off + 86);
    fMetrics.CapHeight := ReadI16(off + 88);
  end;
  if fMetrics.CapHeight = 0 then
    fMetrics.CapHeight := Round(0.7 * fMetrics.UnitsPerEm);
  if fMetrics.XHeight = 0 then
    fMetrics.XHeight := Round(0.5 * fMetrics.UnitsPerEm);
end;

procedure TTTFFont.ParsePost;
var
  off: Integer;
  isFixedPitch: Cardinal;
begin
  off := TableOffset('post');
  fMetrics.ItalicAngle := ReadFixed(off + 4);
  isFixedPitch := ReadU32(off + 12);
  fMetrics.IsFixedPitch := isFixedPitch <> 0;
end;

procedure TTTFFont.ParseCmap;
var
  cmapOff, numEncodings, i: Integer;
  recOff: Integer;
  platformID, encodingID, format: Word;
  subOff: Cardinal;
  bestSubOff: Cardinal;
  bestFormat: Word;
  bestPriority, curPriority: Integer;
begin
  cmapOff := TableOffset('cmap');
  numEncodings := ReadU16(cmapOff + 2);

  bestSubOff   := 0;
  bestFormat   := 0;
  bestPriority := -1;
  for i := 0 to numEncodings - 1 do
  begin
    recOff     := cmapOff + 4 + i * 8;
    platformID := ReadU16(recOff);
    encodingID := ReadU16(recOff + 2);
    subOff     := ReadU32(recOff + 4);
    format     := ReadU16(cmapOff + Integer(subOff));

    // Full-range Unicode first, then BMP Unicode, then the Windows symbol table.
    curPriority := -1;
    if format = 12 then
    begin
      if      (platformID = 3) and (encodingID = 10) then curPriority := 120
      else if (platformID = 0)                       then curPriority := 110;
    end
    else if format = 4 then
    begin
      if      (platformID = 3) and (encodingID = 1)  then curPriority := 100
      else if (platformID = 0)                       then curPriority := 80
      else if (platformID = 3) and (encodingID = 0)  then curPriority := 50;
    end;

    if curPriority > bestPriority then
    begin
      bestPriority := curPriority;
      bestSubOff   := subOff;
      bestFormat   := format;
      fSymbolCmap  := (platformID = 3) and (encodingID = 0);
    end;
  end;

  if bestPriority < 0 then
    raise ETTFParseError.CreateFmt('No usable Unicode cmap subtable (format 4 or 12) in %s', [fSourceLabel]);

  if bestFormat = 12 then
    ParseCmapFormat12(cmapOff + Integer(bestSubOff))
  else
    ParseCmapFormat4(cmapOff + Integer(bestSubOff));
end;

procedure TTTFFont.ParseCmapFormat4(ASubtableOffset: Integer);
var
  segCount, i, seg: Integer;
  endCode, startCode: array of Word;
  idDelta: array of SmallInt;
  idRangeOffsets: array of Word;
  endCodeOff, startCodeOff, idDeltaOff, idRangeOff: Integer;
  glyphIdOff, glyphIdx, cp: Integer;
begin
  segCount := ReadU16(ASubtableOffset + 6) div 2;

  endCodeOff   := ASubtableOffset + 14;
  startCodeOff := endCodeOff   + segCount * 2 + 2;
  idDeltaOff   := startCodeOff + segCount * 2;
  idRangeOff   := idDeltaOff   + segCount * 2;

  SetLength(endCode, segCount);
  SetLength(startCode, segCount);
  SetLength(idDelta, segCount);
  SetLength(idRangeOffsets, segCount);
  for i := 0 to segCount - 1 do
  begin
    endCode[i]        := ReadU16(endCodeOff   + i * 2);
    startCode[i]      := ReadU16(startCodeOff + i * 2);
    idDelta[i]        := ReadI16(idDeltaOff   + i * 2);
    idRangeOffsets[i] := ReadU16(idRangeOff   + i * 2);
  end;

  for seg := 0 to segCount - 1 do
  begin
    if startCode[seg] = $FFFF then Continue;
    for cp := startCode[seg] to endCode[seg] do
    begin
      if idRangeOffsets[seg] = 0 then
        glyphIdx := (cp + idDelta[seg]) and $FFFF
      else
      begin
        // glyphIdArray entry addressed relative to this segment's idRangeOffset slot
        glyphIdOff := idRangeOff + seg * 2 + Integer(idRangeOffsets[seg])
                    + (cp - startCode[seg]) * 2;
        if (glyphIdOff < 0) or (glyphIdOff + 2 > Length(fBytes)) then
          glyphIdx := 0
        else
        begin
          glyphIdx := ReadU16(glyphIdOff);
          if glyphIdx <> 0 then
            glyphIdx := (glyphIdx + idDelta[seg]) and $FFFF;
        end;
      end;
      if (glyphIdx > 0) and (glyphIdx < fMetrics.NumGlyphs) then
        fCmap.AddOrSetValue(Cardinal(cp), Word(glyphIdx));
    end;
  end;
end;

procedure TTTFFont.ParseCmapFormat12(ASubtableOffset: Integer);
var
  numGroups, g: Cardinal;
  grpOff: Integer;
  startChar, endChar, startGlyph, cp: Cardinal;
begin
  numGroups := ReadU32(ASubtableOffset + 12);
  for g := 0 to numGroups - 1 do
  begin
    grpOff     := ASubtableOffset + 16 + Integer(g) * 12;
    startChar  := ReadU32(grpOff);
    endChar    := ReadU32(grpOff + 4);
    startGlyph := ReadU32(grpOff + 8);
    if (endChar < startChar) or (endChar > $10FFFF) then Continue;
    for cp := startChar to endChar do
      if startGlyph + (cp - startChar) < Cardinal(fMetrics.NumGlyphs) then
        fCmap.AddOrSetValue(cp, Word(startGlyph + (cp - startChar)));
  end;
end;

procedure TTTFFont.ParseName;
var
  off, count, storageOffset: Integer;
  recOff, i: Integer;
  platformID, encodingID, languageID, nameID, nameLength, nameOffset: Word;
  bestPostScriptPriority, bestFamilyPriority, bestSubfamilyPriority: Integer;
  curPriority: Integer;
  rawAddr, k: Integer;
  decoded: string;
  isUtf16: Boolean;
begin
  off := TableOffset('name');
  count := ReadU16(off + 2);
  storageOffset := ReadU16(off + 4);

  bestPostScriptPriority := -1;
  bestFamilyPriority     := -1;
  bestSubfamilyPriority  := -1;

  for i := 0 to count - 1 do
  begin
    recOff      := off + 6 + i * 12;
    platformID  := ReadU16(recOff);
    encodingID  := ReadU16(recOff + 2);
    languageID  := ReadU16(recOff + 4);
    nameID      := ReadU16(recOff + 6);
    nameLength  := ReadU16(recOff + 8);
    nameOffset  := ReadU16(recOff + 10);

    // Priority: Windows English (3,1,0x0409) > other Windows Unicode > Mac Roman English (1,0,0)
    if (platformID = 3) and (encodingID = 1) and (languageID = $0409) then
    begin
      curPriority := 100;
      isUtf16 := True;
    end
    else if (platformID = 3) and ((encodingID = 1) or (encodingID = 0)) then
    begin
      curPriority := 70;
      isUtf16 := True;
    end
    else if (platformID = 1) and (encodingID = 0) and (languageID = 0) then
    begin
      curPriority := 50;
      isUtf16 := False;
    end
    else
      Continue;

    rawAddr := off + storageOffset + nameOffset;
    if (rawAddr < 0) or (rawAddr + nameLength > Length(fBytes)) then
      Continue;

    if isUtf16 then
    begin
      // UTF-16BE big-endian
      SetLength(decoded, nameLength div 2);
      for k := 0 to (nameLength div 2) - 1 do
        decoded[k + 1] := WideChar((Word(fBytes[rawAddr + k * 2]) shl 8)
                                   or Word(fBytes[rawAddr + k * 2 + 1]));
    end
    else
    begin
      // Mac Roman -> approximate as ASCII (good enough for our names)
      SetLength(decoded, nameLength);
      for k := 0 to nameLength - 1 do
        decoded[k + 1] := WideChar(fBytes[rawAddr + k]);
    end;

    case nameID of
      1: if curPriority > bestFamilyPriority then
         begin bestFamilyPriority := curPriority; fMetrics.FamilyName := decoded; end;
      2: if curPriority > bestSubfamilyPriority then
         begin bestSubfamilyPriority := curPriority; fMetrics.SubfamilyName := decoded; end;
      6: if curPriority > bestPostScriptPriority then
         begin bestPostScriptPriority := curPriority; fMetrics.PostScriptName := decoded; end;
    end;
  end;

  // Fallback: synthesise a PostScript name from family + subfamily if missing
  if fMetrics.PostScriptName = '' then
  begin
    fMetrics.PostScriptName := StringReplace(fMetrics.FamilyName, ' ', '', [rfReplaceAll]);
    if (fMetrics.SubfamilyName <> '') and not SameText(fMetrics.SubfamilyName, 'Regular') then
      fMetrics.PostScriptName := fMetrics.PostScriptName + '-' +
        StringReplace(fMetrics.SubfamilyName, ' ', '', [rfReplaceAll]);
  end;
end;

procedure TTTFFont.ParseLoca;
var
  off, i, n: Integer;
  e: TTTFTableEntry;
  glyfLen: Cardinal;
begin
  off := TableOffset('loca');
  glyfLen := fTables['glyf'].Length;
  e := fTables['loca'];
  n := fMetrics.NumGlyphs + 1;
  SetLength(fLoca, n);
  for i := 0 to n - 1 do
  begin
    if fIndexToLocFormat = 0 then
    begin
      if Cardinal(i * 2 + 2) > e.Length then
        fLoca[i] := glyfLen
      else
        fLoca[i] := Cardinal(ReadU16(off + i * 2)) * 2;
    end
    else
    begin
      if Cardinal(i * 4 + 4) > e.Length then
        fLoca[i] := glyfLen
      else
        fLoca[i] := ReadU32(off + i * 4);
    end;
    if fLoca[i] > glyfLen then
      fLoca[i] := glyfLen;
  end;
end;

procedure TTTFFont.ComputeFlagsAndStemV;
var
  flags: Cardinal;
begin
  flags := 0;
  if fMetrics.IsFixedPitch then flags := flags or PDF_FLAG_FIXEDPITCH;
  // Treat non-Symbol fonts as nonsymbolic (Phase 4 doesn't ship Symbol/Dingbats via TTF)
  flags := flags or PDF_FLAG_NONSYMBOLIC;
  if fMetrics.IsItalic     then flags := flags or PDF_FLAG_ITALIC;
  if fMetrics.UsWeightClass >= 700 then flags := flags or PDF_FLAG_FORCEBOLD;
  fMetrics.PdfFlags := flags;

  // StemV approximation: 50 + (weight-50)/9 (Adobe's heuristic). Bold ~120, regular ~75.
  if fMetrics.UsWeightClass = 0 then
    fMetrics.StemV := 75
  else
    fMetrics.StemV := 50 + (fMetrics.UsWeightClass - 50) div 9;
  if fMetrics.StemV < 50 then fMetrics.StemV := 50;
end;

function TTTFFont.GlyphIndex(ACodepoint: Cardinal): Word;
begin
  if fCmap.TryGetValue(ACodepoint, Result) then Exit;
  // Symbol fonts usually store their characters at U+F000 + code.
  if fSymbolCmap and (ACodepoint <= $FF) and fCmap.TryGetValue($F000 + ACodepoint, Result) then Exit;
  Result := 0;
end;

function TTTFFont.GlyphAdvance(AGlyphIndex: Word): Word;
begin
  if (AGlyphIndex < Length(fGlyphAdvances)) then
    Result := fGlyphAdvances[AGlyphIndex]
  else
    Result := 0;
end;

function TTTFFont.GlyphRange(AGlyphIndex: Word; out AOffset, ALength: Cardinal): Boolean;
begin
  AOffset := 0;
  ALength := 0;
  if (Length(fLoca) = 0) or (AGlyphIndex >= fMetrics.NumGlyphs) then Exit(False);
  AOffset := fLoca[AGlyphIndex];
  if fLoca[AGlyphIndex + 1] > AOffset then
    ALength := fLoca[AGlyphIndex + 1] - AOffset;
  Result := ALength > 0;
end;

function TTTFFont.GlyphComponents(AGlyphIndex: Word): TArray<Word>;
const
  ARG_1_AND_2_ARE_WORDS    = $0001;
  WE_HAVE_A_SCALE          = $0008;
  MORE_COMPONENTS          = $0020;
  WE_HAVE_AN_X_AND_Y_SCALE = $0040;
  WE_HAVE_A_TWO_BY_TWO     = $0080;
var
  glyfOff: Integer;
  goff, glen: Cardinal;
  p, limit: Integer;
  flags: Word;
  list: TList<Word>;
begin
  Result := nil;
  if not GlyphRange(AGlyphIndex, goff, glen) then Exit;
  glyfOff := TableOffset('glyf');
  p := glyfOff + Integer(goff);
  limit := p + Integer(glen);
  if ReadI16(p) >= 0 then Exit;  // simple glyph
  Inc(p, 10);
  list := TList<Word>.Create;
  try
    repeat
      if p + 4 > limit then Break;
      flags := ReadU16(p);
      list.Add(ReadU16(p + 2));
      Inc(p, 4);
      if (flags and ARG_1_AND_2_ARE_WORDS) <> 0 then Inc(p, 4) else Inc(p, 2);
      if (flags and WE_HAVE_A_SCALE) <> 0 then Inc(p, 2)
      else if (flags and WE_HAVE_AN_X_AND_Y_SCALE) <> 0 then Inc(p, 4)
      else if (flags and WE_HAVE_A_TWO_BY_TWO) <> 0 then Inc(p, 8);
    until (flags and MORE_COMPONENTS) = 0;
    Result := list.ToArray;
  finally
    list.Free;
  end;
end;

function TTTFFont.FontUnitsToPdf(AValue: Integer): Integer;
begin
  if fMetrics.UnitsPerEm = 0 then
    Result := AValue
  else
    Result := Round(AValue * 1000.0 / fMetrics.UnitsPerEm);
end;

function TTTFFont.HasTrueTypeOutlines: Boolean;
begin
  Result := HasTable('glyf') and HasTable('loca');
end;

function TTTFFont.EmbeddingRestricted: Boolean;
begin
  // Bit 1 alone means "restricted licence". Bit 9 (bitmap only) also rules
  // out embedding outlines.
  Result := ((fMetrics.FsType and $000F) = $0002) or ((fMetrics.FsType and $0200) <> 0);
end;

function TTTFFont.SubsettingForbidden: Boolean;
begin
  Result := (fMetrics.FsType and $0100) <> 0;
end;

// ---------------------------------------------------------------------------
// sfnt assembly
// ---------------------------------------------------------------------------

function SfntChecksum(const AData: TBytes; AOffset, ALength: Integer): Cardinal;
var
  i, n: Integer;
  word_: Cardinal;
  k: Integer;
begin
  Result := 0;
  n := (ALength + 3) div 4;
  for i := 0 to n - 1 do
  begin
    word_ := 0;
    for k := 0 to 3 do
    begin
      word_ := word_ shl 8;
      if i * 4 + k < ALength then
        word_ := word_ or AData[AOffset + i * 4 + k];
    end;
    Result := Result + word_;
  end;
end;

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

function BuildSfnt(const ATables: array of TSfntTable): TBytes;
var
  tables: TArray<TSfntTable>;
  i, n, pow2, log2, total, off, headOff: Integer;
  checksums: array of Cardinal;
  offsets: array of Integer;
  table: TSfntTable;
  isCFF: Boolean;
begin
  n := Length(ATables);
  SetLength(tables, n);
  isCFF := False;
  for i := 0 to n - 1 do
  begin
    tables[i] := ATables[i];
    if tables[i].Tag = 'CFF ' then isCFF := True;
  end;
  TArray.Sort<TSfntTable>(tables, TComparer<TSfntTable>.Construct(
    function(const A, B: TSfntTable): Integer
    begin
      Result := CompareStr(string(A.Tag), string(B.Tag));
    end));

  pow2 := 1;
  log2 := 0;
  while pow2 * 2 <= n do
  begin
    pow2 := pow2 * 2;
    Inc(log2);
  end;

  total := 12 + 16 * n;
  SetLength(offsets, n);
  SetLength(checksums, n);
  headOff := -1;
  for i := 0 to n - 1 do
  begin
    offsets[i] := total;
    Inc(total, (Length(tables[i].Data) + 3) and not 3);
  end;

  SetLength(Result, total);
  FillChar(Result[0], total, 0);
  if isCFF then PutU32(Result, 0, SFNT_OTTO) else PutU32(Result, 0, TTF_VERSION_TRUE);
  PutU16(Result, 4, n);
  PutU16(Result, 6, pow2 * 16);
  PutU16(Result, 8, log2);
  PutU16(Result, 10, n * 16 - pow2 * 16);

  for i := 0 to n - 1 do
  begin
    table := tables[i];
    off := offsets[i];
    if Length(table.Data) > 0 then
      Move(table.Data[0], Result[off], Length(table.Data));
    if table.Tag = 'head' then
    begin
      headOff := off;
      if Length(table.Data) >= 12 then
        PutU32(Result, off + 8, 0);  // checkSumAdjustment is zero while summing
    end;
    checksums[i] := SfntChecksum(Result, off, Length(table.Data));

    Result[12 + i * 16]     := Ord(table.Tag[1]);
    Result[12 + i * 16 + 1] := Ord(table.Tag[2]);
    Result[12 + i * 16 + 2] := Ord(table.Tag[3]);
    Result[12 + i * 16 + 3] := Ord(table.Tag[4]);
    PutU32(Result, 12 + i * 16 + 4, checksums[i]);
    PutU32(Result, 12 + i * 16 + 8, off);
    PutU32(Result, 12 + i * 16 + 12, Length(table.Data));
  end;

  if headOff >= 0 then
    PutU32(Result, headOff + 8, $B1B0AFBA - SfntChecksum(Result, 0, total));
end;

end.
