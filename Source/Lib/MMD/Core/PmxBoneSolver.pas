unit PmxBoneSolver;

// PMXの親子階層、回転・移動付与、CCD IKを合成して最終ボーン変換を求める。

interface

uses
  PmxModel,
  PmxPoseTypes;

// 入力姿勢を変更せず、付与変形とIKを適用したグローバル変換を返す。
procedure CalculateFinalBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
// 編集ドラッグ用に、親子階層と付与変形だけを適用し、反復IKを省略する。
procedure CalculateInteractiveBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);

implementation

uses
  System.Math,
  System.SysUtils,
  PmxPoseMath;

type
  TBoneVisitStates = array of Byte;
  TBoneOrder = array of Integer;

procedure CalculateEffectivePose(const Model: TPmxModel;
  const InputPoses: TPmxBonePoses; BoneIndex: Integer;
  var EffectivePoses: TPmxBonePoses; var States: TBoneVisitStates);
var
  Bone: TPmxBone;
  SourceIndex: Integer;
begin
  if States[BoneIndex] = 2 then
    Exit;
  if States[BoneIndex] = 1 then
    raise EInvalidOpException.CreateFmt(
      'PMX bone grant dependency contains a cycle at %d', [BoneIndex]);
  States[BoneIndex] := 1;
  Bone := Model.Bones[BoneIndex];
  EffectivePoses[BoneIndex] := InputPoses[BoneIndex];
  EffectivePoses[BoneIndex].Rotation := NormalizeQuaternion(
    EffectivePoses[BoneIndex].Rotation);
  if ((Bone.Flags and PMX_BONE_FLAG_LOCAL_APPEND) <> 0) and
    ((Bone.Flags and (PMX_BONE_FLAG_INHERIT_ROTATION or
      PMX_BONE_FLAG_INHERIT_TRANSLATION)) <> 0) then
  begin
    SourceIndex := Bone.InheritParentIndex;
    CalculateEffectivePose(Model, InputPoses, SourceIndex, EffectivePoses,
      States);
    if (Bone.Flags and PMX_BONE_FLAG_INHERIT_TRANSLATION) <> 0 then
      EffectivePoses[BoneIndex].Translation := AddVector(
        EffectivePoses[BoneIndex].Translation,
        ScaleVector(EffectivePoses[SourceIndex].Translation,
          Bone.InheritWeight));
    if (Bone.Flags and PMX_BONE_FLAG_INHERIT_ROTATION) <> 0 then
      EffectivePoses[BoneIndex].Rotation := NormalizeQuaternion(
        MultiplyQuaternion(EffectivePoses[BoneIndex].Rotation,
          ScaleQuaternionRotation(EffectivePoses[SourceIndex].Rotation,
            Bone.InheritWeight)));
  end;
  States[BoneIndex] := 2;
end;

procedure CalculateGlobalTransform(const Model: TPmxModel;
  const EffectivePoses: TPmxBonePoses; BoneIndex: Integer;
  var Transforms: TPmxBoneTransforms; var States: TBoneVisitStates);
var
  BindOffset: TPmxVector3;
  Bone: TPmxBone;
  LocalPose: TPmxBonePose;
  ParentRotation: TPmxQuaternion;
  ParentIndex: Integer;
  RotationGrant: TPmxQuaternion;
  SourceIndex: Integer;
  TranslationGrant: TPmxVector3;
