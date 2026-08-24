unit PmxMorphReader;

// PMXモーフを解析し、姿勢・表情で利用する変位をモデルへ格納する。

interface

uses
  PmxBinaryStream,
  PmxModel;

// 全モーフを読み、頂点・ボーン・グループ変位を保持して参照範囲を検証する。
procedure ReadPmxMorphs(Stream: TPmxBinaryStream; Model: TPmxModel);

implementation

uses
  System.SysUtils;

const
  MAX_MORPH_COUNT = 1000000;
  MAX_MORPH_OFFSET_COUNT = 10000000;

procedure CheckReference(Index, Count: Integer; const FieldName: string);
begin
  if (Index < 0) or (Index >= Count) then
    raise EPmxFormatError.CreateFmt('PMX %s is out of range: %d', [FieldName, Index]);
end;

procedure ReadGroupOffsets(Stream: TPmxBinaryStream; var Morph: TPmxMorph;
  OffsetCount: Integer);
var
  I: Integer;
begin
  SetLength(Morph.GroupOffsets, OffsetCount);
  for I := 0 to OffsetCount - 1 do
  begin
    Morph.GroupOffsets[I].MorphIndex := Stream.ReadSignedIndex(Stream.MorphIndexSize);
    Morph.GroupOffsets[I].Weight := Stream.ReadSingle;
  end;
end;

procedure ReadVertexOffsets(Stream: TPmxBinaryStream; Model: TPmxModel;
  var Morph: TPmxMorph; OffsetCount: Integer);
var
  I: Integer;
begin
  SetLength(Morph.VertexOffsets, OffsetCount);
  for I := 0 to OffsetCount - 1 do
  begin
    Morph.VertexOffsets[I].VertexIndex := Stream.ReadVertexIndex;
    CheckReference(Morph.VertexOffsets[I].VertexIndex, Length(Model.Vertices),
      'morph vertex index');
    Morph.VertexOffsets[I].Offset := Stream.ReadVector3;
  end;
end;

procedure ReadBoneOffsets(Stream: TPmxBinaryStream; Model: TPmxModel;
  var Morph: TPmxMorph; OffsetCount: Integer);
var
  I: Integer;
begin
  SetLength(Morph.BoneOffsets, OffsetCount);
  for I := 0 to OffsetCount - 1 do
  begin
    Morph.BoneOffsets[I].BoneIndex := Stream.ReadSignedIndex(Stream.BoneIndexSize);
    CheckReference(Morph.BoneOffsets[I].BoneIndex, Length(Model.Bones),
      'morph bone index');
    Morph.BoneOffsets[I].Translation := Stream.ReadVector3;
    Morph.BoneOffsets[I].Rotation := Stream.ReadVector4;
  end;
end;

procedure SkipOffsets(Stream: TPmxBinaryStream; MorphType: TPmxMorphType;
  OffsetCount: Integer);
var
  I: Integer;
begin
  for I := 0 to OffsetCount - 1 do
    case MorphType of
      pmtUV, pmtAdditionalUV1, pmtAdditionalUV2, pmtAdditionalUV3,
      pmtAdditionalUV4:
        begin
          Stream.ReadVertexIndex;
          Stream.Skip(4 * SizeOf(Single));
        end;
      pmtMaterial:
        begin
          Stream.ReadSignedIndex(Stream.MaterialIndexSize);
          Stream.Skip(1 + 28 * SizeOf(Single));
        end;
      pmtImpulse:
        begin
          Stream.ReadSignedIndex(Stream.RigidBodyIndexSize);
          Stream.Skip(1 + 6 * SizeOf(Single));
        end;
    else
      raise EPmxFormatError.Create('Unsupported PMX morph offset');
    end;
end;

procedure ValidateGroupReferences(const Model: TPmxModel);
var
  I, J: Integer;
begin
  for I := 0 to High(Model.Morphs) do
    for J := 0 to High(Model.Morphs[I].GroupOffsets) do
      CheckReference(Model.Morphs[I].GroupOffsets[J].MorphIndex,
        Length(Model.Morphs), 'group morph index');
end;

procedure ReadPmxMorphs(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  I, MorphCount, OffsetCount: Integer;
  MorphTypeValue: Byte;
begin
  MorphCount := Stream.ReadInt32;
  CheckPmxCount(MorphCount, MAX_MORPH_COUNT, 'morph count');
  SetLength(Model.Morphs, MorphCount);
  for I := 0 to MorphCount - 1 do
  begin
    Model.Morphs[I].Name := Stream.ReadText;
    Stream.ReadText;
    Model.Morphs[I].Panel := Stream.ReadByte;
    MorphTypeValue := Stream.ReadByte;
    if MorphTypeValue > Byte(Ord(High(TPmxMorphType))) then
      raise EPmxFormatError.CreateFmt('Unsupported PMX morph type: %d', [MorphTypeValue]);
    Model.Morphs[I].MorphType := TPmxMorphType(MorphTypeValue);
    OffsetCount := Stream.ReadInt32;
    CheckPmxCount(OffsetCount, MAX_MORPH_OFFSET_COUNT, 'morph offset count');
    case Model.Morphs[I].MorphType of
      pmtGroup, pmtFlip:
        ReadGroupOffsets(Stream, Model.Morphs[I], OffsetCount);
      pmtVertex:
        ReadVertexOffsets(Stream, Model, Model.Morphs[I], OffsetCount);
      pmtBone:
        ReadBoneOffsets(Stream, Model, Model.Morphs[I], OffsetCount);
    else
      SkipOffsets(Stream, Model.Morphs[I].MorphType, OffsetCount);
    end;
  end;
  ValidateGroupReferences(Model);
end;

end.
