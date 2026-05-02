// Copyright (c) 2026 Steve Maughan — MIT License (see LICENSE at repo root).

unit smPDF;

interface

uses
  SysUtils, Classes, Types, UITypes, Generics.Collections, Vcl.Graphics,
  smPDF.Page, smPDF.Writer, smPDF.Fonts, smPDF.TTF, smPDF.Images;

type
  EPDFError = class(Exception);

  // Internal: result of resolving Font.Name + Bold + Italics to either a
  // built-in PDF font or an installed TTF. Exposed in interface only because
  // private TsmPDF method signatures need it.
  TPDFResolvedFont = record
    PdfFontName: string;
    IsStandard:  Boolean;
    StdFont:     TStandardFont;
    TTFFont:     TTTFFont;
  end;

  TPDFOrientation = (poPortrait, poLandscape);

  TPDFPaperSize = (
    psLetter,
    psLegal,
    psA2,
    psA3,
    psA4,
    psA5,
    psCustom
  );

  TPDFStrokeStyle = (ssNone, ssThin, ssMedium, ssThick);

  TPDFPenStyle = (penSolid, penDash, penDot, penDashDot, penNone);

  TPDFBrushStyle = (brushSolid, brushClear);

  TPDFTextPadding = (tpNone, tpTight, tpSingle, tpDouble);

  TPDFLineCap  = (lcButt, lcRound, lcSquare);
  TPDFLineJoin = (ljMiter, ljRound, ljBevel);

  TPDFPointList = TList<TPoint>;

  TPDFFont = class
  strict private
    fName:        string;
    fSize:        Integer;
    fColor:       TColor;
    fStrokeColor: TColor;
    fUnderline:   Boolean;
    fItalics:     Boolean;
    fBold:        Boolean;
    fStrokeStyle: TPDFStrokeStyle;
  public
    constructor Create;

    property Name:        string          read fName        write fName;
    property Size:        Integer         read fSize        write fSize;
    property Color:       TColor          read fColor       write fColor;
    property Bold:        Boolean         read fBold        write fBold;
    property Italics:     Boolean         read fItalics     write fItalics;
    property Underline:  Boolean          read fUnderline   write fUnderline;
    property StrokeStyle: TPDFStrokeStyle read fStrokeStyle write fStrokeStyle;
    property StrokeColor: TColor          read fStrokeColor write fStrokeColor;
  end;

  TPDFPen = class
  strict private
    fColor:    TColor;
    fWidth:    Double;
    fStyle:    TPDFPenStyle;
    fLineCap:  TPDFLineCap;
    fLineJoin: TPDFLineJoin;
  public
    constructor Create;

    property Color:    TColor       read fColor    write fColor;
    property Width:    Double       read fWidth    write fWidth;
    property Style:    TPDFPenStyle read fStyle    write fStyle;
    property LineCap:  TPDFLineCap  read fLineCap  write fLineCap;
    property LineJoin: TPDFLineJoin read fLineJoin write fLineJoin;
  end;

  TPDFBrush = class
  strict private
    fColor: TColor;
    fStyle: TPDFBrushStyle;
  public
    constructor Create;

    property Color: TColor         read fColor write fColor;
    property Style: TPDFBrushStyle read fStyle write fStyle;
  end;

  TsmPDF = class
  strict private
    fSize:            TPDFPaperSize;
    fOrientation:     TPDFOrientation;
    fDPI:             Integer;
    fHeight:          Integer;
    fWidth:           Integer;
    fPaperColor:      TColor;
    fCompressStreams: Boolean;
    fPen:             TPDFPen;
    fFont:            TPDFFont;
    fBrush:           TPDFBrush;
    fPages:             TObjectList<TPDFPage>;
    fCurrentPage:       TPDFPage;
    fTTFFonts:          TObjectDictionary<string, TTTFFont>;  // PostScript name -> font
    fImageData:         TDictionary<string, TPDFImageData>;   // image key -> extracted data
    fImageKeyByPicture: TDictionary<TObject, string>;         // TPicture pointer -> key (for dedup)

    procedure ResolvePaperSize(APaperSize: TPDFPaperSize; ADPI, AWidth, AHeight: Integer; out AWidthPx, AHeightPx: Integer);
    procedure EnsureCurrentPage;
    procedure EmitOneTextLine(const AText: string; X, Y: Integer; ASizePt: Double);

    function ResolveCurrentFont: TPDFResolvedFont;
    function MeasureWidthPt(const AResolved: TPDFResolvedFont; ASizePt: Double; const AAnsi: AnsiString): Double;
    function FontAscentPt(const AResolved: TPDFResolvedFont; ASizePt: Double): Double;
    function FontLineHeightPt(const AResolved: TPDFResolvedFont; ASizePt: Double): Double;

    function EmitTrueTypeFont(AWriter: TPDFWriter; ATTF: TTTFFont): TPDFObjectId;
    function EmitImageObject(AWriter: TPDFWriter; const AData: TPDFImageData): TPDFObjectId;
    function GetOrAddImage(APicture: TPicture): string;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure NewPage(const APaperSize: TPDFPaperSize; const AOrientation: TPDFOrientation;
      const ADPI: Integer = 300; const APaperColor: TColor = clWhite;
      const AWidth: Integer = 0; const AHeight: Integer = 0); overload;
    procedure NewPage; overload;

    procedure Save(const AFileName: string); overload;
    procedure Save(const AFileName: string; const AEmbedFonts: Boolean); overload;

    // AAngle rotates the text counter-clockwise (in degrees) around (X, Y) —
    // matches VCL TFont.Orientation. 0 = horizontal, 90 = reads upward,
    // -90 = reads downward, 180 = upside down. The Brush text-background,
    // Font.Underline, and Font.StrokeStyle outline all rotate with the text.
    procedure DrawText(const AText: string; X, Y: Integer; AAngle: Double = 0); overload;
    procedure DrawText(const AText: string; ARect: TRect); overload;
    procedure DrawText(const AText: string; ARect: TRect; AAlignment: TAlignment); overload;
    procedure DrawParagraph(const AText: string; ARect: TRect; AAlignment: TAlignment;
      APadding: TPDFTextPadding);

    // Measure text in pixels at the current page DPI, using the current Font
    // (Name/Size/Bold/Italics). All four require an active page (NewPage first)
    // so DPI is unambiguous.
    function TextWidth(const AText: string): Integer;
    function TextHeight(const AText: string): Integer;
    function TextExtent(const AText: string): TSize;

    // Word-wrap AText into AMaxWidthPx using the same path as DrawParagraph and
    // return the resulting block size (widest line × N lines × line-height).
    function MeasureParagraph(const AText: string; AMaxWidthPx: Integer; APadding: TPDFTextPadding = tpSingle): TSize;

    procedure DrawLine(const x1, y1, x2, y2: Integer);
    procedure DrawBox(const x1, y1, x2, y2: Integer);
    procedure DrawOval(const x1, y1, x2, y2: Integer);
    procedure DrawMultiLine(const APointList: TPDFPointList);

    // DrawPolygon walks the point list as a closed polygon. Whenever a point
    // equals the start of the current subpath, the subpath is closed and the
    // next point begins a new subpath. Nested subpaths become holes via the
    // even-odd fill rule. An unclosed final subpath is auto-closed at the end.
    procedure DrawPolygon(const APointList: TPDFPointList); overload;

    // Same, but constrained to the given rectangle. Polygon geometry outside
    // the rect is hidden by a PDF clip path; coordinates are not modified.
    procedure DrawPolygon(const APointList: TPDFPointList; AClipRect: TRect); overload;

    procedure DrawPicture(const APicture: TPicture; ARect: TRect;
      AAlignment: TAlignment = taLeftJustify; AStretch: Boolean = False); overload;
    procedure DrawPicture(const APicture: TPicture; x1, y1: Integer); overload;

    function PageCount: Integer;

    property Size:            TPDFPaperSize   read fSize;
    property Orientation:     TPDFOrientation read fOrientation;
    property Width:           Integer         read fWidth;
    property Height:          Integer         read fHeight;
    property DPI:             Integer         read fDPI;
    property CompressStreams: Boolean         read fCompressStreams write fCompressStreams;
    property Font:            TPDFFont        read fFont;
    property Pen:             TPDFPen         read fPen;
    property Brush:           TPDFBrush       read fBrush;
    property PaperColor:      TColor          read fPaperColor;
  end;