begin
  if States[BoneIndex] = 2 then
    Exit;
  if States[BoneIndex] = 1 then
    raise EInvalidOpException.CreateFmt(
      'PMX bone hierarchy contains a cycle at %d', [BoneIndex]);
  States[BoneIndex] := 1;
  Bone := Model.Bones[BoneIndex];
  ParentIndex := Bone.ParentIndex;
  LocalPose := EffectivePoses[BoneIndex];
  if ParentIndex < 0 then
    ParentRotation := IdentityQuaternion
  else
  begin
    CalculateGlobalTransform(Model, EffectivePoses, ParentIndex, Transforms,
      States);
    ParentRotation := Transforms[ParentIndex].Rotation;
  end;
  if ((Bone.Flags and PMX_BONE_FLAG_LOCAL_APPEND) = 0) and
    ((Bone.Flags and (PMX_BONE_FLAG_INHERIT_ROTATION or
      PMX_BONE_FLAG_INHERIT_TRANSLATION)) <> 0) then
  begin
    SourceIndex := Bone.InheritParentIndex;
    CalculateGlobalTransform(Model, EffectivePoses, SourceIndex, Transforms,
      States);
    if (Bone.Flags and PMX_BONE_FLAG_INHERIT_TRANSLATION) <> 0 then
    begin
      TranslationGrant := SubtractVector(Transforms[SourceIndex].Position,
        Model.Bones[SourceIndex].Position);
      TranslationGrant := RotateVector(InverseQuaternion(ParentRotation),
        TranslationGrant);
      LocalPose.Translation := AddVector(LocalPose.Translation,
        ScaleVector(TranslationGrant, Bone.InheritWeight));
    end;
    if (Bone.Flags and PMX_BONE_FLAG_INHERIT_ROTATION) <> 0 then
    begin
      RotationGrant := NormalizeQuaternion(MultiplyQuaternion(
        MultiplyQuaternion(InverseQuaternion(ParentRotation),
          Transforms[SourceIndex].Rotation), ParentRotation));
      LocalPose.Rotation := NormalizeQuaternion(MultiplyQuaternion(
        LocalPose.Rotation, ScaleQuaternionRotation(RotationGrant,
          Bone.InheritWeight)));
    end;
  end;
  if ParentIndex < 0 then
  begin
    Transforms[BoneIndex].Position := AddVector(
      Bone.Position, LocalPose.Translation);
    Transforms[BoneIndex].Rotation := LocalPose.Rotation;
  end
  else
  begin
    BindOffset := SubtractVector(Bone.Position,
      Model.Bones[ParentIndex].Position);
    BindOffset := AddVector(BindOffset, LocalPose.Translation);
    Transforms[BoneIndex].Position := AddVector(
      Transforms[ParentIndex].Position,
      RotateVector(Transforms[ParentIndex].Rotation, BindOffset));
    Transforms[BoneIndex].Rotation := NormalizeQuaternion(
      MultiplyQuaternion(Transforms[ParentIndex].Rotation,
        LocalPose.Rotation));
  end;
  States[BoneIndex] := 2;
end;

procedure CalculateBaseTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
var
  BoneIndex: Integer;
  EffectivePoses: TPmxBonePoses;
  States: TBoneVisitStates;
begin
  SetLength(EffectivePoses, Length(Model.Bones));
  SetLength(States, Length(Model.Bones));
  for BoneIndex := 0 to High(Model.Bones) do
    CalculateEffectivePose(Model, Poses, BoneIndex, EffectivePoses, States);
  SetLength(Transforms, Length(Model.Bones));
  if Length(States) > 0 then
    FillChar(States[0], Length(States) * SizeOf(States[0]), 0);
  for BoneIndex := 0 to High(Model.Bones) do
    CalculateGlobalTransform(Model, EffectivePoses, BoneIndex, Transforms,
      States);
end;

procedure ClampLinkRotation(var Pose: TPmxBonePose;
  const Link: TPmxIkLink);
var
  Euler: TPmxVector3;
begin
  if not Link.HasLimits then
    Exit;
  Euler := QuaternionToEulerXYZ(Pose.Rotation);
  Euler.X := EnsureRange(Euler.X, Link.LimitMin.X, Link.LimitMax.X);
  Euler.Y := EnsureRange(Euler.Y, Link.LimitMin.Y, Link.LimitMax.Y);
  Euler.Z := EnsureRange(Euler.Z, Link.LimitMin.Z, Link.LimitMax.Z);
  Pose.Rotation := QuaternionFromEulerXYZ(Euler.X, Euler.Y, Euler.Z);
end;

function BuildBoneOrder(const Model: TPmxModel): TBoneOrder;
var
  I, J, Value: Integer;
begin
  SetLength(Result, Length(Model.Bones));
  for I := 0 to High(Result) do
    Result[I] := I;
  for I := 1 to High(Result) do
  begin
    Value := Result[I];
    J := I - 1;
    while (J >= 0) and
      ((Model.Bones[Result[J]].DeformLayer > Model.Bones[Value].DeformLayer) or
      ((Model.Bones[Result[J]].DeformLayer = Model.Bones[Value].DeformLayer) and
      (Result[J] > Value))) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := Value;
  end;
