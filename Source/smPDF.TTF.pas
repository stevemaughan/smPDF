unit smPDF.TTF;

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

    // Vertical metrics in font units (positive ascent, negative descent)
    Ascent:         SmallInt;
    Descent:        SmallInt;
    LineGap:        SmallInt;

    // From OS/2 (preferred over hhea where available)
    CapHeight:      SmallInt;
    XHeight:        SmallInt;

    // Style
    ItalicAngle:    Double;     // signed degrees, negative = forward slant
    IsBold:         Boolean;
    IsItalic:       Boolean;
    IsFixedPitch:   Boolean;
    UsWeightClass:  Word;       // OS/2 usWeightClass; 400 = regular, 700 = bold

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
    fGlyphAdvances:  array of Word;   // per glyph index, in font units
    fCmap:           TDictionary<Word, Word>;  // codepoint -> glyph index
    fWinAnsiWidths:  array[0..255] of Word;    // cached widths in font units

    function ReadU16(AOffset: Integer): Word;
    function ReadI16(AOffset: Integer): SmallInt;
    function ReadU32(AOffset: Integer): Cardinal;
    function ReadFixed(AOffset: Integer): Double;
    function ReadAnsi(AOffset, ALen: Integer): AnsiString;
    function TableOffset(const ATag: AnsiString): Integer;
    function HasTable(const ATag: AnsiString): Boolean;

    procedure ParseAll;
    procedure ParseTableDirectory;
    procedure ParseHead;
    procedure ParseHhea;
    procedure ParseMaxp;
    procedure ParseHmtx;
    procedure ParseOS2;
    procedure ParsePost;
    procedure ParseCmap;
    procedure ParseName;
    procedure ComputeFlagsAndStemV;
    procedure CacheWinAnsiWidths;
  public
    constructor Create(const AFilePath: string);
    constructor CreateFromBytes(const ABytes: TBytes; const ASourceLabel: string = '<bytes>');
    destructor Destroy; override;

    function GlyphIndex(ACodepoint: Word): Word;     // 0 if missing
    function GlyphAdvance(AGlyphIndex: Word): Word;  // font units
    function CharWidthWinAnsi(AByte: Byte): Word;    // font units

    // Convert a font-unit value to PDF 1/1000-em units.
    function FontUnitsToPdf(AValue: Integer): Integer;

    property Bytes:        TBytes           read fBytes;
    property Metrics:      TTTFFontMetrics  read fMetrics;
    property SourceLabel:  string           read fSourceLabel;
  end;

implementation

uses
  IOUtils;

const
  TTF_MAGIC_NUMBER = $5F0F3CF5;
  TTF_VERSION_TRUE = $00010000;
  PDF_FLAG_FIXEDPITCH  = 1;
  PDF_FLAG_SERIF       = 2;
  PDF_FLAG_SYMBOLIC    = 4;
  PDF_FLAG_SCRIPT      = 8;
  PDF_FLAG_NONSYMBOLIC = 32;
  PDF_FLAG_ITALIC      = 64;
  PDF_FLAG_FORCEBOLD   = 262144;

constructor TTTFFont.Create(const AFilePath: string);
begin
  inherited Create;
  fSourceLabel := AFilePath;
  fBytes       := TFile.ReadAllBytes(AFilePath);
  fTables      := TDictionary<AnsiString, TTTFTableEntry>.Create;
  fCmap        := TDictionary<Word, Word>.Create;
  ParseAll;
end;

constructor TTTFFont.CreateFromBytes(const ABytes: TBytes; const ASourceLabel: string);
begin
  inherited Create;
  fSourceLabel := ASourceLabel;
  fBytes       := Copy(ABytes, 0, Length(ABytes));
  fTables      := TDictionary<AnsiString, TTTFTableEntry>.Create;
  fCmap        := TDictionary<Word, Word>.Create;
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
  ComputeFlagsAndStemV;
  CacheWinAnsiWidths;
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
    raise ETTFParseError.Create('TrueType Collections (.ttc) are not supported in Phase 4');
  if (sfntVersion <> TTF_VERSION_TRUE) and (sfntVersion <> $74727565) then  // 'true'
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
  fMetrics.XMin := ReadI16(off + 36);
  fMetrics.YMin := ReadI16(off + 38);
  fMetrics.XMax := ReadI16(off + 40);
  fMetrics.YMax := ReadI16(off + 42);

  macStyle := ReadU16(off + 44);
  fMetrics.IsBold   := (macStyle and $1) <> 0;
  fMetrics.IsItalic := (macStyle and $2) <> 0;
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
begin
  off := TableOffset('OS/2');
  version := ReadU16(off);
  fMetrics.UsWeightClass := ReadU16(off + 4);
  fsSelection := ReadU16(off + 62);
  if (fsSelection and $1) <> 0 then
    fMetrics.IsItalic := True;
  // sTypoAscender/Descender (signed, in font units)
  fMetrics.Ascent  := ReadI16(off + 68);
  fMetrics.Descent := ReadI16(off + 70);
  fMetrics.LineGap := ReadI16(off + 72);
  if version >= 2 then
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
  platformID, encodingID: Word;
  subOff: Cardinal;
  bestSubOff: Cardinal;
  bestPriority: Integer;
  curPriority: Integer;

  // format-4 inner state
  format, subtableLength, segCountX2, segCount: Word;
  endCode, startCode: array of Word;
  idDelta: array of SmallInt;
  idRangeOffsets: array of Word;
  endCodeOff, startCodeOff, idDeltaOff, idRangeOff: Integer;
  seg, glyphIdOff, glyphIdx: Integer;
  cp: Integer;
  rangeAddr, indexAddr: Integer;