implementation

uses
  System.Math, smPDF.Geometry, smPDF.Types, smPDF.WinFonts;

{ TPDFFont }

constructor TPDFFont.Create;
begin
  inherited;
  fName        := 'Helvetica';
  fSize        := 12;
  fColor       := clBlack;
  fStrokeColor := clBlack;
  fStrokeStyle := ssNone;
end;

{ TPDFPen }

constructor TPDFPen.Create;
begin
  inherited;
  fColor    := clBlack;
  fWidth    := 1.0;
  fStyle    := penSolid;
  fLineCap  := lcButt;
  fLineJoin := ljMiter;
end;

{ TPDFBrush }

constructor TPDFBrush.Create;
begin
  inherited;
  fColor := clWhite;
  fStyle := brushClear;
end;

{ TsmPDF }

constructor TsmPDF.Create;
begin
  inherited;
  fPen               := TPDFPen.Create;
  fBrush             := TPDFBrush.Create;
  fFont              := TPDFFont.Create;
  fPages             := TObjectList<TPDFPage>.Create(True);
  fTTFFonts          := TObjectDictionary<string, TTTFFont>.Create([doOwnsValues]);
  fImageData         := TDictionary<string, TPDFImageData>.Create;
  fImageKeyByPicture := TDictionary<TObject, string>.Create;
  fCurrentPage       := nil;
  fCompressStreams := True;
  fSize            := psA4;
  fOrientation     := poPortrait;
  fDPI             := 300;
end;

destructor TsmPDF.Destroy;
begin
  fImageKeyByPicture.Free;
  fImageData.Free;
  fTTFFonts.Free;
  fPages.Free;
  fFont.Free;
  fBrush.Free;
  fPen.Free;
  inherited;
end;

function TsmPDF.ResolveCurrentFont: TPDFResolvedFont;
var
  ttfPath: string;
  ttf: TTTFFont;
begin
  if IsStandard14FamilyName(fFont.Name) then
  begin
    Result.IsStandard  := True;
    Result.TTFFont     := nil;
    Result.StdFont     := ResolveStandardFont(fFont.Name, fFont.Bold, fFont.Italics);
    Result.PdfFontName := StandardFontPdfName(Result.StdFont);
    Exit;
  end;

  ttfPath := LookupSystemTTFPath(fFont.Name, fFont.Bold, fFont.Italics);
  if ttfPath = '' then
  begin
    // Unknown family and no installed TTF -> fall back to Helvetica
    Result.IsStandard  := True;
    Result.TTFFont     := nil;
    Result.StdFont     := ResolveStandardFont('Helvetica', fFont.Bold, fFont.Italics);
    Result.PdfFontName := StandardFontPdfName(Result.StdFont);
    Exit;
  end;

  // Load + cache by PostScript name (each bold/italic variant is its own file)
  ttf := TTTFFont.Create(ttfPath);
  try
    var psName := ttf.Metrics.PostScriptName;
    if fTTFFonts.ContainsKey(psName) then
    begin
      // Already loaded a font with this PostScript name; reuse the cached
      // instance and discard the just-loaded duplicate.
      ttf.Free;
      ttf := fTTFFonts[psName];
    end
    else
      fTTFFonts.Add(psName, ttf);
  except
    ttf.Free;
    raise;
  end;

  Result.IsStandard  := False;
  Result.TTFFont     := ttf;
  Result.StdFont     := sfHelvetica;  // unused
  Result.PdfFontName := ttf.Metrics.PostScriptName;
end;

function TsmPDF.MeasureWidthPt(const AResolved: TPDFResolvedFont; ASizePt: Double;
  const AAnsi: AnsiString): Double;
var
  i, sumUnits: Integer;
begin
  if AResolved.IsStandard then
    Result := StandardFontTextWidth(AResolved.StdFont, ASizePt, AAnsi)
  else
  begin
    sumUnits := 0;
    for i := 1 to Length(AAnsi) do
      sumUnits := sumUnits + AResolved.TTFFont.CharWidthWinAnsi(Byte(AAnsi[i]));
    if AResolved.TTFFont.Metrics.UnitsPerEm = 0 then
      Result := 0
    else
      Result := sumUnits * ASizePt / AResolved.TTFFont.Metrics.UnitsPerEm;
  end;
end;

function TsmPDF.FontAscentPt(const AResolved: TPDFResolvedFont; ASizePt: Double): Double;
begin
  if AResolved.IsStandard then
    Result := StandardFontAscent(AResolved.StdFont, ASizePt)
  else
    Result := AResolved.TTFFont.Metrics.Ascent
            * ASizePt / AResolved.TTFFont.Metrics.UnitsPerEm;
end;

function TsmPDF.FontLineHeightPt(const AResolved: TPDFResolvedFont; ASizePt: Double): Double;
begin
  // Same 1.2x convention for both Standard 14 and TTF.
  Result := 1.2 * ASizePt;
