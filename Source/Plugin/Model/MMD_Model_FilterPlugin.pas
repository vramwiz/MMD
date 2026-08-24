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
  BoneOffsetXItem: TFILTER_ITEM_TRACK;
  BonePreviewItem: TFILTER_ITEM_CHECK;
  ModelFileItem: TFILTER_ITEM_FILE;
  ModelScaleItem: TFILTER_ITEM_TRACK;
  PluginTableInitialized: Boolean;

type
  TBoneVertices = array of TVERTEX_COLOR;
  TColorNormalVertices = array of TVERTEX_COLOR_NORM;
  TTextureNormalVertices = array of TVERTEX_TEXTURE_NORM;

const
  PMX_MATERIAL_DRAW_BOTH_FACES = $01;
  PMX_BONE_IK = $0020;
  // draw_polyの1フレーム上限を切り分けるため、検証モデルの本体材質を優先する。
  KIRITAN_CORE_MATERIAL_ORDER: array[0..20] of Integer = (
    0, 1, 2, 3, 4, 6, 12, 14, 15, 16, 28, 29, 30, 34, 35, 36, 9, 8, 11,
    13, 32);

threadvar
  BoneVertices: TBoneVertices;
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

function NeedsDoubleSided(MaterialIndex: Integer): Boolean;
begin
  Result := (MaterialIndex <= 6) or (MaterialIndex = 28);
end;

procedure SetTransformedPosition(var X, Y, Z: Single;
  const Position: TPmxVector3; InternalScale: Single);
begin
  X := Position.X * InternalScale;
  Y := -Position.Y * InternalScale;
  Z := Position.Z * InternalScale;
end;

procedure SetTransformedNormal(var X, Y, Z: Single;
  const Normal: TPmxVector3);
begin
  X := Normal.X;
  Y := -Normal.Y;
  Z := Normal.Z;
end;

procedure SetBoneVertex(var Vertex: TVERTEX_COLOR; X, Y, Z, R, G, B: Single);
begin
  Vertex.X := X;
  Vertex.Y := Y;
  Vertex.Z := Z;
  Vertex.R := R;
  Vertex.G := G;
  Vertex.B := B;
  Vertex.A := 1.0;
end;

procedure AddBoneQuad(var Vertices: TBoneVertices; var VertexIndex: Integer;
  AX, AY, AZ, BX, BY, BZ, PX, PY, PZ, R, G, B: Single);
begin
  SetBoneVertex(Vertices[VertexIndex], AX - PX, AY - PY, AZ - PZ, R, G, B);
  SetBoneVertex(Vertices[VertexIndex + 1], AX + PX, AY + PY, AZ + PZ, R, G, B);
  SetBoneVertex(Vertices[VertexIndex + 2], BX + PX, BY + PY, BZ + PZ, R, G, B);
  SetBoneVertex(Vertices[VertexIndex + 3], AX - PX, AY - PY, AZ - PZ, R, G, B);
  SetBoneVertex(Vertices[VertexIndex + 4], BX + PX, BY + PY, BZ + PZ, R, G, B);
  SetBoneVertex(Vertices[VertexIndex + 5], BX - PX, BY - PY, BZ - PZ, R, G, B);
  Inc(VertexIndex, 6);
end;

procedure BuildBoneVertices(const Model: TPmxModel; InternalScale,
  OffsetX: Single; var Vertices: TBoneVertices);
var
  AX, AY, AZ: Single;
  Bone: TPmxBone;
  BoneIndex: Integer;
  BX, BY, BZ: Single;
  DX, DY, DZ: Single;
  Length_: Single;
  Parent: TPmxBone;
  PX, PY, PZ: Single;
  QX, QY, QZ: Single;
  R, G, B: Single;
  Thickness: Single;
  VertexIndex: Integer;