begin
  cmapOff := TableOffset('cmap');
  numEncodings := ReadU16(cmapOff + 2);

  bestSubOff := 0;
  bestPriority := -1;
  for i := 0 to numEncodings - 1 do
  begin
    recOff     := cmapOff + 4 + i * 8;
    platformID := ReadU16(recOff);
    encodingID := ReadU16(recOff + 2);
    subOff     := ReadU32(recOff + 4);

    // Priority: prefer Microsoft Unicode BMP, fall back to Unicode, then Microsoft Symbol
    if      (platformID = 3) and (encodingID = 1)  then curPriority := 100  // Win Unicode BMP
    else if (platformID = 0)                       then curPriority := 80   // Unicode
    else if (platformID = 3) and (encodingID = 0)  then curPriority := 50   // Win Symbol
    else                                                curPriority := 0;

    if curPriority > bestPriority then
    begin
      bestPriority := curPriority;
      bestSubOff   := subOff;
    end;
  end;

  if bestPriority < 0 then
    raise ETTFParseError.CreateFmt('No usable cmap subtable in %s', [fSourceLabel]);

  format := ReadU16(cmapOff + Integer(bestSubOff));
  if format <> 4 then
    raise ETTFParseError.CreateFmt(
      'cmap format %d not supported (Phase 4 needs format 4) in %s',
      [format, fSourceLabel]);

  subtableLength := ReadU16(cmapOff + Integer(bestSubOff) + 2);
  segCountX2 := ReadU16(cmapOff + Integer(bestSubOff) + 6);
  segCount   := segCountX2 div 2;

  endCodeOff   := cmapOff + Integer(bestSubOff) + 14;
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

  // Walk every codepoint in every segment and store the mapping.
  // For Phase 4 (WinAnsi only) we really only need 0..255, but populating the
  // full BMP costs little and keeps us flexible.
  for seg := 0 to segCount - 1 do
  begin
    if startCode[seg] = $FFFF then Continue;
    for cp := startCode[seg] to endCode[seg] do
    begin
      if idRangeOffsets[seg] = 0 then
        glyphIdx := (cp + idDelta[seg]) and $FFFF
      else
      begin
        // glyphIdArray index into idRangeOffsets[seg] storage
        rangeAddr := idRangeOff + seg * 2;
        indexAddr := rangeAddr + Integer(idRangeOffsets[seg])
                              + (cp - startCode[seg]) * 2;
        glyphIdOff := indexAddr;
        if (glyphIdOff < 0) or (glyphIdOff + 2 > Length(fBytes)) then
          glyphIdx := 0
        else
        begin
          glyphIdx := ReadU16(glyphIdOff);
          if glyphIdx <> 0 then
            glyphIdx := (glyphIdx + idDelta[seg]) and $FFFF;
        end;
      end;
      if (glyphIdx > 0) and (cp <= $FFFF) then
        fCmap.AddOrSetValue(Word(cp), Word(glyphIdx));
    end;
  end;

  // Suppress unused-variable hint (kept for spec readability)
  if subtableLength = 0 then;
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

    // Priority: Windows English (3,1,0x0409) > Mac Roman English (1,0,0)
    if (platformID = 3) and (encodingID = 1) and (languageID = $0409) then
    begin
      curPriority := 100;
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
    fMetrics.PostScriptName := fMetrics.FamilyName;
    if (fMetrics.SubfamilyName <> '') and not SameText(fMetrics.SubfamilyName, 'Regular') then
      fMetrics.PostScriptName := fMetrics.PostScriptName + '-' +
        StringReplace(fMetrics.SubfamilyName, ' ', '', [rfReplaceAll]);
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

procedure TTTFFont.CacheWinAnsiWidths;
var
  enc: TEncoding;
  b: Integer;
  buf: TBytes;
  s: string;
  cp: Word;
  glyph: Word;
begin
  enc := TEncoding.GetEncoding(1252);
  try
    SetLength(buf, 1);
    for b := 0 to 255 do
    begin
      buf[0] := Byte(b);
      try
        s := enc.GetString(buf);
      except
        s := '';
      end;
      if s = '' then
      begin
        fWinAnsiWidths[b] := 0;
        Continue;
      end;
      cp := Ord(s[1]);
      glyph := GlyphIndex(cp);
      if glyph = 0 then
        fWinAnsiWidths[b] := 0
      else
        fWinAnsiWidths[b] := fGlyphAdvances[glyph];
    end;
  finally
    enc.Free;
  end;
end;

function TTTFFont.GlyphIndex(ACodepoint: Word): Word;
begin
  if not fCmap.TryGetValue(ACodepoint, Result) then
    Result := 0;
end;

function TTTFFont.GlyphAdvance(AGlyphIndex: Word): Word;
begin
  if (AGlyphIndex < Length(fGlyphAdvances)) then
    Result := fGlyphAdvances[AGlyphIndex]
  else
    Result := 0;
end;

function TTTFFont.CharWidthWinAnsi(AByte: Byte): Word;
begin
  Result := fWinAnsiWidths[AByte];
end;

function TTTFFont.FontUnitsToPdf(AValue: Integer): Integer;
begin
  if fMetrics.UnitsPerEm = 0 then
    Result := AValue
  else
    Result := Round(AValue * 1000.0 / fMetrics.UnitsPerEm);
end;

end.
