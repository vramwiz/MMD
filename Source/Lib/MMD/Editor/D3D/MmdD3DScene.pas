unit MmdD3DScene;

// PMX姿勢から、カメラに依存しないD3Dプレビュー頂点と投影範囲を生成する。

interface

uses
  PmxModel,
  PmxMorph,
  PmxPose;

type
  TMmdPreviewVertex = packed record
    X, Y, Z: Single;
    R, G, B, A: Single;
    U, V: Single;
    NormalX, NormalY, NormalZ: Single;
    Lighting: Single;
  end;
  TMmdPreviewVertices = array of TMmdPreviewVertex;
  TMmdPreviewBatch = record
    FirstVertex: Integer;
    VertexCount: Integer;
    TextureIndex: Integer;
  end;
  TMmdPreviewBatches = array of TMmdPreviewBatch;
  TMmdPreviewBoneSegment = record
    BoneIndex: Integer;
    StartBoneIndex: Integer;
    StartPosition: TPmxVector3;
    EndPosition: TPmxVector3;
  end;
  TMmdPreviewBoneSegments = array of TMmdPreviewBoneSegment;
  TMmdPreviewTargetKind = (ptNone, ptJoint, ptBone);
  TMmdPreviewTarget = record
    Kind: TMmdPreviewTargetKind;
    JointIndex: Integer;
    BoneIndex: Integer;
    Locked: Boolean;
  end;
  TMmdPreviewJoint = record
    BoneIndex: Integer;
    Position: TPmxVector3;
  end;
  TMmdPreviewJoints = array of TMmdPreviewJoint;
  TMmdPreviewProjection = record
    ModelWidth: Single;
    ModelHeight: Single;
    Radius: Single;
  end;
  TMmdPreviewScene = record
    Triangles: TMmdPreviewVertices;
    Batches: TMmdPreviewBatches;
    BoneLines: TMmdPreviewVertices;
    BoneShapes: TMmdPreviewVertices;
    BoneSegments: TMmdPreviewBoneSegments;
    Joints: TMmdPreviewJoints;
    Center: TPmxVector3;
    Projection: TMmdPreviewProjection;
  end;
  TMmdPreviewCamera = record
    Yaw: Single;
    Pitch: Single;
    Zoom: Single;
    PanX: Single;
    PanY: Single;
  end;

// CPUスキニングを行い、モデル中心を原点とするプレビュー頂点を構築する。
procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget;
  out Scene: TMmdPreviewScene);
// 初回に決めた中心と投影範囲を維持し、姿勢頂点と骨格だけを再構築する。
procedure BuildPreviewSceneWithFrame(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget; const Center: TPmxVector3;
  const Projection: TMmdPreviewProjection; out Scene: TMmdPreviewScene);
// モデル頂点を再生成せず、姿勢に追従する骨格線と関節位置だけを構築する。
procedure BuildPreviewSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget;
  const Center: TPmxVector3; out BoneLines: TMmdPreviewVertices;
  out BoneSegments: TMmdPreviewBoneSegments; out Joints: TMmdPreviewJoints);
// 対象なしを表す、各番号が-1の選択値を返す。
function EmptyPreviewTarget: TMmdPreviewTarget;
// 正面表示、等倍の初期カメラ値を返す。
function DefaultPreviewCamera: TMmdPreviewCamera;
// GPUシェーダーと同じ計算で、テスト用にモデル座標をNDCへ投影する。
function ProjectPreviewPosition(const Position: TPmxVector3;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight: Integer): TPmxVector3;

implementation

uses
  System.Math,
  MmdD3DDeform;

function DefaultPreviewCamera: TMmdPreviewCamera;
begin
  Result := Default(TMmdPreviewCamera);
  Result.Zoom := 1.0;
end;

function EmptyPreviewTarget: TMmdPreviewTarget;
begin
  Result := Default(TMmdPreviewTarget);
  Result.Kind := ptNone;
  Result.JointIndex := -1;
  Result.BoneIndex := -1;
end;

