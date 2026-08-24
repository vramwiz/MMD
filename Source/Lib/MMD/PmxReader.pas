unit PmxReader;

interface

uses
  PmxModel;

function GetCachedPmxModel(const FileName: string): TPmxModel;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.SysUtils;

const
  MAX_VERTEX_COUNT = 10000000;
  MAX_INDEX_COUNT = 30000000;
  MAX_TEXTURE_COUNT = 100000;
  MAX_MATERIAL_COUNT = 100000;
  MAX_BONE_COUNT = 1000000;
  MAX_IK_LINK_COUNT = 1000000;
  BONE_FLAG_TAIL_IS_BONE = $0001;
  BONE_FLAG_IK = $0020;
  BONE_FLAG_INHERIT_ROTATION = $0100;
  BONE_FLAG_INHERIT_TRANSLATION = $0200;
  BONE_FLAG_FIXED_AXIS = $0400;
  BONE_FLAG_LOCAL_COORDINATE = $0800;
  BONE_FLAG_EXTERNAL_PARENT = $2000;

type
  EPmxFormatError = class(Exception);

  TPmxBinaryReader = class
  private
    FData: TBytes;
    FOffset: Integer;
    FEncoding: TEncoding;
    FAdditionalUVCount: Byte;
    FVertexIndexSize: Byte;
    FTextureIndexSize: Byte;
    FBoneIndexSize: Byte;
    procedure EnsureAvailable(ByteCount: Integer);
    procedure Skip(ByteCount: Integer);
    function ReadByte: Byte;
    function ReadUInt16: Word;
    function ReadInt16: SmallInt;
    function ReadInt32: Integer;
    function ReadSingle: Single;
    function ReadText: string;
    function ReadSignedIndex(IndexSize: Byte): Integer;
    function ReadVertexIndex: Integer;
    function ReadVector2: TPmxVector2;
    function ReadVector3: TPmxVector3;
    function ReadVector4: TPmxVector4;
    procedure ReadHeader(Model: TPmxModel);
    procedure ReadVertices(Model: TPmxModel);
    procedure ReadSurfaces(Model: TPmxModel);
    procedure ReadTextures(Model: TPmxModel);
    procedure ReadMaterials(Model: TPmxModel);
    procedure ReadBones(Model: TPmxModel);
  public
    constructor Create(const FileName: string);
    function ReadModel(const FileName: string): TPmxModel;
  end;

var
  ModelCache: TObjectDictionary<string, TPmxModel>;
  ModelCacheLock: TObject;

procedure CheckCount(Value, Maximum: Integer; const FieldName: string);
begin
  if (Value < 0) or (Value > Maximum) then
    raise EPmxFormatError.CreateFmt('Invalid PMX %s: %d', [FieldName, Value]);
end;

function NormalizedCacheKey(const FileName: string): string;
begin
  Result := LowerCase(TPath.GetFullPath(FileName));
end;

constructor TPmxBinaryReader.Create(const FileName: string);
begin
  inherited Create;
  FData := TFile.ReadAllBytes(FileName);
end;

procedure TPmxBinaryReader.EnsureAvailable(ByteCount: Integer);
begin
  if (ByteCount < 0) or (FOffset > Length(FData) - ByteCount) then
    raise EPmxFormatError.CreateFmt('Unexpected end of PMX at byte %d', [FOffset]);
end;

procedure TPmxBinaryReader.Skip(ByteCount: Integer);
begin
  EnsureAvailable(ByteCount);
  Inc(FOffset, ByteCount);
end;

function TPmxBinaryReader.ReadByte: Byte;
begin
  EnsureAvailable(SizeOf(Result));
  Result := FData[FOffset];
  Inc(FOffset);
end;

function TPmxBinaryReader.ReadUInt16: Word;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryReader.ReadInt16: SmallInt;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryReader.ReadInt32: Integer;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryReader.ReadSingle: Single;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryReader.ReadText: string;
var
  ByteCount: Integer;
begin
  ByteCount := ReadInt32;
  CheckCount(ByteCount, Length(FData), 'text length');
  EnsureAvailable(ByteCount);
  Result := FEncoding.GetString(FData, FOffset, ByteCount);
  Inc(FOffset, ByteCount);
