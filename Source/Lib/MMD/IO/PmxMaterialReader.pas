unit PmxMaterialReader;

// PMXテクスチャ参照と材質情報を読み込み、面範囲との整合性を検証する。

interface

uses
  PmxBinaryStream,
  PmxModel;

// PMX相対パスを絶対パスへ解決し、各テクスチャの存在状態もModelへ保存する。
procedure ReadPmxTextures(Stream: TPmxBinaryStream; Model: TPmxModel);
// 材質と対応面範囲を追加し、全Indexが過不足なく材質へ割り当たることを検証する。
procedure ReadPmxMaterials(Stream: TPmxBinaryStream; Model: TPmxModel);

implementation

uses
  System.IOUtils,
  System.SysUtils;

const
  MAX_TEXTURE_COUNT = 100000;
  MAX_MATERIAL_COUNT = 100000;

procedure ReadPmxTextures(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  BaseDirectory: string;
  I: Integer;
  RelativePath: string;
  TextureCount: Integer;
begin
  TextureCount := Stream.ReadInt32;
  CheckPmxCount(TextureCount, MAX_TEXTURE_COUNT, 'texture count');
  SetLength(Model.Textures, TextureCount);
  SetLength(Model.TextureAvailable, TextureCount);
  BaseDirectory := ExtractFileDir(Model.SourcePath);
  for I := 0 to TextureCount - 1 do
  begin
    RelativePath := StringReplace(Stream.ReadText, '/', PathDelim, [rfReplaceAll]);
    Model.Textures[I] := TPath.GetFullPath(TPath.Combine(BaseDirectory, RelativePath));
    Model.TextureAvailable[I] := TFile.Exists(Model.Textures[I]);
  end;
end;

procedure ReadPmxMaterials(Stream: TPmxBinaryStream; Model: TPmxModel);
var
  I: Integer;
  MaterialCount: Integer;
  SurfaceCursor: Integer;
  ToonReference: Byte;
begin
  MaterialCount := Stream.ReadInt32;
  CheckPmxCount(MaterialCount, MAX_MATERIAL_COUNT, 'material count');
  SetLength(Model.Materials, MaterialCount);
  SurfaceCursor := 0;
  for I := 0 to MaterialCount - 1 do
  begin
    Model.Materials[I].Name := Stream.ReadText;
    Stream.ReadText;
    Model.Materials[I].Diffuse := Stream.ReadVector4;
    Stream.ReadVector3;
    Model.Materials[I].SpecularStrength := Stream.ReadSingle;
    Stream.ReadVector3;
    Model.Materials[I].Flags := Stream.ReadByte;
    Stream.ReadVector4;
    Stream.ReadSingle;
    Model.Materials[I].TextureIndex := Stream.ReadSignedIndex(Stream.TextureIndexSize);
    Stream.ReadSignedIndex(Stream.TextureIndexSize);
    Stream.ReadByte;
    ToonReference := Stream.ReadByte;
    case ToonReference of
      0: Stream.ReadSignedIndex(Stream.TextureIndexSize);
      1: Stream.ReadByte;
    else
      raise EPmxFormatError.CreateFmt('Invalid PMX toon reference: %d', [ToonReference]);
    end;
    Stream.ReadText;
    Model.Materials[I].SurfaceStart := SurfaceCursor;
    Model.Materials[I].SurfaceCount := Stream.ReadInt32;
    CheckPmxCount(Model.Materials[I].SurfaceCount, Length(Model.Indices),
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

end.
