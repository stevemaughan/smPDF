unit smPDF.Page;

interface

uses
  SysUtils, Classes, Generics.Collections, smPDF.Writer, smPDF.Types, smPDF.Buffer;

type
  TPDFPage = class
  strict private
    fWidthPoints:   Double;
    fHeightPoints:  Double;
    fDpi:           Integer;
    fScale:         Double;                       // points per pixel = 72 / DPI
    fContent:       TPDFByteBuffer;
    fPathContent:   TPDFByteBuffer;               // path operators captured between BeginPathCapture/EndPathCapture
    fOut:           TPDFByteBuffer;               // where operators are written: fContent or fPathContent
    fClipDepth:     Integer;
    fCoordDecimals: Integer;                      // decimals for path coordinates (0..3)
    fFontMap:       TDictionary<string, string>;  // PDF font name -> page-local resource name (F1, F2, ...)
    fFontOrder:     TList<string>;                // insertion order for stable iteration
    fImageMap:      TDictionary<string, string>;  // image key -> page-local name (Im1, Im2, ...)
    fImageOrder:    TList<string>;                // insertion order for stable iteration

    procedure WriteRaw(const AStr: string);
    procedure WriteOp(const AOperator: string; const AOperands: array of Double);
    procedure WriteCoordOp(const AOperator: string; const AOperands: array of Double);
    function  PdfX(XPx: Double): Double; inline;
    function  PdfY(YPx: Double): Double; inline;
    function  GetWidthPixels: Integer;
    function  GetHeightPixels: Integer;
  public
    // Page size in pixels at ADpi (the 1.x constructor).
    constructor Create(AWidthPixels, AHeightPixels, ADpi: Integer);
    // Page size in points, exactly; ADpi only sets the pixel unit for drawing.
    constructor CreatePoints(AWidthPoints, AHeightPoints: Double; ADpi: Integer);
    destructor  Destroy; override;

    function WidthPoints: Double;
    function HeightPoints: Double;

    function Emit(AWriter: TPDFWriter; AParentId: TPDFObjectId;
      AFontIds: TDictionary<string, TPDFObjectId> = nil;
      AImageIds: TDictionary<string, TPDFObjectId> = nil;
      ACompress: Boolean = False): TPDFObjectId;

    // ---------- Page-local font resource registry ----------
    // Returns the page-local resource name (F1, F2, ...) for the given PDF font
    // base-name. Idempotent — calling with the same name returns the same alias.
    function UseFont(const APdfFontName: string): string;
    // PDF font base-names registered on this page, in insertion order. TsmPDF.Save
    // iterates these to know which font dicts the document needs.
    function UsedFontNames: TArray<string>;

    // ---------- Page-local image resource registry ----------
    // Returns the page-local resource name (Im1, Im2, ...) for the given image key.
    // Idempotent — calling with the same key returns the same alias.
    function UseImage(const AImageKey: string): string;
    // Image keys registered on this page, in insertion order.
    function UsedImageKeys: TArray<string>;

    // Draw an already-registered image at the given user-pixel rectangle.
    // Internally emits "q  W 0 0 H X Y cm  /ImN Do  Q" using PDF coords.
    procedure DrawImageUserRect(const AResName: string;
      AX1Px, AY1Px, AX2Px, AY2Px: Double);

    // ---------- Graphics state ----------
    procedure SaveState;
    procedure RestoreState;
    procedure SetStrokeRGB(R, G, B: Double);
    procedure SetFillRGB(R, G, B: Double);
    procedure SetLineWidthPt(W: Double);
    procedure SetDashPattern(const APattern: array of Double; APhase: Double);
    procedure SetLineCap(ACap: Integer);
    procedure SetLineJoin(AJoin: Integer);
    // Concatenate an affine transform onto the current transformation matrix
    // (PDF "cm" operator). Effects all subsequent drawing until RestoreState.
    procedure ConcatMatrix(A, B, C, D, E, F: Double);

    // ---------- Path construction (user pixel coords, top-left origin, Y down) ----------
    procedure UserMoveTo(XPx, YPx: Double);
    procedure UserLineTo(XPx, YPx: Double);
    procedure UserCurveTo(X1Px, Y1Px, X2Px, Y2Px, X3Px, Y3Px: Double);
    procedure UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px: Double);
    procedure UserOvalPath(X1Px, Y1Px, X2Px, Y2Px: Double);
    procedure ClosePath;

    // ---------- Painting ----------
    procedure Stroke;
    procedure FillEvenOdd;
    procedure FillNonZero;
    procedure FillAndStrokeEvenOdd;
    procedure FillAndStrokeNonZero;
    procedure DiscardPath;

    // ---------- Clipping ----------
    // Constructs a rectangle path in user coords and uses it as the current
    // clipping path with the even-odd rule, then discards (n) so nothing is painted.
    procedure SetClipRect(X1Px, Y1Px, X2Px, Y2Px: Double);

    // ---------- Text ----------
    procedure BeginText;                                            // BT
    procedure EndText;                                              // ET
    procedure SetTextFont(const AResourceName: string;
      ASizePoints: Double);                                         // /F1 12 Tf
    procedure SetTextMatrixUserBaseline(XPx, YPxBaseline: Double);  // 1 0 0 1 X Y Tm
    procedure SetTextMatrixUser(A, B, C, D, XPx, YPxBaseline: Double); // A B C D X Y Tm
    procedure SetTextRenderingMode(AMode: Integer);                 // 0=fill, 1=stroke, 2=fill+stroke, 3=invisible
    procedure ShowTextAnsi(const AAnsiBytes: AnsiString);           // (...) Tj — bytes already WinAnsi
    procedure ShowTextBytes(const ACodes: array of Word);           // (...) Tj — one byte per code
    procedure ShowTextGlyphs(const AGlyphs: array of Word);         // <gid gid ...> Tj — Identity-H

    // ---------- Clip stack ----------
    // q, rectangle, W n. Every PushClip must be matched by PopClip; any still
    // open when the page is written are closed there so q/Q always balance.
    procedure PushClip(X1Px, Y1Px, X2Px, Y2Px: Double);
    procedure PopClip;

    // ---------- Deferred paths ----------
    // Between these calls, operators go to a side buffer instead of the page,
    // so the graphics state for painting can be written before the path.
    procedure BeginPathCapture;
    procedure EndPathCapture;
    procedure AppendCapturedPath;
    function  CapturedPathSize: Integer;

    function ContentStreamSize: Integer;

    property WidthPixels:   Integer read GetWidthPixels;
    property HeightPixels:  Integer read GetHeightPixels;
    property Dpi:           Integer read fDpi;
    property ClipDepth:     Integer read fClipDepth;
    // Decimals written for path coordinates (m, l, c, re); 3 by default.
    property CoordDecimals: Integer read fCoordDecimals write fCoordDecimals;
  end;

