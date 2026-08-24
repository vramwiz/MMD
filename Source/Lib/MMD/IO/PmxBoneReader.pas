unit PmxBoneReader;

// PMXボーンとIK付加情報を読み飛ばしつつ、階層と頂点Weightを検証する。

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
  BONE_FLAG_TAIL_IS_BONE = $0001;
  BONE_FLAG_IK = $0020;
  BONE_FLAG_INHERIT_ROTATION = $0100;
  BONE_FLAG_INHERIT_TRANSLATION = $0200;
  BONE_FLAG_FIXED_AXIS = $0400;
  BONE_FLAG_LOCAL_COORDINATE = $0800;
  BONE_FLAG_EXTERNAL_PARENT = $2000;

procedure ReadBoneOptionalData(Stream: TPmxBinaryStream; Flags: Word);
var
  HasLimits: Byte;
  J, LinkCount: Integer;
begin
  if (Flags and BONE_FLAG_TAIL_IS_BONE) <> 0 then
    Stream.ReadSignedIndex(Stream.BoneIndexSize)
  else
    Stream.ReadVector3;
  if (Flags and (BONE_FLAG_INHERIT_ROTATION or
    BONE_FLAG_INHERIT_TRANSLATION)) <> 0 then
  begin
    Stream.ReadSignedIndex(Stream.BoneIndexSize);
    Stream.ReadSingle;
  end;
  if (Flags and BONE_FLAG_FIXED_AXIS) <> 0 then
    Stream.ReadVector3;
  if (Flags and BONE_FLAG_LOCAL_COORDINATE) <> 0 then
  begin
    Stream.ReadVector3;
    Stream.ReadVector3;
  end;
  if (Flags and BONE_FLAG_EXTERNAL_PARENT) <> 0 then
    Stream.ReadInt32;
  if (Flags and BONE_FLAG_IK) = 0 then
    Exit;
  Stream.ReadSignedIndex(Stream.BoneIndexSize);
  Stream.ReadInt32;
  Stream.ReadSingle;
  LinkCount := Stream.ReadInt32;
  CheckPmxCount(LinkCount, MAX_IK_LINK_COUNT, 'IK link count');
  for J := 0 to LinkCount - 1 do
  begin
    Stream.ReadSignedIndex(Stream.BoneIndexSize);
    HasLimits := Stream.ReadByte;
    case HasLimits of
      0: ;
      1:
        begin
          Stream.ReadVector3;
          Stream.ReadVector3;
        end;
    else
      raise EPmxFormatError.CreateFmt('Invalid PMX IK limit flag: %d',
        [HasLimits]);
    end;
  end;
end;

procedure ValidateBoneReferences(const Model: TPmxModel);
var
  BoneCount, I, J: Integer;
  WeightSum: Single;
begin
  BoneCount := Length(Model.Bones);
  for I := 0 to BoneCount - 1 do
    if (Model.Bones[I].ParentIndex < -1) or
      (Model.Bones[I].ParentIndex >= BoneCount) then
      raise EPmxFormatError.CreateFmt('PMX parent bone index is out of range: %d',
        [Model.Bones[I].ParentIndex]);
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
    Stream.ReadInt32;
    Model.Bones[I].Flags := Stream.ReadUInt16;
    ReadBoneOptionalData(Stream, Model.Bones[I].Flags);
  end;
  ValidateBoneReferences(Model);
end;

end.