end;

function TsmPDF.EmitTrueTypeFont(AWriter: TPDFWriter; ATTF: TTTFFont): TPDFObjectId;
var
  m: TTTFFontMetrics;
  fontFileId, descriptorId: TPDFObjectId;
  i: Integer;
  bytesCopy: TBytes;
begin
  m := ATTF.Metrics;

  // FontFile2 — embedded TTF stream with /Length1 = original file length
  bytesCopy := ATTF.Bytes;
  fontFileId := AWriter.EmitStreamObject(bytesCopy,
    procedure(w: TPDFWriter)
    begin
      w.WriteName('Length1'); w.WriteInt(Length(bytesCopy));
    end);

  // FontDescriptor
  descriptorId := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('FontDescriptor');
      AWriter.WriteName('FontName'); AWriter.WriteName(m.PostScriptName);
      AWriter.WriteName('Flags');    AWriter.WriteInt(Integer(m.PdfFlags));

      AWriter.WriteName('FontBBox');
      AWriter.BeginArray;
        AWriter.WriteInt(ATTF.FontUnitsToPdf(m.XMin));
        AWriter.WriteInt(ATTF.FontUnitsToPdf(m.YMin));
        AWriter.WriteInt(ATTF.FontUnitsToPdf(m.XMax));
        AWriter.WriteInt(ATTF.FontUnitsToPdf(m.YMax));
      AWriter.EndArray;

      AWriter.WriteName('ItalicAngle'); AWriter.WriteNumber(m.ItalicAngle);
      AWriter.WriteName('Ascent');      AWriter.WriteInt(ATTF.FontUnitsToPdf(m.Ascent));
      AWriter.WriteName('Descent');     AWriter.WriteInt(ATTF.FontUnitsToPdf(m.Descent));
      AWriter.WriteName('CapHeight');   AWriter.WriteInt(ATTF.FontUnitsToPdf(m.CapHeight));
      AWriter.WriteName('StemV');       AWriter.WriteInt(m.StemV);
      AWriter.WriteName('FontFile2');   AWriter.WriteRef(fontFileId);
    AWriter.EndDict;
  AWriter.EndObject;

  // Font dictionary (TrueType)
  Result := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');           AWriter.WriteName('Font');
      AWriter.WriteName('Subtype');        AWriter.WriteName('TrueType');
      AWriter.WriteName('BaseFont');       AWriter.WriteName(m.PostScriptName);
      AWriter.WriteName('Encoding');       AWriter.WriteName('WinAnsiEncoding');
      AWriter.WriteName('FirstChar');      AWriter.WriteInt(32);
      AWriter.WriteName('LastChar');       AWriter.WriteInt(255);
      AWriter.WriteName('Widths');
      AWriter.BeginArray;
        for i := 32 to 255 do
          AWriter.WriteInt(ATTF.FontUnitsToPdf(ATTF.CharWidthWinAnsi(Byte(i))));
      AWriter.EndArray;
      AWriter.WriteName('FontDescriptor'); AWriter.WriteRef(descriptorId);
    AWriter.EndDict;
  AWriter.EndObject;
end;

procedure TsmPDF.ResolvePaperSize(APaperSize: TPDFPaperSize; ADPI, AWidth, AHeight: Integer;
  out AWidthPx, AHeightPx: Integer);
begin
  case APaperSize of
    psLetter: begin AWidthPx := PointsToPixels(612.0,    ADPI); AHeightPx := PointsToPixels(792.0,    ADPI); end;
    psLegal:  begin AWidthPx := PointsToPixels(612.0,    ADPI); AHeightPx := PointsToPixels(1008.0,   ADPI); end;
    psA2:     begin AWidthPx := PointsToPixels(1190.55,  ADPI); AHeightPx := PointsToPixels(1683.78,  ADPI); end;
    psA3:     begin AWidthPx := PointsToPixels(841.89,   ADPI); AHeightPx := PointsToPixels(1190.55,  ADPI); end;
    psA4:     begin AWidthPx := PointsToPixels(595.28,   ADPI); AHeightPx := PointsToPixels(841.89,   ADPI); end;
    psA5:     begin AWidthPx := PointsToPixels(419.53,   ADPI); AHeightPx := PointsToPixels(595.28,   ADPI); end;
    psCustom:
      begin
        if (AWidth <= 0) or (AHeight <= 0) then
          raise EPDFError.Create('psCustom requires positive width and height (pixels)');
        AWidthPx  := AWidth;
        AHeightPx := AHeight;
      end;
  else
    raise EPDFError.Create('Unknown paper size');
  end;
end;

procedure TsmPDF.NewPage(const APaperSize: TPDFPaperSize; const AOrientation: TPDFOrientation;
  const ADPI: Integer; const APaperColor: TColor;
  const AWidth: Integer; const AHeight: Integer);
var
  widthPx, heightPx, tmp: Integer;
  rgb: Cardinal;
  r, g, b: Double;
begin
  if ADPI <= 0 then
    raise EPDFError.Create('NewPage: ADPI must be positive');

  ResolvePaperSize(APaperSize, ADPI, AWidth, AHeight, widthPx, heightPx);

  if AOrientation = poLandscape then
  begin
    tmp := widthPx;
    widthPx := heightPx;
    heightPx := tmp;
  end;

  fSize        := APaperSize;
  fOrientation := AOrientation;
  fDPI         := ADPI;
  fWidth       := widthPx;
  fHeight      := heightPx;
  fPaperColor  := APaperColor;

  fCurrentPage := TPDFPage.Create(widthPx, heightPx, ADPI);
  fPages.Add(fCurrentPage);

  // Paint the page background as a full-page filled rectangle. Skipped for
  // clWhite so default-coloured pages stay byte-identical to the pre-feature
  // output. Emitted before any user drawing so subsequent content sits on top.
  // (RGB decomposition inlined because ColorToRGBFloats is declared later in
  // this implementation section than NewPage.)
  if APaperColor <> clWhite then
  begin
    rgb := Cardinal(ColorToRGB(APaperColor));
    r := ( rgb         and $FF) / 255.0;
    g := ((rgb shr  8) and $FF) / 255.0;
    b := ((rgb shr 16) and $FF) / 255.0;
    fCurrentPage.SaveState;
    fCurrentPage.SetFillRGB(r, g, b);
    fCurrentPage.UserRectanglePath(0, 0, widthPx, heightPx);
    fCurrentPage.FillEvenOdd;
    fCurrentPage.RestoreState;
  end;
end;

