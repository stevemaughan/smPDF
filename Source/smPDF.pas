// Copyright (c) 2026 Steve Maughan — MIT License (see LICENSE at repo root).

unit smPDF;

interface

uses
  SysUtils, Classes, Types, UITypes, Generics.Collections, Vcl.Graphics,
  smPDF.Page, smPDF.Writer, smPDF.Fonts, smPDF.TTF, smPDF.Images, smPDF.FontRegistry;

const
  // SemVer string, bumped per https://semver.org/. Read at runtime via
  // SMPDF_VERSION; useful for diagnostics, About boxes, and bug reports.
  SMPDF_VERSION = '1.0.0';

type
  EPDFError = class(Exception);

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

  TPDFFillRule = (frEvenOdd, frNonZero);

  TPDFLineCap  = (lcButt, lcRound, lcSquare);
  TPDFLineJoin = (ljMiter, ljRound, ljBevel);

  TPDFPointList  = TList<TPoint>;
  TPDFPointFList = TList<TPointF>;

  TPDFFont = class
  strict private
    fName:        string;
    fSize:        Double;
    fColor:       TColor;
    fStrokeColor: TColor;
    fUnderline:   Boolean;
    fItalics:     Boolean;
    fBold:        Boolean;
    fStrokeStyle: TPDFStrokeStyle;
  public
    constructor Create;

    property Name:        string          read fName        write fName;
    // Points. Fractional sizes are written as given (e.g. 7.35).
    property Size:        Double          read fSize        write fSize;
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
    fWidthPt:         Double;
    fHeightPt:        Double;
    fPaperColor:      TColor;
    fCompressStreams: Boolean;
    fPen:             TPDFPen;
    fFont:            TPDFFont;
    fBrush:           TPDFBrush;
    fPages:             TObjectList<TPDFPage>;
    fCurrentPage:       TPDFPage;
    fFonts:             TPDFFontRegistry;
    fWarnings:          TStringList;
    fImageData:         TDictionary<string, TPDFImageData>;   // image key -> extracted data
    fImageKeyByPicture: TDictionary<TObject, string>;         // TPicture pointer -> key (for dedup)
    fPathOpen:          Boolean;
    fPathHasPoint:      Boolean;

    procedure StartPage(AWidthPt, AHeightPt: Double; ADPI: Integer; APaperColor: TColor);
    procedure EnsureCurrentPage;
    procedure EnsureCanDraw;
    procedure EnsurePathOpen(const AMethod: string);
    procedure FinishPath(ADoFill, ADoStroke: Boolean; AFillRule: TPDFFillRule);
    function  PxToPt(APixels: Double): Double; inline;
    function  PtToPx(APoints: Double): Double; inline;
    function  EffectiveFontSize: Double;
    procedure MeasureTextPx(const AText: string; out AWidthPx, AHeightPx: Double);
    procedure EmitOneTextLine(const AText: string; X, Y: Double; ASizePt: Double);
    procedure DrawTextInRect(const AText: string; ALeft, ATop, ARight, ABottom: Double;
      AAlignment: TAlignment);
    procedure DrawParagraphInRect(const AText: string; ALeft, ATop, ARight, ABottom: Double;
      AAlignment: TAlignment; APadding: TPDFTextPadding);
    function  MeasureParagraphF(const AText: string; AMaxWidthPx: Double;
      APadding: TPDFTextPadding): TSizeF;
    procedure DrawPictureInRect(const APicture: TPicture; ALeft, ATop, ARight, ABottom: Double;
      AAlignment: TAlignment; AStretch: Boolean);

    function ResolveCurrentFont: TPDFFontResolution;
    function MeasureWidthPt(const AResolved: TPDFFontResolution; ASizePt: Double; const AAnsi: AnsiString): Double;
    function FontAscentPt(const AResolved: TPDFFontResolution; ASizePt: Double): Double;
    function FontLineHeightPt(const AResolved: TPDFFontResolution; ASizePt: Double): Double;
    function GetWarnings: TStrings;

    procedure WriteDocument(AWriter: TPDFWriter);
    function EmitTrueTypeFont(AWriter: TPDFWriter; AFace: TPDFFontFace): TPDFObjectId;
    function EmitStandardFont(AWriter: TPDFWriter; AFont: TStandardFont): TPDFObjectId;
    function EmitImageObject(AWriter: TPDFWriter; const AData: TPDFImageData): TPDFObjectId;
    function GetOrAddImage(APicture: TPicture): string;
    function GetWidth: Integer;
    function GetHeight: Integer;
  public
    constructor Create;
    destructor  Destroy; override;

    // AWidth / AHeight are pixels at ADPI and only used for psCustom.
    procedure NewPage(const APaperSize: TPDFPaperSize; const AOrientation: TPDFOrientation;
      const ADPI: Integer = 300; const APaperColor: TColor = clWhite;
      const AWidth: Integer = 0; const AHeight: Integer = 0); overload;
    // Page size in points, used exactly for the MediaBox. At ADPI = 72 one
    // drawing pixel is one point, so coordinates can be given in points.
    procedure NewPage(const AWidthPt, AHeightPt: Double; const ADPI: Integer = 72;
      const APaperColor: TColor = clWhite); overload;
    procedure NewPage; overload;

    // Save returns the number of bytes written. The stream overload writes at
    // AStream.Position and leaves the stream open.
    function Save(const AFileName: string): Int64; overload;
    function Save(const AFileName: string; const AEmbedFonts: Boolean): Int64; overload;
    function Save(AStream: TStream): Int64; overload;
    function ToBytes: TBytes;

    // AAngle rotates the text counter-clockwise (in degrees) around (X, Y) —
    // matches VCL TFont.Orientation. 0 = horizontal, 90 = reads upward,
    // -90 = reads downward, 180 = upside down. The Brush text-background,
    // Font.Underline, and Font.StrokeStyle outline all rotate with the text.
    procedure DrawText(const AText: string; X, Y: Integer; AAngle: Double = 0); overload;
    procedure DrawText(const AText: string; X, Y: Double; AAngle: Double = 0); overload;
    // The rect overloads pick the largest font size that fits the text in the
    // rectangle (they ignore Font.Size); they are not VCL TextRect.
    procedure DrawText(const AText: string; ARect: TRect); overload;
    procedure DrawText(const AText: string; ARect: TRect; AAlignment: TAlignment); overload;
    procedure DrawParagraph(const AText: string; ARect: TRect; AAlignment: TAlignment;
      APadding: TPDFTextPadding);

    // Measure text in pixels at the current page DPI, using the current Font
    // (Name/Size/Bold/Italics). All require an active page (NewPage first)
    // so DPI is unambiguous. The F variants return unrounded values.
    function TextWidth(const AText: string): Integer;
    function TextHeight(const AText: string): Integer;
    function TextExtent(const AText: string): TSize;
    function TextWidthF(const AText: string): Double;
    function TextHeightF(const AText: string): Double;
    function TextExtentF(const AText: string): TSizeF;

    // Word-wrap AText into AMaxWidthPx using the same path as DrawParagraph and
    // return the resulting block size (widest line × N lines × line-height).
    function MeasureParagraph(const AText: string; AMaxWidthPx: Integer; APadding: TPDFTextPadding = tpSingle): TSize;

    procedure DrawLine(const x1, y1, x2, y2: Integer); overload;
    procedure DrawLine(const x1, y1, x2, y2: Double); overload;
    procedure DrawBox(const x1, y1, x2, y2: Integer); overload;
    procedure DrawBox(const x1, y1, x2, y2: Double); overload;
    procedure DrawOval(const x1, y1, x2, y2: Integer); overload;
    procedure DrawOval(const x1, y1, x2, y2: Double); overload;
    procedure DrawMultiLine(const APointList: TPDFPointList); overload;
    procedure DrawMultiLine(const APointList: TPDFPointFList); overload;

    // DrawPolygon walks the point list as a closed polygon. Whenever a point
    // equals the start of the current subpath, the subpath is closed and the
    // next point begins a new subpath. Nested subpaths become holes via the
    // even-odd fill rule. An unclosed final subpath is auto-closed at the end.
    procedure DrawPolygon(const APointList: TPDFPointList); overload;
    procedure DrawPolygon(const APointList: TPDFPointFList); overload;

    // Same, but constrained to the given rectangle. Polygon geometry outside
    // the rect is hidden by a PDF clip path; coordinates are not modified.
    procedure DrawPolygon(const APointList: TPDFPointList; AClipRect: TRect); overload;
    procedure DrawPolygon(const APointList: TPDFPointFList; AClipRect: TRectF); overload;

    // Rings are given explicitly: ACounts[i] points of APoints form part i,
    // closed with h. Parts with fewer than 2 points are skipped; the counts
    // must not add up to more than Length(APoints). Open arrays, so existing
    // buffers can be passed without copying.
    procedure DrawPolyPolygon(const APoints: array of TPointF; const ACounts: array of Integer;
      AFillRule: TPDFFillRule = frEvenOdd); overload;
    procedure DrawPolyPolygon(const APoints: array of TPoint; const ACounts: array of Integer;
      AFillRule: TPDFFillRule = frEvenOdd); overload;
    // Strokes the first ACount points (all of them when ACount = -1) as one
    // open path with the current Pen.
    procedure DrawPolyline(const APoints: array of TPointF; ACount: Integer = -1); overload;

    // Clip everything drawn afterwards to R (intersected with any clip already
    // pushed) until the matching PopClip. Clips still open are closed
    // automatically when the page is written.
    procedure PushClipRect(const R: TRectF); overload;
    procedure PushClipRect(const R: TRect); overload;
    procedure PopClip;

    // General paths in page pixels, painted with the current Pen / Brush.
    // Between BeginPath and a Fill/Stroke call no other drawing, clipping or
    // NewPage is allowed.
    procedure BeginPath;
    procedure MoveTo(X, Y: Double);
    procedure LineTo(X, Y: Double);
    procedure CurveTo(X1, Y1, X2, Y2, X3, Y3: Double);
    procedure ClosePath;
    procedure FillPath(AFillRule: TPDFFillRule = frNonZero);
    procedure StrokePath;
    procedure FillAndStrokePath(AFillRule: TPDFFillRule = frNonZero);
    // A zero radius draws exactly what DrawBox draws.
    procedure DrawRoundRect(const R: TRectF; ARadiusX, ARadiusY: Double);

    procedure DrawPicture(const APicture: TPicture; ARect: TRect;
      AAlignment: TAlignment = taLeftJustify; AStretch: Boolean = False); overload;
    procedure DrawPicture(const APicture: TPicture; ARect: TRectF;
      AAlignment: TAlignment = taLeftJustify; AStretch: Boolean = False); overload;
    procedure DrawPicture(const APicture: TPicture; x1, y1: Integer); overload;

    function PageCount: Integer;

    property Size:            TPDFPaperSize   read fSize;
    property Orientation:     TPDFOrientation read fOrientation;
    // Current page size in pixels at the page DPI, rounded.
    property Width:           Integer         read GetWidth;
    property Height:          Integer         read GetHeight;
    // Current page size in points, exact.
    property WidthPt:         Double          read fWidthPt;
    property HeightPt:        Double          read fHeightPt;
    property DPI:             Integer         read fDPI;
    property CompressStreams: Boolean         read fCompressStreams write fCompressStreams;
    property Font:            TPDFFont        read fFont;
    property Pen:             TPDFPen         read fPen;
    property Brush:           TPDFBrush       read fBrush;
    property PaperColor:      TColor          read fPaperColor;
    // Everything the library had to work around, one line each: fonts that
    // were missing, not TrueType, or not embeddable, and characters a font
    // could not show. Read-only; cleared only by creating a new TsmPDF.
    property Warnings:        TStrings        read GetWarnings;
  end;

