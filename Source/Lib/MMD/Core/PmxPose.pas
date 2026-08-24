unit PmxPose;

// PMXのボーン姿勢、親子変換、線形スキニングを描画方式から独立して計算する。

interface

uses
  PmxModel;

type
  TPmxQuaternion = record
    X, Y, Z, W: Single;
  end;

  TPmxBonePose = record
    Translation: TPmxVector3;
    Rotation: TPmxQuaternion;
  end;

  TPmxBoneTransform = record
    Position: TPmxVector3;
    Rotation: TPmxQuaternion;
  end;

  TPmxSkinnedVertex = record
    Position: TPmxVector3;
    Normal: TPmxVector3;
  end;

  TPmxNamedBonePose = record
    BoneName: string;
    Pose: TPmxBonePose;
  end;

  TPmxBonePoses = array of TPmxBonePose;
  TPmxBoneTransforms = array of TPmxBoneTransform;
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
// ローカル姿勢と親子階層から全ボーンのグローバル姿勢を計算する。
procedure CalculateBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
// BDEF1、BDEF2、BDEF4頂点をCPUで線形スキニングする。
procedure SkinVerticesLinear(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; var Vertices: TPmxSkinnedVertices);

implementation

uses
  System.Math,
  System.SysUtils;

type
  TBoneVisitStates = array of Byte;

function AddVector(const A, B: TPmxVector3): TPmxVector3;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
  Result.Z := A.Z + B.Z;
end;

function SubtractVector(const A, B: TPmxVector3): TPmxVector3;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function ScaleVector(const Value: TPmxVector3; Scale: Single): TPmxVector3;
begin
  Result.X := Value.X * Scale;
  Result.Y := Value.Y * Scale;
  Result.Z := Value.Z * Scale;
end;

function NormalizeVector(const Value: TPmxVector3): TPmxVector3;
var
  Length_: Single;
begin
  Length_ := Sqrt(Value.X * Value.X + Value.Y * Value.Y +
    Value.Z * Value.Z);
  if Length_ <= 0.000001 then
  begin
    Result.X := 0.0;
    Result.Y := 0.0;
    Result.Z := 0.0;
  end
  else
    Result := ScaleVector(Value, 1.0 / Length_);
end;

function IdentityQuaternion: TPmxQuaternion;
begin
  Result.X := 0.0;
  Result.Y := 0.0;
  Result.Z := 0.0;
  Result.W := 1.0;
end;

function NormalizeQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
var
  Length_: Single;
begin
  Length_ := Sqrt(Value.X * Value.X + Value.Y * Value.Y +
    Value.Z * Value.Z + Value.W * Value.W);
  if Length_ <= 0.000001 then
    Result := IdentityQuaternion
  else
  begin
    Result.X := Value.X / Length_;
    Result.Y := Value.Y / Length_;
    Result.Z := Value.Z / Length_;
    Result.W := Value.W / Length_;
  end;
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

function MultiplyQuaternion(const A, B: TPmxQuaternion): TPmxQuaternion;
begin
  Result.X := A.W * B.X + A.X * B.W + A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.W * B.Y - A.X * B.Z + A.Y * B.W + A.Z * B.X;
  Result.Z := A.W * B.Z + A.X * B.Y - A.Y * B.X + A.Z * B.W;
  Result.W := A.W * B.W - A.X * B.X - A.Y * B.Y - A.Z * B.Z;
end;

function RotateVector(const Rotation: TPmxQuaternion;
  const Value: TPmxVector3): TPmxVector3;
var
  Cross1: TPmxVector3;
  Cross2: TPmxVector3;
begin
  Cross1.X := Rotation.Y * Value.Z - Rotation.Z * Value.Y;
  Cross1.Y := Rotation.Z * Value.X - Rotation.X * Value.Z;
  Cross1.Z := Rotation.X * Value.Y - Rotation.Y * Value.X;
  Cross2.X := Rotation.Y * Cross1.Z - Rotation.Z * Cross1.Y;
  Cross2.Y := Rotation.Z * Cross1.X - Rotation.X * Cross1.Z;
  Cross2.Z := Rotation.X * Cross1.Y - Rotation.Y * Cross1.X;
  Result.X := Value.X + 2.0 * (Rotation.W * Cross1.X + Cross2.X);
  Result.Y := Value.Y + 2.0 * (Rotation.W * Cross1.Y + Cross2.Y);
  Result.Z := Value.Z + 2.0 * (Rotation.W * Cross1.Z + Cross2.Z);
end;

function QuaternionFromAxisAngle(const Axis: TPmxVector3;
  AngleRadians: Single): TPmxQuaternion;
var
  HalfAngle: Single;
  NormalizedAxis: TPmxVector3;
  SinHalfAngle: Single;
begin
  NormalizedAxis := NormalizeVector(Axis);
  if (NormalizedAxis.X = 0.0) and (NormalizedAxis.Y = 0.0) and
    (NormalizedAxis.Z = 0.0) then
    Exit(IdentityQuaternion);
  HalfAngle := AngleRadians * 0.5;
  SinHalfAngle := Sin(HalfAngle);
  Result.X := NormalizedAxis.X * SinHalfAngle;
  Result.Y := NormalizedAxis.Y * SinHalfAngle;
  Result.Z := NormalizedAxis.Z * SinHalfAngle;
  Result.W := Cos(HalfAngle);
