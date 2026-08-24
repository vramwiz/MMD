unit MmdPoseEditOperations;

// ポーズ編集GUIの選択ボーンと階層に対する一括編集操作を提供する。

interface

uses
  PmxModel,
  PmxPoseTypes;

// 開始ボーン自身と、その子孫に該当する姿勢だけを初期化し、処理数を返す。
function ResetBoneBranch(Model: TPmxModel; StartBone: Integer;
  var Poses: TPmxBonePoses): Integer;

implementation

function IsInBoneBranch(Model: TPmxModel; BoneIndex,
  StartBone: Integer): Boolean;
var
  Guard, ParentIndex: Integer;
begin
  Result := False;
  ParentIndex := BoneIndex;
  Guard := 0;
  while (ParentIndex >= 0) and (ParentIndex <= High(Model.Bones)) and
    (Guard <= Length(Model.Bones)) do
  begin
    if ParentIndex = StartBone then
      Exit(True);
    ParentIndex := Model.Bones[ParentIndex].ParentIndex;
    Inc(Guard);
  end;
end;

function ResetBoneBranch(Model: TPmxModel; StartBone: Integer;
  var Poses: TPmxBonePoses): Integer;
var
  BoneIndex, LastIndex: Integer;
begin
  Result := 0;
  if (Model = nil) or (StartBone < 0) or
    (StartBone > High(Model.Bones)) then
    Exit;
  LastIndex := High(Poses);
  if LastIndex > High(Model.Bones) then
    LastIndex := High(Model.Bones);
  for BoneIndex := 0 to LastIndex do
    if IsInBoneBranch(Model, BoneIndex, StartBone) then
    begin
      Poses[BoneIndex] := Default(TPmxBonePose);
      Poses[BoneIndex].Rotation.W := 1.0;
      Inc(Result);
    end;
end;

end.