implementation

uses
  System.Math, smPDF.Geometry, smPDF.Types, smPDF.Subset;

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
  fWarnings          := TStringList.Create;
  fFonts             := TPDFFontRegistry.Create(fWarnings);
  fImageData         := TDictionary<string, TPDFImageData>.Create;
  fImageKeyByPicture := TDictionary<TObject, string>.Create;
  fCurrentPage       := nil;
  fCompressStreams := True;
  fSize            := psA4;
  fOrientation     := poPortrait;
  fDPI             := 300;
  fWidthPt         := 595.28;
  fHeightPt        := 841.89;
end;

destructor TsmPDF.Destroy;
begin
  fImageKeyByPicture.Free;
  fImageData.Free;
  fFonts.Free;
  fWarnings.Free;
  fPages.Free;
  fFont.Free;
  fBrush.Free;
  fPen.Free;
  inherited;
end;

function TsmPDF.PxToPt(APixels: Double): Double;
begin
  Result := APixels * POINTS_PER_INCH / fDPI;
end;

function TsmPDF.PtToPx(APoints: Double): Double;
begin
  Result := APoints * fDPI / POINTS_PER_INCH;
end;

function TsmPDF.GetWidth: Integer;
begin
  Result := PointsToPixels(fWidthPt, fDPI);
end;

function TsmPDF.GetHeight: Integer;
begin
  Result := PointsToPixels(fHeightPt, fDPI);
end;

function TsmPDF.EffectiveFontSize: Double;
begin
  Result := fFont.Size;
  if Result <= 0 then Result := 12;
end;

function TsmPDF.GetWarnings: TStrings;
begin
  Result := fWarnings;
end;

function TsmPDF.ResolveCurrentFont: TPDFFontResolution;
begin
  Result := fFonts.Resolve(fFont.Name, fFont.Bold, fFont.Italics);
end;

function TsmPDF.MeasureWidthPt(const AResolved: TPDFFontResolution; ASizePt: Double;
  const AAnsi: AnsiString): Double;
var
  i, sumUnits: Integer;
  ttf: TTTFFont;
begin
  if AResolved.Face.IsStandard then
    Result := StandardFontTextWidth(AResolved.Face.StdFont, ASizePt, AAnsi)
  else
  begin
    ttf := AResolved.Face.TTF;
    sumUnits := 0;
    for i := 1 to Length(AAnsi) do
      sumUnits := sumUnits + ttf.CharWidthWinAnsi(Byte(AAnsi[i]));
    Result := sumUnits * ASizePt / ttf.Metrics.UnitsPerEm;
  end;