end;

function QuaternionFromEulerXYZ(X, Y, Z: Single): TPmxQuaternion;
var
  Axis: TPmxVector3;
  RotationX: TPmxQuaternion;
  RotationY: TPmxQuaternion;
  RotationZ: TPmxQuaternion;
begin
  Axis.X := 1.0;
  Axis.Y := 0.0;
  Axis.Z := 0.0;
  RotationX := QuaternionFromAxisAngle(Axis, X);
  Axis.X := 0.0;
  Axis.Y := 1.0;
  RotationY := QuaternionFromAxisAngle(Axis, Y);
  Axis.Y := 0.0;
  Axis.Z := 1.0;
  RotationZ := QuaternionFromAxisAngle(Axis, Z);
  Result := NormalizeQuaternion(MultiplyQuaternion(RotationZ,
    MultiplyQuaternion(RotationY, RotationX)));
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
    Poses[BoneIndex].Translation.X := 0.0;
    Poses[BoneIndex].Translation.Y := 0.0;
    Poses[BoneIndex].Translation.Z := 0.0;
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
    raise EArgumentException.Create('Bone pose count does not match the PMX model');
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

procedure CalculateBoneTransform(const Model: TPmxModel;
  const Poses: TPmxBonePoses; BoneIndex: Integer;
  var Transforms: TPmxBoneTransforms; var States: TBoneVisitStates);
var
  BindOffset: TPmxVector3;
  ParentIndex: Integer;
begin
  if States[BoneIndex] = 2 then
    Exit;
  if States[BoneIndex] = 1 then
    raise EInvalidOpException.CreateFmt('PMX bone hierarchy contains a cycle at %d',
      [BoneIndex]);
  States[BoneIndex] := 1;
  ParentIndex := Model.Bones[BoneIndex].ParentIndex;
  if ParentIndex < 0 then
  begin
    Transforms[BoneIndex].Position := AddVector(
      Model.Bones[BoneIndex].Position, Poses[BoneIndex].Translation);
    Transforms[BoneIndex].Rotation := NormalizeQuaternion(
      Poses[BoneIndex].Rotation);
  end
  else
  begin
    CalculateBoneTransform(Model, Poses, ParentIndex, Transforms, States);
    BindOffset := SubtractVector(Model.Bones[BoneIndex].Position,
      Model.Bones[ParentIndex].Position);
    BindOffset := AddVector(BindOffset, Poses[BoneIndex].Translation);
    Transforms[BoneIndex].Position := AddVector(
      Transforms[ParentIndex].Position,
      RotateVector(Transforms[ParentIndex].Rotation, BindOffset));
    Transforms[BoneIndex].Rotation := NormalizeQuaternion(MultiplyQuaternion(
      Transforms[ParentIndex].Rotation, Poses[BoneIndex].Rotation));
  end;
  States[BoneIndex] := 2;
end;

procedure CalculateBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
var
  BoneIndex: Integer;
  States: TBoneVisitStates;
begin
  if Length(Poses) <> Length(Model.Bones) then
    raise EArgumentException.Create('Bone pose count does not match the PMX model');
  SetLength(Transforms, Length(Model.Bones));
  SetLength(States, Length(Model.Bones));
  for BoneIndex := 0 to High(Model.Bones) do
    CalculateBoneTransform(Model, Poses, BoneIndex, Transforms, States);
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
  var Target: TPmxSkinnedVertex);
var
  BoneIndex: Integer;
  InfluenceIndex: Integer;
  InfluenceCount: Integer;
  TransformedNormal: TPmxVector3;
  TransformedPosition: TPmxVector3;
  Weight: Single;
begin
  case Source.DeformType of
    pdtBdef1: InfluenceCount := 1;
    pdtBdef2: InfluenceCount := 2;
    pdtBdef4: InfluenceCount := 4;
  else
    begin
      Target.Position := Source.Position;
      Target.Normal := Source.Normal;
      Exit;
    end;
  end;

  Target.Position.X := 0.0;
  Target.Position.Y := 0.0;
  Target.Position.Z := 0.0;
  Target.Normal.X := 0.0;
  Target.Normal.Y := 0.0;
  Target.Normal.Z := 0.0;
  for InfluenceIndex := 0 to InfluenceCount - 1 do
  begin
    Weight := Source.BoneWeights[InfluenceIndex];
    if Weight <= 0.0 then
      Continue;
    BoneIndex := Source.BoneIndices[InfluenceIndex];
    TransformedPosition := TransformPosition(Model, Transforms, BoneIndex,
      Source.Position);
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
    raise EArgumentException.Create('Bone transform count does not match the PMX model');
  SetLength(Vertices, Length(Model.Vertices));
  for VertexIndex := 0 to High(Model.Vertices) do
    SkinVertexLinear(Model, Transforms, Model.Vertices[VertexIndex],
      Vertices[VertexIndex]);
end;

end.