function RotatePosition(const Position: TPmxVector3;
  const Camera: TMmdPreviewCamera): TPmxVector3;
var
  CosPitch, CosYaw, SinPitch, SinYaw: Single;
  Z: Single;
begin
  SinCos(Camera.Yaw, SinYaw, CosYaw);
  SinCos(Camera.Pitch, SinPitch, CosPitch);
  Result.X := Position.X * CosYaw + Position.Z * SinYaw;
  Z := -Position.X * SinYaw + Position.Z * CosYaw;
  Result.Y := Position.Y * CosPitch - Z * SinPitch;
  Result.Z := Position.Y * SinPitch + Z * CosPitch;
end;

function ProjectPreviewPosition(const Position: TPmxVector3;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight: Integer): TPmxVector3;
var
  PixelScale: Single;
  Rotated: TPmxVector3;
begin
  ViewWidth := Max(ViewWidth, 1);
  ViewHeight := Max(ViewHeight, 1);
  Rotated := RotatePosition(Position, Camera);
  PixelScale := 0.9 * EnsureRange(Camera.Zoom, 0.2, 5.0) *
    Min(ViewWidth / Projection.ModelWidth, ViewHeight / Projection.ModelHeight);
  Result.X := Rotated.X * 2.0 * PixelScale / ViewWidth;
  Result.X := Result.X + Camera.PanX * 2.0 / ViewWidth;
  Result.Y := Rotated.Y * 2.0 * PixelScale / ViewHeight;
  Result.Y := Result.Y - Camera.PanY * 2.0 / ViewHeight;
  Result.Z := 0.5 + Rotated.Z * 0.45 / Projection.Radius;
end;

procedure SetVertex(var Vertex: TMmdPreviewVertex; const Position,
  Center: TPmxVector3; const UV: TPmxVector2; const Normal: TPmxVector3;
  Lighting, R, G, B, A: Single);
begin
  Vertex.X := Position.X - Center.X;
  Vertex.Y := Position.Y - Center.Y;
  Vertex.Z := Position.Z - Center.Z;
  Vertex.R := R;
  Vertex.G := G;
  Vertex.B := B;
  Vertex.A := A;
  Vertex.U := UV.X;
  Vertex.V := UV.Y;
  Vertex.NormalX := Normal.X;
  Vertex.NormalY := Normal.Y;
  Vertex.NormalZ := Normal.Z;
  Vertex.Lighting := Lighting;
end;

procedure CalculateBounds(const Vertices: TPmxSkinnedVertices;
  out BoundsMin, BoundsMax: TPmxVector3);
var
  Index: Integer;
  Position: TPmxVector3;
begin
  BoundsMin := Vertices[0].Position;
  BoundsMax := BoundsMin;
  for Index := 1 to High(Vertices) do
  begin
    Position := Vertices[Index].Position;
    BoundsMin.X := Min(BoundsMin.X, Position.X);
    BoundsMin.Y := Min(BoundsMin.Y, Position.Y);
    BoundsMin.Z := Min(BoundsMin.Z, Position.Z);
    BoundsMax.X := Max(BoundsMax.X, Position.X);
    BoundsMax.Y := Max(BoundsMax.Y, Position.Y);
    BoundsMax.Z := Max(BoundsMax.Z, Position.Z);
  end;
end;

procedure BuildTriangles(const Model: TPmxModel;
  const Skinned: TPmxSkinnedVertices; const Center: TPmxVector3;
  out Vertices: TMmdPreviewVertices; out Batches: TMmdPreviewBatches);
var
  BatchCount: Integer;
  IndexOffset: Integer;
  Material: TPmxMaterial;
  MaterialIndex: Integer;
  Normal: TPmxVector3;
  Position: TPmxVector3;
  SourceIndex: Integer;
  VertexIndex: Integer;
