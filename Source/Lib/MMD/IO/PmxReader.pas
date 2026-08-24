unit PmxReader;

// 分割されたPMX読込処理を順序制御し、絶対パス単位の読取専用キャッシュを提供する。

interface

uses
  PmxModel;

// 絶対パス単位の共有キャッシュから不変Modelを返し、未読込時だけPMXを解析する。
function GetCachedPmxModel(const FileName: string): TPmxModel;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  PmxBinaryStream,
  PmxBoneReader,
  PmxGeometryReader,
  PmxMaterialReader;

var
  ModelCache: TObjectDictionary<string, TPmxModel>;
  ModelCacheLock: TObject;

function LoadPmxModel(const FileName: string): TPmxModel;
var
  Stream: TPmxBinaryStream;
begin
  Stream := TPmxBinaryStream.Create(FileName);
  try
    Result := TPmxModel.Create;
    try
      Result.SourcePath := TPath.GetFullPath(FileName);
      ReadPmxHeader(Stream, Result);
      ReadPmxVertices(Stream, Result);
      ReadPmxSurfaces(Stream, Result);
      ReadPmxTextures(Stream, Result);
      ReadPmxMaterials(Stream, Result);
      ReadPmxBones(Stream, Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

function GetCachedPmxModel(const FileName: string): TPmxModel;
var
  CacheKey: string;
begin
  CacheKey := LowerCase(TPath.GetFullPath(FileName));
  // 解析済みModelは以後変更しないため、全表示オブジェクトで同じ実体を共有できる。
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