end;

function TsmPDF.FontAscentPt(const AResolved: TPDFFontResolution; ASizePt: Double): Double;
begin
  if AResolved.Face.IsStandard then
    Result := StandardFontAscent(AResolved.Face.StdFont, ASizePt)
  else
    Result := AResolved.Face.TTF.Metrics.Ascent
            * ASizePt / AResolved.Face.TTF.Metrics.UnitsPerEm;
end;

function TsmPDF.FontLineHeightPt(const AResolved: TPDFFontResolution; ASizePt: Double): Double;
begin
  // Same 1.2x convention for both Standard 14 and TTF.
  Result := 1.2 * ASizePt;
end;

function TsmPDF.EmitStandardFont(AWriter: TPDFWriter; AFont: TStandardFont): TPDFObjectId;
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

procedure RecordWinAnsiGlyphs(AFace: TPDFFontFace; const AAnsi: AnsiString);
var
  i: Integer;
  cp: Cardinal;
  gid: Word;
begin
  for i := 1 to Length(AAnsi) do
  begin
    cp := WinAnsiToUnicode(Byte(AAnsi[i]));
    gid := AFace.TTF.GlyphIndex(cp);
    if gid <> 0 then
      AFace.RecordGlyph(gid, cp);
  end;
end;

// The embedded font program: a hollow subset carrying only the glyphs drawn,
// or the whole font when its fsType forbids subsetting.
function EmbeddedFontProgram(AFace: TPDFFontFace; out AFontName: string): TBytes;
var
  used: TArray<Word>;
  charMap: TArray<TSubsetCharMapping>;
  i: Integer;
  ttf: TTTFFont;
begin
  ttf := AFace.TTF;
  if ttf.SubsettingForbidden then
  begin
    AFontName := ttf.Metrics.PostScriptName;
    Exit(ttf.Bytes);
  end;
  used := AFace.UsedGlyphs;
  SetLength(charMap, Length(used));
  for i := 0 to High(used) do
  begin
    charMap[i].GlyphId   := used[i];
    charMap[i].Codepoint := AFace.UsedGlyphCodepoint(used[i]);
  end;
  AFontName := MakeSubsetTag(ttf.Metrics.PostScriptName, SubsetGlyphClosure(ttf, used)) +
    '+' + ttf.Metrics.PostScriptName;
  Result := BuildHollowSubset(ttf, used, charMap, AFontName);
end;

function TsmPDF.EmitTrueTypeFont(AWriter: TPDFWriter; AFace: TPDFFontFace): TPDFObjectId;
var
  ATTF: TTTFFont;
  m: TTTFFontMetrics;
  fontFileId, descriptorId: TPDFObjectId;
  i: Integer;
  program_, payload: TBytes;
  fontName: string;
  rawLength: Integer;
  compress: Boolean;
begin
  ATTF := AFace.TTF;
  m := ATTF.Metrics;
  program_ := EmbeddedFontProgram(AFace, fontName);

  // FontFile2 — embedded TTF stream; /Length1 is always the uncompressed length
  rawLength := Length(program_);
  compress  := fCompressStreams;
  if compress then
    payload := FlateCompress(program_)
  else
    payload := program_;
  fontFileId := AWriter.EmitStreamObject(payload,
    procedure(w: TPDFWriter)
    begin
      if compress then
      begin
        w.WriteName('Filter'); w.WriteName('FlateDecode');
      end;
      w.WriteName('Length1'); w.WriteInt(rawLength);
    end);

  // FontDescriptor
  descriptorId := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('FontDescriptor');
      AWriter.WriteName('FontName'); AWriter.WriteName(fontName);
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
      AWriter.WriteName('BaseFont');       AWriter.WriteName(fontName);
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

// Exact paper sizes in points (portrait).
procedure PaperSizePoints(APaperSize: TPDFPaperSize; out AWidthPt, AHeightPt: Double);
begin
  case APaperSize of
    psLetter: begin AWidthPt := 612.0;   AHeightPt := 792.0;   end;
    psLegal:  begin AWidthPt := 612.0;   AHeightPt := 1008.0;  end;
    psA2:     begin AWidthPt := 1190.55; AHeightPt := 1683.78; end;
    psA3:     begin AWidthPt := 841.89;  AHeightPt := 1190.55; end;
    psA4:     begin AWidthPt := 595.28;  AHeightPt := 841.89;  end;
    psA5:     begin AWidthPt := 419.53;  AHeightPt := 595.28;  end;
  else
    raise EPDFError.Create('Unknown paper size');
  end;
end;

procedure TsmPDF.StartPage(AWidthPt, AHeightPt: Double; ADPI: Integer; APaperColor: TColor);
var
  rgb: Cardinal;
  r, g, b: Double;
begin
  fDPI        := ADPI;
  fWidthPt    := AWidthPt;
  fHeightPt   := AHeightPt;
  fPaperColor := APaperColor;

  fCurrentPage := TPDFPage.CreatePoints(AWidthPt, AHeightPt, ADPI);
  fPages.Add(fCurrentPage);

  // Paint the page background as a full-page filled rectangle. Skipped for
  // clWhite so default-coloured pages carry no extra operators. Emitted
  // before any user drawing so subsequent content sits on top.
  // (RGB decomposition inlined because ColorToRGBFloats is declared later in
  // this implementation section than StartPage.)
  if APaperColor <> clWhite then
  begin
    rgb := Cardinal(ColorToRGB(APaperColor));
    r := ( rgb         and $FF) / 255.0;
    g := ((rgb shr  8) and $FF) / 255.0;
    b := ((rgb shr 16) and $FF) / 255.0;
    fCurrentPage.SaveState;
    fCurrentPage.SetFillRGB(r, g, b);
    fCurrentPage.UserRectanglePath(0, 0, PtToPx(AWidthPt), PtToPx(AHeightPt));
    fCurrentPage.FillEvenOdd;
    fCurrentPage.RestoreState;
  end;
end;

procedure TsmPDF.NewPage(const APaperSize: TPDFPaperSize; const AOrientation: TPDFOrientation;
  const ADPI: Integer; const APaperColor: TColor;
  const AWidth: Integer; const AHeight: Integer);
var
  widthPt, heightPt, tmp: Double;
begin
  if fPathOpen then
    raise EPDFError.Create('NewPage: a path is open. Finish it first.');
  if ADPI <= 0 then
    raise EPDFError.Create('NewPage: ADPI must be positive');

  if APaperSize = psCustom then
  begin
    if (AWidth <= 0) or (AHeight <= 0) then
      raise EPDFError.Create('psCustom requires positive width and height (pixels)');
    widthPt  := PixelsToPoints(AWidth, ADPI);
    heightPt := PixelsToPoints(AHeight, ADPI);
  end
  else
    PaperSizePoints(APaperSize, widthPt, heightPt);

  if AOrientation = poLandscape then
  begin
    tmp := widthPt;
    widthPt := heightPt;
    heightPt := tmp;
  end;

  fSize        := APaperSize;
  fOrientation := AOrientation;
  StartPage(widthPt, heightPt, ADPI, APaperColor);