begin
  SetLength(Vertices, Length(Model.Indices));
  SetLength(Batches, Length(Model.Materials));
  VertexIndex := 0;
  BatchCount := 0;
  for MaterialIndex := 0 to High(Model.Materials) do
  begin
    Material := Model.Materials[MaterialIndex];
    if Material.Diffuse.W <= 0.0001 then
      Continue;
    Batches[BatchCount].FirstVertex := VertexIndex;
    Batches[BatchCount].TextureIndex := Material.TextureIndex;
    for IndexOffset := 0 to Material.SurfaceCount - 1 do
    begin
      SourceIndex := Model.Indices[Material.SurfaceStart + IndexOffset];
      Position := Skinned[SourceIndex].Position;
      Normal := Skinned[SourceIndex].Normal;
      SetVertex(Vertices[VertexIndex], Position, Center,
        Model.Vertices[SourceIndex].UV, Normal, 1.0,
        EnsureRange(Material.Diffuse.X, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Y, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Z, 0.0, 1.0),
        EnsureRange(Material.Diffuse.W, 0.0, 1.0));
      Inc(VertexIndex);
    end;
    Batches[BatchCount].VertexCount :=
      VertexIndex - Batches[BatchCount].FirstVertex;
    Inc(BatchCount);
  end;
  SetLength(Vertices, VertexIndex);
  SetLength(Batches, BatchCount);
end;

procedure BuildBoneLines(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const Center: TPmxVector3;
  const SelectedTarget, HoverTarget: TMmdPreviewTarget;
  out Vertices: TMmdPreviewVertices; out Segments: TMmdPreviewBoneSegments;
  out Joints: TMmdPreviewJoints);
var
  B, G, R: Single;
  BoneIndex: Integer;
  ParentIndex: Integer;
  VertexIndex: Integer;
  SegmentIndex: Integer;
  EmptyUV: TPmxVector2;
  EmptyNormal: TPmxVector3;
begin
  EmptyUV := Default(TPmxVector2);
  EmptyNormal := Default(TPmxVector3);
  SetLength(Vertices, Length(Model.Bones) * 2);
  SetLength(Segments, Length(Model.Bones));
  SetLength(Joints, Length(Model.Bones));
  VertexIndex := 0;
  SegmentIndex := 0;
  for BoneIndex := 0 to High(Model.Bones) do
  begin
    ParentIndex := Model.Bones[BoneIndex].ParentIndex;
    if ParentIndex < 0 then
      Continue;
    if (SelectedTarget.Kind = ptBone) and
      (BoneIndex = SelectedTarget.BoneIndex) then
    begin
      R := 1.0;
      if SelectedTarget.Locked then
      begin
        R := 0.55;
        G := 0.03;
        B := 0.06;
      end
      else
      begin
        G := 0.25;
        B := 0.1;
      end;
    end
    else if (HoverTarget.Kind = ptBone) and
      (BoneIndex = HoverTarget.BoneIndex) then
    begin
      R := 1.0;
      G := 0.85;
      B := 0.15;
    end
    else
    begin
      R := 0.1;
      G := 0.9;
      B := 1.0;
    end;
    SetVertex(Vertices[VertexIndex], Transforms[ParentIndex].Position,
      Center, EmptyUV, EmptyNormal, 0.0, R, G, B, 1.0);
    Inc(VertexIndex);
    SetVertex(Vertices[VertexIndex], Transforms[BoneIndex].Position,
      Center, EmptyUV, EmptyNormal, 0.0, R, G, B, 1.0);
    Inc(VertexIndex);
    Segments[SegmentIndex].BoneIndex := BoneIndex;
    Segments[SegmentIndex].StartBoneIndex := ParentIndex;
    Segments[SegmentIndex].StartPosition.X :=
      Transforms[ParentIndex].Position.X - Center.X;
    Segments[SegmentIndex].StartPosition.Y :=
      Transforms[ParentIndex].Position.Y - Center.Y;
    Segments[SegmentIndex].StartPosition.Z :=
      Transforms[ParentIndex].Position.Z - Center.Z;
    Segments[SegmentIndex].EndPosition.X :=
      Transforms[BoneIndex].Position.X - Center.X;
    Segments[SegmentIndex].EndPosition.Y :=
      Transforms[BoneIndex].Position.Y - Center.Y;
    Segments[SegmentIndex].EndPosition.Z :=
      Transforms[BoneIndex].Position.Z - Center.Z;
    Inc(SegmentIndex);
  end;
  for BoneIndex := 0 to High(Model.Bones) do
  begin
    Joints[BoneIndex].BoneIndex := BoneIndex;
    Joints[BoneIndex].Position.X := Transforms[BoneIndex].Position.X - Center.X;
    Joints[BoneIndex].Position.Y := Transforms[BoneIndex].Position.Y - Center.Y;
    Joints[BoneIndex].Position.Z := Transforms[BoneIndex].Position.Z - Center.Z;
  end;
  SetLength(Vertices, VertexIndex);
  SetLength(Segments, SegmentIndex);
