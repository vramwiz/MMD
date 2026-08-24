unit MMD_Model_Renderer;

// スキニング結果と骨格をAviUtl2のdraw_polyへ変換して描画する。

interface

uses
  AviUtl2FilterTypes,
  PmxModel,
  PmxPose;

const
  DISPLAY_MODE_MODEL = 0;
  DISPLAY_MODE_BONES = 1;
  DISPLAY_MODE_BOTH = 2;

// 指定表示モードに従って骨格と材質を描画する。Videoの描画状態と画像資源を更新する。
procedure RenderPmxModel(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const Skinned: TPmxSkinnedVertices;
  UseSkinning: Boolean; DisplayMode: Integer; InternalScale,
  BoneOffsetX: Single);

implementation

uses
  System.Math;

type
  TBoneVertices = array of TVERTEX_COLOR;
  TColorNormalVertices = array of TVERTEX_COLOR_NORM;
  TTextureNormalVertices = array of TVERTEX_TEXTURE_NORM;

const
  PMX_MATERIAL_DRAW_BOTH_FACES = $01;
  PMX_BONE_IK = $0020;
  WHITE_PIXEL: TPIXEL_RGBA = (R: 255; G: 255; B: 255; A: 255);
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

procedure SetTransformedNormal(var X, Y, Z: Single; const Normal: TPmxVector3);
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

procedure BuildBoneVertices(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; UsePose: Boolean; InternalScale,
  OffsetX: Single; var Vertices: TBoneVertices);
var
  AX, AY, AZ, BX, BY, BZ: Single;
  Bone, Parent: TPmxBone;
  BoneIndex, VertexIndex: Integer;
  BonePosition, ParentPosition: TPmxVector3;
  DX, DY, DZ, Length_, PX, PY, PZ: Single;
  R, G, B, Thickness: Single;
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
    if UsePose then
    begin
      ParentPosition := Transforms[Bone.ParentIndex].Position;
      BonePosition := Transforms[BoneIndex].Position;
    end
    else
    begin
      ParentPosition := Parent.Position;
      BonePosition := Bone.Position;
    end;
    SetTransformedPosition(AX, AY, AZ, ParentPosition, InternalScale);
    SetTransformedPosition(BX, BY, BZ, BonePosition, InternalScale);
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
  const Transforms: TPmxBoneTransforms; UsePose: Boolean; InternalScale,
  OffsetX: Single);
begin
  BuildBoneVertices(Model, Transforms, UsePose, InternalScale, OffsetX,
    BoneVertices);
  if (Length(BoneVertices) = 0) or not Assigned(Video^.SetImageData) then
    Exit;
  Video^.SetImageData(@WHITE_PIXEL, 1, 1);
  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(0);
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(0.0);
  Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR, @BoneVertices[0],
    Length(BoneVertices), 'object');
end;

procedure GetVertexGeometry(const Model: TPmxModel;
  const Skinned: TPmxSkinnedVertices; SourceIndex: Integer;
  UseSkinning: Boolean; var Position, Normal: TPmxVector3);
begin
  if UseSkinning then
  begin
    Position := Skinned[SourceIndex].Position;
    Normal := Skinned[SourceIndex].Normal;
  end
  else
  begin
    Position := Model.Vertices[SourceIndex].Position;
    Normal := Model.Vertices[SourceIndex].Normal;
  end;
end;

procedure BuildTextureVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; const Skinned: TPmxSkinnedVertices;
  UseSkinning: Boolean; InternalScale: Single;
  var Vertices: TTextureNormalVertices);
var
  ExpandedOffset, SourceIndex: Integer;
  Normal, Position: TPmxVector3;
  Vertex: TPmxVertex;
begin
  SetLength(Vertices, Material.SurfaceCount);
  for ExpandedOffset := 0 to Material.SurfaceCount - 1 do
  begin
    SourceIndex := Model.Indices[Material.SurfaceStart +
      SourceIndexOffset(ExpandedOffset)];
    Vertex := Model.Vertices[SourceIndex];
    GetVertexGeometry(Model, Skinned, SourceIndex, UseSkinning, Position, Normal);
    SetTransformedPosition(Vertices[ExpandedOffset].X, Vertices[ExpandedOffset].Y,
      Vertices[ExpandedOffset].Z, Position, InternalScale);
    Vertices[ExpandedOffset].U := Vertex.UV.X;
    Vertices[ExpandedOffset].V := Vertex.UV.Y;
    Vertices[ExpandedOffset].A := EnsureRange(Material.Diffuse.W, 0.0, 1.0);
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Normal);
  end;
end;