procedure TsmPDF.NewPage;
begin
  NewPage(psA4, poPortrait, 300);
end;

procedure TsmPDF.EnsureCurrentPage;
begin
  if fCurrentPage = nil then
    raise EPDFError.Create('No active page. Call NewPage before drawing.');
end;

procedure TsmPDF.Save(const AFileName: string);
var
  writer: TPDFWriter;
  catalogId, pagesRootId, fontId, imgId: TPDFObjectId;
  pageIds: array of TPDFObjectId;
  fontIds, imageIds: TDictionary<string, TPDFObjectId>;
  fontNamesAcrossDoc, imageKeysAcrossDoc: TList<string>;
  pageFontName, pageImageKey: string;
  i: Integer;
  bytes: TBytes;
  fs: TFileStream;
  isSymbolic: Boolean;
begin
  if fPages.Count = 0 then
    raise EPDFError.Create('Cannot save: no pages added. Call NewPage first.');

  fontIds             := TDictionary<string, TPDFObjectId>.Create;
  imageIds            := TDictionary<string, TPDFObjectId>.Create;
  fontNamesAcrossDoc  := TList<string>.Create;
  imageKeysAcrossDoc  := TList<string>.Create;
  writer              := TPDFWriter.Create;
  try
    catalogId := writer.BeginObject;
      writer.BeginDict;
        writer.WriteName('Type');  writer.WriteName('Catalog');
        writer.WriteName('Pages'); writer.WriteRef(2);
      writer.EndDict;
    writer.EndObject;

    // Reserve pages-root id (2) so pages can reference it as /Parent.
    pagesRootId := writer.ReserveObjectId;

    // Aggregate fonts used across all pages, in stable order.
    for i := 0 to fPages.Count - 1 do
      for pageFontName in fPages[i].UsedFontNames do
        if fontNamesAcrossDoc.IndexOf(pageFontName) < 0 then
          fontNamesAcrossDoc.Add(pageFontName);

    // Aggregate images used across all pages, in stable order.
    for i := 0 to fPages.Count - 1 do
      for pageImageKey in fPages[i].UsedImageKeys do
        if imageKeysAcrossDoc.IndexOf(pageImageKey) < 0 then
          imageKeysAcrossDoc.Add(pageImageKey);

    // Emit font dicts. Standard 14 -> single Type1 dict; TTF -> Font + Descriptor + FontFile2.
    for pageFontName in fontNamesAcrossDoc do
    begin
      if fTTFFonts.ContainsKey(pageFontName) then
      begin
        fontId := EmitTrueTypeFont(writer, fTTFFonts[pageFontName]);
        fontIds.Add(pageFontName, fontId);
      end
      else
      begin
        isSymbolic := (pageFontName = 'Symbol') or (pageFontName = 'ZapfDingbats');
        fontId := writer.BeginObject;
          writer.BeginDict;
            writer.WriteName('Type');     writer.WriteName('Font');
            writer.WriteName('Subtype');  writer.WriteName('Type1');
            writer.WriteName('BaseFont'); writer.WriteName(pageFontName);
            if not isSymbolic then
            begin
              writer.WriteName('Encoding'); writer.WriteName('WinAnsiEncoding');
            end;
          writer.EndDict;
        writer.EndObject;
        fontIds.Add(pageFontName, fontId);
      end;
    end;

    // Emit image XObjects (SMask first when needed; EmitImageObject handles ordering).
    for pageImageKey in imageKeysAcrossDoc do
    begin
      imgId := EmitImageObject(writer, fImageData[pageImageKey]);
      imageIds.Add(pageImageKey, imgId);
    end;

    SetLength(pageIds, fPages.Count);
    for i := 0 to fPages.Count - 1 do
      pageIds[i] := fPages[i].Emit(writer, pagesRootId, fontIds, imageIds);

    writer.BeginReservedObject(pagesRootId);
      writer.BeginDict;
        writer.WriteName('Type'); writer.WriteName('Pages');
        writer.WriteName('Kids');
        writer.BeginArray;
          for i := 0 to fPages.Count - 1 do
            writer.WriteRef(pageIds[i]);
        writer.EndArray;
        writer.WriteName('Count'); writer.WriteInt(fPages.Count);
      writer.EndDict;
    writer.EndObject;

    bytes := writer.Finalize(catalogId);

    fs := TFileStream.Create(AFileName, fmCreate);
    try
      if Length(bytes) > 0 then
        fs.WriteBuffer(bytes[0], Length(bytes));
    finally
      fs.Free;
    end;
  finally
    writer.Free;
    imageKeysAcrossDoc.Free;
    fontNamesAcrossDoc.Free;
    imageIds.Free;
    fontIds.Free;
  end;
end;

procedure TsmPDF.Save(const AFileName: string; const AEmbedFonts: Boolean);
begin
  // AEmbedFonts is honoured starting Phase 4 (TTF embedding).
  Save(AFileName);
end;

function TsmPDF.PageCount: Integer;
begin
  Result := fPages.Count;
end;

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------

// Convert a TColor (possibly a system colour) to the three PDF DeviceRGB floats.
procedure ColorToRGBFloats(AColor: TColor; out R, G, B: Double);
var
  rgb: Cardinal;
begin
  rgb := Cardinal(ColorToRGB(AColor));
  R   := ( rgb         and $FF) / 255.0;
  G   := ((rgb shr  8) and $FF) / 255.0;
  B   := ((rgb shr 16) and $FF) / 255.0;
end;

// Translate the user-facing pen style into a PDF dash array.
procedure ApplyPenDash(APage: TPDFPage; AStyle: TPDFPenStyle);
begin
  case AStyle of
    penSolid:   APage.SetDashPattern([],         0.0);
    penDash:    APage.SetDashPattern([3.0, 2.0], 0.0);
    penDot:     APage.SetDashPattern([1.0, 2.0], 0.0);
    penDashDot: APage.SetDashPattern([3.0, 2.0, 1.0, 2.0], 0.0);
    penNone:    ;  // never invoked: callers skip the stroke entirely
  end;
end;

procedure ApplyPenLineEnds(APage: TPDFPage; ACap: TPDFLineCap; AJoin: TPDFLineJoin);
begin
  APage.SetLineCap(Ord(ACap));    // lcButt=0, lcRound=1, lcSquare=2 — same as PDF
  APage.SetLineJoin(Ord(AJoin));  // ljMiter=0, ljRound=1, ljBevel=2 — same as PDF
end;

// Apply the current pen + brush as PDF graphics state on the page.
procedure ApplyStrokeAndFillState(APage: TPDFPage; APen: TPDFPen; ABrush: TPDFBrush);
var
  r, g, b: Double;
