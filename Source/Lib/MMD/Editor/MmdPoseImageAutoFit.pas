unit MmdPoseImageAutoFit;

// 同一カメラの参照画像とモデルのみの描画差を使い、主要ボーンを粗く合わせる。

interface

uses
  Vcl.Graphics,
  PmxModel,
  PmxPose,
  MmdD3DViewport;

// 上半身と四肢の限定軸を段階探索する。改善時だけTrueを返す。
function AutoFitPoseToReference(Model: TPmxModel;
  Viewport: TMmdD3DViewport; SelectedBone: Integer;
  var Poses: TPmxBonePoses): Boolean;
function AutoFitPoseToReferenceScores(Model: TPmxModel;
  Viewport: TMmdD3DViewport; SelectedBone: Integer;
  var Poses: TPmxBonePoses; out InitialScore, FinalScore: UInt64): Boolean;
// テストと将来の進捗表示で共有する低密度画像差スコア。
function PoseImageDifference(Current, Reference: Vcl.Graphics.TBitmap): UInt64;

implementation

uses
  System.Math,
  System.SysUtils,
  PmxPoseMath;

const
  BONE_HEAD: string = #$982D;
  BONE_LEFT_ARM: string = #$5DE6#$8155;
  BONE_LEFT_ELBOW: string = #$5DE6#$3072#$3058;
  BONE_LEFT_KNEE: string = #$5DE6#$3072#$3056;
  BONE_LEFT_LEG: string = #$5DE6#$8DB3;
  BONE_LEFT_SHOULDER: string = #$5DE6#$80A9;
  BONE_NECK: string = #$9996;
  BONE_RIGHT_ARM: string = #$53F3#$8155;
  BONE_RIGHT_ELBOW: string = #$53F3#$3072#$3058;
  BONE_RIGHT_KNEE: string = #$53F3#$3072#$3056;
  BONE_RIGHT_LEG: string = #$53F3#$8DB3;
  BONE_RIGHT_SHOULDER: string = #$53F3#$80A9;
  BONE_UPPER_BODY: string = #$4E0A#$534A#$8EAB;
  BONE_UPPER_BODY2: string = #$4E0A#$534A#$8EAB'2';

type
  TMmdFitAxis = (faX, faY, faZ);
  TMmdFitParameter = record
    BoneIndex: Integer;
    Axis: TMmdFitAxis;
  end;
  TMmdFitParameters = array of TMmdFitParameter;

