program Simple_Demo;

uses
  Vcl.Forms,
  uMainForm in 'uMainForm.pas' {MainForm},
  smPDF in '..\..\Source\smPDF.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