end;

function TPmxBinaryReader.ReadSignedIndex(IndexSize: Byte): Integer;
begin
  case IndexSize of
    1: Result := ShortInt(ReadByte);
    2: Result := ReadInt16;
    4: Result := ReadInt32;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX index size: %d', [IndexSize]);
  end;
end;

function TPmxBinaryReader.ReadVertexIndex: Integer;
begin
  case FVertexIndexSize of
    1: Result := ReadByte;
    2: Result := ReadUInt16;
    4: Result := ReadInt32;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX vertex index size: %d',
      [FVertexIndexSize]);
  end;
end;

function TPmxBinaryReader.ReadVector2: TPmxVector2;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
end;

function TPmxBinaryReader.ReadVector3: TPmxVector3;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
  Result.Z := ReadSingle;
end;

function TPmxBinaryReader.ReadVector4: TPmxVector4;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
  Result.Z := ReadSingle;
  Result.W := ReadSingle;
end;

procedure TPmxBinaryReader.ReadHeader(Model: TPmxModel);
var
  EncodingKind: Byte;
  HeaderSize: Byte;
  I: Integer;
  Signature: AnsiString;
  Version: Single;
begin
  SetLength(Signature, 4);
  EnsureAvailable(4);
  Move(FData[FOffset], Signature[1], 4);
  Inc(FOffset, 4);
  if Signature <> 'PMX ' then
    raise EPmxFormatError.Create('The selected file is not a PMX model');

  Version := ReadSingle;
  if (Abs(Version - 2.0) > 0.001) and (Abs(Version - 2.1) > 0.001) then
    raise EPmxFormatError.CreateFmt('Unsupported PMX version: %.3f', [Version]);

  HeaderSize := ReadByte;
  if HeaderSize < 8 then
    raise EPmxFormatError.CreateFmt('Invalid PMX header size: %d', [HeaderSize]);
  EnsureAvailable(HeaderSize);
  EncodingKind := ReadByte;
  case EncodingKind of
    0: FEncoding := TEncoding.Unicode;
    1: FEncoding := TEncoding.UTF8;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX text encoding: %d', [EncodingKind]);
  end;
  FAdditionalUVCount := ReadByte;
  if FAdditionalUVCount > 4 then
    raise EPmxFormatError.CreateFmt('Invalid PMX additional UV count: %d',
      [FAdditionalUVCount]);
  FVertexIndexSize := ReadByte;
  FTextureIndexSize := ReadByte;
  ReadByte;
  FBoneIndexSize := ReadByte;
  ReadByte;
  ReadByte;
  for I := 8 to HeaderSize - 1 do
    ReadByte;

  Model.Name := ReadText;
  ReadText;
  ReadText;
  ReadText;
end;

procedure TPmxBinaryReader.ReadVertices(Model: TPmxModel);
var
  DeformType: Byte;
  I: Integer;
  J: Integer;
  VertexCount: Integer;
begin
  VertexCount := ReadInt32;
  CheckCount(VertexCount, MAX_VERTEX_COUNT, 'vertex count');
  SetLength(Model.Vertices, VertexCount);
  for I := 0 to VertexCount - 1 do
  begin
    Model.Vertices[I].Position := ReadVector3;
    Model.Vertices[I].Normal := ReadVector3;
    Model.Vertices[I].UV := ReadVector2;
    for J := 1 to FAdditionalUVCount do
      Skip(4 * SizeOf(Single));
    DeformType := ReadByte;
    case DeformType of
      0: ReadSignedIndex(FBoneIndexSize);
      1:
        begin
          ReadSignedIndex(FBoneIndexSize);
          ReadSignedIndex(FBoneIndexSize);
          ReadSingle;
        end;
      2, 4:
        begin
          for J := 1 to 4 do
            ReadSignedIndex(FBoneIndexSize);
          Skip(4 * SizeOf(Single));
        end;
      3:
        begin
          ReadSignedIndex(FBoneIndexSize);
          ReadSignedIndex(FBoneIndexSize);
          ReadSingle;
          Skip(9 * SizeOf(Single));
        end;
    else
      raise EPmxFormatError.CreateFmt('Unsupported PMX deform type: %d', [DeformType]);
    end;
    ReadSingle;
  end;
