unit MmdD3DScene;

// PMX姿勢から、カメラに依存しないD3Dプレビュー頂点と投影範囲を生成する。

interface

uses
  PmxModel,
  PmxPose;

type
  TMmdPreviewVertex = packed record
    X, Y, Z: Single;
    R, G, B, A: Single;
  end;
  TMmdPreviewVertices = array of TMmdPreviewVertex;
  TMmdPreviewProjection = record
    ModelWidth: Single;
    ModelHeight: Single;
    Radius: Single;
  end;
  TMmdPreviewScene = record
    Triangles: TMmdPreviewVertices;
    BoneLines: TMmdPreviewVertices;
    Projection: TMmdPreviewProjection;
  end;
  TMmdPreviewCamera = record
    Yaw: Single;
    Pitch: Single;
    Zoom: Single;
  end;

// CPUスキニングを行い、モデル中心を原点とするプレビュー頂点を構築する。
procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  SelectedBone: Integer; out Scene: TMmdPreviewScene);
// 正面表示、等倍の初期カメラ値を返す。
function DefaultPreviewCamera: TMmdPreviewCamera;
// GPUシェーダーと同じ計算で、テスト用にモデル座標をNDCへ投影する。
function ProjectPreviewPosition(const Position: TPmxVector3;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight: Integer): TPmxVector3;

implementation

uses
  System.Math;

function DefaultPreviewCamera: TMmdPreviewCamera;
begin
  Result := Default(TMmdPreviewCamera);
  Result.Zoom := 1.0;
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
  Result.Y := Rotated.Y * 2.0 * PixelScale / ViewHeight;
  Result.Z := 0.5 + Rotated.Z * 0.45 / Projection.Radius;
end;

procedure SetVertex(var Vertex: TMmdPreviewVertex; const Position,
  Center: TPmxVector3; R, G, B, A: Single);
begin
  Vertex.X := Position.X - Center.X;
  Vertex.Y := Position.Y - Center.Y;
  Vertex.Z := Position.Z - Center.Z;
  Vertex.R := R;
  Vertex.G := G;
  Vertex.B := B;
  Vertex.A := A;
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
  out Vertices: TMmdPreviewVertices);
var
  IndexOffset: Integer;
  Material: TPmxMaterial;
  MaterialIndex: Integer;
  Normal: TPmxVector3;
  Position: TPmxVector3;
  Shade: Single;
  SourceIndex: Integer;
  VertexIndex: Integer;
begin
  SetLength(Vertices, Length(Model.Indices));
  VertexIndex := 0;
  for MaterialIndex := 0 to High(Model.Materials) do
  begin
    Material := Model.Materials[MaterialIndex];
    if Material.Diffuse.W <= 0.0001 then
      Continue;
    for IndexOffset := 0 to Material.SurfaceCount - 1 do
    begin
      SourceIndex := Model.Indices[Material.SurfaceStart + IndexOffset];
      Position := Skinned[SourceIndex].Position;
      Normal := Skinned[SourceIndex].Normal;
      Shade := EnsureRange(0.35 + 0.65 * Abs(
        Normal.X * 0.25 + Normal.Y * 0.55 - Normal.Z * 0.8), 0.2, 1.0);
      SetVertex(Vertices[VertexIndex], Position, Center,
        EnsureRange(Material.Diffuse.X * Shade, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Y * Shade, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Z * Shade, 0.0, 1.0), 1.0);
      Inc(VertexIndex);
    end;
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure BuildBoneLines(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const Center: TPmxVector3;
  SelectedBone: Integer; out Vertices: TMmdPreviewVertices);
var
  B, G, R: Single;
  BoneIndex: Integer;
  ParentIndex: Integer;
  VertexIndex: Integer;
begin
  SetLength(Vertices, Length(Model.Bones) * 2);
  VertexIndex := 0;
  for BoneIndex := 0 to High(Model.Bones) do
  begin
    ParentIndex := Model.Bones[BoneIndex].ParentIndex;
    if ParentIndex < 0 then
      Continue;
    if (BoneIndex = SelectedBone) or (ParentIndex = SelectedBone) then
    begin
      R := 1.0;
      G := 0.25;
      B := 0.1;
    end
    else
    begin
      R := 0.1;
      G := 0.9;
      B := 1.0;
    end;
    SetVertex(Vertices[VertexIndex], Transforms[ParentIndex].Position,
      Center, R, G, B, 1.0);
    Inc(VertexIndex);
    SetVertex(Vertices[VertexIndex], Transforms[BoneIndex].Position,
      Center, R, G, B, 1.0);
    Inc(VertexIndex);
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  SelectedBone: Integer; out Scene: TMmdPreviewScene);
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
  CalculateBoneTransforms(Model, Poses, Transforms);
  SkinVerticesLinear(Model, Transforms, Skinned);
  CalculateBounds(Skinned, BoundsMin, BoundsMax);
  Center.X := (BoundsMin.X + BoundsMax.X) * 0.5;
  Center.Y := (BoundsMin.Y + BoundsMax.Y) * 0.5;
  Center.Z := (BoundsMin.Z + BoundsMax.Z) * 0.5;
  Scene.Projection.ModelWidth := Max(BoundsMax.X - BoundsMin.X, 0.001);
  Scene.Projection.ModelHeight := Max(BoundsMax.Y - BoundsMin.Y, 0.001);
  Depth := Max(BoundsMax.Z - BoundsMin.Z, 0.001);
  Scene.Projection.Radius := Max(0.5 * Sqrt(
    Sqr(Scene.Projection.ModelWidth) + Sqr(Scene.Projection.ModelHeight) +
    Sqr(Depth)), 0.001);
  BuildTriangles(Model, Skinned, Center, Scene.Triangles);
  BuildBoneLines(Model, Transforms, Center, SelectedBone, Scene.BoneLines);
end;

end.
