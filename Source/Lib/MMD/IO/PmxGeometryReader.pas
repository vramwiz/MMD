unit PmxGeometryReader;

// PMXヘッダー、頂点、面Indexをモデルへ読み込む。

interface

uses
  PmxBinaryStream,
  PmxModel;

// 形式・版・文字コード・Index幅を検証し、後続読込に必要なStream状態を設定する。
procedure ReadPmxHeader(Stream: TPmxBinaryStream; Model: TPmxModel);
// 頂点属性と変形情報をModelへ追加する。未知の変形方式は受理しない。
procedure ReadPmxVertices(Stream: TPmxBinaryStream; Model: TPmxModel);
// 三角形IndexをModelへ追加し、頂点範囲との整合性を検証する。
procedure ReadPmxSurfaces(Stream: TPmxBinaryStream; Model: TPmxModel);

implementation

uses
  System.Math,
  System.SysUtils;

const
  MAX_VERTEX_COUNT = 10000000;
  MAX_INDEX_COUNT = 30000000;
  PMX_DEFORM_BDEF1 = 0;
  PMX_DEFORM_BDEF2 = 1;
  PMX_DEFORM_BDEF4 = 2;
  PMX_DEFORM_SDEF = 3;
  PMX_DEFORM_QDEF = 4;

procedure ReadPmxHeader(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  EncodingKind: Byte;
  HeaderSize: Byte;
  I: Integer;
  Signature: AnsiString;
  Version: Single;
begin
  Signature := Stream.ReadAnsi(4);
  if Signature <> 'PMX ' then
    raise EPmxFormatError.Create('The selected file is not a PMX model');
  Version := Stream.ReadSingle;
  if (Abs(Version - 2.0) > 0.001) and (Abs(Version - 2.1) > 0.001) then
    raise EPmxFormatError.CreateFmt('Unsupported PMX version: %.3f', [Version]);
  HeaderSize := Stream.ReadByte;
  if HeaderSize < 8 then
    raise EPmxFormatError.CreateFmt('Invalid PMX header size: %d', [HeaderSize]);
  Stream.EnsureAvailable(HeaderSize);
  EncodingKind := Stream.ReadByte;
  case EncodingKind of
    0: Stream.Encoding := TEncoding.Unicode;
    1: Stream.Encoding := TEncoding.UTF8;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX text encoding: %d', [EncodingKind]);
  end;
  Stream.AdditionalUVCount := Stream.ReadByte;
  if Stream.AdditionalUVCount > 4 then
    raise EPmxFormatError.CreateFmt('Invalid PMX additional UV count: %d',
      [Stream.AdditionalUVCount]);
  Stream.VertexIndexSize := Stream.ReadByte;
  Stream.TextureIndexSize := Stream.ReadByte;
  Stream.ReadByte;
  Stream.BoneIndexSize := Stream.ReadByte;
  Stream.ReadByte;
  Stream.ReadByte;
  for I := 8 to HeaderSize - 1 do
    Stream.ReadByte;
  Model.Name := Stream.ReadText;
  Stream.ReadText;
  Stream.ReadText;
  Stream.ReadText;
end;

procedure ReadPmxVertices(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  DeformType: Byte;
  I, J: Integer;
  VertexCount: Integer;
  Weight: Single;
begin
  VertexCount := Stream.ReadInt32;
  CheckPmxCount(VertexCount, MAX_VERTEX_COUNT, 'vertex count');
  SetLength(Model.Vertices, VertexCount);
  for I := 0 to VertexCount - 1 do
  begin
    Model.Vertices[I].Position := Stream.ReadVector3;
    Model.Vertices[I].Normal := Stream.ReadVector3;
    Model.Vertices[I].UV := Stream.ReadVector2;
    for J := 1 to Stream.AdditionalUVCount do
      Stream.Skip(4 * SizeOf(Single));
    for J := 0 to High(Model.Vertices[I].BoneIndices) do
      Model.Vertices[I].BoneIndices[J] := -1;
    DeformType := Stream.ReadByte;
    case DeformType of
      PMX_DEFORM_BDEF1:
        begin
          Model.Vertices[I].DeformType := pdtBdef1;
          Model.Vertices[I].BoneIndices[0] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          Model.Vertices[I].BoneWeights[0] := 1.0;
        end;
      PMX_DEFORM_BDEF2:
        begin
          Model.Vertices[I].DeformType := pdtBdef2;
          Model.Vertices[I].BoneIndices[0] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          Model.Vertices[I].BoneIndices[1] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          Weight := Stream.ReadSingle;
          Model.Vertices[I].BoneWeights[0] := Weight;
          Model.Vertices[I].BoneWeights[1] := 1.0 - Weight;
        end;
      PMX_DEFORM_BDEF4, PMX_DEFORM_QDEF:
        begin
          if DeformType = PMX_DEFORM_BDEF4 then
            Model.Vertices[I].DeformType := pdtBdef4
          else
            Model.Vertices[I].DeformType := pdtQdef;
          for J := 0 to 3 do
            Model.Vertices[I].BoneIndices[J] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          for J := 0 to 3 do
            Model.Vertices[I].BoneWeights[J] := Stream.ReadSingle;
        end;
      PMX_DEFORM_SDEF:
        begin
          Model.Vertices[I].DeformType := pdtSdef;
          Model.Vertices[I].BoneIndices[0] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          Model.Vertices[I].BoneIndices[1] := Stream.ReadSignedIndex(Stream.BoneIndexSize);
          Weight := Stream.ReadSingle;
          Model.Vertices[I].BoneWeights[0] := Weight;
          Model.Vertices[I].BoneWeights[1] := 1.0 - Weight;
          Model.Vertices[I].SdefC := Stream.ReadVector3;
          Model.Vertices[I].SdefR0 := Stream.ReadVector3;
          Model.Vertices[I].SdefR1 := Stream.ReadVector3;
        end;
    else
      raise EPmxFormatError.CreateFmt('Unsupported PMX deform type: %d', [DeformType]);
    end;
    Stream.ReadSingle;
  end;
end;

procedure ReadPmxSurfaces(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  I, IndexCount: Integer;
begin
  IndexCount := Stream.ReadInt32;
  CheckPmxCount(IndexCount, MAX_INDEX_COUNT, 'surface index count');
  if IndexCount mod 3 <> 0 then
    raise EPmxFormatError.CreateFmt('PMX surface index count is not divisible by 3: %d',
      [IndexCount]);
  SetLength(Model.Indices, IndexCount);
  for I := 0 to IndexCount - 1 do
  begin
    Model.Indices[I] := Stream.ReadVertexIndex;
    if (Model.Indices[I] < 0) or (Model.Indices[I] >= Length(Model.Vertices)) then
      raise EPmxFormatError.CreateFmt('PMX vertex index is out of range: %d',
        [Model.Indices[I]]);
  end;
end;

end.