end;

procedure TPmxBinaryReader.ReadSurfaces(Model: TPmxModel);
var
  I: Integer;
  IndexCount: Integer;
begin
  IndexCount := ReadInt32;
  CheckCount(IndexCount, MAX_INDEX_COUNT, 'surface index count');
  if IndexCount mod 3 <> 0 then
    raise EPmxFormatError.CreateFmt('PMX surface index count is not divisible by 3: %d',
      [IndexCount]);
  SetLength(Model.Indices, IndexCount);
  for I := 0 to IndexCount - 1 do
  begin
    Model.Indices[I] := ReadVertexIndex;
    if (Model.Indices[I] < 0) or (Model.Indices[I] >= Length(Model.Vertices)) then
      raise EPmxFormatError.CreateFmt('PMX vertex index is out of range: %d',
        [Model.Indices[I]]);
  end;
end;

procedure TPmxBinaryReader.ReadTextures(Model: TPmxModel);
var
  BaseDirectory: string;
  I: Integer;
  RelativePath: string;
  TextureCount: Integer;
begin
  TextureCount := ReadInt32;
  CheckCount(TextureCount, MAX_TEXTURE_COUNT, 'texture count');
  SetLength(Model.Textures, TextureCount);
  SetLength(Model.TextureAvailable, TextureCount);
  BaseDirectory := ExtractFileDir(Model.SourcePath);
  for I := 0 to TextureCount - 1 do
  begin
    RelativePath := StringReplace(ReadText, '/', PathDelim, [rfReplaceAll]);
    Model.Textures[I] := TPath.GetFullPath(TPath.Combine(BaseDirectory, RelativePath));
    Model.TextureAvailable[I] := TFile.Exists(Model.Textures[I]);
  end;
end;

procedure TPmxBinaryReader.ReadMaterials(Model: TPmxModel);
var
  I: Integer;
  MaterialCount: Integer;
  SurfaceCursor: Integer;
  ToonReference: Byte;
begin
  MaterialCount := ReadInt32;
  CheckCount(MaterialCount, MAX_MATERIAL_COUNT, 'material count');
  SetLength(Model.Materials, MaterialCount);
  SurfaceCursor := 0;
  for I := 0 to MaterialCount - 1 do
  begin
    Model.Materials[I].Name := ReadText;
    ReadText;
    Model.Materials[I].Diffuse := ReadVector4;
    ReadVector3;
    Model.Materials[I].SpecularStrength := ReadSingle;
    ReadVector3;
    Model.Materials[I].Flags := ReadByte;
    ReadVector4;
    ReadSingle;
    Model.Materials[I].TextureIndex := ReadSignedIndex(FTextureIndexSize);
    ReadSignedIndex(FTextureIndexSize);
    ReadByte;
    ToonReference := ReadByte;
    case ToonReference of
      0: ReadSignedIndex(FTextureIndexSize);
      1: ReadByte;
    else
      raise EPmxFormatError.CreateFmt('Invalid PMX toon reference: %d', [ToonReference]);
    end;
    ReadText;
    Model.Materials[I].SurfaceStart := SurfaceCursor;
    Model.Materials[I].SurfaceCount := ReadInt32;
    CheckCount(Model.Materials[I].SurfaceCount, Length(Model.Indices),
      'material surface count');
    if Model.Materials[I].SurfaceCount mod 3 <> 0 then
      raise EPmxFormatError.CreateFmt('Material surface count is not divisible by 3: %d',
        [Model.Materials[I].SurfaceCount]);
    Inc(SurfaceCursor, Model.Materials[I].SurfaceCount);
    if SurfaceCursor > Length(Model.Indices) then
      raise EPmxFormatError.Create('Material surfaces exceed the PMX surface list');
    if (Model.Materials[I].TextureIndex < -1) or
      (Model.Materials[I].TextureIndex >= Length(Model.Textures)) then
      raise EPmxFormatError.CreateFmt('PMX texture index is out of range: %d',
        [Model.Materials[I].TextureIndex]);
  end;
  if SurfaceCursor <> Length(Model.Indices) then
    raise EPmxFormatError.CreateFmt('Material surfaces cover %d of %d indices',
      [SurfaceCursor, Length(Model.Indices)]);