begin
  if APen.Style <> penNone then
  begin
    ColorToRGBFloats(APen.Color, r, g, b);
    APage.SetStrokeRGB(r, g, b);
    APage.SetLineWidthPt(APen.Width);
    ApplyPenDash(APage, APen.Style);
    ApplyPenLineEnds(APage, APen.LineCap, APen.LineJoin);
  end;
  if ABrush.Style = brushSolid then
  begin
    ColorToRGBFloats(ABrush.Color, r, g, b);
    APage.SetFillRGB(r, g, b);
  end;
end;

// Fill a rectangle using only the Brush, ignoring Pen. Used as the text
// background ("highlighter") behind DrawText / DrawParagraph, mirroring the
// way VCL TCanvas uses Brush during TextOut. No-op when the brush is clear.
procedure FillRectWithBrush(APage: TPDFPage; ABrush: TPDFBrush;
  X1, Y1, X2, Y2: Integer);
var
  r, g, b: Double;
begin
  if ABrush.Style <> brushSolid then Exit;
  ColorToRGBFloats(ABrush.Color, r, g, b);
  APage.SaveState;
  APage.SetFillRGB(r, g, b);
  APage.UserRectanglePath(X1, Y1, X2, Y2);
  APage.FillEvenOdd;
  APage.RestoreState;
end;

// Pick the right paint operator for the current pen + brush combination.
procedure PaintByPenAndBrush(APage: TPDFPage; APen: TPDFPen; ABrush: TPDFBrush; AUseEvenOdd: Boolean);
var
  doStroke, doFill: Boolean;
begin
  doStroke := APen.Style <> penNone;
  doFill   := ABrush.Style = brushSolid;
  if doFill and doStroke then
  begin
    if AUseEvenOdd then APage.FillAndStrokeEvenOdd
    else APage.FillAndStrokeEvenOdd;  // (Phase 2 only emits even-odd; non-zero added later if needed)
  end
  else if doFill then
    APage.FillEvenOdd
  else if doStroke then
    APage.Stroke
  else
    APage.DiscardPath;
end;

// Walk a polygon point list, emitting a path with subpaths split on closure
// (a point that equals the start of the current subpath, *after* the path
// has moved away from the start at least once). The "moved away" guard
// prevents pathological closure when callers feed integer-rounded geographic
// coordinates: many consecutive vertices can round to the same pixel as the
// subpath start, and treating those as a close would split a single ring
// into many degenerate subpaths and leave a stray lineTo in the next ring.
procedure EmitPolygonPath(APage: TPDFPage; const APointList: TPDFPointList);
var
  i: Integer;
  subStart, p: TPoint;
  hasOpen, hasMovedAway: Boolean;
begin
  hasOpen      := False;
  hasMovedAway := False;
  i := 0;
  while i < APointList.Count do
  begin
    p := APointList[i];
    if not hasOpen then
    begin
      subStart     := p;
      APage.UserMoveTo(p.X, p.Y);
      hasOpen      := True;
      hasMovedAway := False;
    end
    else if (p.X = subStart.X) and (p.Y = subStart.Y) then
    begin
      if hasMovedAway then
      begin
        APage.ClosePath;
        hasOpen      := False;
        hasMovedAway := False;
      end;
      // else: redundant duplicate of subStart before any lineTo — ignore.
    end
    else
    begin
      APage.UserLineTo(p.X, p.Y);
      hasMovedAway := True;
    end;
    Inc(i);
  end;
  if hasOpen then
    APage.ClosePath;
end;

// ------------------------------------------------------------------
// Phase 5 — image rendering
// ------------------------------------------------------------------

function TsmPDF.GetOrAddImage(APicture: TPicture): string;
var
  data: TPDFImageData;
begin
  if fImageKeyByPicture.TryGetValue(APicture, Result) then Exit;
  Result := 'img' + IntToStr(fImageData.Count);
  data   := ExtractImageData(APicture);
  fImageData.Add(Result, data);
  fImageKeyByPicture.Add(APicture, Result);
end;

procedure TsmPDF.DrawPicture(const APicture: TPicture; x1, y1: Integer);
var
  key, res: string;
  data: TPDFImageData;
begin
  EnsureCurrentPage;
  if (APicture = nil) or (APicture.Graphic = nil) then Exit;

  key := GetOrAddImage(APicture);
  data := fImageData[key];
  res := fCurrentPage.UseImage(key);
  fCurrentPage.DrawImageUserRect(res, x1, y1,
    x1 + data.Width, y1 + data.Height);
end;

procedure TsmPDF.DrawPicture(const APicture: TPicture; ARect: TRect; AAlignment: TAlignment;
  AStretch: Boolean);
var
  key, res: string;
  data: TPDFImageData;
  x1, y1, x2, y2: Integer;
begin
  EnsureCurrentPage;
  if (APicture = nil) or (APicture.Graphic = nil) then Exit;

  key := GetOrAddImage(APicture);
  data := fImageData[key];
  res := fCurrentPage.UseImage(key);

  if AStretch then
  begin
    // Fill the rectangle exactly; aspect ratio may distort.
    x1 := ARect.Left;  y1 := ARect.Top;
    x2 := ARect.Right; y2 := ARect.Bottom;
  end
  else
  begin
    case AAlignment of
      taCenter:
        x1 := ARect.Left + (ARect.Right - ARect.Left - data.Width) div 2;
      taRightJustify:
        x1 := ARect.Right - data.Width;
    else
      x1 := ARect.Left;
    end;
    y1 := ARect.Top;
    x2 := x1 + data.Width;
    y2 := y1 + data.Height;
  end;

  fCurrentPage.DrawImageUserRect(res, x1, y1, x2, y2);
end;

function TsmPDF.EmitImageObject(AWriter: TPDFWriter; const AData: TPDFImageData): TPDFObjectId;
var
  smaskId: TPDFObjectId;
  payload, smaskBytes: TBytes;
  colorspace: string;
  width:  Integer;
  height: Integer;
  bitsPerComp: Integer;
  numComps: Integer;
