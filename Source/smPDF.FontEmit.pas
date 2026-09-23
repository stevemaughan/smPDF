unit smPDF.FontEmit;

// Writes font objects. The 14 standard fonts become simple Type1 fonts with
// WinAnsi encoding. Every embedded TrueType font is written the same way,
// whatever script it carries: a Type0 font with Identity-H encoding over a
// CIDFontType2 whose CIDs are glyph ids, a subset /FontFile2, a compact /W
// width array and a ToUnicode CMap so the text can be searched and copied.

interface

uses
  SysUtils, smPDF.Writer, smPDF.Fonts, smPDF.FontRegistry;

function EmitStandardFont(AWriter: TPDFWriter; AFont: TStandardFont): TPDFObjectId;
function EmitType0Font(AWriter: TPDFWriter; AFace: TPDFFontFace; ACompress: Boolean): TPDFObjectId;

// The ToUnicode CMap text for glyph -> code point pairs (exposed for tests).
function BuildToUnicodeCMap(const AGlyphs: array of Word; const ACodepoints: array of Cardinal): AnsiString;

implementation

uses
  Classes, smPDF.TTF, smPDF.Subset, smPDF.Images;

const
  PDF_FLAG_SYMBOLIC    = 4;
  PDF_FLAG_NONSYMBOLIC = 32;

function EmitStandardFont(AWriter: TPDFWriter; AFont: TStandardFont): TPDFObjectId;
begin
  Result := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('Font');
      AWriter.WriteName('Subtype');  AWriter.WriteName('Type1');
      AWriter.WriteName('BaseFont'); AWriter.WriteName(StandardFontPdfName(AFont));
      if not StandardFontIsSymbolic(AFont) then
      begin
        AWriter.WriteName('Encoding'); AWriter.WriteName('WinAnsiEncoding');
      end;
    AWriter.EndDict;
  AWriter.EndObject;
end;

function Hex4(AValue: Word): AnsiString;
const
  HEX: array[0..15] of AnsiChar = '0123456789ABCDEF';
begin
  SetLength(Result, 4);
  Result[1] := HEX[(AValue shr 12) and $F];
  Result[2] := HEX[(AValue shr 8) and $F];
  Result[3] := HEX[(AValue shr 4) and $F];
  Result[4] := HEX[AValue and $F];
end;

function Utf16Hex(ACodepoint: Cardinal): AnsiString;
var
  v: Cardinal;
begin
  if ACodepoint > $FFFF then
  begin
    v := ACodepoint - $10000;
    Result := Hex4($D800 + (v shr 10)) + Hex4($DC00 + (v and $3FF));
  end
  else
    Result := Hex4(ACodepoint);
end;

function BuildToUnicodeCMap(const AGlyphs: array of Word; const ACodepoints: array of Cardinal): AnsiString;
const
  MAX_PER_BLOCK = 100;
var
  sb: TStringBuilder;
  i, count, start, n: Integer;
  pairs: array of Integer;
