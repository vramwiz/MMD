unit MmdPoseEditor;

// モデル標準姿勢とポーズオブジェクトの姿勢を、共通の骨格GUIで編集する。

interface

// PMXと現在の姿勢JSONを読み込み、OK時だけ更新後のJSONを返す。
function EditPose(const ModelFileName, CurrentPoseData, EditorCaption: string;
  out NewPoseData: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.SysUtils,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  MmdD3DViewport,
  PmxModel,
  PmxPose,
  PmxPoseCodec,
  PmxReader;

type
  TStandardPoseEditorForm = class(TForm)
  private
    FBoneList: TListBox;
    FEdits: array[0..5] of TEdit;
    FModel: TPmxModel;
    FViewport: TMmdD3DViewport;
    FPoses: TPmxBonePoses;
    procedure ApplyClick(Sender: TObject);
    procedure BoneChanged(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
    procedure ResetBoneClick(Sender: TObject);
    procedure LoadSelectedBone;
    procedure SaveSelectedBone;
  public
    constructor CreateEditor(const ModelFileName, PoseData,
      EditorCaption: string);
    function EncodeCurrentPose: string;
  end;

function QuaternionToEulerXYZ(const Q: TPmxQuaternion): TPmxVector3;
var
  SinPitch: Double;
begin
  Result.X := ArcTan2(2 * (Q.W * Q.X + Q.Y * Q.Z),
    1 - 2 * (Q.X * Q.X + Q.Y * Q.Y));
  SinPitch := 2 * (Q.W * Q.Y - Q.Z * Q.X);
  if Abs(SinPitch) >= 1 then
    Result.Y := Sign(SinPitch) * Pi / 2
  else
    Result.Y := ArcSin(SinPitch);
  Result.Z := ArcTan2(2 * (Q.W * Q.Z + Q.X * Q.Y),
    1 - 2 * (Q.Y * Q.Y + Q.Z * Q.Z));
end;

function IsIdentity(const Pose: TPmxBonePose): Boolean;
begin
  Result := (Abs(Pose.Translation.X) < 0.000001) and
    (Abs(Pose.Translation.Y) < 0.000001) and
    (Abs(Pose.Translation.Z) < 0.000001) and
    (Abs(Pose.Rotation.X) < 0.000001) and
    (Abs(Pose.Rotation.Y) < 0.000001) and
    (Abs(Pose.Rotation.Z) < 0.000001) and
    (Abs(Abs(Pose.Rotation.W) - 1.0) < 0.000001);
end;

constructor TStandardPoseEditorForm.CreateEditor(const ModelFileName,
  PoseData, EditorCaption: string);
const
  FIELD_NAMES: array[0..5] of string =
    ('移動 X', '移動 Y', '移動 Z', '回転 X°', '回転 Y°', '回転 Z°');
var
  ApplyButton: TButton;
  BoneIndex: Integer;
  ButtonPanel: TPanel;
  CancelButton: TButton;
  EditorPanel: TPanel;
  Label_: TLabel;
  NamedPoses: TPmxNamedBonePoses;
  OkButton: TButton;
  ResetAllButton: TButton;
  ResetBoneButton: TButton;
  Row: Integer;
begin
  inherited CreateNew(nil);
  Caption := EditorCaption;
  Position := poScreenCenter;
  Width := 980;
  Height := 680;
  Constraints.MinWidth := 800;
  Constraints.MinHeight := 520;
  BorderStyle := bsSizeable;

  FModel := GetCachedPmxModel(ModelFileName);
  InitializeBonePoses(FModel, FPoses);
  if TryDecodePoseData(PoseData, NamedPoses) then
    ApplyNamedBonePoses(FModel, NamedPoses, FPoses);

  FBoneList := TListBox.Create(Self);
  FBoneList.Parent := Self;
  FBoneList.Align := alLeft;
  FBoneList.Width := 245;
  FBoneList.OnClick := BoneChanged;
  for BoneIndex := 0 to High(FModel.Bones) do
    FBoneList.Items.Add(FModel.Bones[BoneIndex].Name);

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
    FEdits[Row].Left := 95;
    FEdits[Row].Top := 16 + Row * 48;
    FEdits[Row].Width := 120;
  end;

  ApplyButton := TButton.Create(Self);
  ApplyButton.Parent := EditorPanel;
  ApplyButton.Caption := '選択ボーンへ適用';
  ApplyButton.SetBounds(16, 316, 199, 32);
  ApplyButton.OnClick := ApplyClick;
  ResetBoneButton := TButton.Create(Self);
  ResetBoneButton.Parent := EditorPanel;
  ResetBoneButton.Caption := '選択ボーンを初期化';
  ResetBoneButton.SetBounds(16, 356, 199, 32);
  ResetBoneButton.OnClick := ResetBoneClick;
  ResetAllButton := TButton.Create(Self);
  ResetAllButton.Parent := EditorPanel;
  ResetAllButton.Caption := '全ボーンを初期化';
  ResetAllButton.SetBounds(16, 396, 199, 32);
  ResetAllButton.OnClick := ResetAllClick;

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

  if FBoneList.Count > 0 then
  begin
    FBoneList.ItemIndex := 0;
    LoadSelectedBone;
    FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  end;
end;

procedure TStandardPoseEditorForm.LoadSelectedBone;
var
  Euler: TPmxVector3;
  Pose: TPmxBonePose;
begin
  if FBoneList.ItemIndex < 0 then
    Exit;
  Pose := FPoses[FBoneList.ItemIndex];
  Euler := QuaternionToEulerXYZ(Pose.Rotation);
  FEdits[0].Text := FloatToStr(Pose.Translation.X);
  FEdits[1].Text := FloatToStr(Pose.Translation.Y);
  FEdits[2].Text := FloatToStr(Pose.Translation.Z);
  FEdits[3].Text := FloatToStr(RadToDeg(Euler.X));
  FEdits[4].Text := FloatToStr(RadToDeg(Euler.Y));
  FEdits[5].Text := FloatToStr(RadToDeg(Euler.Z));
end;

procedure TStandardPoseEditorForm.SaveSelectedBone;
var
  Values: array[0..5] of Double;
  Index: Integer;
begin
  if FBoneList.ItemIndex < 0 then
    Exit;
  for Index := 0 to 5 do
    if not TryStrToFloat(FEdits[Index].Text, Values[Index]) then
      raise EConvertError.CreateFmt('%s は数値ではありません', [FEdits[Index].Text]);
  with FPoses[FBoneList.ItemIndex] do
  begin
    Translation.X := Values[0];
    Translation.Y := Values[1];
    Translation.Z := Values[2];
    Rotation := QuaternionFromEulerXYZ(DegToRad(Values[3]),
      DegToRad(Values[4]), DegToRad(Values[5]));
  end;
end;

procedure TStandardPoseEditorForm.ApplyClick(Sender: TObject);
begin
  try
    SaveSelectedBone;
    FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  except
    on E: Exception do
      Application.MessageBox(PChar(E.Message), '入力エラー', MB_OK or MB_ICONWARNING);
  end;
end;

procedure TStandardPoseEditorForm.BoneChanged(Sender: TObject);
begin
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
end;

procedure TStandardPoseEditorForm.ResetBoneClick(Sender: TObject);
begin
  if FBoneList.ItemIndex < 0 then
    Exit;
  FPoses[FBoneList.ItemIndex] := Default(TPmxBonePose);
  FPoses[FBoneList.ItemIndex].Rotation := IdentityQuaternion;
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
end;

procedure TStandardPoseEditorForm.ResetAllClick(Sender: TObject);
begin
  InitializeBonePoses(FModel, FPoses);
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
end;

function TStandardPoseEditorForm.EncodeCurrentPose: string;
var
  BoneIndex: Integer;
  Count: Integer;
  NamedPoses: TPmxNamedBonePoses;
begin
  Count := 0;
  SetLength(NamedPoses, Length(FPoses));
  for BoneIndex := 0 to High(FPoses) do
    if not IsIdentity(FPoses[BoneIndex]) then
    begin
      NamedPoses[Count].BoneName := FModel.Bones[BoneIndex].Name;
      NamedPoses[Count].Pose := FPoses[BoneIndex];
      Inc(Count);
    end;
  SetLength(NamedPoses, Count);
  Result := EncodePoseData(NamedPoses);
end;

function EditPose(const ModelFileName, CurrentPoseData, EditorCaption: string;
  out NewPoseData: string): Boolean;
var
  Form: TStandardPoseEditorForm;
begin
  Result := False;
  NewPoseData := CurrentPoseData;
  Form := TStandardPoseEditorForm.CreateEditor(ModelFileName, CurrentPoseData,
    EditorCaption);
  try
    if Form.ShowModal <> mrOk then
      Exit;
    NewPoseData := Form.EncodeCurrentPose;
    Result := True;
  finally
    Form.Free;
  end;
end;

end.