begin
  // Capture record fields locally so the inner anonymous procs can close over them.
  width       := AData.Width;
  height      := AData.Height;
  bitsPerComp := AData.BitsPerComp;
  numComps    := AData.NumComps;
  smaskId     := 0;

  // SMask object first (so the main image dict can reference it directly).
  if AData.Kind = ikRgbWithAlpha then
  begin
    smaskBytes := FlateCompress(AData.AlphaMask);
    smaskId := AWriter.EmitStreamObject(smaskBytes,
      procedure(w: TPDFWriter)
      begin
        w.WriteName('Type');             w.WriteName('XObject');
        w.WriteName('Subtype');          w.WriteName('Image');
        w.WriteName('Width');            w.WriteInt(width);
        w.WriteName('Height');           w.WriteInt(height);
        w.WriteName('ColorSpace');       w.WriteName('DeviceGray');
        w.WriteName('BitsPerComponent'); w.WriteInt(8);
        w.WriteName('Filter');           w.WriteName('FlateDecode');
      end);
  end;

  case AData.Kind of
    ikJpeg:
      begin
        if numComps = 1 then colorspace := 'DeviceGray' else colorspace := 'DeviceRGB';
        Result := AWriter.EmitStreamObject(AData.Body,
          procedure(w: TPDFWriter)
          begin
            w.WriteName('Type');             w.WriteName('XObject');
            w.WriteName('Subtype');          w.WriteName('Image');
            w.WriteName('Width');            w.WriteInt(width);
            w.WriteName('Height');           w.WriteInt(height);
            w.WriteName('ColorSpace');       w.WriteName(colorspace);
            w.WriteName('BitsPerComponent'); w.WriteInt(bitsPerComp);
            w.WriteName('Filter');           w.WriteName('DCTDecode');
          end);
      end;
    ikRgbOpaque:
      begin
        payload := FlateCompress(AData.Body);
        Result := AWriter.EmitStreamObject(payload,
          procedure(w: TPDFWriter)
          begin
            w.WriteName('Type');             w.WriteName('XObject');
            w.WriteName('Subtype');          w.WriteName('Image');
            w.WriteName('Width');            w.WriteInt(width);
            w.WriteName('Height');           w.WriteInt(height);
            w.WriteName('ColorSpace');       w.WriteName('DeviceRGB');
            w.WriteName('BitsPerComponent'); w.WriteInt(8);
            w.WriteName('Filter');           w.WriteName('FlateDecode');
          end);
      end;
    ikRgbWithAlpha:
      begin
        payload := FlateCompress(AData.Body);
        Result := AWriter.EmitStreamObject(payload,
          procedure(w: TPDFWriter)
          begin
            w.WriteName('Type');             w.WriteName('XObject');
            w.WriteName('Subtype');          w.WriteName('Image');
            w.WriteName('Width');            w.WriteInt(width);
            w.WriteName('Height');           w.WriteInt(height);
            w.WriteName('ColorSpace');       w.WriteName('DeviceRGB');
            w.WriteName('BitsPerComponent'); w.WriteInt(8);
            w.WriteName('Filter');           w.WriteName('FlateDecode');
            w.WriteName('SMask');            w.WriteRef(smaskId);
          end);
      end;
  else
    raise EPDFError.Create('Unknown image kind');
  end;
end;

// ------------------------------------------------------------------
// Phase 3 — text rendering with the 14 standard PDF fonts
// ------------------------------------------------------------------

// Word-wrap helper: split text on whitespace and group words into lines that
// fit within AMaxWidthPoints when measured at the given font + size.
// Returns a TStringList the caller must Free.
function WrapTextToLines(const AText: string; AFont: TStandardFont;
  ASizePt: Double; AMaxWidthPoints: Double): TStringList;
var
  words: TArray<string>;
  i: Integer;
  currentLine, candidate: string;
  candidateAnsi: AnsiString;
  candidateWidth: Double;