implementation

uses
  Math, smPDF.Geometry, smPDF.Images;

constructor TPDFPage.Create(AWidthPixels, AHeightPixels, ADpi: Integer);
begin
  CreatePoints(PixelsToPoints(AWidthPixels, ADpi), PixelsToPoints(AHeightPixels, ADpi), ADpi);
end;

constructor TPDFPage.CreatePoints(AWidthPoints, AHeightPoints: Double; ADpi: Integer);
begin
  inherited Create;
  fWidthPoints   := AWidthPoints;
  fHeightPoints  := AHeightPoints;
  fDpi           := ADpi;
  fScale         := POINTS_PER_INCH / ADpi;
  fContent       := TPDFByteBuffer.Create;
  fPathContent   := nil;
  fOut           := fContent;
  fClipDepth     := 0;
  fCoordDecimals := 3;
  fFontMap       := TDictionary<string, string>.Create;
  fFontOrder     := TList<string>.Create;
  fImageMap      := TDictionary<string, string>.Create;
  fImageOrder    := TList<string>.Create;
end;

destructor TPDFPage.Destroy;
begin
  fImageOrder.Free;
  fImageMap.Free;
  fFontOrder.Free;
  fFontMap.Free;
  fPathContent.Free;
  fContent.Free;
  inherited;