end;

procedure TsmPDF.NewPage(const AWidthPt, AHeightPt: Double; const ADPI: Integer;
  const APaperColor: TColor);
begin
  if fPathOpen then
    raise EPDFError.Create('NewPage: a path is open. Finish it first.');
  if ADPI <= 0 then
    raise EPDFError.Create('NewPage: ADPI must be positive');
  if (AWidthPt <= 0) or (AHeightPt <= 0) then
    raise EPDFError.Create('NewPage: page width and height must be positive');

  fSize := psCustom;
  if AWidthPt > AHeightPt then
    fOrientation := poLandscape
  else
    fOrientation := poPortrait;
  StartPage(AWidthPt, AHeightPt, ADPI, APaperColor);
end;

procedure TsmPDF.NewPage;
begin
  // First page: established defaults (A4 portrait, 300 dpi, white paper).
  // Second-and-later pages: inherit the previous page's settings so that a
  // multi-page document with non-default paper/orientation/DPI/colour doesn't
  // need to repeat the full NewPage signature for every page.
  if fPathOpen then
    raise EPDFError.Create('NewPage: a path is open. Finish it first.');
  if fCurrentPage = nil then
    NewPage(psA4, poPortrait, 300)
  else
    StartPage(fWidthPt, fHeightPt, fDPI, fPaperColor);
end;

procedure TsmPDF.EnsureCurrentPage;
begin
  if fCurrentPage = nil then
    raise EPDFError.Create('No active page. Call NewPage before drawing.');
end;

procedure TsmPDF.EnsureCanDraw;
begin
  EnsureCurrentPage;
  if fPathOpen then
    raise EPDFError.Create('A path is open. Finish it with FillPath, StrokePath or ' +
      'FillAndStrokePath before drawing anything else.');
end;

procedure TsmPDF.EnsurePathOpen(const AMethod: string);
begin
  if not fPathOpen then
    raise EPDFError.Create(AMethod + ' needs an open path. Call BeginPath first.');
end;

procedure TsmPDF.WriteDocument(AWriter: TPDFWriter);
var
  writer: TPDFWriter;
  catalogId, pagesRootId, fontId, imgId: TPDFObjectId;
  pageIds: array of TPDFObjectId;
  fontIds, imageIds: TDictionary<string, TPDFObjectId>;
  fontNamesAcrossDoc, imageKeysAcrossDoc: TList<string>;
  pageFontName, pageImageKey: string;
  i: Integer;
  face: TPDFFontFace;
begin
  if fPages.Count = 0 then
    raise EPDFError.Create('Cannot save: no pages added. Call NewPage first.');

  writer              := AWriter;
  fontIds             := TDictionary<string, TPDFObjectId>.Create;
  imageIds            := TDictionary<string, TPDFObjectId>.Create;
  fontNamesAcrossDoc  := TList<string>.Create;
  imageKeysAcrossDoc  := TList<string>.Create;
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
      if not fFonts.FindFace(pageFontName, face) then
        raise EPDFError.CreateFmt('Internal error: font "%s" used on a page is not registered', [pageFontName]);
      if face.IsStandard then
        fontId := EmitStandardFont(writer, face.StdFont)
      else
        fontId := EmitTrueTypeFont(writer, face);
      fontIds.Add(pageFontName, fontId);
    end;

    // Emit image XObjects (SMask first when needed; EmitImageObject handles ordering).
    for pageImageKey in imageKeysAcrossDoc do
    begin
      imgId := EmitImageObject(writer, fImageData[pageImageKey]);
      imageIds.Add(pageImageKey, imgId);
    end;

    SetLength(pageIds, fPages.Count);
    for i := 0 to fPages.Count - 1 do
      pageIds[i] := fPages[i].Emit(writer, pagesRootId, fontIds, imageIds, fCompressStreams);

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

    writer.Finish(catalogId);
  finally
    imageKeysAcrossDoc.Free;
    fontNamesAcrossDoc.Free;
    imageIds.Free;
    fontIds.Free;
  end;
end;

function TsmPDF.ToBytes: TBytes;
var
  stream: TBytesStream;
  size: Int64;
begin
  stream := TBytesStream.Create;
  try
    Save(stream);
    // Take over the stream's buffer and trim it once the stream no longer
    // shares it, so the whole document is never copied.
    Result := stream.Bytes;
    size   := stream.Size;
  finally
    stream.Free;
  end;
  SetLength(Result, size);
end;

function TsmPDF.Save(AStream: TStream): Int64;
var
  writer: TPDFWriter;
begin
  if AStream = nil then
    raise EPDFError.Create('Cannot save: stream is nil.');
  if fPages.Count = 0 then
    raise EPDFError.Create('Cannot save: no pages added. Call NewPage first.');
  if fPathOpen then
    raise EPDFError.Create('Cannot save: a path is open. Finish it first.');
  writer := TPDFWriter.Create(AStream);
  try
    WriteDocument(writer);
    Result := writer.CurrentOffset;
  finally
    writer.Free;
  end;
end;

function TsmPDF.Save(const AFileName: string): Int64;
const
  FILE_BUFFER_SIZE = 1024 * 1024;
var
  fs: TBufferedFileStream;
begin
  // Check before creating the file so a failed build doesn't leave an empty file behind.
  if fPages.Count = 0 then
    raise EPDFError.Create('Cannot save: no pages added. Call NewPage first.');
  fs := TBufferedFileStream.Create(AFileName, fmCreate, FILE_BUFFER_SIZE);
  try
    try
      Result := Save(fs);
    finally
      fs.Free;
    end;
  except
    SysUtils.DeleteFile(AFileName);
    raise;
  end;
end;

function TsmPDF.Save(const AFileName: string; const AEmbedFonts: Boolean): Int64;
begin
  // AEmbedFonts is accepted for source compatibility; fonts are always embedded.
  Result := Save(AFileName);
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

// Apply only the pen, for stroke-only paths (lines, polylines).
procedure ApplyStrokeState(APage: TPDFPage; APen: TPDFPen);
var
  r, g, b: Double;
begin
  ColorToRGBFloats(APen.Color, r, g, b);
  APage.SetStrokeRGB(r, g, b);
  APage.SetLineWidthPt(APen.Width);
  ApplyPenDash(APage, APen.Style);
  ApplyPenLineEnds(APage, APen.LineCap, APen.LineJoin);
end;

// Fill a rectangle using only the Brush, ignoring Pen. Used as the text
// background ("highlighter") behind DrawText / DrawParagraph, mirroring the
// way VCL TCanvas uses Brush during TextOut. No-op when the brush is clear.
procedure FillRectWithBrush(APage: TPDFPage; ABrush: TPDFBrush;
  X1, Y1, X2, Y2: Double);
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
procedure PaintByPenAndBrush(APage: TPDFPage; APen: TPDFPen; ABrush: TPDFBrush;
  AFillRule: TPDFFillRule = frEvenOdd);