begin
  Result := TStringList.Create;
  if AText = '' then Exit;

  words := AText.Split([' ', #9, #13, #10],
    TStringSplitOptions.ExcludeEmpty);
  if Length(words) = 0 then Exit;

  currentLine := '';
  for i := 0 to High(words) do
  begin
    if currentLine = '' then
      candidate := words[i]
    else
      candidate := currentLine + ' ' + words[i];

    candidateAnsi  := StringToWinAnsi(candidate);
    candidateWidth := StandardFontTextWidth(AFont, ASizePt, candidateAnsi);

    if (candidateWidth <= AMaxWidthPoints) or (currentLine = '') then
      currentLine := candidate
    else
    begin
      Result.Add(currentLine);
      currentLine := words[i];
    end;
  end;
  if currentLine <> '' then
    Result.Add(currentLine);
end;

// Map StrokeStyle to a point-width for outlined text. Scales with font size so
// the outline stays visually proportional, with a small absolute floor so very
// small text doesn't lose its outline to sub-pixel widths.
function TextStrokeWidthPt(AStyle: TPDFStrokeStyle; ASizePt: Double): Double;
begin
  case AStyle of
    ssThin:   Result := Max(0.025 * ASizePt, 0.25);
    ssMedium: Result := Max(0.05  * ASizePt, 0.50);
    ssThick:  Result := Max(0.10  * ASizePt, 1.00);
  else
    Result := 0;
  end;
end;

procedure TsmPDF.EmitOneTextLine(const AText: string; X, Y: Integer; ASizePt: Double);
var
  resolved: TPDFResolvedFont;
  resName: string;
  ansi: AnsiString;
  sizePt, ascentPt, ascentPx: Double;
  baselineYPx: Integer;
  r, g, b, sr, sg, sb: Double;
  textWidthPt, textWidthPx: Double;
  underlineYPx: Integer;
  underlineThicknessPt: Double;
  strokeText: Boolean;
begin
  sizePt := ASizePt;
  if sizePt <= 0 then sizePt := 12;

  resolved := ResolveCurrentFont;
  resName  := fCurrentPage.UseFont(resolved.PdfFontName);

  ansi := StringToWinAnsi(AText);

  ascentPt    := FontAscentPt(resolved, sizePt);
  ascentPx    := ascentPt * fDPI / 72.0;
  baselineYPx := Y + Round(ascentPx);

  strokeText := fFont.StrokeStyle <> ssNone;

  fCurrentPage.SaveState;
  ColorToRGBFloats(fFont.Color, r, g, b);
  fCurrentPage.SetFillRGB(r, g, b);
  if strokeText then
  begin
    ColorToRGBFloats(fFont.StrokeColor, sr, sg, sb);
    fCurrentPage.SetStrokeRGB(sr, sg, sb);
    fCurrentPage.SetLineWidthPt(TextStrokeWidthPt(fFont.StrokeStyle, sizePt));
  end;
  fCurrentPage.BeginText;
  fCurrentPage.SetTextFont(resName, sizePt);
  if strokeText then
    fCurrentPage.SetTextRenderingMode(2);  // fill + stroke each glyph
  fCurrentPage.SetTextMatrixUserBaseline(X, baselineYPx);
  fCurrentPage.ShowTextAnsi(ansi);
  fCurrentPage.EndText;
  fCurrentPage.RestoreState;

  if fFont.Underline and (Length(ansi) > 0) then
  begin
    textWidthPt := MeasureWidthPt(resolved, sizePt, ansi);
    textWidthPx := textWidthPt * fDPI / 72.0;

    underlineThicknessPt := 0.05 * sizePt;
    if underlineThicknessPt < 0.5 then underlineThicknessPt := 0.5;

    // Underline sits ~0.12em below the baseline (PDF underlinePosition convention).
    underlineYPx := baselineYPx + Round(0.12 * sizePt * fDPI / 72.0);

    fCurrentPage.SaveState;
    fCurrentPage.SetStrokeRGB(r, g, b);
    fCurrentPage.SetLineWidthPt(underlineThicknessPt);
    fCurrentPage.SetDashPattern([], 0);
    fCurrentPage.SetLineCap(0);
    fCurrentPage.UserMoveTo(X, underlineYPx);
    fCurrentPage.UserLineTo(X + Round(textWidthPx), underlineYPx);
    fCurrentPage.Stroke;
    fCurrentPage.RestoreState;
  end;
end;

procedure TsmPDF.DrawText(const AText: string; X, Y: Integer; AAngle: Double);
var
  ext: TSize;
  rotated: Boolean;
  thetaRad, cosT, sinT: Double;
  pivotPt: TPDFPointF;
  cm_e, cm_f: Double;
begin
  EnsureCurrentPage;
  if AText = '' then Exit;

  // Wrap the rest in q ... cm ... Q so the Brush background, the text, the
  // Underline stroke, and the StrokeStyle glyph outline all rotate together.
  // No cm is emitted when AAngle is zero, so default callers stay byte-clean.
  rotated := Abs(AAngle) > 1e-9;
  if rotated then
  begin
    thetaRad := AAngle * Pi / 180.0;
    cosT := Cos(thetaRad);
    sinT := Sin(thetaRad);
    pivotPt := PixelToPdfPoint(X, Y, fDPI, fCurrentPage.HeightPixels);
    // Affine that rotates by AAngle degrees CCW around the pivot in PDF coords.
    // PDF row-vector form [a b c d e f] = [cos, sin, -sin, cos, ex, ey] where:
    //   ex = px*(1 - cos) + py*sin
    //   ey = py*(1 - cos) - px*sin
    cm_e := pivotPt.X * (1 - cosT) + pivotPt.Y * sinT;
    cm_f := pivotPt.Y * (1 - cosT) - pivotPt.X * sinT;
    fCurrentPage.SaveState;
    fCurrentPage.ConcatMatrix(cosT, sinT, -sinT, cosT, cm_e, cm_f);
  end;

  if fBrush.Style = brushSolid then
  begin
    ext := TextExtent(AText);
    FillRectWithBrush(fCurrentPage, fBrush, X, Y, X + ext.cx, Y + ext.cy);
  end;
  EmitOneTextLine(AText, X, Y, fFont.Size);

  if rotated then
    fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawText(const AText: string; ARect: TRect);
begin
  DrawText(AText, ARect, taLeftJustify);
end;

procedure TsmPDF.DrawText(const AText: string; ARect: TRect; AAlignment: TAlignment);
const
  REF_SIZE_PT = 100.0;  // arbitrary; only ratios matter
var
  resolved: TPDFResolvedFont;
  ansi: AnsiString;
  refWidthPt, refLineHeightPt: Double;
  rectWidthPt, rectHeightPt: Double;
  sizePt: Double;
  textWidthPx, lineHeightPx: Double;
  x, y: Integer;
begin
  EnsureCurrentPage;

  rectWidthPt  := (ARect.Right  - ARect.Left) * 72.0 / fDPI;
  rectHeightPt := (ARect.Bottom - ARect.Top)  * 72.0 / fDPI;
  if (rectWidthPt <= 0) or (rectHeightPt <= 0) then Exit;

  // VCL TextRect-style background: paint the whole rect (independent of text
  // length / alignment) so the fill stays even when AText is empty.
  FillRectWithBrush(fCurrentPage, fBrush, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);

  if AText = '' then Exit;

  resolved := ResolveCurrentFont;
  ansi     := StringToWinAnsi(AText);

  // Pick the largest font size that fits the text inside ARect on both axes
  // while preserving the font's natural width:height ratio.
  refWidthPt      := MeasureWidthPt(resolved, REF_SIZE_PT, ansi);
  refLineHeightPt := FontLineHeightPt(resolved, REF_SIZE_PT);
  if (refWidthPt <= 0) or (refLineHeightPt <= 0) then Exit;

  sizePt := REF_SIZE_PT * Min(rectWidthPt  / refWidthPt,
                              rectHeightPt / refLineHeightPt);
  if sizePt <= 0 then Exit;

  textWidthPx  := MeasureWidthPt(resolved, sizePt, ansi) * fDPI / 72.0;
  lineHeightPx := FontLineHeightPt(resolved, sizePt)     * fDPI / 72.0;

  case AAlignment of
    taCenter:       x := ARect.Left + Round((ARect.Right - ARect.Left - textWidthPx) / 2);
    taRightJustify: x := ARect.Right - Round(textWidthPx);
  else
    x := ARect.Left;
  end;

  y := ARect.Top + Round((ARect.Bottom - ARect.Top - lineHeightPx) / 2);
  if y < ARect.Top then y := ARect.Top;

  EmitOneTextLine(AText, x, y, sizePt);
end;

procedure TsmPDF.DrawParagraph(const AText: string; ARect: TRect; AAlignment: TAlignment;
  APadding: TPDFTextPadding);
var
  font: TStandardFont;
  sizePt, paddingMult, lineHeightPx, maxWidthPt: Double;
  lines: TStringList;
  ansi: AnsiString;
  i, lineX, lineY: Integer;
  lineWidthPx: Double;
begin
  EnsureCurrentPage;

  // Single rect-sized background fill for the whole paragraph (not per-line).
  if (ARect.Right > ARect.Left) and (ARect.Bottom > ARect.Top) then
    FillRectWithBrush(fCurrentPage, fBrush, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);

  if AText = '' then Exit;

  sizePt := fFont.Size;
  if sizePt <= 0 then sizePt := 12;

  font := ResolveStandardFont(fFont.Name, fFont.Bold, fFont.Italics);

  case APadding of
    tpNone, tpTight: paddingMult := 1.0;
    tpSingle:        paddingMult := 1.2;
    tpDouble:        paddingMult := 2.4;
  else
    paddingMult := 1.2;
  end;
  lineHeightPx := paddingMult * sizePt * fDPI / 72.0;

  maxWidthPt := (ARect.Right - ARect.Left) * 72.0 / fDPI;

  lines := WrapTextToLines(AText, font, sizePt, maxWidthPt);
  try
    for i := 0 to lines.Count - 1 do
    begin
      ansi        := StringToWinAnsi(lines[i]);
      lineWidthPx := StandardFontTextWidth(font, sizePt, ansi) * fDPI / 72.0;

      case AAlignment of
        taCenter:
          lineX := ARect.Left + Round((ARect.Right - ARect.Left - lineWidthPx) / 2);
        taRightJustify:
          lineX := ARect.Right - Round(lineWidthPx);
      else
        lineX := ARect.Left;
      end;

      lineY := ARect.Top + Round(i * lineHeightPx);
      // Stop if we'd drop below the rect (Phase 3 truncates rather than
      // overflowing — caller can inspect rect height before calling for now).
      if lineY > ARect.Bottom then Break;

      EmitOneTextLine(lines[i], lineX, lineY, fFont.Size);
    end;
  finally
    lines.Free;
  end;
end;

// ------------------------------------------------------------------
// Text measurement
// ------------------------------------------------------------------

function TsmPDF.TextExtent(const AText: string): TSize;
var
  resolved: TPDFResolvedFont;
  ansi: AnsiString;
  sizePt, widthPt, lineHeightPt: Double;
begin
  EnsureCurrentPage;

  sizePt := fFont.Size;
  if sizePt <= 0 then sizePt := 12;

  resolved     := ResolveCurrentFont;
  lineHeightPt := FontLineHeightPt(resolved, sizePt);

  if AText = '' then
    widthPt := 0
  else
  begin
    ansi    := StringToWinAnsi(AText);
    widthPt := MeasureWidthPt(resolved, sizePt, ansi);
  end;

  Result := TSize.Create(
    Round(widthPt      * fDPI / 72.0),
    Round(lineHeightPt * fDPI / 72.0)
  );
end;

function TsmPDF.TextWidth(const AText: string): Integer;
begin
  Result := TextExtent(AText).cx;
end;

function TsmPDF.TextHeight(const AText: string): Integer;
begin
  Result := TextExtent(AText).cy;
end;

function TsmPDF.MeasureParagraph(const AText: string; AMaxWidthPx: Integer;
  APadding: TPDFTextPadding): TSize;
var
  font: TStandardFont;
  sizePt, paddingMult, lineHeightPx, maxWidthPt: Double;
  lines: TStringList;
  ansi: AnsiString;
  i: Integer;
  lineWidthPx, widestPx: Double;
begin
  EnsureCurrentPage;
  Result := TSize.Create(0, 0);
  if (AText = '') or (AMaxWidthPx <= 0) then Exit;

  sizePt := fFont.Size;
  if sizePt <= 0 then sizePt := 12;

  // Mirror DrawParagraph: word-wrap uses the standard-14 font corresponding to
  // the current Font.Name/Bold/Italics. TTF families fall back here too, so
  // measurements match what DrawParagraph will actually render.
  font := ResolveStandardFont(fFont.Name, fFont.Bold, fFont.Italics);

  case APadding of
    tpNone, tpTight: paddingMult := 1.0;
    tpSingle:        paddingMult := 1.2;
    tpDouble:        paddingMult := 2.4;
  else
    paddingMult := 1.2;
  end;
  lineHeightPx := paddingMult * sizePt * fDPI / 72.0;

  maxWidthPt := AMaxWidthPx * 72.0 / fDPI;

  lines := WrapTextToLines(AText, font, sizePt, maxWidthPt);
  try
    if lines.Count = 0 then Exit;
    widestPx := 0;
    for i := 0 to lines.Count - 1 do
    begin
      ansi        := StringToWinAnsi(lines[i]);
      lineWidthPx := StandardFontTextWidth(font, sizePt, ansi) * fDPI / 72.0;
      if lineWidthPx > widestPx then widestPx := lineWidthPx;
    end;
    Result := TSize.Create(Round(widestPx), Round(lines.Count * lineHeightPx));
  finally
    lines.Free;
  end;
end;

// ------------------------------------------------------------------
// Phase 2 — graphics primitives
// ------------------------------------------------------------------

procedure TsmPDF.DrawLine(const x1, y1, x2, y2: Integer);
var
  r, g, b: Double;
begin
  EnsureCurrentPage;
  if fPen.Style = penNone then Exit;  // lines have no fill; nothing to draw

  fCurrentPage.SaveState;
  ColorToRGBFloats(fPen.Color, r, g, b);
  fCurrentPage.SetStrokeRGB(r, g, b);
  fCurrentPage.SetLineWidthPt(fPen.Width);
  ApplyPenDash(fCurrentPage, fPen.Style);
  ApplyPenLineEnds(fCurrentPage, fPen.LineCap, fPen.LineJoin);
  fCurrentPage.UserMoveTo(x1, y1);
  fCurrentPage.UserLineTo(x2, y2);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawBox(const x1, y1, x2, y2: Integer);
begin
  EnsureCurrentPage;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  fCurrentPage.UserRectanglePath(x1, y1, x2, y2);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, False);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawOval(const x1, y1, x2, y2: Integer);
