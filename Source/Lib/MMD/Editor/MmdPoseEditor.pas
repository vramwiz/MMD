unit MmdPoseEditor;

// モデル標準姿勢とポーズオブジェクトの姿勢を、共通の骨格GUIで編集する。

interface

// PMXと現在の姿勢JSONを読み込み、OK時だけ更新後のJSONを返す。
function EditPose(const ModelFileName, CurrentPoseData, EditorCaption: string;
  out NewPoseData: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Math,
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls,
  MmdPoseEditOperations,
  MmdPoseEditorLayout,
  MmdPoseHistory,
  MmdPoseImageAutoFit,
  MmdPoseImageClipboard,
  MmdPoseSymmetry,
  PmxModel,
  PmxMorph,
  PmxPose,
  PmxPoseCodec,
  PmxReader;

type
  TStandardPoseEditorForm = class(TMmdPoseEditorFormBase)
  private
    FHistory: TMmdPoseHistory;
    FModel: TPmxModel;
    FPoses: TPmxBonePoses;
    procedure ApplyClick(Sender: TObject);
    procedure AutoFitClick(Sender: TObject);
    procedure BoneChanged(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
    procedure ResetBranchClick(Sender: TObject);
    procedure ResetBoneClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure SymmetryChanged(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure ViewportBoneSelected(Sender: TObject);
    procedure ViewportPoseChanged(Sender: TObject);
    procedure ViewportPoseEditFinished(Sender: TObject);
    procedure ViewportPoseEditStarted(Sender: TObject);
    procedure LoadSelectedBone;
    procedure MorphWeightsChanged(Sender: TObject);
    procedure SaveSelectedBone;
    procedure UpdateHistoryButtons;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateEditor(const ModelFileName, PoseData,
      EditorCaption: string);
    destructor Destroy; override;
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
var
  BoneIndex: Integer;
  NamedPoses: TPmxNamedBonePoses;
begin
  inherited CreateLayout(EditorCaption);
  FHistory := TMmdPoseHistory.Create;

  FModel := GetCachedPmxModel(ModelFileName);
  InitializeBonePoses(FModel, FPoses);
  if TryDecodePoseData(PoseData, NamedPoses) then
    ApplyNamedBonePoses(FModel, NamedPoses, FPoses);

  FBoneList.OnClick := BoneChanged;
  for BoneIndex := 0 to High(FModel.Bones) do
    FBoneList.Items.Add(FModel.Bones[BoneIndex].Name);
  FMorphPreview.SetModel(FModel);
  FMorphPreview.OnWeightsChanged := MorphWeightsChanged;

  FApplyButton.OnClick := ApplyClick;
  FAutoFitButton.OnClick := AutoFitClick;
  FResetBoneButton.OnClick := ResetBoneClick;
  FResetBranchButton.OnClick := ResetBranchClick;
  FResetAllButton.OnClick := ResetAllClick;
  FSymmetryCheck.OnClick := SymmetryChanged;
  FUndoButton.OnClick := UndoClick;
  FRedoButton.OnClick := RedoClick;
  FViewport.OnBoneSelected := ViewportBoneSelected;
  FViewport.OnPoseChanged := ViewportPoseChanged;
  FViewport.OnPoseEditFinished := ViewportPoseEditFinished;
  FViewport.OnPoseEditStarted := ViewportPoseEditStarted;

  if FBoneList.Count > 0 then
  begin
    FBoneList.ItemIndex := 0;
    LoadSelectedBone;
    FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  end;
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.AutoFitClick(Sender: TObject);
var
  BeforePoses: TPmxBonePoses;
begin
  if not FViewport.HasReferenceImage then
    Exit;
  BeforePoses := Copy(FPoses);
  FAutoFitButton.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    if AutoFitPoseToReference(FModel, FViewport, FBoneList.ItemIndex,
      FPoses) then
    begin
      FHistory.RecordBeforeEdit(BeforePoses);
      LoadSelectedBone;
      UpdateHistoryButtons;
    end
    else
      MessageDlg('参照画像との差を改善できませんでした。'#13#10 +
        '現在姿勢が近い場合、または画像差が大きい場合は手動で調整してください。',
        mtInformation, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
    FAutoFitButton.Enabled := FViewport.HasReferenceImage;
  end;
end;

procedure TStandardPoseEditorForm.MorphWeightsChanged(Sender: TObject);
var
  Weights: TPmxMorphWeights;
begin
  FMorphPreview.CopyWeights(Weights);
  FViewport.SetMorphWeights(Weights);
end;

destructor TStandardPoseEditorForm.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

procedure TStandardPoseEditorForm.SymmetryChanged(Sender: TObject);
begin
  FViewport.SymmetricEditing := FSymmetryCheck.Checked;
end;

procedure TStandardPoseEditorForm.UpdateHistoryButtons;
begin
  FUndoButton.Enabled := FHistory.CanUndo;
  FRedoButton.Enabled := FHistory.CanRedo;
end;

procedure TStandardPoseEditorForm.ViewportPoseEditStarted(Sender: TObject);
begin
  FHistory.RecordBeforeEdit(FPoses);
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.ViewportPoseEditFinished(Sender: TObject);
begin
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.UndoClick(Sender: TObject);
var
  Restored: TPmxBonePoses;
begin
  if not FHistory.Undo(FPoses, Restored) then
    Exit;
  FPoses := Restored;
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.RedoClick(Sender: TObject);
var
  Restored: TPmxBonePoses;
begin
  if not FHistory.Redo(FPoses, Restored) then
    Exit;
  FPoses := Restored;
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.KeyDown(var Key: Word; Shift: TShiftState);
var
  Bitmap: TBitmap;
begin
  if ssCtrl in Shift then
    case Key of
      Ord('Z'):
        begin
          UndoClick(Self);
          Key := 0;
          Exit;
        end;
      Ord('Y'):
        begin
          RedoClick(Self);
          Key := 0;
          Exit;
        end;
      Ord('C'):
        if not (ActiveControl is TCustomEdit) then
        begin
          if not CopyModelImageToClipboard(FViewport) then
            MessageDlg('モデル画像をクリップボードへコピーできませんでした。',
              mtError, [mbOK], 0);
          Key := 0;
          Exit;
        end;
      Ord('V'):
        if not (ActiveControl is TCustomEdit) then
        begin
          Bitmap := TBitmap.Create;
          try
            if PasteImageFromClipboard(Bitmap) then
            begin
              FViewport.SetReferenceImage(Bitmap);
              FAutoFitButton.Enabled := True;
            end
            else
              MessageDlg('クリップボードに貼り付け可能な画像がありません。',
                mtInformation, [mbOK], 0);
          finally
            Bitmap.Free;
          end;
          Key := 0;
          Exit;
        end;
    end;
  inherited KeyDown(Key, Shift);
end;

procedure TStandardPoseEditorForm.ViewportBoneSelected(Sender: TObject);
begin
  FBoneList.ItemIndex := FViewport.SelectedBone;
  FBoneList.TopIndex := Max(FBoneList.ItemIndex - 5, 0);
  LoadSelectedBone;
end;

procedure TStandardPoseEditorForm.ViewportPoseChanged(Sender: TObject);
begin
  FViewport.CopyPoses(FPoses);
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
var
  BeforePoses: TPmxBonePoses;
  MirrorIndex: Integer;
begin
  try
    BeforePoses := Copy(FPoses);
    SaveSelectedBone;
    if FSymmetryCheck.Checked then
    begin
      MirrorIndex := FindSymmetricBone(FModel, FBoneList.ItemIndex);
      if MirrorIndex >= 0 then
        FPoses[MirrorIndex] := MirrorBonePose(FPoses[FBoneList.ItemIndex]);
    end;
    FHistory.RecordBeforeEdit(BeforePoses);
    FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
    UpdateHistoryButtons;
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
var
  BeforePoses: TPmxBonePoses;
  MirrorIndex: Integer;
begin
  if FBoneList.ItemIndex < 0 then
    Exit;
  BeforePoses := Copy(FPoses);
  FPoses[FBoneList.ItemIndex] := Default(TPmxBonePose);
  FPoses[FBoneList.ItemIndex].Rotation := IdentityQuaternion;
  if FSymmetryCheck.Checked then
  begin
    MirrorIndex := FindSymmetricBone(FModel, FBoneList.ItemIndex);
    if MirrorIndex >= 0 then
      FPoses[MirrorIndex] := MirrorBonePose(FPoses[FBoneList.ItemIndex]);
  end;
  FHistory.RecordBeforeEdit(BeforePoses);
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.ResetBranchClick(Sender: TObject);
var
  BeforePoses: TPmxBonePoses;
  MirrorIndex: Integer;
begin
  if FBoneList.ItemIndex < 0 then
    Exit;
  BeforePoses := Copy(FPoses);
  ResetBoneBranch(FModel, FBoneList.ItemIndex, FPoses);
  if FSymmetryCheck.Checked then
  begin
    MirrorIndex := FindSymmetricBone(FModel, FBoneList.ItemIndex);
    if MirrorIndex >= 0 then
      ResetBoneBranch(FModel, MirrorIndex, FPoses);
  end;
  FHistory.RecordBeforeEdit(BeforePoses);
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  UpdateHistoryButtons;
end;

procedure TStandardPoseEditorForm.ResetAllClick(Sender: TObject);
var
  BeforePoses: TPmxBonePoses;
begin
  BeforePoses := Copy(FPoses);
  InitializeBonePoses(FModel, FPoses);
  FHistory.RecordBeforeEdit(BeforePoses);
  LoadSelectedBone;
  FViewport.SetScene(FModel, FPoses, FBoneList.ItemIndex);
  UpdateHistoryButtons;
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