end;

procedure ApplyIkBone(const Model: TPmxModel; IkBoneIndex: Integer;
  var WorkPoses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
var
  Angle, Dot_: Single;
  AxisWorld: TPmxVector3;
  DeltaLocal, DeltaWorld, ParentRotation: TPmxQuaternion;
  DirectionEffector, DirectionTarget: TPmxVector3;
  EffectorPosition, JointPosition, TargetPosition: TPmxVector3;
  IkBone: TPmxBone;
  Iteration, IterationCount: Integer;
  Link: TPmxIkLink;
  LinkIndex, ParentIndex: Integer;
begin
  IkBone := Model.Bones[IkBoneIndex];
  IterationCount := Min(IkBone.IkLoopCount, 256);
  for Iteration := 0 to IterationCount - 1 do
  begin
    CalculateBaseTransforms(Model, WorkPoses, Transforms);
    TargetPosition := Transforms[IkBoneIndex].Position;
    EffectorPosition := Transforms[IkBone.IkTargetIndex].Position;
    if DotVector(SubtractVector(TargetPosition, EffectorPosition),
      SubtractVector(TargetPosition, EffectorPosition)) <= 0.0000001 then
      Break;
    for LinkIndex := 0 to High(IkBone.IkLinks) do
    begin
      Link := IkBone.IkLinks[LinkIndex];
      CalculateBaseTransforms(Model, WorkPoses, Transforms);
      TargetPosition := Transforms[IkBoneIndex].Position;
      EffectorPosition := Transforms[IkBone.IkTargetIndex].Position;
      JointPosition := Transforms[Link.BoneIndex].Position;
      DirectionEffector := NormalizeVector(SubtractVector(EffectorPosition,
        JointPosition));
      DirectionTarget := NormalizeVector(SubtractVector(TargetPosition,
        JointPosition));
      Dot_ := EnsureRange(DotVector(DirectionEffector, DirectionTarget),
        -1.0, 1.0);
      Angle := Min(ArcCos(Dot_), IkBone.IkAngleLimit);
      if Angle <= 0.00001 then
        Continue;
      AxisWorld := NormalizeVector(CrossVector(DirectionEffector,
        DirectionTarget));
      if DotVector(AxisWorld, AxisWorld) <= 0.000001 then
        Continue;
      ParentIndex := Model.Bones[Link.BoneIndex].ParentIndex;
      if ParentIndex < 0 then
        ParentRotation := IdentityQuaternion
      else
        ParentRotation := Transforms[ParentIndex].Rotation;
      DeltaWorld := QuaternionFromAxisAngle(AxisWorld, Angle);
      DeltaLocal := NormalizeQuaternion(MultiplyQuaternion(
        MultiplyQuaternion(InverseQuaternion(ParentRotation), DeltaWorld),
        ParentRotation));
      WorkPoses[Link.BoneIndex].Rotation := NormalizeQuaternion(
        MultiplyQuaternion(DeltaLocal, WorkPoses[Link.BoneIndex].Rotation));
      ClampLinkRotation(WorkPoses[Link.BoneIndex], Link);
    end;
  end;
  CalculateBaseTransforms(Model, WorkPoses, Transforms);
end;

procedure CalculateFinalBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
var
  BoneIndex: Integer;
  Order: TBoneOrder;
  WorkPoses: TPmxBonePoses;
begin
  if Length(Poses) <> Length(Model.Bones) then
    raise EArgumentException.Create(
      'Bone pose count does not match the PMX model');
  WorkPoses := Copy(Poses);
  Order := BuildBoneOrder(Model);
  CalculateBaseTransforms(Model, WorkPoses, Transforms);
  for BoneIndex in Order do
    if (Model.Bones[BoneIndex].Flags and PMX_BONE_FLAG_IK) <> 0 then
      ApplyIkBone(Model, BoneIndex, WorkPoses, Transforms);
end;

procedure CalculateInteractiveBoneTransforms(const Model: TPmxModel;
  const Poses: TPmxBonePoses; var Transforms: TPmxBoneTransforms);
begin
  if Length(Poses) <> Length(Model.Bones) then
    raise EArgumentException.Create(
      'Bone pose count does not match the PMX model');
  CalculateBaseTransforms(Model, Poses, Transforms);
end;

end.