begin
  EnsureCurrentPage;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  fCurrentPage.UserOvalPath(x1, y1, x2, y2);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, False);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawMultiLine(const APointList: TPDFPointList);
var
  r, g, b: Double;
  i: Integer;
begin
  EnsureCurrentPage;
  if APointList.Count < 2 then Exit;
  if fPen.Style = penNone then Exit;  // open polylines have no fill

  fCurrentPage.SaveState;
  ColorToRGBFloats(fPen.Color, r, g, b);
  fCurrentPage.SetStrokeRGB(r, g, b);
  fCurrentPage.SetLineWidthPt(fPen.Width);
  ApplyPenDash(fCurrentPage, fPen.Style);
  ApplyPenLineEnds(fCurrentPage, fPen.LineCap, fPen.LineJoin);
  fCurrentPage.UserMoveTo(APointList[0].X, APointList[0].Y);
  for i := 1 to APointList.Count - 1 do
    fCurrentPage.UserLineTo(APointList[i].X, APointList[i].Y);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointList);
begin
  EnsureCurrentPage;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPath(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, True);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointList; AClipRect: TRect);
begin
  EnsureCurrentPage;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  fCurrentPage.SetClipRect(AClipRect.Left, AClipRect.Top, AClipRect.Right, AClipRect.Bottom);
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPath(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, True);
  fCurrentPage.RestoreState;
end;

end.