function FindBone(Model: TPmxModel; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Model.Bones) do
    if SameText(Model.Bones[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

procedure AddParameter(Model: TPmxModel; Viewport: TMmdD3DViewport;
  const BoneName: string; Axis: TMmdFitAxis; var Parameters: TMmdFitParameters);
var
  BoneIndex, Count: Integer;
begin
  BoneIndex := FindBone(Model, BoneName);
  if (BoneIndex < 0) or Viewport.IsBoneLocked(BoneIndex) then
    Exit;
  Count := Length(Parameters);
  SetLength(Parameters, Count + 1);
  Parameters[Count].BoneIndex := BoneIndex;
  Parameters[Count].Axis := Axis;
end;

procedure AddXYZ(Model: TPmxModel; Viewport: TMmdD3DViewport;
  const BoneName: string; var Parameters: TMmdFitParameters);
begin
  AddParameter(Model, Viewport, BoneName, faX, Parameters);
  AddParameter(Model, Viewport, BoneName, faY, Parameters);
  AddParameter(Model, Viewport, BoneName, faZ, Parameters);
end;

procedure BuildParameters(Model: TPmxModel; Viewport: TMmdD3DViewport;
  out Parameters: TMmdFitParameters);
begin
  Parameters := nil;
  AddXYZ(Model, Viewport, BONE_UPPER_BODY, Parameters);
  AddXYZ(Model, Viewport, BONE_UPPER_BODY2, Parameters);
  AddXYZ(Model, Viewport, BONE_LEFT_LEG, Parameters);
  AddXYZ(Model, Viewport, BONE_RIGHT_LEG, Parameters);
  AddParameter(Model, Viewport, BONE_LEFT_KNEE, faX, Parameters);
  AddParameter(Model, Viewport, BONE_RIGHT_KNEE, faX, Parameters);
  AddParameter(Model, Viewport, BONE_LEFT_SHOULDER, faZ, Parameters);
  AddParameter(Model, Viewport, BONE_RIGHT_SHOULDER, faZ, Parameters);
  AddXYZ(Model, Viewport, BONE_LEFT_ARM, Parameters);
  AddXYZ(Model, Viewport, BONE_RIGHT_ARM, Parameters);
  AddParameter(Model, Viewport, BONE_LEFT_ELBOW, faX, Parameters);
  AddParameter(Model, Viewport, BONE_LEFT_ELBOW, faZ, Parameters);
  AddParameter(Model, Viewport, BONE_RIGHT_ELBOW, faX, Parameters);
  AddParameter(Model, Viewport, BONE_RIGHT_ELBOW, faZ, Parameters);
  AddXYZ(Model, Viewport, BONE_NECK, Parameters);
  AddXYZ(Model, Viewport, BONE_HEAD, Parameters);
end;

function IsForeground(Pixel: PByte): Boolean;
begin
  Result := (Abs(Integer(Pixel[0]) - 19) +
    Abs(Integer(Pixel[1]) - 15) + Abs(Integer(Pixel[2]) - 14)) > 36;
end;

function PoseImageDifference(Current, Reference: Vcl.Graphics.TBitmap): UInt64;
var
  CurrentForeground, ReferenceForeground: Boolean;
  CurrentPixel, ReferencePixel: PByte;
  SampleStep, X, Y: Integer;
begin
  Result := 0;
  SampleStep := Max(2, Min(Current.Width, Current.Height) div 180);
  Y := 0;
  while Y < Current.Height do
  begin
    CurrentPixel := Current.ScanLine[Y];
    ReferencePixel := Reference.ScanLine[Y];
    X := 0;
    while X < Current.Width do
    begin
      CurrentForeground := IsForeground(CurrentPixel + X * 4);
      ReferenceForeground := IsForeground(ReferencePixel + X * 4);
      if CurrentForeground <> ReferenceForeground then
        Inc(Result, 1024)
      else if CurrentForeground then
      begin
        Inc(Result, Abs(Integer(CurrentPixel[X * 4]) -
          Integer(ReferencePixel[X * 4])));
        Inc(Result, Abs(Integer(CurrentPixel[X * 4 + 1]) -
          Integer(ReferencePixel[X * 4 + 1])));
        Inc(Result, Abs(Integer(CurrentPixel[X * 4 + 2]) -
          Integer(ReferencePixel[X * 4 + 2])));
      end;
      Inc(X, SampleStep);
    end;
    Inc(Y, SampleStep);
  end;
end;

function ScorePose(Model: TPmxModel; Viewport: TMmdD3DViewport;
  SelectedBone: Integer; const Poses: TPmxBonePoses; Reference,
  Current: TBitmap): UInt64;
begin
  Viewport.SetScene(Model, Poses, SelectedBone);
  if not Viewport.CaptureModelImage(Current) then
    Exit(High(UInt64));
  Result := PoseImageDifference(Current, Reference);
end;

function ParameterAxis(Axis: TMmdFitAxis): TPmxVector3;
begin
  Result := Default(TPmxVector3);
  case Axis of
    faX: Result.X := 1;
    faY: Result.Y := 1;
    faZ: Result.Z := 1;
  end;
end;

function AutoFitPoseToReferenceScores(Model: TPmxModel;
  Viewport: TMmdD3DViewport; SelectedBone: Integer;
  var Poses: TPmxBonePoses; out InitialScore, FinalScore: UInt64): Boolean;
const
  STEPS_DEGREES: array[0..2] of Single = (30, 15, 7.5);
var
  Axis: TPmxVector3;
  BaseRotation, CandidateRotation, BestRotation: TPmxQuaternion;
  BestScore, CandidateScore: UInt64;
  Current, Reference: TBitmap;
  Direction, ParameterIndex, StepIndex: Integer;
  Parameters: TMmdFitParameters;
begin
  Result := False;
  InitialScore := 0;
  FinalScore := 0;
  if (Model = nil) or (Viewport = nil) or not Viewport.HasReferenceImage then
    Exit;
  BuildParameters(Model, Viewport, Parameters);
  if Length(Parameters) = 0 then
    Exit;
  Current := TBitmap.Create;
  Reference := TBitmap.Create;
  try
    Viewport.CopyReferenceImageForViewport(Reference);
    BestScore := ScorePose(Model, Viewport, SelectedBone, Poses, Reference,
      Current);
    InitialScore := BestScore;
    for StepIndex := Low(STEPS_DEGREES) to High(STEPS_DEGREES) do
      for ParameterIndex := 0 to High(Parameters) do
      begin
        BaseRotation := Poses[Parameters[ParameterIndex].BoneIndex].Rotation;
        BestRotation := BaseRotation;
        Axis := ParameterAxis(Parameters[ParameterIndex].Axis);
        for Direction := -1 to 1 do
          if Direction <> 0 then
          begin
            CandidateRotation := NormalizeQuaternion(MultiplyQuaternion(
              QuaternionFromAxisAngle(Axis,
                DegToRad(STEPS_DEGREES[StepIndex] * Direction)),
              BaseRotation));
            Poses[Parameters[ParameterIndex].BoneIndex].Rotation :=
              CandidateRotation;
            CandidateScore := ScorePose(Model, Viewport, SelectedBone, Poses,
              Reference, Current);
            if CandidateScore < BestScore then
            begin
              BestScore := CandidateScore;
              BestRotation := CandidateRotation;
            end;
          end;
        Poses[Parameters[ParameterIndex].BoneIndex].Rotation := BestRotation;
      end;
    Viewport.SetScene(Model, Poses, SelectedBone);
    Viewport.Update;
    FinalScore := BestScore;
    Result := BestScore < InitialScore;
  finally
    Reference.Free;
    Current.Free;
  end;
end;

function AutoFitPoseToReference(Model: TPmxModel;
  Viewport: TMmdD3DViewport; SelectedBone: Integer;
  var Poses: TPmxBonePoses): Boolean;
var
  FinalScore, InitialScore: UInt64;
begin
  Result := AutoFitPoseToReferenceScores(Model, Viewport, SelectedBone,
    Poses, InitialScore, FinalScore);
end;

end.
