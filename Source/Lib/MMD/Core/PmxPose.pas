unit PmxPose;

// PMX姿勢の公開APIを保ち、最終ボーン計算とCPUスキニングを接続する。

interface

uses
  PmxModel,
  PmxMorph,
  PmxPoseTypes;

type
  TPmxQuaternion = PmxPoseTypes.TPmxQuaternion;
  TPmxBonePose = PmxPoseTypes.TPmxBonePose;
  TPmxBoneTransform = PmxPoseTypes.TPmxBoneTransform;
  TPmxBonePoses = PmxPoseTypes.TPmxBonePoses;
  TPmxBoneTransforms = PmxPoseTypes.TPmxBoneTransforms;

  TPmxSkinnedVertex = record
    Position: TPmxVector3;
    Normal: TPmxVector3;
  end;
  TPmxNamedBonePose = record
    BoneName: string;
    Pose: TPmxBonePose;
  end;
  TPmxNamedBonePoses = array of TPmxNamedBonePose;
  TPmxSkinnedVertices = array of TPmxSkinnedVertex;

// 回転なしを表す単位Quaternionを返す。
function IdentityQuaternion: TPmxQuaternion;
// Quaternionを単位長へ正規化し、長さ0の場合は単位Quaternionを返す。
function NormalizeQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
// 正規化した軸とラジアン角からQuaternionを生成する。
function QuaternionFromAxisAngle(const Axis: TPmxVector3;
  AngleRadians: Single): TPmxQuaternion;
// ローカルX、Y、Zの順に適用するラジアン角からQuaternionを生成する。
function QuaternionFromEulerXYZ(X, Y, Z: Single): TPmxQuaternion;
// PMXのボーン名からボーン番号を検索し、見つからなければ-1を返す。
function FindBoneIndex(const Model: TPmxModel; const BoneName: string): Integer;
// 全ボーンを移動なし、回転なしの初期姿勢へ設定する。
procedure InitializeBonePoses(const Model: TPmxModel; var Poses: TPmxBonePoses);
// 名前付き姿勢を初期化済みのボーン配列へ適用し、有効な変形があればTrueを返す。
function ApplyNamedBonePoses(const Model: TPmxModel;
  const NamedPoses: TPmxNamedBonePoses; var Poses: TPmxBonePoses): Boolean;
// ローカル姿勢へ付与変形とIKを適用し、全ボーンのグローバル姿勢を計算する。
procedure CalculateBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
// BDEF1、BDEF2、BDEF4頂点をCPUで線形スキニングする。
procedure SkinVerticesLinear(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; var Vertices: TPmxSkinnedVertices); overload;
// モーフ適用済み頂点位置を使い、法線とウェイトはModelの頂点属性からスキニングする。
procedure SkinVerticesLinear(const Model: TPmxModel; const Positions: TPmxVertexPositions;
  const Transforms: TPmxBoneTransforms; var Vertices: TPmxSkinnedVertices); overload;

implementation

uses
  System.Math,
  System.SysUtils,
  PmxBoneSolver,
  PmxPoseMath;

function IdentityQuaternion: TPmxQuaternion;
begin
  Result := PmxPoseMath.IdentityQuaternion;
end;

function NormalizeQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
begin
  Result := PmxPoseMath.NormalizeQuaternion(Value);
end;

function QuaternionFromAxisAngle(const Axis: TPmxVector3;
  AngleRadians: Single): TPmxQuaternion;
begin
  Result := PmxPoseMath.QuaternionFromAxisAngle(Axis, AngleRadians);
end;

function QuaternionFromEulerXYZ(X, Y, Z: Single): TPmxQuaternion;
begin
  Result := PmxPoseMath.QuaternionFromEulerXYZ(X, Y, Z);
end;

function IsIdentityPose(const Pose: TPmxBonePose): Boolean;
begin
  Result := (Abs(Pose.Translation.X) <= 0.000001) and
    (Abs(Pose.Translation.Y) <= 0.000001) and
    (Abs(Pose.Translation.Z) <= 0.000001) and
    (Abs(Pose.Rotation.X) <= 0.000001) and
    (Abs(Pose.Rotation.Y) <= 0.000001) and
    (Abs(Pose.Rotation.Z) <= 0.000001) and
    (Abs(Abs(Pose.Rotation.W) - 1.0) <= 0.000001);
end;

function FindBoneIndex(const Model: TPmxModel; const BoneName: string): Integer;
begin
  for Result := 0 to High(Model.Bones) do
    if Model.Bones[Result].Name = BoneName then
      Exit;
  Result := -1;
end;