end;

procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget;
  out Scene: TMmdPreviewScene);
var
  BoundsMax, BoundsMin: TPmxVector3;
  Center: TPmxVector3;
  Depth: Single;
  Skinned: TPmxSkinnedVertices;
  Transforms: TPmxBoneTransforms;
begin
  Scene := Default(TMmdPreviewScene);
  if (Model = nil) or (Length(Model.Vertices) = 0) then
    Exit;
  DeformPreviewModel(Model, Poses, MorphWeights, Transforms, Skinned);
  CalculateBounds(Skinned, BoundsMin, BoundsMax);
  Center.X := (BoundsMin.X + BoundsMax.X) * 0.5;
  Center.Y := (BoundsMin.Y + BoundsMax.Y) * 0.5;
  Center.Z := (BoundsMin.Z + BoundsMax.Z) * 0.5;
  Scene.Center := Center;
  Scene.Projection.ModelWidth := Max(BoundsMax.X - BoundsMin.X, 0.001);
  Scene.Projection.ModelHeight := Max(BoundsMax.Y - BoundsMin.Y, 0.001);
  Depth := Max(BoundsMax.Z - BoundsMin.Z, 0.001);
  Scene.Projection.Radius := Max(0.5 * Sqrt(
    Sqr(Scene.Projection.ModelWidth) + Sqr(Scene.Projection.ModelHeight) +
    Sqr(Depth)), 0.001);
  BuildTriangles(Model, Skinned, Center, Scene.Triangles, Scene.Batches);
  BuildBoneLines(Model, Transforms, Center, SelectedTarget, HoverTarget,
    Scene.BoneLines, Scene.BoneSegments, Scene.Joints);
end;

procedure BuildPreviewSceneWithFrame(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget; const Center: TPmxVector3;
  const Projection: TMmdPreviewProjection; out Scene: TMmdPreviewScene);
var
  Skinned: TPmxSkinnedVertices;
  Transforms: TPmxBoneTransforms;
begin
  Scene := Default(TMmdPreviewScene);
  if (Model = nil) or (Length(Model.Vertices) = 0) then
    Exit;
  DeformPreviewModel(Model, Poses, MorphWeights, Transforms, Skinned);
  Scene.Center := Center;
  Scene.Projection := Projection;
  BuildTriangles(Model, Skinned, Center, Scene.Triangles, Scene.Batches);
  BuildBoneLines(Model, Transforms, Center, SelectedTarget, HoverTarget,
    Scene.BoneLines, Scene.BoneSegments, Scene.Joints);
end;

procedure BuildPreviewSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget;
  const Center: TPmxVector3; out BoneLines: TMmdPreviewVertices;
  out BoneSegments: TMmdPreviewBoneSegments; out Joints: TMmdPreviewJoints);
var
  Transforms: TPmxBoneTransforms;
begin
  BoneLines := nil;
  BoneSegments := nil;
  Joints := nil;
  if Model = nil then
    Exit;
  CalculatePreviewSkeleton(Model, Poses, MorphWeights, Transforms);
  BuildBoneLines(Model, Transforms, Center, SelectedTarget, HoverTarget,
    BoneLines, BoneSegments, Joints);
end;

end.
