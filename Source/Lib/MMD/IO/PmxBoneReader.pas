unit PmxBoneReader;

// PMXボーン、付与変形、IKリンクを読み込み、参照と頂点Weightを検証する。

interface

uses
  PmxBinaryStream,
  PmxModel;

// ボーンを追加し、親番号と全頂点のボーン参照・Weightを検証する。
procedure ReadPmxBones(Stream: TPmxBinaryStream; Model: TPmxModel);

implementation

uses
  System.Math,
  System.SysUtils;

const
  MAX_BONE_COUNT = 1000000;
  MAX_IK_LINK_COUNT = 1000000;
  MAX_IK_LOOP_COUNT = 1000000;

function IsFiniteVector(const Value: TPmxVector3): Boolean;
begin
  Result := not IsNan(Value.X) and not IsInfinite(Value.X) and
    not IsNan(Value.Y) and not IsInfinite(Value.Y) and
    not IsNan(Value.Z) and not IsInfinite(Value.Z);
end;

procedure ReadBoneOptionalData(Stream: TPmxBinaryStream; var Bone: TPmxBone);
var
  HasLimits: Byte;
  J, LinkCount: Integer;
begin
  if (Bone.Flags and PMX_BONE_FLAG_TAIL_IS_BONE) <> 0 then
    Stream.ReadSignedIndex(Stream.BoneIndexSize)
  else
    Stream.ReadVector3;
  if (Bone.Flags and (PMX_BONE_FLAG_INHERIT_ROTATION or
    PMX_BONE_FLAG_INHERIT_TRANSLATION)) <> 0 then
  begin
    Bone.InheritParentIndex := Stream.ReadSignedIndex(Stream.BoneIndexSize);
    Bone.InheritWeight := Stream.ReadSingle;
  end;
  if (Bone.Flags and PMX_BONE_FLAG_FIXED_AXIS) <> 0 then
    Stream.ReadVector3;
  if (Bone.Flags and PMX_BONE_FLAG_LOCAL_COORDINATE) <> 0 then
  begin
    Stream.ReadVector3;
    Stream.ReadVector3;
  end;
  if (Bone.Flags and PMX_BONE_FLAG_EXTERNAL_PARENT) <> 0 then
    Stream.ReadInt32;
  if (Bone.Flags and PMX_BONE_FLAG_IK) = 0 then
    Exit;
  Bone.IkTargetIndex := Stream.ReadSignedIndex(Stream.BoneIndexSize);
  Bone.IkLoopCount := Stream.ReadInt32;
  CheckPmxCount(Bone.IkLoopCount, MAX_IK_LOOP_COUNT, 'IK loop count');
  Bone.IkAngleLimit := Stream.ReadSingle;
  LinkCount := Stream.ReadInt32;
  CheckPmxCount(LinkCount, MAX_IK_LINK_COUNT, 'IK link count');
  SetLength(Bone.IkLinks, LinkCount);
  for J := 0 to LinkCount - 1 do
  begin
    Bone.IkLinks[J].BoneIndex :=
      Stream.ReadSignedIndex(Stream.BoneIndexSize);
    HasLimits := Stream.ReadByte;
    case HasLimits of
      0: Bone.IkLinks[J].HasLimits := False;
      1:
        begin
          Bone.IkLinks[J].HasLimits := True;
          Bone.IkLinks[J].LimitMin := Stream.ReadVector3;
          Bone.IkLinks[J].LimitMax := Stream.ReadVector3;
        end;
    else
      raise EPmxFormatError.CreateFmt('Invalid PMX IK limit flag: %d',
        [HasLimits]);
    end;
  end;
end;

procedure ValidateBoneReferences(const Model: TPmxModel);
var
  Bone: TPmxBone;
  BoneCount, I, J: Integer;
  Link: TPmxIkLink;
  WeightSum: Single;
