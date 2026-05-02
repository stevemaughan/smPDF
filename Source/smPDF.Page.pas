unit smPDF.Page;

interface

uses
  SysUtils, Classes, Generics.Collections, smPDF.Writer, smPDF.Types;

type
  TPDFPage = class
  strict private
    fWidthPixels:   Integer;
    fHeightPixels:  Integer;
    fDpi:           Integer;
    fContentStream: TBytesStream;
    fFontMap:       TDictionary<string, string>;  // PDF font name -> page-local resource name (F1, F2, ...)
    fFontOrder:     TList<string>;                // insertion order for stable iteration
    fImageMap:      TDictionary<string, string>;  // image key -> page-local name (Im1, Im2, ...)
    fImageOrder:    TList<string>;                // insertion order for stable iteration

    procedure WriteRaw(const ABytes: TBytes); overload;
    procedure WriteRaw(const AStr: string); overload;
    procedure WriteRawAnsi(const AAnsi: AnsiString);
    procedure WriteOp(const AOperator: string; const AOperands: array of Double);
    function  ToPdfPoint(XPx, YPx: Integer): TPDFPointF;
  public
    constructor Create(AWidthPixels, AHeightPixels, ADpi: Integer);
    destructor  Destroy; override;

    function WidthPoints: Double;
    function HeightPoints: Double;

    function Emit(AWriter: TPDFWriter; AParentId: TPDFObjectId;
      AFontIds: TDictionary<string, TPDFObjectId> = nil;
      AImageIds: TDictionary<string, TPDFObjectId> = nil): TPDFObjectId;

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
      AX1Px, AY1Px, AX2Px, AY2Px: Integer);

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
    procedure UserMoveTo(XPx, YPx: Integer);
    procedure UserLineTo(XPx, YPx: Integer);
    procedure UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px: Integer);
    procedure UserOvalPath(X1Px, Y1Px, X2Px, Y2Px: Integer);
    procedure ClosePath;

    // ---------- Painting ----------
    procedure Stroke;
    procedure FillEvenOdd;
    procedure FillAndStrokeEvenOdd;
    procedure DiscardPath;

    // ---------- Clipping ----------
    // Constructs a rectangle path in user coords and uses it as the current
    // clipping path with the even-odd rule, then discards (n) so nothing is painted.
    procedure SetClipRect(X1Px, Y1Px, X2Px, Y2Px: Integer);

    // ---------- Text ----------
    procedure BeginText;                                            // BT
    procedure EndText;                                              // ET
    procedure SetTextFont(const AResourceName: string;
      ASizePoints: Double);                                         // /F1 12 Tf
    procedure SetTextMatrixUserBaseline(XPx, YPxBaseline: Integer); // 1 0 0 1 X Y Tm
    procedure SetTextRenderingMode(AMode: Integer);                 // 0=fill, 1=stroke, 2=fill+stroke, 3=invisible
    procedure ShowTextAnsi(const AAnsiBytes: AnsiString);           // (...) Tj — bytes already WinAnsi

    function ContentStreamSize: Integer;

    property WidthPixels:   Integer read fWidthPixels;
    property HeightPixels:  Integer read fHeightPixels;
    property Dpi:           Integer read fDpi;
  end;

implementation

uses
  Math, smPDF.Geometry;

constructor TPDFPage.Create(AWidthPixels, AHeightPixels, ADpi: Integer);
begin
  inherited Create;
  fWidthPixels   := AWidthPixels;
  fHeightPixels  := AHeightPixels;
  fDpi           := ADpi;
  fContentStream := TBytesStream.Create;
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
  fContentStream.Free;
  inherited;
end;

procedure TPDFPage.WriteRawAnsi(const AAnsi: AnsiString);
var
  bytes: TBytes;
begin
  if AAnsi = '' then Exit;
  SetLength(bytes, Length(AAnsi));
  Move(AAnsi[1], bytes[0], Length(AAnsi));
  WriteRaw(bytes);
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
  AX1Px, AY1Px, AX2Px, AY2Px: Integer);
var
  pTL, pBR: TPDFPointF;
  llX, llY, w, h: Double;
