unit uMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    btnExport: TButton;
    procedure btnExportClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

uses
  smPDF;

{$R *.dfm}

procedure TMainForm.btnExportClick(Sender: TObject);
var
  PDF:   TsmPDF;
  xRect: TRect;
begin

  //-- Create the object
  PDF := TsmPDF.Create;

  //-- Start a new page on pale-ivory paper to demonstrate APaperColor.
  PDF.NewPage(TPDFPaperSize.psLetter, TPDFOrientation.poPortrait, 300, $00E0F8FF);

  //-- Write a Title
  xRect := Rect(0, 0, PDF.Width, PDF.Height div 10);
  PDF.DrawText('Main Title', xRect, TAlignment.taCenter);

  //-- More Complex Text
  PDF.Font.StrokeStyle := ssMedium;
  PDF.Font.StrokeColor := clBlack;
  PDF.Font.Color := clRed;
  PDF.Font.Size := 24;

  PDF.Brush.Color := clLtGray;
  PDF.Pen.Style := penDot;
  PDF.Pen.Color := clDkGray;

  PDF.DrawText('Cool PDF Writer!', PDF.Width div 4, PDF.Height div 3);

  //-- Save next to the EXE so output lands in _out regardless of working dir.
  PDF.Save(ExtractFilePath(ParamStr(0)) + 'Simple.pdf');

  //-- Recover memory
  FreeAndNil(PDF);

end;

end.