begin
  BoneCount := Length(Model.Bones);
  for I := 0 to BoneCount - 1 do
  begin
    Bone := Model.Bones[I];
    if (Model.Bones[I].ParentIndex < -1) or
      (Model.Bones[I].ParentIndex >= BoneCount) then
      raise EPmxFormatError.CreateFmt('PMX parent bone index is out of range: %d',
        [Model.Bones[I].ParentIndex]);
    if (Bone.Flags and (PMX_BONE_FLAG_INHERIT_ROTATION or
      PMX_BONE_FLAG_INHERIT_TRANSLATION)) <> 0 then
    begin
      if (Bone.InheritParentIndex < 0) or
        (Bone.InheritParentIndex >= BoneCount) then
        raise EPmxFormatError.CreateFmt(
          'PMX inherit parent bone index is out of range: %d',
          [Bone.InheritParentIndex]);
      if IsNan(Bone.InheritWeight) or IsInfinite(Bone.InheritWeight) then
        raise EPmxFormatError.Create('PMX inherit weight is not finite');
    end;
    if (Bone.Flags and PMX_BONE_FLAG_IK) <> 0 then
    begin
      if (Bone.IkTargetIndex < 0) or (Bone.IkTargetIndex >= BoneCount) then
        raise EPmxFormatError.CreateFmt(
          'PMX IK target bone index is out of range: %d',
          [Bone.IkTargetIndex]);
      if IsNan(Bone.IkAngleLimit) or IsInfinite(Bone.IkAngleLimit) or
        (Bone.IkAngleLimit < 0) then
        raise EPmxFormatError.Create('PMX IK angle limit is invalid');
      for Link in Bone.IkLinks do
      begin
        if (Link.BoneIndex < 0) or (Link.BoneIndex >= BoneCount) then
          raise EPmxFormatError.CreateFmt(
            'PMX IK link bone index is out of range: %d', [Link.BoneIndex]);
        if Link.HasLimits and
          (not IsFiniteVector(Link.LimitMin) or
          not IsFiniteVector(Link.LimitMax) or
          (Link.LimitMin.X > Link.LimitMax.X) or
          (Link.LimitMin.Y > Link.LimitMax.Y) or
          (Link.LimitMin.Z > Link.LimitMax.Z)) then
          raise EPmxFormatError.Create(
            'PMX IK link angle limits are invalid');
      end;
    end;
  end;
  for I := 0 to High(Model.Vertices) do
  begin
    WeightSum := 0.0;
    for J := 0 to High(Model.Vertices[I].BoneIndices) do
    begin
      if (Model.Vertices[I].BoneIndices[J] < -1) or
        (Model.Vertices[I].BoneIndices[J] >= BoneCount) then
        raise EPmxFormatError.CreateFmt(
          'PMX vertex %d bone index is out of range: %d',
          [I, Model.Vertices[I].BoneIndices[J]]);
      if IsNan(Model.Vertices[I].BoneWeights[J]) or
        IsInfinite(Model.Vertices[I].BoneWeights[J]) or
        (Model.Vertices[I].BoneWeights[J] < 0.0) or
        (Model.Vertices[I].BoneWeights[J] > 1.0) then
        raise EPmxFormatError.CreateFmt(
          'PMX vertex %d has invalid bone weight: %g',
          [I, Model.Vertices[I].BoneWeights[J]]);
      if (Model.Vertices[I].BoneIndices[J] < 0) and
        (Model.Vertices[I].BoneWeights[J] > 0.0) then
        raise EPmxFormatError.CreateFmt(
          'PMX vertex %d has a weighted missing bone', [I]);
      WeightSum := WeightSum + Model.Vertices[I].BoneWeights[J];
    end;
    if Abs(WeightSum - 1.0) > 0.001 then
      raise EPmxFormatError.CreateFmt(
        'PMX vertex %d bone weights do not sum to 1: %g', [I, WeightSum]);
  end;
end;

procedure ReadPmxBones(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  BoneCount, I: Integer;
begin
  BoneCount := Stream.ReadInt32;
  CheckPmxCount(BoneCount, MAX_BONE_COUNT, 'bone count');
  SetLength(Model.Bones, BoneCount);
  for I := 0 to BoneCount - 1 do
  begin
    Model.Bones[I].Name := Stream.ReadText;
    Stream.ReadText;
    Model.Bones[I].Position := Stream.ReadVector3;
    Model.Bones[I].ParentIndex := Stream.ReadSignedIndex(Stream.BoneIndexSize);
    Model.Bones[I].DeformLayer := Stream.ReadInt32;
    Model.Bones[I].Flags := Stream.ReadUInt16;
    Model.Bones[I].InheritParentIndex := -1;
    Model.Bones[I].IkTargetIndex := -1;
    ReadBoneOptionalData(Stream, Model.Bones[I]);
  end;
  ValidateBoneReferences(Model);
end;

end.
