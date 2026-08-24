unit MmdPoseEditorLayout;

// ポーズ編集フォームの静的なVCLコントロール構成と配置だけを生成する。

interface

uses
  System.UITypes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  MmdD3DViewport,
  MmdMorphPreviewPanel;

type
  TMmdPoseEditControls = array[0..5] of TEdit;

  TMmdPoseEditorFormBase = class(TForm)
  protected
    FApplyButton: TButton;
    FBoneList: TListBox;
    FEdits: TMmdPoseEditControls;
    FMorphPreview: TMmdMorphPreviewPanel;
    FRedoButton: TButton;
    FResetAllButton: TButton;
    FResetBoneButton: TButton;
    FResetBranchButton: TButton;
    FSymmetryCheck: TCheckBox;
    FUndoButton: TButton;
    FViewport: TMmdD3DViewport;
  public
    // モデル非依存の編集欄、操作ボタン、D3D表示領域を配置する。
    constructor CreateLayout(const EditorCaption: string);
  end;

implementation

uses
  Vcl.ExtCtrls;

constructor TMmdPoseEditorFormBase.CreateLayout(const EditorCaption: string);
const
  FIELD_NAMES: array[0..5] of string =
    ('移動 X', '移動 Y', '移動 Z', '回転 X°', '回転 Y°', '回転 Z°');
var
  ButtonPanel, EditorPanel, LeftPanel: TPanel;
  CancelButton, OkButton: TButton;
  Label_: TLabel;
  Row: Integer;
begin
  inherited CreateNew(nil);
  Caption := EditorCaption;
  Position := poScreenCenter;
  Width := 980;
  Height := 680;
  Constraints.MinWidth := 800;
  Constraints.MinHeight := 630;
  BorderStyle := bsSizeable;
  KeyPreview := True;

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 245;
  LeftPanel.BevelOuter := bvNone;

  FMorphPreview := TMmdMorphPreviewPanel.Create(Self);
  FMorphPreview.Parent := LeftPanel;
  FMorphPreview.Align := alBottom;

  FBoneList := TListBox.Create(Self);
  FBoneList.Parent := LeftPanel;
  FBoneList.Align := alClient;

  EditorPanel := TPanel.Create(Self);
  EditorPanel.Parent := Self;
  EditorPanel.Align := alRight;
  EditorPanel.Width := 235;
  EditorPanel.BevelOuter := bvNone;
  for Row := 0 to 5 do
  begin
    Label_ := TLabel.Create(Self);
    Label_.Parent := EditorPanel;
    Label_.Caption := FIELD_NAMES[Row];
    Label_.Left := 16;
    Label_.Top := 20 + Row * 48;
    FEdits[Row] := TEdit.Create(Self);
    FEdits[Row].Parent := EditorPanel;
    FEdits[Row].SetBounds(95, 16 + Row * 48, 120, 24);
  end;

  FSymmetryCheck := TCheckBox.Create(Self);
  FSymmetryCheck.Parent := EditorPanel;
  FSymmetryCheck.Caption := '左右対称編集';
  FSymmetryCheck.SetBounds(16, 286, 199, 24);
  FApplyButton := TButton.Create(Self);
  FApplyButton.Parent := EditorPanel;
  FApplyButton.Caption := '選択ボーンへ適用';
  FApplyButton.SetBounds(16, 316, 199, 32);
  FResetBoneButton := TButton.Create(Self);
  FResetBoneButton.Parent := EditorPanel;
  FResetBoneButton.Caption := '選択ボーンを初期化';
  FResetBoneButton.SetBounds(16, 356, 199, 32);
  FResetBranchButton := TButton.Create(Self);
  FResetBranchButton.Parent := EditorPanel;
  FResetBranchButton.Caption := '選択ボーンから先を初期化';
  FResetBranchButton.SetBounds(16, 396, 199, 32);
  FResetAllButton := TButton.Create(Self);
  FResetAllButton.Parent := EditorPanel;
  FResetAllButton.Caption := '全ボーンを初期化';
  FResetAllButton.SetBounds(16, 436, 199, 32);
  FUndoButton := TButton.Create(Self);
  FUndoButton.Parent := EditorPanel;
  FUndoButton.Caption := '元に戻す';
  FUndoButton.SetBounds(16, 476, 95, 32);
  FRedoButton := TButton.Create(Self);
  FRedoButton.Parent := EditorPanel;
  FRedoButton.Caption := 'やり直す';
  FRedoButton.SetBounds(120, 476, 95, 32);

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := EditorPanel;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 55;
  ButtonPanel.BevelOuter := bvNone;
  OkButton := TButton.Create(Self);
  OkButton.Parent := ButtonPanel;
  OkButton.Caption := 'OK';
  OkButton.ModalResult := mrOk;
  OkButton.Default := True;
  OkButton.SetBounds(16, 10, 95, 32);
  CancelButton := TButton.Create(Self);
  CancelButton.Parent := ButtonPanel;
  CancelButton.Caption := 'キャンセル';
  CancelButton.ModalResult := mrCancel;
  CancelButton.Cancel := True;
  CancelButton.SetBounds(120, 10, 95, 32);

  FViewport := TMmdD3DViewport.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := alClient;
end;

end.
