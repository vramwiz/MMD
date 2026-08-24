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
  DisplayModeItem: TFILTER_ITEM_SELECT;
  DisplayModeItems: array[0..3] of TFILTER_ITEM_SELECT_ITEM;
  ModelFileItem: TFILTER_ITEM_FILE;
  ModelScaleItem: TFILTER_ITEM_TRACK;
  PluginTableInitialized: Boolean;

type
  TBoneVertices = array of TVERTEX_COLOR;
  TColorNormalVertices = array of TVERTEX_COLOR_NORM;
  TTextureNormalVertices = array of TVERTEX_TEXTURE_NORM;

const
  DISPLAY_MODE_MODEL = 0;
  DISPLAY_MODE_BONES = 1;
  DISPLAY_MODE_BOTH = 2;
  PMX_MATERIAL_DRAW_BOTH_FACES = $01;
  PMX_BONE_IK = $0020;
  WHITE_PIXEL: TPIXEL_RGBA = (R: 255; G: 255; B: 255; A: 255);
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
  R, G, B: Single;
  Thickness: Single;
  VertexIndex: Integer;
begin
  SetLength(Vertices, Length(Model.Bones) * 3);
  VertexIndex := 0;
  Thickness := Max(0.75, InternalScale * 0.1);
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
    SetBoneVertex(Vertices[VertexIndex], AX - PX, AY - PY, AZ - PZ, R, G, B);
    SetBoneVertex(Vertices[VertexIndex + 1], AX + PX, AY + PY, AZ + PZ, R, G, B);
    SetBoneVertex(Vertices[VertexIndex + 2], BX, BY, BZ, R, G, B);
    Inc(VertexIndex, 3);
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure DrawBones(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  InternalScale, OffsetX: Single);
begin
  BuildBoneVertices(Model, InternalScale, OffsetX, BoneVertices);
  if (Length(BoneVertices) = 0) or not Assigned(Video^.SetImageData) then
    Exit;
  // v2.1.6aは頂点カラーでもnilの画像リソースを拒否する。
  Video^.SetImageData(@WHITE_PIXEL, 1, 1);
  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(0);
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(0.0);
  Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR, @BoneVertices[0],
    Length(BoneVertices), 'object');
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
  DisplayMode: Integer;
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
    DisplayMode := EnsureRange(DisplayModeItem.Value, DISPLAY_MODE_MODEL,
      DISPLAY_MODE_BOTH);
    if Assigned(Video^.SetSamplerMode) then
      Video^.SetSamplerMode(SAMPLER_MODE_LOOP);
    if DisplayMode = DISPLAY_MODE_BONES then
      DrawBones(Video, Model, InternalScale, 0.0)
    else
    begin
      if DisplayMode = DISPLAY_MODE_BOTH then
        DrawBones(Video, Model, InternalScale,
          EnsureRange(BoneOffsetXItem.Value, -100.0, 100.0) * InternalScale);
      for DrawOrderIndex := 0 to High(KIRITAN_CORE_MATERIAL_ORDER) do
      begin
        MaterialIndex := KIRITAN_CORE_MATERIAL_ORDER[DrawOrderIndex];
        if MaterialIndex <= High(Model.Materials) then
          DrawMaterial(Video, Model, Model.Materials[MaterialIndex], InternalScale,
            NeedsDoubleSided(MaterialIndex));
      end;
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
    DisplayModeItems[0].Name := '標準';
    DisplayModeItems[0].Value := DISPLAY_MODE_MODEL;
    DisplayModeItems[1].Name := 'ボーンのみ';
    DisplayModeItems[1].Value := DISPLAY_MODE_BONES;
    DisplayModeItems[2].Name := '両方';
    DisplayModeItems[2].Value := DISPLAY_MODE_BOTH;
    DisplayModeItems[3].Name := nil;
    DisplayModeItems[3].Value := 0;
    AddSelect(DisplayModeItem, '表示モード', DISPLAY_MODE_MODEL,
      @DisplayModeItems[0]);
    AddTrack(ModelScaleItem, 'MMD倍率', 15.0, 0.1, 100.0, 0.1);
    AddTrack(BoneOffsetXItem, 'ボーンXずらし', 30.0, -100.0, 100.0, 1.0);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