begin
  // Only glyphs that stand for a real character can be mapped.
  SetLength(pairs, Length(AGlyphs));
  count := 0;
  for i := 0 to High(AGlyphs) do
    if (AGlyphs[i] <> 0) and (ACodepoints[i] <> 0) then
    begin
      pairs[count] := i;
      Inc(count);
    end;

  sb := TStringBuilder.Create;
  try
    sb.Append('/CIDInit /ProcSet findresource begin'#10);
    sb.Append('12 dict begin'#10);
    sb.Append('begincmap'#10);
    sb.Append('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def'#10);
    sb.Append('/CMapName /Adobe-Identity-UCS def'#10);
    sb.Append('/CMapType 2 def'#10);
    sb.Append('1 begincodespacerange'#10);
    sb.Append('<0000> <FFFF>'#10);
    sb.Append('endcodespacerange'#10);
    start := 0;
    while start < count do
    begin
      n := count - start;
      if n > MAX_PER_BLOCK then n := MAX_PER_BLOCK;
      sb.Append(n).Append(' beginbfchar'#10);
      for i := start to start + n - 1 do
        sb.Append('<').Append(string(Hex4(AGlyphs[pairs[i]]))).Append('> <')
          .Append(string(Utf16Hex(ACodepoints[pairs[i]]))).Append('>'#10);
      sb.Append('endbfchar'#10);
      Inc(start, n);
    end;
    sb.Append('endcmap'#10);
    sb.Append('CMapName currentdict /CMap defineresource pop'#10);
    sb.Append('end'#10);
    sb.Append('end'#10);
    Result := AnsiString(sb.ToString);
  finally
    sb.Free;
  end;
end;

function EmitStreamMaybeCompressed(AWriter: TPDFWriter; const AData: TBytes;
  ACompress: Boolean; ALength1: Integer): TPDFObjectId;
var
  payload: TBytes;
begin
  if ACompress then
    payload := FlateCompress(AData)
  else
    payload := AData;
  Result := AWriter.EmitStreamObject(payload,
    procedure(w: TPDFWriter)
    begin
      if ACompress then
      begin
        w.WriteName('Filter'); w.WriteName('FlateDecode');
      end;
      if ALength1 >= 0 then
      begin
        w.WriteName('Length1'); w.WriteInt(ALength1);
      end;
    end);
end;

// Glyph width in PDF text-space units (1/1000 em), kept to 3 decimals so
// positions in the viewer match what TextWidth measured.
function GlyphWidth1000(ATTF: TTTFFont; AGlyph: Word): Double;
begin
  Result := ATTF.GlyphAdvance(AGlyph) * 1000.0 / ATTF.Metrics.UnitsPerEm;
end;

function EmitType0Font(AWriter: TPDFWriter; AFace: TPDFFontFace; ACompress: Boolean): TPDFObjectId;
var
  ttf: TTTFFont;
  m: TTTFFontMetrics;
  used, closure: TArray<Word>;
  codepoints: TArray<Cardinal>;
  charMap: TArray<TSubsetCharMapping>;
  program_: TBytes;
  fontName: string;
  fontFileId, descriptorId, cidFontId, toUnicodeId: TPDFObjectId;
  cmapText: AnsiString;
  cmapBytes: TBytes;
  i, k, runStart: Integer;
  flags: Cardinal;
begin
  ttf := AFace.TTF;
  m := ttf.Metrics;
  used := AFace.UsedGlyphs;
  SetLength(codepoints, Length(used));
  SetLength(charMap, Length(used));
  for i := 0 to High(used) do
  begin
    codepoints[i] := AFace.UsedGlyphCodepoint(used[i]);
    charMap[i].GlyphId := used[i];
    charMap[i].Codepoint := codepoints[i];
  end;

  if ttf.SubsettingForbidden then
  begin
    fontName := m.PostScriptName;
    program_ := ttf.Bytes;
  end
  else
  begin
    closure := SubsetGlyphClosure(ttf, used);
    // The face key is unique in the document even when two fonts share a
    // PostScript name, so their subsets get different tags.
    fontName := MakeSubsetTag(AFace.Key, closure) + '+' + m.PostScriptName;
    program_ := BuildHollowSubset(ttf, used, charMap, fontName);
  end;

  fontFileId := EmitStreamMaybeCompressed(AWriter, program_, ACompress, Length(program_));

  flags := (m.PdfFlags and not PDF_FLAG_NONSYMBOLIC) or PDF_FLAG_SYMBOLIC;
  descriptorId := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('FontDescriptor');
      AWriter.WriteName('FontName'); AWriter.WriteName(fontName);
      AWriter.WriteName('Flags');    AWriter.WriteInt(flags);
      AWriter.WriteName('FontBBox');
      AWriter.BeginArray;
        AWriter.WriteInt(ttf.FontUnitsToPdf(m.XMin));
        AWriter.WriteInt(ttf.FontUnitsToPdf(m.YMin));
        AWriter.WriteInt(ttf.FontUnitsToPdf(m.XMax));
        AWriter.WriteInt(ttf.FontUnitsToPdf(m.YMax));
      AWriter.EndArray;
      AWriter.WriteName('ItalicAngle'); AWriter.WriteNumber(m.ItalicAngle);
      AWriter.WriteName('Ascent');      AWriter.WriteInt(ttf.FontUnitsToPdf(m.Ascent));
      AWriter.WriteName('Descent');     AWriter.WriteInt(ttf.FontUnitsToPdf(m.Descent));
      AWriter.WriteName('CapHeight');   AWriter.WriteInt(ttf.FontUnitsToPdf(m.CapHeight));
      AWriter.WriteName('StemV');       AWriter.WriteInt(m.StemV);
      AWriter.WriteName('FontFile2');   AWriter.WriteRef(fontFileId);
    AWriter.EndDict;
  AWriter.EndObject;

  cidFontId := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('Font');
      AWriter.WriteName('Subtype');  AWriter.WriteName('CIDFontType2');
      AWriter.WriteName('BaseFont'); AWriter.WriteName(fontName);
      AWriter.WriteName('CIDSystemInfo');
      AWriter.BeginDict;
        AWriter.WriteName('Registry');   AWriter.WriteLiteralString('Adobe');
        AWriter.WriteName('Ordering');   AWriter.WriteLiteralString('Identity');
        AWriter.WriteName('Supplement'); AWriter.WriteInt(0);
      AWriter.EndDict;
      AWriter.WriteName('FontDescriptor'); AWriter.WriteRef(descriptorId);
      AWriter.WriteName('DW'); AWriter.WriteInt(1000);
      // Consecutive glyph ids share one entry: gid [w1 w2 ...]
      AWriter.WriteName('W');
      AWriter.BeginArray;
        i := 0;
        while i <= High(used) do
        begin
          runStart := i;
          while (i < High(used)) and (used[i + 1] = used[i] + 1) do Inc(i);
          AWriter.WriteInt(used[runStart]);
          AWriter.BeginArray;
            for k := runStart to i do
              AWriter.WriteNumber(GlyphWidth1000(ttf, used[k]));
          AWriter.EndArray;
          Inc(i);
        end;
      AWriter.EndArray;
      AWriter.WriteName('CIDToGIDMap'); AWriter.WriteName('Identity');
    AWriter.EndDict;
  AWriter.EndObject;

  cmapText := BuildToUnicodeCMap(used, codepoints);
  SetLength(cmapBytes, Length(cmapText));
  if Length(cmapText) > 0 then
    Move(cmapText[1], cmapBytes[0], Length(cmapText));
  toUnicodeId := EmitStreamMaybeCompressed(AWriter, cmapBytes, ACompress, -1);

  Result := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('Font');
      AWriter.WriteName('Subtype');  AWriter.WriteName('Type0');
      AWriter.WriteName('BaseFont'); AWriter.WriteName(fontName);
      AWriter.WriteName('Encoding'); AWriter.WriteName('Identity-H');
      AWriter.WriteName('DescendantFonts');
      AWriter.BeginArray;
        AWriter.WriteRef(cidFontId);
      AWriter.EndArray;
      AWriter.WriteName('ToUnicode'); AWriter.WriteRef(toUnicodeId);
    AWriter.EndDict;
  AWriter.EndObject;
end;

end.
