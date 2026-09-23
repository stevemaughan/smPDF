unit Tests.PDF.Helpers;

// Shared helpers for tests that need to look inside a finished PDF: turning the
// bytes into a searchable string, and pulling out (and inflating) its streams.

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  TPdfTestStream = record
    ObjectNumber: Integer;
    Dict:         string;   // the text between "N 0 obj" and "stream"
    Raw:          TBytes;   // the bytes exactly as stored
    Data:         TBytes;   // Raw, inflated when the dict says /FlateDecode
  end;

function PdfBytesToString(const ABytes: TBytes): string;
function InflateBytes(const ABytes: TBytes): TBytes;
function ExtractPdfStreams(const ABytes: TBytes): TArray<TPdfTestStream>;
function BytesToLatin1(const ABytes: TBytes): string;
function CountSubstring(const ASubstring, AString: string): Integer;

// Integer value of "/Key N" inside a dictionary string, or -1.
function DictInt(const ADict, AKey: string): Integer;

implementation

uses
  StrUtils, System.ZLib;

function PdfBytesToString(const ABytes: TBytes): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Char(ABytes[i]);
end;

function BytesToLatin1(const ABytes: TBytes): string;
begin
  Result := PdfBytesToString(ABytes);
end;

function InflateBytes(const ABytes: TBytes): TBytes;
var
  src: TBytesStream;
  dst: TBytesStream;
  z: TZDecompressionStream;
begin
  src := TBytesStream.Create(ABytes);
  dst := TBytesStream.Create;
  try
    z := TZDecompressionStream.Create(src);
    try
      dst.CopyFrom(z, 0);
    finally
      z.Free;
    end;
    Result := Copy(dst.Bytes, 0, dst.Size);
  finally
    dst.Free;
    src.Free;
  end;
end;

function CountSubstring(const ASubstring, AString: string): Integer;
var
  p, found: Integer;
begin
  Result := 0;
  if ASubstring = '' then Exit;
  p := 1;
  repeat
    found := PosEx(ASubstring, AString, p);
    if found > 0 then
    begin
      Inc(Result);
      p := found + Length(ASubstring);
    end;
  until found = 0;
end;

function DictInt(const ADict, AKey: string): Integer;
var
  p, q: Integer;
  key: string;
begin
  Result := -1;
  key := '/' + AKey + ' ';
  p := Pos(key, ADict);
  if p = 0 then Exit;
  p := p + Length(key);
  q := p;
  while (q <= Length(ADict)) and CharInSet(ADict[q], ['0'..'9']) do Inc(q);
  if q > p then
    Result := StrToInt(Copy(ADict, p, q - p));
end;

function ExtractPdfStreams(const ABytes: TBytes): TArray<TPdfTestStream>;
var
  s: string;
  list: TList<TPdfTestStream>;
  objPos, streamPos, dataStart, len, numStart, lineStart: Integer;
  item: TPdfTestStream;
begin
  s := PdfBytesToString(ABytes);
  list := TList<TPdfTestStream>.Create;
  try
    objPos := PosEx(' 0 obj', s, 1);
    while objPos > 0 do
    begin
      lineStart := objPos;
      while (lineStart > 1) and (s[lineStart - 1] <> #10) do Dec(lineStart);
      numStart := lineStart;
      item.ObjectNumber := StrToIntDef(Copy(s, numStart, objPos - numStart), -1);

      streamPos := PosEx('stream'#10, s, objPos);
      if (streamPos > 0) and ((PosEx('endobj', s, objPos) > streamPos) or (PosEx('endobj', s, objPos) = 0)) then
      begin
        item.Dict := Copy(s, objPos + 6, streamPos - objPos - 6);
        len := DictInt(item.Dict, 'Length');
        dataStart := streamPos + Length('stream'#10);
        item.Raw := Copy(ABytes, dataStart - 1, len);
        if Pos('/FlateDecode', item.Dict) > 0 then
          item.Data := InflateBytes(item.Raw)
        else
          item.Data := item.Raw;
        list.Add(item);
        objPos := PosEx(' 0 obj', s, dataStart + len);
      end
      else
        objPos := PosEx(' 0 obj', s, objPos + 6);
    end;
    Result := list.ToArray;
  finally
    list.Free;
  end;
end;

end.