var
  doStroke, doFill: Boolean;
begin
  doStroke := APen.Style <> penNone;
  doFill   := ABrush.Style = brushSolid;
  if doFill and doStroke then
  begin
    if AFillRule = frEvenOdd then APage.FillAndStrokeEvenOdd
    else APage.FillAndStrokeNonZero;
  end
  else if doFill then
  begin
    if AFillRule = frEvenOdd then APage.FillEvenOdd
    else APage.FillNonZero;
  end
  else if doStroke then
    APage.Stroke
  else
    APage.DiscardPath;
end;

procedure CheckPartCounts(const ACounts: array of Integer; APointCount: Integer);
var
  i: Integer;
  total: Int64;
begin
  total := 0;
  for i := 0 to High(ACounts) do
  begin
    if ACounts[i] < 0 then
      raise EPDFError.CreateFmt('DrawPolyPolygon: part %d has a negative point count', [i]);
    Inc(total, ACounts[i]);
  end;
  if total > APointCount then
    raise EPDFError.CreateFmt(
      'DrawPolyPolygon: part counts add up to %d but only %d points were given', [total, APointCount]);
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

// Floating-point twin of the above.
procedure EmitPolygonPathF(APage: TPDFPage; const APointList: TPDFPointFList);
var
  i: Integer;
  subStart, p: TPointF;
  hasOpen, hasMovedAway: Boolean;
begin
  hasOpen      := False;
  hasMovedAway := False;
  for i := 0 to APointList.Count - 1 do
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
    end
    else
    begin
      APage.UserLineTo(p.X, p.Y);
      hasMovedAway := True;
    end;
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
  EnsureCanDraw;
  if (APicture = nil) or (APicture.Graphic = nil) then Exit;

  key := GetOrAddImage(APicture);
  data := fImageData[key];
  res := fCurrentPage.UseImage(key);
  fCurrentPage.DrawImageUserRect(res, x1, y1,
    x1 + data.Width, y1 + data.Height);
end;

procedure TsmPDF.DrawPictureInRect(const APicture: TPicture; ALeft, ATop, ARight, ABottom: Double;
  AAlignment: TAlignment; AStretch: Boolean);
var
  key, res: string;
  data: TPDFImageData;
  x1, y1, x2, y2: Double;
begin
  EnsureCanDraw;
  if (APicture = nil) or (APicture.Graphic = nil) then Exit;

  key := GetOrAddImage(APicture);
  data := fImageData[key];
  res := fCurrentPage.UseImage(key);

  if AStretch then
  begin
    // Fill the rectangle exactly; aspect ratio may distort.
    x1 := ALeft;  y1 := ATop;
    x2 := ARight; y2 := ABottom;
  end
  else
  begin
    case AAlignment of
      taCenter:
        x1 := ALeft + (ARight - ALeft - data.Width) / 2;
      taRightJustify:
        x1 := ARight - data.Width;
    else
      x1 := ALeft;
    end;
    y1 := ATop;
    x2 := x1 + data.Width;
    y2 := y1 + data.Height;
  end;

  fCurrentPage.DrawImageUserRect(res, x1, y1, x2, y2);
end;

procedure TsmPDF.DrawPicture(const APicture: TPicture; ARect: TRect; AAlignment: TAlignment;
  AStretch: Boolean);
var
  left: Integer;
begin
  // Integer rects keep the 1.x whole-pixel centring.
  if (not AStretch) and (AAlignment = taCenter) and (APicture <> nil) and (APicture.Graphic <> nil) then
  begin
    EnsureCanDraw;
    left := ARect.Left + (ARect.Right - ARect.Left - fImageData[GetOrAddImage(APicture)].Width) div 2;
    DrawPictureInRect(APicture, left, ARect.Top, left + (ARect.Right - ARect.Left), ARect.Bottom,
      taLeftJustify, False);
  end
  else
    DrawPictureInRect(APicture, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, AAlignment, AStretch);
end;

procedure TsmPDF.DrawPicture(const APicture: TPicture; ARect: TRectF; AAlignment: TAlignment;
  AStretch: Boolean);
begin
  DrawPictureInRect(APicture, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, AAlignment, AStretch);
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

const
  // GDI's synthetic bold widens strokes by about 1/32 em; its synthetic
  // italic slants by about 12 degrees.
  SYNTHETIC_BOLD_EM   = 0.03;
  SYNTHETIC_ITALIC_TAN = 0.2126;

procedure TsmPDF.EmitOneTextLine(const AText: string; X, Y: Double; ASizePt: Double);
var
  resolved: TPDFFontResolution;
  resName: string;
  ansi: AnsiString;
  sizePt, baselineYPx: Double;
  r, g, b, sr, sg, sb: Double;
  textWidthPx: Double;
  underlineYPx: Double;
  underlineThicknessPt: Double;
  strokeText, emboldened: Boolean;
begin
  sizePt := ASizePt;
  if sizePt <= 0 then sizePt := 12;

  resolved := ResolveCurrentFont;
  resName  := fCurrentPage.UseFont(resolved.Face.Key);

  ansi := StringToWinAnsi(AText);
  if not resolved.Face.IsStandard then
    RecordWinAnsiGlyphs(resolved.Face, ansi);

  baselineYPx := Y + PtToPx(FontAscentPt(resolved, sizePt));

  strokeText := fFont.StrokeStyle <> ssNone;
  emboldened := resolved.SyntheticBold and not strokeText;

  fCurrentPage.SaveState;
  ColorToRGBFloats(fFont.Color, r, g, b);
  fCurrentPage.SetFillRGB(r, g, b);
  if strokeText then
  begin
    ColorToRGBFloats(fFont.StrokeColor, sr, sg, sb);
    fCurrentPage.SetStrokeRGB(sr, sg, sb);
    fCurrentPage.SetLineWidthPt(TextStrokeWidthPt(fFont.StrokeStyle, sizePt));
  end
  else if emboldened then
  begin
    fCurrentPage.SetStrokeRGB(r, g, b);
    fCurrentPage.SetLineWidthPt(SYNTHETIC_BOLD_EM * sizePt);
  end;
  fCurrentPage.BeginText;
  fCurrentPage.SetTextFont(resName, sizePt);
  if strokeText or emboldened then
    fCurrentPage.SetTextRenderingMode(2);  // fill + stroke each glyph
  if resolved.SyntheticItalic then
    fCurrentPage.SetTextMatrixUser(1, 0, SYNTHETIC_ITALIC_TAN, 1, X, baselineYPx)
  else
    fCurrentPage.SetTextMatrixUserBaseline(X, baselineYPx);
  fCurrentPage.ShowTextAnsi(ansi);
  fCurrentPage.EndText;
  fCurrentPage.RestoreState;

  if fFont.Underline and (Length(ansi) > 0) then
  begin
    textWidthPx := PtToPx(MeasureWidthPt(resolved, sizePt, ansi));

    underlineThicknessPt := 0.05 * sizePt;
    if underlineThicknessPt < 0.5 then underlineThicknessPt := 0.5;

    // Underline sits ~0.12em below the baseline (PDF underlinePosition convention).
    underlineYPx := baselineYPx + PtToPx(0.12 * sizePt);

    fCurrentPage.SaveState;
    fCurrentPage.SetStrokeRGB(r, g, b);
    fCurrentPage.SetLineWidthPt(underlineThicknessPt);
    fCurrentPage.SetDashPattern([], 0);
    fCurrentPage.SetLineCap(0);
    fCurrentPage.UserMoveTo(X, underlineYPx);
    fCurrentPage.UserLineTo(X + textWidthPx, underlineYPx);
    fCurrentPage.Stroke;
    fCurrentPage.RestoreState;
  end;
