{$M+}
unit smPDF.TestFramework;

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  ETestFailed = class(Exception);
  ETestSkipped = class(Exception);

  TTestCase = class
  protected
    procedure SetUp; virtual;
    procedure TearDown; virtual;

    procedure Fail(const AMsg: string);
    // Ends the test without failing it. For tests that depend on something
    // the machine may not have (an installed font, mutool on the PATH).
    procedure Skip(const AReason: string);

    procedure AssertTrue(ACondition: Boolean; const AMsg: string = '');
    procedure AssertFalse(ACondition: Boolean; const AMsg: string = '');

    procedure AssertEquals(const AExpected, AActual: string; const AMsg: string = ''); overload;
    procedure AssertEquals(AExpected, AActual: Integer; const AMsg: string = ''); overload;
    procedure AssertEquals(AExpected, AActual: Int64; const AMsg: string = ''); overload;
    procedure AssertEquals(AExpected, AActual: Double; ATolerance: Double = 1e-9; const AMsg: string = ''); overload;
    procedure AssertEquals(AExpected, AActual: Boolean; const AMsg: string = ''); overload;

    procedure AssertNotEmpty(const AString: string; const AMsg: string = '');
    procedure AssertContains(const ASubstring, AHaystack: string; const AMsg: string = '');
    procedure AssertStartsWith(const APrefix, AString: string; const AMsg: string = '');

    procedure AssertBytesEqual(const AExpected, AActual: TBytes; const AMsg: string = '');
  end;

  TTestCaseClass = class of TTestCase;

  TTestRegistry = class
  strict private
    class var FClasses: TList<TTestCaseClass>;
  public
    class constructor Create;
    class destructor Destroy;

    class procedure RegisterTestCase(ATestClass: TTestCaseClass);
    class function Classes: TList<TTestCaseClass>;
  end;

  TTestStatus = (tsPassed, tsFailed, tsError, tsSkipped);

  TTestResult = record
    ClassName: string;
    MethodName: string;
    Status: TTestStatus;
    Message: string;
    DurationMs: Double;
  end;

  TTestRunner = class
  public
    class function RunAll: TArray<TTestResult>;
    class procedure WriteConsole(const AResults: TArray<TTestResult>);
    class procedure WriteJUnit(const AFileName: string; const AResults: TArray<TTestResult>);
    class function FailureCount(const AResults: TArray<TTestResult>): Integer;
  end;

implementation

uses
  Math, Diagnostics, RTTI, TypInfo, IOUtils;

{ TTestCase }

procedure TTestCase.SetUp;
begin
end;

procedure TTestCase.TearDown;
begin
end;

procedure TTestCase.Fail(const AMsg: string);
begin
  raise ETestFailed.Create(AMsg);
end;

procedure TTestCase.Skip(const AReason: string);
begin
  raise ETestSkipped.Create(AReason);
end;

procedure TTestCase.AssertTrue(ACondition: Boolean; const AMsg: string);
begin
  if not ACondition then
    Fail('AssertTrue failed: ' + AMsg);
end;

procedure TTestCase.AssertFalse(ACondition: Boolean; const AMsg: string);
begin
  if ACondition then
    Fail('AssertFalse failed: ' + AMsg);
end;

procedure TTestCase.AssertEquals(const AExpected, AActual: string; const AMsg: string);
begin
  if AExpected <> AActual then
    Fail(Format('AssertEquals failed: expected "%s" got "%s" (%s)', [AExpected, AActual, AMsg]));
end;

procedure TTestCase.AssertEquals(AExpected, AActual: Integer; const AMsg: string);
begin
  if AExpected <> AActual then
    Fail(Format('AssertEquals failed: expected %d got %d (%s)', [AExpected, AActual, AMsg]));
end;

procedure TTestCase.AssertEquals(AExpected, AActual: Int64; const AMsg: string);
begin
  if AExpected <> AActual then
    Fail(Format('AssertEquals failed: expected %d got %d (%s)', [AExpected, AActual, AMsg]));
end;

