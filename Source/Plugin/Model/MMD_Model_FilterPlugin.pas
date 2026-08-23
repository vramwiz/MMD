unit MMD_Model_FilterPlugin;

// モデル表示Filterの登録と、PMX静止モデルの3D描画を担当する。

interface

uses
  AviUtl2FilterTypes;

function GetModelFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Math,
  System.SysUtils,
  PluginFilterTable,
  PmxModel,
  PmxReader;

var
  ModelFileItem: TFILTER_ITEM_FILE;
  PluginTableInitialized: Boolean;

type
  TColorNormalVertices = array of TVERTEX_COLOR_NORM;
  TTextureNormalVertices = array of TVERTEX_TEXTURE_NORM;

const
  PMX_INTERNAL_SCALE = 15.0;
  PMX_MATERIAL_DRAW_BOTH_FACES = $01;
  // draw_polyの1フレーム上限を切り分けるため、検証モデルの本体材質を優先する。
  KIRITAN_CORE_MATERIAL_ORDER: array[0..20] of Integer = (
    0, 1, 2, 3, 4, 6, 12, 14, 15, 16, 28, 29, 30, 34, 35, 36, 9, 8, 11,
    13, 32);

threadvar
  ColorVertices: TColorNormalVertices;
  TextureVertices: TTextureNormalVertices;

function SourceIndexOffset(ExpandedOffset: Integer): Integer;
begin
  case ExpandedOffset mod 3 of
    0: Result := ExpandedOffset;
    1: Result := ExpandedOffset + 1;
  else
    Result := ExpandedOffset - 1;
  end;
end;

procedure SetTransformedPosition(var X, Y, Z: Single;
  const Position: TPmxVector3);
begin
  X := Position.X * PMX_INTERNAL_SCALE;
  Y := -Position.Y * PMX_INTERNAL_SCALE;
  Z := Position.Z * PMX_INTERNAL_SCALE;
end;

procedure SetTransformedNormal(var X, Y, Z: Single;
  const Normal: TPmxVector3);
begin
  X := Normal.X;
  Y := -Normal.Y;
  Z := Normal.Z;
end;

procedure BuildTextureVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; var Vertices: TTextureNormalVertices);
var
  ExpandedOffset: Integer;
  SourceIndex: Integer;
  Vertex: TPmxVertex;
begin
  SetLength(Vertices, Material.SurfaceCount);
  for ExpandedOffset := 0 to Material.SurfaceCount - 1 do
  begin
    SourceIndex := Model.Indices[Material.SurfaceStart +
      SourceIndexOffset(ExpandedOffset)];
    Vertex := Model.Vertices[SourceIndex];
    SetTransformedPosition(Vertices[ExpandedOffset].X, Vertices[ExpandedOffset].Y,
      Vertices[ExpandedOffset].Z, Vertex.Position);
    Vertices[ExpandedOffset].U := Vertex.UV.X;
    Vertices[ExpandedOffset].V := Vertex.UV.Y;
    Vertices[ExpandedOffset].A := EnsureRange(Material.Diffuse.W, 0.0, 1.0);
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Vertex.Normal);
  end;
end;

procedure BuildColorVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; var Vertices: TColorNormalVertices);
var
  Alpha: Single;
  ExpandedOffset: Integer;
  SourceIndex: Integer;
  Vertex: TPmxVertex;
begin
  SetLength(Vertices, Material.SurfaceCount);
  Alpha := EnsureRange(Material.Diffuse.W, 0.0, 1.0);
  for ExpandedOffset := 0 to Material.SurfaceCount - 1 do
  begin
    SourceIndex := Model.Indices[Material.SurfaceStart +
      SourceIndexOffset(ExpandedOffset)];
    Vertex := Model.Vertices[SourceIndex];
    SetTransformedPosition(Vertices[ExpandedOffset].X, Vertices[ExpandedOffset].Y,
      Vertices[ExpandedOffset].Z, Vertex.Position);
    Vertices[ExpandedOffset].R := EnsureRange(Material.Diffuse.X, 0.0, 1.0);
    Vertices[ExpandedOffset].G := EnsureRange(Material.Diffuse.Y, 0.0, 1.0);
    Vertices[ExpandedOffset].B := EnsureRange(Material.Diffuse.Z, 0.0, 1.0);
    Vertices[ExpandedOffset].A := Alpha;
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Vertex.Normal);
  end;
end;

function DrawMaterial(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  const Material: TPmxMaterial): Boolean;
var
  HasTexture: Boolean;
  Resource: string;
begin
  if (Material.SurfaceCount = 0) or (Material.Diffuse.W <= 0.0001) then
    Exit(True);

  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(Ord((Material.Flags and
      PMX_MATERIAL_DRAW_BOTH_FACES) = 0));
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(EnsureRange(Material.SpecularStrength, 0.0, 1.0));

  HasTexture := (Material.TextureIndex >= 0) and
    Model.TextureAvailable[Material.TextureIndex];
  if HasTexture then
  begin
    BuildTextureVertices(Model, Material, TextureVertices);
    Resource := 'image:' + Model.Textures[Material.TextureIndex];
    Result := Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_TEXTURE_NORM,
      @TextureVertices[0], Length(TextureVertices), PWideChar(Resource)) <> 0;
  end
  else
  begin
    BuildColorVertices(Model, Material, ColorVertices);
    Result := Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR_NORM,
      @ColorVertices[0], Length(ColorVertices), nil) <> 0;
  end;
end;

function ModelProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  DrawOrderIndex: Integer;
  MaterialIndex: Integer;
  Model: TPmxModel;
  ModelFileName: string;
begin
  Result := 1;
  try
    if (Video = nil) or not Assigned(Video^.DrawPoly) or
      (ModelFileItem.Value = nil) then
      Exit;
    ModelFileName := string(ModelFileItem.Value);
    if ModelFileName = '' then
      Exit;

    Model := GetCachedPmxModel(ModelFileName);
    if Assigned(Video^.SetSamplerMode) then
      Video^.SetSamplerMode(SAMPLER_MODE_LOOP);
    for DrawOrderIndex := 0 to High(KIRITAN_CORE_MATERIAL_ORDER) do
    begin
      MaterialIndex := KIRITAN_CORE_MATERIAL_ORDER[DrawOrderIndex];
      if MaterialIndex <= High(Model.Materials) then
        DrawMaterial(Video, Model, Model.Materials[MaterialIndex]);
    end;
    if Assigned(Video^.SetDefaultAnchor) then
      Video^.SetDefaultAnchor(640, 640);
    // フレームバッファへ直接描画した後は、空のオブジェクト画像を描く後続処理を中断する。
    Result := 0;
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
end;

function GetModelFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT,
      'モデル表示', 'MMD', 'PMXモデルをAviUtl2の3D空間へ表示するフィルター',
      ModelProcVideo, nil);
    AddFile(ModelFileItem, 'モデルファイル', '',
      'PMXモデル (*.pmx)'#0'*.pmx'#0 +
      'すべてのファイル (*.*)'#0'*.*'#0#0);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