procedure BuildColorVertices(const Model: TPmxModel;
  const Material: TPmxMaterial; const Skinned: TPmxSkinnedVertices;
  UseSkinning: Boolean; InternalScale: Single;
  var Vertices: TColorNormalVertices);
var
  Alpha: Single;
  ExpandedOffset, SourceIndex: Integer;
  Normal, Position: TPmxVector3;
begin
  SetLength(Vertices, Material.SurfaceCount);
  Alpha := EnsureRange(Material.Diffuse.W, 0.0, 1.0);
  for ExpandedOffset := 0 to Material.SurfaceCount - 1 do
  begin
    SourceIndex := Model.Indices[Material.SurfaceStart +
      SourceIndexOffset(ExpandedOffset)];
    GetVertexGeometry(Model, Skinned, SourceIndex, UseSkinning, Position, Normal);
    SetTransformedPosition(Vertices[ExpandedOffset].X, Vertices[ExpandedOffset].Y,
      Vertices[ExpandedOffset].Z, Position, InternalScale);
    Vertices[ExpandedOffset].R := EnsureRange(Material.Diffuse.X, 0.0, 1.0);
    Vertices[ExpandedOffset].G := EnsureRange(Material.Diffuse.Y, 0.0, 1.0);
    Vertices[ExpandedOffset].B := EnsureRange(Material.Diffuse.Z, 0.0, 1.0);
    Vertices[ExpandedOffset].A := Alpha;
    SetTransformedNormal(Vertices[ExpandedOffset].VX, Vertices[ExpandedOffset].VY,
      Vertices[ExpandedOffset].VZ, Normal);
  end;
end;

procedure DrawMaterial(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  const Material: TPmxMaterial; const Skinned: TPmxSkinnedVertices;
  UseSkinning: Boolean; InternalScale: Single; ForceDoubleSided: Boolean);
var
  HasTexture: Boolean;
  Resource: string;
begin
  if (Material.SurfaceCount = 0) or (Material.Diffuse.W <= 0.0001) then
    Exit;
  if Assigned(Video^.SetCullingState) then
    Video^.SetCullingState(Ord(not ForceDoubleSided and
      ((Material.Flags and PMX_MATERIAL_DRAW_BOTH_FACES) = 0)));
  if Assigned(Video^.SetMaterialShine) then
    Video^.SetMaterialShine(EnsureRange(Material.SpecularStrength, 0.0, 1.0));
  HasTexture := (Material.TextureIndex >= 0) and
    Model.TextureAvailable[Material.TextureIndex];
  if HasTexture then
  begin
    BuildTextureVertices(Model, Material, Skinned, UseSkinning, InternalScale,
      TextureVertices);
    Resource := 'image:' + Model.Textures[Material.TextureIndex];
    Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_TEXTURE_NORM, @TextureVertices[0],
      Length(TextureVertices), PWideChar(Resource));
  end
  else
  begin
    BuildColorVertices(Model, Material, Skinned, UseSkinning, InternalScale,
      ColorVertices);
    Video^.DrawPoly(VERTEX_TYPE_TRIANGLE_COLOR_NORM, @ColorVertices[0],
      Length(ColorVertices), nil);
  end;
end;

procedure RenderPmxModel(Video: PFILTER_PROC_VIDEO; const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const Skinned: TPmxSkinnedVertices;
  UseSkinning: Boolean; DisplayMode: Integer; InternalScale,
  BoneOffsetX: Single);
var
  DrawOrderIndex, MaterialIndex: Integer;
begin
  if Assigned(Video^.SetSamplerMode) then
    Video^.SetSamplerMode(SAMPLER_MODE_LOOP);
  if DisplayMode = DISPLAY_MODE_BONES then
    DrawBones(Video, Model, Transforms, UseSkinning, InternalScale, 0.0)
  else
  begin
    if DisplayMode = DISPLAY_MODE_BOTH then
      DrawBones(Video, Model, Transforms, UseSkinning, InternalScale,
        BoneOffsetX * InternalScale);
    // 1オブジェクトの頂点上限内で主要部位を欠落させない検証済み順序を使う。
    for DrawOrderIndex := 0 to High(KIRITAN_CORE_MATERIAL_ORDER) do
    begin
      MaterialIndex := KIRITAN_CORE_MATERIAL_ORDER[DrawOrderIndex];
      if MaterialIndex <= High(Model.Materials) then
        DrawMaterial(Video, Model, Model.Materials[MaterialIndex], Skinned,
          UseSkinning, InternalScale, NeedsDoubleSided(MaterialIndex));
    end;
  end;
end;

end.
