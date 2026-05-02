object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object btnExport: TButton
    Left = 256
    Top = 168
    Width = 75
    Height = 25
    Caption = 'Export'
    TabOrder = 0
    OnClick = btnExportClick
  end
end