procedure TTestCase.AssertEquals(AExpected, AActual: Double; ATolerance: Double; const AMsg: string);
begin
  if not SameValue(AExpected, AActual, ATolerance) then
    Fail(Format('AssertEquals failed: expected %g got %g (tol %g) (%s)',
      [AExpected, AActual, ATolerance, AMsg]));
end;

procedure TTestCase.AssertEquals(AExpected, AActual: Boolean; const AMsg: string);
begin
  if AExpected <> AActual then
    Fail(Format('AssertEquals failed: expected %s got %s (%s)',
      [BoolToStr(AExpected, True), BoolToStr(AActual, True), AMsg]));
end;

procedure TTestCase.AssertNotEmpty(const AString: string; const AMsg: string);
begin
  if AString = '' then
    Fail('AssertNotEmpty failed: ' + AMsg);
end;

procedure TTestCase.AssertContains(const ASubstring, AHaystack: string; const AMsg: string);
begin
  if Pos(ASubstring, AHaystack) = 0 then
    Fail(Format('AssertContains failed: "%s" not found in "%s" (%s)',
      [ASubstring, AHaystack, AMsg]));
end;

procedure TTestCase.AssertStartsWith(const APrefix, AString: string; const AMsg: string);
begin
  if Copy(AString, 1, Length(APrefix)) <> APrefix then
    Fail(Format('AssertStartsWith failed: "%s" does not start with "%s" (%s)',
      [AString, APrefix, AMsg]));
end;

procedure TTestCase.AssertBytesEqual(const AExpected, AActual: TBytes; const AMsg: string);
var
  i: Integer;
begin
  if Length(AExpected) <> Length(AActual) then
    Fail(Format('AssertBytesEqual failed: lengths differ (expected %d, got %d) (%s)',
      [Length(AExpected), Length(AActual), AMsg]));
  for i := 0 to High(AExpected) do
    if AExpected[i] <> AActual[i] then
      Fail(Format('AssertBytesEqual failed at index %d: expected $%.2x got $%.2x (%s)',
        [i, AExpected[i], AActual[i], AMsg]));
end;

{ TTestRegistry }

class constructor TTestRegistry.Create;
begin
  FClasses := TList<TTestCaseClass>.Create;
end;

class destructor TTestRegistry.Destroy;
begin
  FClasses.Free;
end;

class procedure TTestRegistry.RegisterTestCase(ATestClass: TTestCaseClass);
begin
  if FClasses.IndexOf(ATestClass) < 0 then
    FClasses.Add(ATestClass);
end;

class function TTestRegistry.Classes: TList<TTestCaseClass>;
begin
  Result := FClasses;
end;

{ TTestRunner }

class function TTestRunner.RunAll: TArray<TTestResult>;
var
  cls: TTestCaseClass;
  ctx: TRttiContext;
  rtype: TRttiType;
  method: TRttiMethod;
  results: TList<TTestResult>;
  res: TTestResult;
  instance: TTestCase;
  sw: TStopwatch;
begin
  results := TList<TTestResult>.Create;
  try
    ctx := TRttiContext.Create;
    try
      for cls in TTestRegistry.Classes do
      begin
        rtype := ctx.GetType(cls);
        for method in rtype.GetMethods do
        begin
          if (method.Visibility <> mvPublished) then Continue;
          if (Length(method.GetParameters) <> 0) then Continue;
          if (method.MethodKind <> mkProcedure) then Continue;
          if SameText(method.Name, 'SetUp') or SameText(method.Name, 'TearDown') then Continue;

          res.ClassName := cls.ClassName;
          res.MethodName := method.Name;
          res.Status := tsPassed;
          res.Message := '';

          sw := TStopwatch.StartNew;
          instance := cls.Create;
          try
            try
              instance.SetUp;
              try
                method.Invoke(instance, []);
              finally
                instance.TearDown;
              end;
            except
              on E: ETestSkipped do
              begin
                res.Status := tsSkipped;
                res.Message := E.Message;
              end;
              on E: ETestFailed do
              begin
                res.Status := tsFailed;
                res.Message := E.Message;
              end;
              on E: Exception do
              begin
                res.Status := tsError;
                res.Message := E.ClassName + ': ' + E.Message;
              end;
            end;
          finally
            instance.Free;
          end;
          sw.Stop;
          res.DurationMs := sw.Elapsed.TotalMilliseconds;
          results.Add(res);
        end;
      end;
    finally
      ctx.Free;
    end;
    Result := results.ToArray;
  finally
    results.Free;
  end;