end;

function TPDFPage.PdfX(XPx: Double): Double;
begin
  Result := XPx * fScale;
end;

function TPDFPage.PdfY(YPx: Double): Double;
begin
  Result := fHeightPoints - YPx * fScale;
end;

function TPDFPage.GetWidthPixels: Integer;
begin
  Result := PointsToPixels(fWidthPoints, fDpi);
end;

function TPDFPage.GetHeightPixels: Integer;
begin
  Result := PointsToPixels(fHeightPoints, fDpi);
end;

function TPDFPage.UseFont(const APdfFontName: string): string;
begin
  if fFontMap.TryGetValue(APdfFontName, Result) then
    Exit;
  Result := 'F' + IntToStr(fFontOrder.Count + 1);
  fFontMap.Add(APdfFontName, Result);
  fFontOrder.Add(APdfFontName);
end;

function TPDFPage.UsedFontNames: TArray<string>;
begin
  Result := fFontOrder.ToArray;
end;

function TPDFPage.UseImage(const AImageKey: string): string;
begin
  if fImageMap.TryGetValue(AImageKey, Result) then
    Exit;
  Result := 'Im' + IntToStr(fImageOrder.Count + 1);
  fImageMap.Add(AImageKey, Result);
  fImageOrder.Add(AImageKey);
end;

function TPDFPage.UsedImageKeys: TArray<string>;
begin
  Result := fImageOrder.ToArray;
end;

procedure TPDFPage.DrawImageUserRect(const AResName: string;
  AX1Px, AY1Px, AX2Px, AY2Px: Double);
var
  llX, llY, w, h: Double;
