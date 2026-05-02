unit smPDF.Types;

interface

type
  TPDFPointF = record
    X, Y: Double;
    constructor Create(AX, AY: Double);
  end;

  TPDFRectF = record
    X1, Y1, X2, Y2: Double;
    constructor Create(AX1, AY1, AX2, AY2: Double);
    function Width: Double;
    function Height: Double;
  end;

  TPDFPaperDimensions = record
    WidthPixels:  Integer;
    HeightPixels: Integer;
  end;

implementation

constructor TPDFPointF.Create(AX, AY: Double);
begin
  X := AX;
  Y := AY;
end;

constructor TPDFRectF.Create(AX1, AY1, AX2, AY2: Double);
begin
  X1 := AX1;
  Y1 := AY1;
  X2 := AX2;
  Y2 := AY2;
end;

function TPDFRectF.Width: Double;
begin
  Result := X2 - X1;
end;

function TPDFRectF.Height: Double;
begin
  Result := Y2 - Y1;
end;

end.