end;

procedure TsmPDF.DrawText(const AText: string; X, Y: Integer; AAngle: Double);
begin
  DrawText(AText, Double(X), Double(Y), AAngle);
end;

procedure TsmPDF.DrawText(const AText: string; X, Y: Double; AAngle: Double);
var
  extW, extH: Double;
  rotated: Boolean;
  thetaRad, cosT, sinT: Double;
  pivotX, pivotY: Double;
  cm_e, cm_f: Double;
begin
  EnsureCanDraw;
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
    pivotX := PxToPt(X);
    pivotY := fHeightPt - PxToPt(Y);
    // Affine that rotates by AAngle degrees CCW around the pivot in PDF coords.
    // PDF row-vector form [a b c d e f] = [cos, sin, -sin, cos, ex, ey] where:
    //   ex = px*(1 - cos) + py*sin
    //   ey = py*(1 - cos) - px*sin
    cm_e := pivotX * (1 - cosT) + pivotY * sinT;
    cm_f := pivotY * (1 - cosT) - pivotX * sinT;
    fCurrentPage.SaveState;
    fCurrentPage.ConcatMatrix(cosT, sinT, -sinT, cosT, cm_e, cm_f);
  end;

  if fBrush.Style = brushSolid then
  begin
    MeasureTextPx(AText, extW, extH);
    FillRectWithBrush(fCurrentPage, fBrush, X, Y, X + extW, Y + extH);
  end;
  EmitOneTextLine(AText, X, Y, EffectiveFontSize);

  if rotated then
    fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawText(const AText: string; ARect: TRect);
begin
  DrawText(AText, ARect, taLeftJustify);
end;

procedure TsmPDF.DrawText(const AText: string; ARect: TRect; AAlignment: TAlignment);
begin
  DrawTextInRect(AText, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, AAlignment);
end;

procedure TsmPDF.DrawTextInRect(const AText: string; ALeft, ATop, ARight, ABottom: Double;
  AAlignment: TAlignment);
const
  REF_SIZE_PT = 100.0;  // arbitrary; only ratios matter
var
  resolved: TPDFFontResolution;
  ansi: AnsiString;
  refWidthPt, refLineHeightPt: Double;
  rectWidthPt, rectHeightPt: Double;
  sizePt: Double;
  textWidthPx, lineHeightPx: Double;
  x, y: Double;
begin
  EnsureCanDraw;

  rectWidthPt  := PxToPt(ARight - ALeft);
  rectHeightPt := PxToPt(ABottom - ATop);
  if (rectWidthPt <= 0) or (rectHeightPt <= 0) then Exit;

  // VCL TextRect-style background: paint the whole rect (independent of text
  // length / alignment) so the fill stays even when AText is empty.
  FillRectWithBrush(fCurrentPage, fBrush, ALeft, ATop, ARight, ABottom);

  if AText = '' then Exit;

  resolved := ResolveCurrentFont;
  ansi     := StringToWinAnsi(AText);

  // Pick the largest font size that fits the text inside the rect on both axes
  // while preserving the font's natural width:height ratio.
  refWidthPt      := MeasureWidthPt(resolved, REF_SIZE_PT, ansi);
  refLineHeightPt := FontLineHeightPt(resolved, REF_SIZE_PT);
  if (refWidthPt <= 0) or (refLineHeightPt <= 0) then Exit;

  sizePt := REF_SIZE_PT * Min(rectWidthPt  / refWidthPt,
                              rectHeightPt / refLineHeightPt);
  if sizePt <= 0 then Exit;

  textWidthPx  := PtToPx(MeasureWidthPt(resolved, sizePt, ansi));
  lineHeightPx := PtToPx(FontLineHeightPt(resolved, sizePt));

  case AAlignment of
    taCenter:       x := ALeft + (ARight - ALeft - textWidthPx) / 2;
    taRightJustify: x := ARight - textWidthPx;
  else
    x := ALeft;
  end;

  y := ATop + (ABottom - ATop - lineHeightPx) / 2;
  if y < ATop then y := ATop;

  EmitOneTextLine(AText, x, y, sizePt);
end;

function PaddingMultiplier(APadding: TPDFTextPadding): Double;
begin
  case APadding of
    tpNone, tpTight: Result := 1.0;
    tpSingle:        Result := 1.2;
    tpDouble:        Result := 2.4;
  else
    Result := 1.2;
  end;
end;

procedure TsmPDF.DrawParagraph(const AText: string; ARect: TRect; AAlignment: TAlignment;
  APadding: TPDFTextPadding);
begin
  DrawParagraphInRect(AText, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, AAlignment, APadding);
end;

procedure TsmPDF.DrawParagraphInRect(const AText: string; ALeft, ATop, ARight, ABottom: Double;
  AAlignment: TAlignment; APadding: TPDFTextPadding);
var
  font: TStandardFont;
  sizePt, lineHeightPx, maxWidthPt: Double;
  lines: TStringList;
  ansi: AnsiString;
  i: Integer;
  lineX, lineY, lineWidthPx: Double;
begin
  EnsureCanDraw;

  // Single rect-sized background fill for the whole paragraph (not per-line).
  if (ARight > ALeft) and (ABottom > ATop) then
    FillRectWithBrush(fCurrentPage, fBrush, ALeft, ATop, ARight, ABottom);

  if AText = '' then Exit;

  sizePt := EffectiveFontSize;

  font := ResolveStandardFont(fFont.Name, fFont.Bold, fFont.Italics);

  lineHeightPx := PtToPx(PaddingMultiplier(APadding) * sizePt);
  maxWidthPt   := PxToPt(ARight - ALeft);

  lines := WrapTextToLines(AText, font, sizePt, maxWidthPt);
  try
    for i := 0 to lines.Count - 1 do
    begin
      ansi        := StringToWinAnsi(lines[i]);
      lineWidthPx := PtToPx(StandardFontTextWidth(font, sizePt, ansi));

      case AAlignment of
        taCenter:
          lineX := ALeft + (ARight - ALeft - lineWidthPx) / 2;
        taRightJustify:
          lineX := ARight - lineWidthPx;
      else
        lineX := ALeft;
      end;

      lineY := ATop + i * lineHeightPx;
      // Stop if we'd drop below the rect (truncates rather than overflowing).
      if lineY > ABottom then Break;

      EmitOneTextLine(lines[i], lineX, lineY, sizePt);
    end;
  finally
    lines.Free;
  end;
end;