end;

class procedure TTestRunner.WriteConsole(const AResults: TArray<TTestResult>);
var
  r: TTestResult;
  passed, failed, errors, skipped: Integer;
  totalMs: Double;
  prefix: string;
begin
  passed := 0; failed := 0; errors := 0; skipped := 0; totalMs := 0;
  for r in AResults do
  begin
    case r.Status of
      tsPassed: begin Inc(passed); prefix := '  PASS'; end;
      tsFailed: begin Inc(failed); prefix := '  FAIL'; end;
      tsError:  begin Inc(errors); prefix := ' ERROR'; end;
      tsSkipped: begin Inc(skipped); prefix := '  SKIP'; end;
    end;
    totalMs := totalMs + r.DurationMs;
    Writeln(Format('%s  %s.%s  (%.2f ms)', [prefix, r.ClassName, r.MethodName, r.DurationMs]));
    if r.Status <> tsPassed then
      Writeln('        ' + r.Message);
  end;
  Writeln('');
  Writeln(Format('Tests: %d passed, %d failed, %d errors, %d skipped  (%.2f ms total)',
    [passed, failed, errors, skipped, totalMs]));
end;

class procedure TTestRunner.WriteJUnit(const AFileName: string; const AResults: TArray<TTestResult>);
var
  sb: TStringBuilder;
  r: TTestResult;
  failures, errors, skipped, total: Integer;
  totalSecs: Double;

  function Esc(const S: string): string;
  begin
    Result := S;
    Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
    Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  end;

begin
  failures := 0; errors := 0; skipped := 0; total := Length(AResults); totalSecs := 0;
  for r in AResults do
  begin
    if r.Status = tsFailed then Inc(failures);
    if r.Status = tsError then Inc(errors);
    if r.Status = tsSkipped then Inc(skipped);
    totalSecs := totalSecs + r.DurationMs / 1000.0;
  end;

  sb := TStringBuilder.Create;
  try
    sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    sb.AppendLine(Format('<testsuite name="smPDF" tests="%d" failures="%d" errors="%d" skipped="%d" time="%.3f">',
      [total, failures, errors, skipped, totalSecs]));
    for r in AResults do
    begin
      sb.AppendFormat('  <testcase classname="%s" name="%s" time="%.3f"',
        [Esc(r.ClassName), Esc(r.MethodName), r.DurationMs / 1000.0]);
      case r.Status of
        tsPassed: sb.AppendLine(' />');
        tsFailed:
          begin
            sb.AppendLine('>');
            sb.AppendLine(Format('    <failure message="%s"/>', [Esc(r.Message)]));
            sb.AppendLine('  </testcase>');
          end;
        tsError:
          begin
            sb.AppendLine('>');
            sb.AppendLine(Format('    <error message="%s"/>', [Esc(r.Message)]));
            sb.AppendLine('  </testcase>');
          end;
        tsSkipped:
          begin
            sb.AppendLine('>');
            sb.AppendLine(Format('    <skipped message="%s"/>', [Esc(r.Message)]));
            sb.AppendLine('  </testcase>');
          end;
      end;
    end;
    sb.AppendLine('</testsuite>');
    TFile.WriteAllText(AFileName, sb.ToString, TEncoding.UTF8);
  finally
    sb.Free;
  end;
end;

class function TTestRunner.FailureCount(const AResults: TArray<TTestResult>): Integer;
var
  r: TTestResult;
begin
  Result := 0;
  for r in AResults do
    if r.Status in [tsFailed, tsError] then Inc(Result);
end;

end.