end;

procedure TPmxBinaryReader.ReadBones(Model: TPmxModel);
var
  BoneCount: Integer;
  HasLimits: Byte;
  I: Integer;
  J: Integer;
  LinkCount: Integer;
begin
  BoneCount := ReadInt32;
  CheckCount(BoneCount, MAX_BONE_COUNT, 'bone count');
  SetLength(Model.Bones, BoneCount);
  for I := 0 to BoneCount - 1 do
  begin
    Model.Bones[I].Name := ReadText;
    ReadText;
    Model.Bones[I].Position := ReadVector3;
    Model.Bones[I].ParentIndex := ReadSignedIndex(FBoneIndexSize);
    ReadInt32;
    Model.Bones[I].Flags := ReadUInt16;

    if (Model.Bones[I].Flags and BONE_FLAG_TAIL_IS_BONE) <> 0 then
      ReadSignedIndex(FBoneIndexSize)
    else
      ReadVector3;
    if (Model.Bones[I].Flags and (BONE_FLAG_INHERIT_ROTATION or
      BONE_FLAG_INHERIT_TRANSLATION)) <> 0 then
    begin
      ReadSignedIndex(FBoneIndexSize);
      ReadSingle;
    end;
    if (Model.Bones[I].Flags and BONE_FLAG_FIXED_AXIS) <> 0 then
      ReadVector3;
    if (Model.Bones[I].Flags and BONE_FLAG_LOCAL_COORDINATE) <> 0 then
    begin
      ReadVector3;
      ReadVector3;
    end;
    if (Model.Bones[I].Flags and BONE_FLAG_EXTERNAL_PARENT) <> 0 then
      ReadInt32;
    if (Model.Bones[I].Flags and BONE_FLAG_IK) <> 0 then
    begin
      ReadSignedIndex(FBoneIndexSize);
      ReadInt32;
      ReadSingle;
      LinkCount := ReadInt32;
      CheckCount(LinkCount, MAX_IK_LINK_COUNT, 'IK link count');
      for J := 0 to LinkCount - 1 do
      begin
        ReadSignedIndex(FBoneIndexSize);
        HasLimits := ReadByte;
        case HasLimits of
          0: ;
          1:
            begin
              ReadVector3;
              ReadVector3;
            end;
        else
          raise EPmxFormatError.CreateFmt('Invalid PMX IK limit flag: %d',
            [HasLimits]);
        end;
      end;
    end;
  end;

  for I := 0 to BoneCount - 1 do
    if (Model.Bones[I].ParentIndex < -1) or
      (Model.Bones[I].ParentIndex >= BoneCount) then
      raise EPmxFormatError.CreateFmt('PMX parent bone index is out of range: %d',
        [Model.Bones[I].ParentIndex]);
end;

function TPmxBinaryReader.ReadModel(const FileName: string): TPmxModel;
begin
  Result := TPmxModel.Create;
  try
    Result.SourcePath := TPath.GetFullPath(FileName);
    ReadHeader(Result);
    ReadVertices(Result);
    ReadSurfaces(Result);
    ReadTextures(Result);
    ReadMaterials(Result);
    ReadBones(Result);
  except
    Result.Free;
    raise;
  end;
end;

function LoadPmxModel(const FileName: string): TPmxModel;
var
  Reader: TPmxBinaryReader;
begin
  Reader := TPmxBinaryReader.Create(FileName);
  try
    Result := Reader.ReadModel(FileName);
  finally
    Reader.Free;
  end;
end;

function GetCachedPmxModel(const FileName: string): TPmxModel;
var
  CacheKey: string;
begin
  CacheKey := NormalizedCacheKey(FileName);
  TMonitor.Enter(ModelCacheLock);
  try
    if not ModelCache.TryGetValue(CacheKey, Result) then
    begin
      Result := LoadPmxModel(FileName);
      ModelCache.Add(CacheKey, Result);
    end;
  finally
    TMonitor.Exit(ModelCacheLock);
  end;
end;

initialization
  ModelCacheLock := TObject.Create;
  ModelCache := TObjectDictionary<string, TPmxModel>.Create([doOwnsValues]);

finalization
  ModelCache.Free;
  ModelCacheLock.Free;

end.