procedure InitializeBonePoses(const Model: TPmxModel; var Poses: TPmxBonePoses);
var
  BoneIndex: Integer;
begin
  SetLength(Poses, Length(Model.Bones));
  for BoneIndex := 0 to High(Poses) do
  begin
    Poses[BoneIndex] := Default(TPmxBonePose);
    Poses[BoneIndex].Rotation := IdentityQuaternion;
  end;
end;

function ApplyNamedBonePoses(const Model: TPmxModel;
  const NamedPoses: TPmxNamedBonePoses; var Poses: TPmxBonePoses): Boolean;
var
  BoneIndex: Integer;
  NamedPose: TPmxNamedBonePose;
begin
  if Length(Poses) <> Length(Model.Bones) then
    raise EArgumentException.Create(
      'Bone pose count does not match the PMX model');
  Result := False;
  for NamedPose in NamedPoses do
  begin
    BoneIndex := FindBoneIndex(Model, NamedPose.BoneName);
    if BoneIndex < 0 then
      Continue;
    Poses[BoneIndex] := NamedPose.Pose;
    Poses[BoneIndex].Rotation := NormalizeQuaternion(
      Poses[BoneIndex].Rotation);
    Result := Result or not IsIdentityPose(Poses[BoneIndex]);
  end;
end;

procedure CalculateBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
begin
  CalculateFinalBoneTransforms(Model, Poses, Transforms);
end;

function TransformPosition(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; BoneIndex: Integer;
  const Position: TPmxVector3): TPmxVector3;
begin
  Result := AddVector(Transforms[BoneIndex].Position,
    RotateVector(Transforms[BoneIndex].Rotation,
      SubtractVector(Position, Model.Bones[BoneIndex].Position)));
end;

procedure SkinVertexLinear(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const Source: TPmxVertex;
  const SourcePosition: TPmxVector3; var Target: TPmxSkinnedVertex);
var
  BoneIndex, InfluenceCount, InfluenceIndex: Integer;
  TransformedNormal, TransformedPosition: TPmxVector3;
  Weight: Single;
begin
  case Source.DeformType of
    pdtBdef1: InfluenceCount := 1;
    pdtBdef2: InfluenceCount := 2;
    pdtBdef4: InfluenceCount := 4;
  else
    begin
      Target.Position := SourcePosition;
      Target.Normal := Source.Normal;
      Exit;
    end;
  end;
  Target := Default(TPmxSkinnedVertex);
  for InfluenceIndex := 0 to InfluenceCount - 1 do
  begin
    Weight := Source.BoneWeights[InfluenceIndex];
    if Weight <= 0 then
      Continue;
    BoneIndex := Source.BoneIndices[InfluenceIndex];
    TransformedPosition := TransformPosition(Model, Transforms, BoneIndex,
      SourcePosition);
    TransformedNormal := RotateVector(Transforms[BoneIndex].Rotation,
      Source.Normal);
    Target.Position := AddVector(Target.Position,
      ScaleVector(TransformedPosition, Weight));
    Target.Normal := AddVector(Target.Normal,
      ScaleVector(TransformedNormal, Weight));
  end;
  Target.Normal := NormalizeVector(Target.Normal);
end;

procedure SkinVerticesLinear(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; var Vertices: TPmxSkinnedVertices);
var
  VertexIndex: Integer;
begin
  if Length(Transforms) <> Length(Model.Bones) then
    raise EArgumentException.Create(
      'Bone transform count does not match the PMX model');
  SetLength(Vertices, Length(Model.Vertices));
  for VertexIndex := 0 to High(Model.Vertices) do
    SkinVertexLinear(Model, Transforms, Model.Vertices[VertexIndex],
      Model.Vertices[VertexIndex].Position, Vertices[VertexIndex]);
end;

procedure SkinVerticesLinear(const Model: TPmxModel; const Positions: TPmxVertexPositions;
  const Transforms: TPmxBoneTransforms; var Vertices: TPmxSkinnedVertices);
var
  VertexIndex: Integer;
begin
  if Length(Positions) <> Length(Model.Vertices) then
    raise EArgumentException.Create(
      'Morph vertex position count does not match the PMX model');
  if Length(Transforms) <> Length(Model.Bones) then
    raise EArgumentException.Create(
      'Bone transform count does not match the PMX model');
  SetLength(Vertices, Length(Model.Vertices));
  for VertexIndex := 0 to High(Model.Vertices) do
    SkinVertexLinear(Model, Transforms, Model.Vertices[VertexIndex],
      Positions[VertexIndex], Vertices[VertexIndex]);
end;

end.