begin
  SetLength(Vertices, Length(Model.Bones) * 12);
  VertexIndex := 0;
  Thickness := Max(0.5, InternalScale * 0.08);
  for BoneIndex := 0 to High(Model.Bones) do
  begin
    Bone := Model.Bones[BoneIndex];
    if Bone.ParentIndex < 0 then
      Continue;
    Parent := Model.Bones[Bone.ParentIndex];
    SetTransformedPosition(AX, AY, AZ, Parent.Position, InternalScale);
    SetTransformedPosition(BX, BY, BZ, Bone.Position, InternalScale);
    AX := AX + OffsetX;
    BX := BX + OffsetX;
    DX := BX - AX;
    DY := BY - AY;
    DZ := BZ - AZ;
    Length_ := Sqrt(DX * DX + DY * DY + DZ * DZ);
    if Length_ < 0.0001 then
      Continue;
    DX := DX / Length_;
    DY := DY / Length_;
    DZ := DZ / Length_;

    if Abs(DZ) < 0.9 then
    begin
      PX := DY;
      PY := -DX;
      PZ := 0.0;
    end
    else
    begin
      PX := -DZ;
      PY := 0.0;
      PZ := DX;
    end;
    Length_ := Sqrt(PX * PX + PY * PY + PZ * PZ);
    PX := PX / Length_ * Thickness;
    PY := PY / Length_ * Thickness;
    PZ := PZ / Length_ * Thickness;
    QX := (DY * PZ - DZ * PY);
    QY := (DZ * PX - DX * PZ);
    QZ := (DX * PY - DY * PX);

    if (Bone.Flags and PMX_BONE_IK) <> 0 then
    begin
      R := 1.0;
      G := 0.85;
      B := 0.1;
    end
    else
    begin
      R := 0.1;
      G := 0.9;
      B := 1.0;
    end;
    AddBoneQuad(Vertices, VertexIndex, AX, AY, AZ, BX, BY, BZ,
      PX, PY, PZ, R, G, B);
    AddBoneQuad(Vertices, VertexIndex, AX, AY, AZ, BX, BY, BZ,
      QX, QY, QZ, R, G, B);
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure DrawBones(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  InternalScale, OffsetX: Single);
begin
  BuildBoneVertices(Model, InternalScale, OffsetX, BoneVertices);
  if Length(BoneVertices) = 0 then
    Exit;
  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(0);
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(0.0);
  Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR, @BoneVertices[0],
    Length(BoneVertices), nil);
end;

procedure BuildTextureVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; InternalScale: Single;
  var Vertices: TTextureNormalVertices);
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
      Vertices[ExpandedOffset].Z, Vertex.Position, InternalScale);
    Vertices[ExpandedOffset].U := Vertex.UV.X;
    Vertices[ExpandedOffset].V := Vertex.UV.Y;
    Vertices[ExpandedOffset].A := EnsureRange(Material.Diffuse.W, 0.0, 1.0);
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Vertex.Normal);
  end;
end;

procedure BuildColorVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; InternalScale: Single;
  var Vertices: TColorNormalVertices);
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
      Vertices[ExpandedOffset].Z, Vertex.Position, InternalScale);
    Vertices[ExpandedOffset].R := EnsureRange(Material.Diffuse.X, 0.0, 1.0);
    Vertices[ExpandedOffset].G := EnsureRange(Material.Diffuse.Y, 0.0, 1.0);
    Vertices[ExpandedOffset].B := EnsureRange(Material.Diffuse.Z, 0.0, 1.0);
    Vertices[ExpandedOffset].A := Alpha;
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Vertex.Normal);
  end;
end;

function DrawMaterial(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  const Material: TPmxMaterial; InternalScale: Single;
  ForceDoubleSided: Boolean): Boolean;
var
  HasTexture: Boolean;
  Resource: string;
begin
  if (Material.SurfaceCount = 0) or (Material.Diffuse.W <= 0.0001) then
    Exit(True);

  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(Ord(not ForceDoubleSided and
      ((Material.Flags and PMX_MATERIAL_DRAW_BOTH_FACES) = 0)));
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(EnsureRange(Material.SpecularStrength, 0.0, 1.0));

  HasTexture := (Material.TextureIndex >= 0) and
    Model.TextureAvailable[Material.TextureIndex];
  if HasTexture then
  begin
    BuildTextureVertices(Model, Material, InternalScale, TextureVertices);
    Resource := 'image:' + Model.Textures[Material.TextureIndex];
    Result := Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_TEXTURE_NORM,
      @TextureVertices[0], Length(TextureVertices), PWideChar(Resource)) <> 0;
  end
  else
  begin
    BuildColorVertices(Model, Material, InternalScale, ColorVertices);
    Result := Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR_NORM,
      @ColorVertices[0], Length(ColorVertices), nil) <> 0;
  end;
end;

function ModelProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  DrawOrderIndex: Integer;
  InternalScale: Single;
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
    InternalScale := EnsureRange(ModelScaleItem.Value, 0.1, 100.0);
    if Assigned(Video^.SetSamplerMode) then
      Video^.SetSamplerMode(SAMPLER_MODE_LOOP);
    // モデル描画後では頂点キュー上限に達するため、確認用ボーンを先に描く。
    if BonePreviewItem.Value <> 0 then
      DrawBones(Video, Model, InternalScale,
        EnsureRange(BoneOffsetXItem.Value, -100.0, 100.0) * InternalScale);
    for DrawOrderIndex := 0 to High(KIRITAN_CORE_MATERIAL_ORDER) do
    begin
      MaterialIndex := KIRITAN_CORE_MATERIAL_ORDER[DrawOrderIndex];
      if MaterialIndex <= High(Model.Materials) then
        DrawMaterial(Video, Model, Model.Materials[MaterialIndex], InternalScale,
          NeedsDoubleSided(MaterialIndex));
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
    AddTrack(ModelScaleItem, 'MMD倍率', 15.0, 0.1, 100.0, 0.1);
    AddCheck(BonePreviewItem, 'ボーン表示', 0);
    AddTrack(BoneOffsetXItem, 'ボーンXずらし', 30.0, -100.0, 100.0, 1.0);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