// ------------------------------------------------------------------
// Text measurement
// ------------------------------------------------------------------

procedure TsmPDF.MeasureTextPx(const AText: string; out AWidthPx, AHeightPx: Double);
var
  resolved: TPDFFontResolution;
  sizePt, widthPt: Double;
begin
  EnsureCurrentPage;

  sizePt   := EffectiveFontSize;
  resolved := ResolveCurrentFont;

  if AText = '' then
    widthPt := 0
  else
    widthPt := MeasureWidthPt(resolved, sizePt, StringToWinAnsi(AText));

  AWidthPx  := PtToPx(widthPt);
  AHeightPx := PtToPx(FontLineHeightPt(resolved, sizePt));
end;

function TsmPDF.TextExtentF(const AText: string): TSizeF;
var
  w, h: Double;
begin
  MeasureTextPx(AText, w, h);
  Result := TSizeF.Create(w, h);
end;

function TsmPDF.TextWidthF(const AText: string): Double;
var
  h: Double;
begin
  MeasureTextPx(AText, Result, h);
end;

function TsmPDF.TextHeightF(const AText: string): Double;
var
  w: Double;
begin
  MeasureTextPx(AText, w, Result);
end;

function TsmPDF.TextExtent(const AText: string): TSize;
var
  w, h: Double;
begin
  MeasureTextPx(AText, w, h);
  Result := TSize.Create(Round(w), Round(h));
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
  ext: TSizeF;
begin
  ext := MeasureParagraphF(AText, AMaxWidthPx, APadding);
  Result := TSize.Create(Round(ext.cx), Round(ext.cy));
end;

function TsmPDF.MeasureParagraphF(const AText: string; AMaxWidthPx: Double;
  APadding: TPDFTextPadding): TSizeF;
var
  font: TStandardFont;
  sizePt, lineHeightPx, maxWidthPt: Double;
  lines: TStringList;
  i: Integer;
  lineWidthPx, widestPx: Double;
begin
  EnsureCurrentPage;
  Result := TSizeF.Create(0, 0);
  if (AText = '') or (AMaxWidthPx <= 0) then Exit;

  sizePt := EffectiveFontSize;

  // Mirror DrawParagraph: word-wrap uses the standard-14 font corresponding to
  // the current Font.Name/Bold/Italics. TTF families fall back here too, so
  // measurements match what DrawParagraph will actually render.
  font := ResolveStandardFont(fFont.Name, fFont.Bold, fFont.Italics);

  lineHeightPx := PtToPx(PaddingMultiplier(APadding) * sizePt);
  maxWidthPt   := PxToPt(AMaxWidthPx);

  lines := WrapTextToLines(AText, font, sizePt, maxWidthPt);
  try
    if lines.Count = 0 then Exit;
    widestPx := 0;
    for i := 0 to lines.Count - 1 do
    begin
      lineWidthPx := PtToPx(StandardFontTextWidth(font, sizePt, StringToWinAnsi(lines[i])));
      if lineWidthPx > widestPx then widestPx := lineWidthPx;
    end;
    Result := TSizeF.Create(widestPx, lines.Count * lineHeightPx);
  finally
    lines.Free;
  end;
end;

// ------------------------------------------------------------------
// Phase 2 — graphics primitives
// ------------------------------------------------------------------

procedure TsmPDF.DrawLine(const x1, y1, x2, y2: Integer);
begin
  DrawLine(Double(x1), Double(y1), Double(x2), Double(y2));
end;

procedure TsmPDF.DrawLine(const x1, y1, x2, y2: Double);
begin
  EnsureCanDraw;
  if fPen.Style = penNone then Exit;  // lines have no fill; nothing to draw

  fCurrentPage.SaveState;
  ApplyStrokeState(fCurrentPage, fPen);
  fCurrentPage.UserMoveTo(x1, y1);
  fCurrentPage.UserLineTo(x2, y2);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawBox(const x1, y1, x2, y2: Integer);
begin
  DrawBox(Double(x1), Double(y1), Double(x2), Double(y2));
end;

procedure TsmPDF.DrawBox(const x1, y1, x2, y2: Double);
begin
  EnsureCanDraw;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  fCurrentPage.UserRectanglePath(x1, y1, x2, y2);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawOval(const x1, y1, x2, y2: Integer);
begin
  DrawOval(Double(x1), Double(y1), Double(x2), Double(y2));
end;

procedure TsmPDF.DrawOval(const x1, y1, x2, y2: Double);
begin
  EnsureCanDraw;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  fCurrentPage.UserOvalPath(x1, y1, x2, y2);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawMultiLine(const APointList: TPDFPointList);
var
  i: Integer;
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if fPen.Style = penNone then Exit;  // open polylines have no fill

  fCurrentPage.SaveState;
  ApplyStrokeState(fCurrentPage, fPen);
  fCurrentPage.UserMoveTo(APointList[0].X, APointList[0].Y);
  for i := 1 to APointList.Count - 1 do
    fCurrentPage.UserLineTo(APointList[i].X, APointList[i].Y);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawMultiLine(const APointList: TPDFPointFList);
var
  i: Integer;
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if fPen.Style = penNone then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeState(fCurrentPage, fPen);
  fCurrentPage.UserMoveTo(APointList[0].X, APointList[0].Y);
  for i := 1 to APointList.Count - 1 do
    fCurrentPage.UserLineTo(APointList[i].X, APointList[i].Y);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointList);
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPath(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointFList);
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPathF(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointList; AClipRect: TRect);
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  fCurrentPage.SetClipRect(AClipRect.Left, AClipRect.Top, AClipRect.Right, AClipRect.Bottom);
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPath(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolygon(const APointList: TPDFPointFList; AClipRect: TRectF);
begin
  EnsureCanDraw;
  if APointList.Count < 2 then Exit;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  fCurrentPage.SetClipRect(AClipRect.Left, AClipRect.Top, AClipRect.Right, AClipRect.Bottom);
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  EmitPolygonPathF(fCurrentPage, APointList);
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolyPolygon(const APoints: array of TPointF; const ACounts: array of Integer;
  AFillRule: TPDFFillRule);
var
  part, i, first, n: Integer;
begin
  EnsureCanDraw;
  CheckPartCounts(ACounts, Length(APoints));
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  first := 0;
  for part := 0 to High(ACounts) do
  begin
    n := ACounts[part];
    if n >= 2 then
    begin
      fCurrentPage.UserMoveTo(APoints[first].X, APoints[first].Y);
      for i := first + 1 to first + n - 1 do
        fCurrentPage.UserLineTo(APoints[i].X, APoints[i].Y);
      fCurrentPage.ClosePath;
    end;
    Inc(first, n);
  end;
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, AFillRule);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolyPolygon(const APoints: array of TPoint; const ACounts: array of Integer;
  AFillRule: TPDFFillRule);
var
  part, i, first, n: Integer;