begin
  llX := PdfX(AX1Px);
  llY := PdfY(AY2Px);            // bottom-left in PDF coords
  w   := PdfX(AX2Px) - llX;
  h   := PdfY(AY1Px) - llY;

  SaveState;
  // PDF cm: a b c d e f -> [a b 0; c d 0; e f 1] applied to image's unit square
  WriteOp('cm', [w, 0, 0, h, llX, llY]);
  WriteRaw('/' + AResName + ' Do'#10);
  RestoreState;
end;

function TPDFPage.WidthPoints: Double;
begin
  Result := fWidthPoints;
end;

function TPDFPage.HeightPoints: Double;
begin
  Result := fHeightPoints;
end;

function TPDFPage.ContentStreamSize: Integer;
begin
  Result := fContent.Size;
end;

procedure TPDFPage.PushClip(X1Px, Y1Px, X2Px, Y2Px: Double);
begin
  SaveState;
  UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px);
  WriteRaw('W n'#10);
  Inc(fClipDepth);
end;

procedure TPDFPage.PopClip;
begin
  if fClipDepth <= 0 then
    raise EInvalidOpException.Create('PopClip without a matching PushClip');
  RestoreState;
  Dec(fClipDepth);
end;

procedure TPDFPage.BeginPathCapture;
begin
  if fPathContent = nil then
    fPathContent := TPDFByteBuffer.Create;
  fPathContent.Clear;
  fOut := fPathContent;
end;

procedure TPDFPage.EndPathCapture;
begin
  fOut := fContent;
end;

procedure TPDFPage.AppendCapturedPath;
begin
  fContent.AppendBuffer(fPathContent);
end;

function TPDFPage.CapturedPathSize: Integer;
begin
  if fPathContent = nil then
    Result := 0
  else
    Result := fPathContent.Size;
end;

procedure TPDFPage.WriteRaw(const AStr: string);
begin
  fOut.AppendAscii(AStr);
end;

procedure TPDFPage.WriteOp(const AOperator: string; const AOperands: array of Double);
var
  i: Integer;
begin
  for i := 0 to High(AOperands) do
  begin
    fOut.AppendNumber(AOperands[i]);
    fOut.AppendByte(Ord(' '));
  end;
  fOut.AppendAscii(AOperator);
  fOut.AppendByte(10);
end;

procedure TPDFPage.WriteCoordOp(const AOperator: string; const AOperands: array of Double);
var
  i: Integer;
begin
  for i := 0 to High(AOperands) do
  begin
    fOut.AppendCoord(AOperands[i], fCoordDecimals);
    fOut.AppendByte(Ord(' '));
  end;
  fOut.AppendAscii(AOperator);
  fOut.AppendByte(10);
end;

// ---------- Graphics state ----------

procedure TPDFPage.SaveState;
begin
  WriteRaw('q'#10);
end;

procedure TPDFPage.RestoreState;
begin
  WriteRaw('Q'#10);
end;

procedure TPDFPage.SetStrokeRGB(R, G, B: Double);
begin
  WriteOp('RG', [R, G, B]);
end;

procedure TPDFPage.SetFillRGB(R, G, B: Double);
begin
  WriteOp('rg', [R, G, B]);
end;

procedure TPDFPage.SetLineWidthPt(W: Double);
begin
  WriteOp('w', [W]);
end;

procedure TPDFPage.SetDashPattern(const APattern: array of Double; APhase: Double);
var
  i: Integer;
begin
  fOut.AppendByte(Ord('['));
  for i := 0 to High(APattern) do
  begin
    if i > 0 then fOut.AppendByte(Ord(' '));
    fOut.AppendNumber(APattern[i]);
  end;
  fOut.AppendAscii('] ');
  fOut.AppendNumber(APhase);
  fOut.AppendAscii(' d'#10);
end;

procedure TPDFPage.SetLineCap(ACap: Integer);
begin
  fOut.AppendInt(ACap);
  fOut.AppendAscii(' J'#10);
end;

procedure TPDFPage.SetLineJoin(AJoin: Integer);
begin
  fOut.AppendInt(AJoin);
  fOut.AppendAscii(' j'#10);
end;

procedure TPDFPage.ConcatMatrix(A, B, C, D, E, F: Double);
begin
  WriteOp('cm', [A, B, C, D, E, F]);
end;

// ---------- Path construction ----------

procedure TPDFPage.UserMoveTo(XPx, YPx: Double);
begin
  fOut.AppendPointOp(PdfX(XPx), PdfY(YPx), 'm', fCoordDecimals);
end;

procedure TPDFPage.UserLineTo(XPx, YPx: Double);
begin
  fOut.AppendPointOp(PdfX(XPx), PdfY(YPx), 'l', fCoordDecimals);
end;

procedure TPDFPage.UserCurveTo(X1Px, Y1Px, X2Px, Y2Px, X3Px, Y3Px: Double);
begin
  WriteCoordOp('c', [PdfX(X1Px), PdfY(Y1Px), PdfX(X2Px), PdfY(Y2Px), PdfX(X3Px), PdfY(Y3Px)]);
end;

procedure TPDFPage.UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px: Double);
var
  x1, y1, x2, y2: Double;
begin
  x1 := PdfX(X1Px);
  y1 := PdfY(Y1Px);
  x2 := PdfX(X2Px);
  y2 := PdfY(Y2Px);
  WriteCoordOp('re', [Min(x1, x2), Min(y1, y2), Abs(x2 - x1), Abs(y1 - y2)]);
end;

procedure TPDFPage.UserOvalPath(X1Px, Y1Px, X2Px, Y2Px: Double);
const
  KAPPA = 0.5522847498307933;  // 4*(sqrt(2)-1)/3 — best-fit cubic for a quarter circle
var
  cx, cy, rx, ry, kx, ky: Double;
begin
  cx := (PdfX(X1Px) + PdfX(X2Px)) / 2.0;
  cy := (PdfY(Y1Px) + PdfY(Y2Px)) / 2.0;
  rx := Abs(PdfX(X2Px) - PdfX(X1Px)) / 2.0;
  ry := Abs(PdfY(Y1Px) - PdfY(Y2Px)) / 2.0;
  kx := KAPPA * rx;
  ky := KAPPA * ry;

  // Top of ellipse, then four cubic-bezier quadrants going clockwise (in PDF coord sense)
  WriteCoordOp('m', [cx,            cy + ry]);
  WriteCoordOp('c', [cx + kx, cy + ry,  cx + rx, cy + ky,  cx + rx, cy]);
  WriteCoordOp('c', [cx + rx, cy - ky,  cx + kx, cy - ry,  cx,      cy - ry]);
  WriteCoordOp('c', [cx - kx, cy - ry,  cx - rx, cy - ky,  cx - rx, cy]);
  WriteCoordOp('c', [cx - rx, cy + ky,  cx - kx, cy + ry,  cx,      cy + ry]);
  ClosePath;
end;

procedure TPDFPage.ClosePath;
begin
  WriteRaw('h'#10);
end;

// ---------- Painting ----------

procedure TPDFPage.Stroke;
begin
  WriteRaw('S'#10);
end;

procedure TPDFPage.FillEvenOdd;
begin
  WriteRaw('f*'#10);
end;

procedure TPDFPage.FillNonZero;
begin
  WriteRaw('f'#10);
end;

procedure TPDFPage.FillAndStrokeEvenOdd;
begin
  WriteRaw('B*'#10);
end;

procedure TPDFPage.FillAndStrokeNonZero;
begin
  WriteRaw('B'#10);
end;

procedure TPDFPage.DiscardPath;
begin
  WriteRaw('n'#10);
end;

// ---------- Clipping ----------

procedure TPDFPage.SetClipRect(X1Px, Y1Px, X2Px, Y2Px: Double);
begin
  UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px);
  WriteRaw('W*'#10);  // intersect with current clip path, even-odd rule
  WriteRaw('n'#10);   // discard the rectangle path itself; it served only as the clip
end;

// ---------- Text ----------

procedure TPDFPage.BeginText;
begin
  WriteRaw('BT'#10);
end;

procedure TPDFPage.EndText;
begin
  WriteRaw('ET'#10);
end;

procedure TPDFPage.SetTextFont(const AResourceName: string; ASizePoints: Double);
begin
  fOut.AppendByte(Ord('/'));
  fOut.AppendAscii(AResourceName);
  fOut.AppendByte(Ord(' '));
  fOut.AppendNumber(ASizePoints);
  fOut.AppendAscii(' Tf'#10);
end;

procedure TPDFPage.SetTextMatrixUserBaseline(XPx, YPxBaseline: Double);
begin
  WriteOp('Tm', [1.0, 0.0, 0.0, 1.0, PdfX(XPx), PdfY(YPxBaseline)]);
end;

procedure TPDFPage.SetTextMatrixUser(A, B, C, D, XPx, YPxBaseline: Double);
begin
  WriteOp('Tm', [A, B, C, D, PdfX(XPx), PdfY(YPxBaseline)]);
end;

procedure TPDFPage.SetTextRenderingMode(AMode: Integer);
begin
  fOut.AppendInt(AMode);
  fOut.AppendAscii(' Tr'#10);
end;

procedure TPDFPage.ShowTextAnsi(const AAnsiBytes: AnsiString);
var
  i: Integer;
  c: AnsiChar;
begin
  fOut.AppendByte(Ord('('));
  for i := 1 to Length(AAnsiBytes) do
  begin
    c := AAnsiBytes[i];
    case c of
      '(': fOut.AppendAscii('\(');
      ')': fOut.AppendAscii('\)');
      '\': fOut.AppendAscii('\\');
      #10: fOut.AppendAscii('\n');
      #13: fOut.AppendAscii('\r');
      #9:  fOut.AppendAscii('\t');
      #8:  fOut.AppendAscii('\b');
      #12: fOut.AppendAscii('\f');
    else
      fOut.AppendByte(Ord(c));
    end;
  end;
  fOut.AppendAscii(') Tj'#10);
end;

procedure TPDFPage.ShowTextBytes(const ACodes: array of Word);
var
  ansi: AnsiString;
  i: Integer;
begin
  SetLength(ansi, Length(ACodes));
  for i := 0 to High(ACodes) do
    ansi[i + 1] := AnsiChar(Byte(ACodes[i]));
  ShowTextAnsi(ansi);
end;

procedure TPDFPage.ShowTextGlyphs(const AGlyphs: array of Word);
const
  HEX: array[0..15] of Byte = (48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70);
var
  i: Integer;
  g: Word;
begin
  fOut.AppendByte(Ord('<'));
  for i := 0 to High(AGlyphs) do
  begin
    g := AGlyphs[i];
    fOut.AppendByte(HEX[(g shr 12) and $F]);
    fOut.AppendByte(HEX[(g shr 8) and $F]);
    fOut.AppendByte(HEX[(g shr 4) and $F]);
    fOut.AppendByte(HEX[g and $F]);
  end;
  fOut.AppendAscii('> Tj'#10);
end;

// ---------- Object emission ----------

function TPDFPage.Emit(AWriter: TPDFWriter; AParentId: TPDFObjectId;
  AFontIds: TDictionary<string, TPDFObjectId> = nil;
  AImageIds: TDictionary<string, TPDFObjectId> = nil;
  ACompress: Boolean = False): TPDFObjectId;
var
  packed_: TBytes;
  contentId, pageId: TPDFObjectId;
  fontName, imageKey: string;
  fontObjId, imageObjId: TPDFObjectId;
  hasFonts, hasImages: Boolean;
  userSize: NativeInt;
  i: Integer;
begin
  // Close clips left open by the caller, without changing the page: the
  // Q operators are appended only for the duration of this write.
  userSize := fContent.Size;
  for i := 1 to fClipDepth do
    fContent.AppendAscii('Q'#10);
  try
  if ACompress then
  begin
    packed_ := FlateCompress(fContent.Memory, fContent.Size);
    contentId := AWriter.EmitStreamObject(packed_,
      procedure(w: TPDFWriter)
      begin
        w.WriteName('Filter'); w.WriteName('FlateDecode');
      end);
    packed_ := nil;
  end
  else
    contentId := AWriter.EmitStreamObject(fContent.Memory, fContent.Size, nil);
  finally
    fContent.Truncate(userSize);
  end;

  hasFonts  := (AFontIds  <> nil) and (fFontOrder.Count  > 0);
  hasImages := (AImageIds <> nil) and (fImageOrder.Count > 0);

  pageId := AWriter.BeginObject;
    AWriter.BeginDict;
      AWriter.WriteName('Type');     AWriter.WriteName('Page');
      AWriter.WriteName('Parent');   AWriter.WriteRef(AParentId);
      AWriter.WriteName('MediaBox'); AWriter.BeginArray;
        AWriter.WriteNumber(0);
        AWriter.WriteNumber(0);
        AWriter.WriteNumber(WidthPoints);
        AWriter.WriteNumber(HeightPoints);
      AWriter.EndArray;
      AWriter.WriteName('Resources');
      AWriter.BeginDict;
        if hasFonts then
        begin
          AWriter.WriteName('Font');
          AWriter.BeginDict;
            for fontName in fFontOrder do
              if AFontIds.TryGetValue(fontName, fontObjId) then
              begin
                AWriter.WriteName(fFontMap[fontName]);
                AWriter.WriteRef(fontObjId);
              end;
          AWriter.EndDict;
        end;
        if hasImages then
        begin
          AWriter.WriteName('XObject');
          AWriter.BeginDict;
            for imageKey in fImageOrder do
              if AImageIds.TryGetValue(imageKey, imageObjId) then
              begin
                AWriter.WriteName(fImageMap[imageKey]);
                AWriter.WriteRef(imageObjId);
              end;
          AWriter.EndDict;
        end;
      AWriter.EndDict;
      AWriter.WriteName('Contents'); AWriter.WriteRef(contentId);
    AWriter.EndDict;
  AWriter.EndObject;

  Result := pageId;
end;

end.