begin
  pTL := ToPdfPoint(AX1Px, AY1Px);
  pBR := ToPdfPoint(AX2Px, AY2Px);

  llX := pTL.X;
  llY := pBR.Y;            // bottom-left in PDF coords
  w   := pBR.X - pTL.X;
  h   := pTL.Y - pBR.Y;

  SaveState;
  // PDF cm: a b c d e f -> [a b 0; c d 0; e f 1] applied to image's unit square
  WriteOp('cm', [w, 0, 0, h, llX, llY]);
  WriteRaw('/' + AResName + ' Do'#10);
  RestoreState;
end;

function TPDFPage.WidthPoints: Double;
begin
  Result := PixelsToPoints(fWidthPixels, fDpi);
end;

function TPDFPage.HeightPoints: Double;
begin
  Result := PixelsToPoints(fHeightPixels, fDpi);
end;

function TPDFPage.ContentStreamSize: Integer;
begin
  Result := fContentStream.Size;
end;

procedure TPDFPage.WriteRaw(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    fContentStream.WriteBuffer(ABytes[0], Length(ABytes));
end;

procedure TPDFPage.WriteRaw(const AStr: string);
var
  bytes: TBytes;
  i: Integer;
begin
  if AStr = '' then Exit;
  SetLength(bytes, Length(AStr));
  for i := 1 to Length(AStr) do
    bytes[i - 1] := Byte(Ord(AStr[i]) and $FF);
  WriteRaw(bytes);
end;

procedure TPDFPage.WriteOp(const AOperator: string; const AOperands: array of Double);
var
  i: Integer;
  s: string;
begin
  s := '';
  for i := 0 to High(AOperands) do
  begin
    if i > 0 then s := s + ' ';
    s := s + FormatPdfNumber(AOperands[i]);
  end;
  if Length(AOperands) > 0 then s := s + ' ';
  s := s + AOperator + #10;
  WriteRaw(s);
end;

function TPDFPage.ToPdfPoint(XPx, YPx: Integer): TPDFPointF;
begin
  Result := PixelToPdfPoint(XPx, YPx, fDpi, fHeightPixels);
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
  s: string;
begin
  s := '[';
  for i := 0 to High(APattern) do
  begin
    if i > 0 then s := s + ' ';
    s := s + FormatPdfNumber(APattern[i]);
  end;
  s := s + '] ' + FormatPdfNumber(APhase) + ' d'#10;
  WriteRaw(s);
end;

procedure TPDFPage.SetLineCap(ACap: Integer);
begin
  WriteRaw(IntToStr(ACap) + ' J'#10);
end;

procedure TPDFPage.SetLineJoin(AJoin: Integer);
begin
  WriteRaw(IntToStr(AJoin) + ' j'#10);
end;

procedure TPDFPage.ConcatMatrix(A, B, C, D, E, F: Double);
begin
  WriteOp('cm', [A, B, C, D, E, F]);
end;

// ---------- Path construction ----------

procedure TPDFPage.UserMoveTo(XPx, YPx: Integer);
var
  p: TPDFPointF;
begin
  p := ToPdfPoint(XPx, YPx);
  WriteOp('m', [p.X, p.Y]);
end;

procedure TPDFPage.UserLineTo(XPx, YPx: Integer);
var
  p: TPDFPointF;
begin
  p := ToPdfPoint(XPx, YPx);
  WriteOp('l', [p.X, p.Y]);
end;

procedure TPDFPage.UserRectanglePath(X1Px, Y1Px, X2Px, Y2Px: Integer);
var
  p1, p2: TPDFPointF;
  llX, llY, w, h: Double;
begin
  p1 := ToPdfPoint(X1Px, Y1Px);
  p2 := ToPdfPoint(X2Px, Y2Px);

  llX := Min(p1.X, p2.X);
  llY := Min(p1.Y, p2.Y);
  w   := Abs(p2.X - p1.X);
  h   := Abs(p1.Y - p2.Y);

  WriteOp('re', [llX, llY, w, h]);
end;

procedure TPDFPage.UserOvalPath(X1Px, Y1Px, X2Px, Y2Px: Integer);
const
  KAPPA = 0.5522847498307933;  // 4*(sqrt(2)-1)/3 — best-fit cubic for a quarter circle
var
  pTL, pBR: TPDFPointF;
  cx, cy, rx, ry, kx, ky: Double;
begin
  pTL := ToPdfPoint(X1Px, Y1Px);
  pBR := ToPdfPoint(X2Px, Y2Px);

  cx := (pTL.X + pBR.X) / 2.0;
  cy := (pTL.Y + pBR.Y) / 2.0;
  rx := Abs(pBR.X - pTL.X) / 2.0;
  ry := Abs(pTL.Y - pBR.Y) / 2.0;
  kx := KAPPA * rx;
  ky := KAPPA * ry;

  // Top of ellipse, then four cubic-bezier quadrants going clockwise (in PDF coord sense)
  WriteOp('m', [cx,            cy + ry]);
  WriteOp('c', [cx + kx, cy + ry,  cx + rx, cy + ky,  cx + rx, cy]);
  WriteOp('c', [cx + rx, cy - ky,  cx + kx, cy - ry,  cx,      cy - ry]);
  WriteOp('c', [cx - kx, cy - ry,  cx - rx, cy - ky,  cx - rx, cy]);
  WriteOp('c', [cx - rx, cy + ky,  cx - kx, cy + ry,  cx,      cy + ry]);
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

procedure TPDFPage.FillAndStrokeEvenOdd;
begin
  WriteRaw('B*'#10);
end;

procedure TPDFPage.DiscardPath;
begin
  WriteRaw('n'#10);
end;

// ---------- Clipping ----------

procedure TPDFPage.SetClipRect(X1Px, Y1Px, X2Px, Y2Px: Integer);
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
  WriteRaw('/' + AResourceName + ' ' + FormatPdfNumber(ASizePoints) + ' Tf'#10);
end;

procedure TPDFPage.SetTextMatrixUserBaseline(XPx, YPxBaseline: Integer);
var
  p: TPDFPointF;
begin
  p := ToPdfPoint(XPx, YPxBaseline);
  WriteOp('Tm', [1.0, 0.0, 0.0, 1.0, p.X, p.Y]);
end;

procedure TPDFPage.SetTextRenderingMode(AMode: Integer);
begin
  WriteRaw(IntToStr(AMode) + ' Tr'#10);
end;

procedure TPDFPage.ShowTextAnsi(const AAnsiBytes: AnsiString);
var
  esc: AnsiString;
  i: Integer;
  c: AnsiChar;
begin
  esc := '(';
  for i := 1 to Length(AAnsiBytes) do
  begin
    c := AAnsiBytes[i];
    case c of
      '(': esc := esc + AnsiString('\(');
      ')': esc := esc + AnsiString('\)');
      '\': esc := esc + AnsiString('\\');
      #10: esc := esc + AnsiString('\n');
      #13: esc := esc + AnsiString('\r');
      #9:  esc := esc + AnsiString('\t');
      #8:  esc := esc + AnsiString('\b');
      #12: esc := esc + AnsiString('\f');
    else
      esc := esc + c;
    end;
  end;
  esc := esc + AnsiString(') Tj'#10);
  WriteRawAnsi(esc);
end;

// ---------- Object emission ----------

function TPDFPage.Emit(AWriter: TPDFWriter; AParentId: TPDFObjectId;
  AFontIds: TDictionary<string, TPDFObjectId> = nil;
  AImageIds: TDictionary<string, TPDFObjectId> = nil): TPDFObjectId;
var
  contentBytes: TBytes;
  contentId, pageId: TPDFObjectId;
  fontName, imageKey: string;
  fontObjId, imageObjId: TPDFObjectId;
  hasFonts, hasImages: Boolean;
begin
  SetLength(contentBytes, fContentStream.Size);
  if fContentStream.Size > 0 then
    Move(fContentStream.Memory^, contentBytes[0], fContentStream.Size);

  contentId := AWriter.EmitStreamObject(contentBytes);

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
