unit MmdPoseSymmetry;

// 左右ボーン名の対応解決と、モデルX=0面を基準としたローカル姿勢の反転を行う。

interface

uses
  PmxModel,
  PmxPoseTypes;

// ボーン名中の「左」「右」を入れ替え、同名の反対側ボーン番号を返す。
function FindSymmetricBone(Model: TPmxModel; BoneIndex: Integer): Integer;
// X座標を反転し、回転軸をX鏡映した反対側用ローカル姿勢を返す。
function MirrorBonePose(const Pose: TPmxBonePose): TPmxBonePose;

implementation

uses
  System.SysUtils;

function SwappedBoneName(const Name: string): string;
var
  MarkerPosition: Integer;
begin
  MarkerPosition := Pos('左', Name);
  if MarkerPosition > 0 then
    Exit(Copy(Name, 1, MarkerPosition - 1) + '右' +
      Copy(Name, MarkerPosition + 1, MaxInt));
  MarkerPosition := Pos('右', Name);
  if MarkerPosition > 0 then
    Exit(Copy(Name, 1, MarkerPosition - 1) + '左' +
      Copy(Name, MarkerPosition + 1, MaxInt));
  Result := '';
end;

function FindSymmetricBone(Model: TPmxModel; BoneIndex: Integer): Integer;
var
  CandidateName: string;
  Index: Integer;
begin
  Result := -1;
  if (Model = nil) or (BoneIndex < 0) or (BoneIndex > High(Model.Bones)) then
    Exit;
  CandidateName := SwappedBoneName(Model.Bones[BoneIndex].Name);
  if CandidateName = '' then
    Exit;
  for Index := 0 to High(Model.Bones) do
    if SameText(Model.Bones[Index].Name, CandidateName) then
      Exit(Index);
end;

function MirrorBonePose(const Pose: TPmxBonePose): TPmxBonePose;
begin
  Result := Pose;
  Result.Translation.X := -Result.Translation.X;
  Result.Rotation.Y := -Result.Rotation.Y;
  Result.Rotation.Z := -Result.Rotation.Z;
end;

end.