begin
  EnsureCanDraw;
  CheckPartCounts(ACounts, Length(APoints));
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  first := 0;
  for part := 0 to High(ACounts) do
  begin
    n := ACounts[part];
    if n >= 2 then
    begin
      fCurrentPage.UserMoveTo(APoints[first].X, APoints[first].Y);
      for i := first + 1 to first + n - 1 do
        fCurrentPage.UserLineTo(APoints[i].X, APoints[i].Y);
      fCurrentPage.ClosePath;
    end;
    Inc(first, n);
  end;
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush, AFillRule);
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.DrawPolyline(const APoints: array of TPointF; ACount: Integer);
var
  i, n: Integer;
begin
  EnsureCanDraw;
  if ACount < 0 then
    n := Length(APoints)
  else
  begin
    if ACount > Length(APoints) then
      raise EPDFError.CreateFmt('DrawPolyline: count %d exceeds the %d points given',
        [ACount, Length(APoints)]);
    n := ACount;
  end;
  if n < 2 then Exit;
  if fPen.Style = penNone then Exit;

  fCurrentPage.SaveState;
  ApplyStrokeState(fCurrentPage, fPen);
  fCurrentPage.UserMoveTo(APoints[0].X, APoints[0].Y);
  for i := 1 to n - 1 do
    fCurrentPage.UserLineTo(APoints[i].X, APoints[i].Y);
  fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

// ------------------------------------------------------------------
// Clip stack
// ------------------------------------------------------------------

procedure TsmPDF.PushClipRect(const R: TRectF);
begin
  EnsureCanDraw;
  fCurrentPage.PushClip(R.Left, R.Top, R.Right, R.Bottom);
end;

procedure TsmPDF.PushClipRect(const R: TRect);
begin
  EnsureCanDraw;
  fCurrentPage.PushClip(R.Left, R.Top, R.Right, R.Bottom);
end;

procedure TsmPDF.PopClip;
begin
  EnsureCanDraw;
  if fCurrentPage.ClipDepth = 0 then
    raise EPDFError.Create('PopClip without a matching PushClipRect on this page.');
  fCurrentPage.PopClip;
end;

// ------------------------------------------------------------------
// Path API
// ------------------------------------------------------------------

procedure TsmPDF.BeginPath;
begin
  EnsureCanDraw;
  fCurrentPage.BeginPathCapture;
  fPathOpen     := True;
  fPathHasPoint := False;
end;

procedure TsmPDF.MoveTo(X, Y: Double);
begin
  EnsurePathOpen('MoveTo');
  fCurrentPage.UserMoveTo(X, Y);
  fPathHasPoint := True;
end;

procedure TsmPDF.LineTo(X, Y: Double);
begin
  EnsurePathOpen('LineTo');
  if not fPathHasPoint then
    raise EPDFError.Create('LineTo needs a current point. Call MoveTo first.');
  fCurrentPage.UserLineTo(X, Y);
end;

procedure TsmPDF.CurveTo(X1, Y1, X2, Y2, X3, Y3: Double);
begin
  EnsurePathOpen('CurveTo');
  if not fPathHasPoint then
    raise EPDFError.Create('CurveTo needs a current point. Call MoveTo first.');
  fCurrentPage.UserCurveTo(X1, Y1, X2, Y2, X3, Y3);
end;

procedure TsmPDF.ClosePath;
begin
  EnsurePathOpen('ClosePath');
  if fPathHasPoint then
    fCurrentPage.ClosePath;
end;

procedure TsmPDF.FinishPath(ADoFill, ADoStroke: Boolean; AFillRule: TPDFFillRule);
var
  r, g, b: Double;
begin
  fCurrentPage.EndPathCapture;
  fPathOpen := False;

  ADoFill   := ADoFill   and (fBrush.Style = brushSolid);
  ADoStroke := ADoStroke and (fPen.Style <> penNone);
  if (fCurrentPage.CapturedPathSize = 0) or not (ADoFill or ADoStroke) then Exit;

  fCurrentPage.SaveState;
  if ADoStroke then
    ApplyStrokeState(fCurrentPage, fPen);
  if ADoFill then
  begin
    ColorToRGBFloats(fBrush.Color, r, g, b);
    fCurrentPage.SetFillRGB(r, g, b);
  end;
  fCurrentPage.AppendCapturedPath;
  if ADoFill and ADoStroke then
  begin
    if AFillRule = frEvenOdd then fCurrentPage.FillAndStrokeEvenOdd
    else fCurrentPage.FillAndStrokeNonZero;
  end
  else if ADoFill then
  begin
    if AFillRule = frEvenOdd then fCurrentPage.FillEvenOdd
    else fCurrentPage.FillNonZero;
  end
  else
    fCurrentPage.Stroke;
  fCurrentPage.RestoreState;
end;

procedure TsmPDF.FillPath(AFillRule: TPDFFillRule);
begin
  EnsurePathOpen('FillPath');
  FinishPath(True, False, AFillRule);
end;

procedure TsmPDF.StrokePath;
begin
  EnsurePathOpen('StrokePath');
  FinishPath(False, True, frNonZero);
end;

procedure TsmPDF.FillAndStrokePath(AFillRule: TPDFFillRule);
begin
  EnsurePathOpen('FillAndStrokePath');
  FinishPath(True, True, AFillRule);
end;

procedure TsmPDF.DrawRoundRect(const R: TRectF; ARadiusX, ARadiusY: Double);
const
  KAPPA = 0.5522847498307933;  // same quarter-circle constant as UserOvalPath
var
  l, t, rt, b, rx, ry, kx, ky: Double;
begin
  EnsureCanDraw;
  l  := Min(R.Left, R.Right);
  rt := Max(R.Left, R.Right);
  t  := Min(R.Top, R.Bottom);
  b  := Max(R.Top, R.Bottom);
  rx := Min(Abs(ARadiusX), (rt - l) / 2);
  ry := Min(Abs(ARadiusY), (b - t) / 2);
  if (rx <= 0) or (ry <= 0) then
  begin
    DrawBox(R.Left, R.Top, R.Right, R.Bottom);
    Exit;
  end;
  if (fPen.Style = penNone) and (fBrush.Style = brushClear) then Exit;

  kx := KAPPA * rx;
  ky := KAPPA * ry;
  fCurrentPage.SaveState;
  ApplyStrokeAndFillState(fCurrentPage, fPen, fBrush);
  fCurrentPage.UserMoveTo(l + rx, t);
  fCurrentPage.UserLineTo(rt - rx, t);
  fCurrentPage.UserCurveTo(rt - rx + kx, t, rt, t + ry - ky, rt, t + ry);
  fCurrentPage.UserLineTo(rt, b - ry);
  fCurrentPage.UserCurveTo(rt, b - ry + ky, rt - rx + kx, b, rt - rx, b);
  fCurrentPage.UserLineTo(l + rx, b);
  fCurrentPage.UserCurveTo(l + rx - kx, b, l, b - ry + ky, l, b - ry);
  fCurrentPage.UserLineTo(l, t + ry);
  fCurrentPage.UserCurveTo(l, t + ry - ky, l + rx - kx, t, l + rx, t);
  fCurrentPage.ClosePath;
  PaintByPenAndBrush(fCurrentPage, fPen, fBrush);
  fCurrentPage.RestoreState;
end;

end.
