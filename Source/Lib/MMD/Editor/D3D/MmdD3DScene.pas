unit MmdD3DScene;

// PMX姿勢からD3Dプレビュー用の三角形・骨格頂点を生成する。

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
  TMmdPreviewScene = record
    Triangles: TMmdPreviewVertices;
    BoneLines: TMmdPreviewVertices;
  end;

// CPUスキニングを行い、正規化デバイス座標のプレビュー頂点を構築する。
procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  SelectedBone, ViewWidth, ViewHeight: Integer; out Scene: TMmdPreviewScene);

implementation

uses
  System.Math;

procedure SetVertex(var Vertex: TMmdPreviewVertex; const Position: TPmxVector3;
  CenterX, CenterY, MinZ, ScaleX, ScaleY, ScaleZ, R, G, B, A: Single);
begin
  Vertex.X := (Position.X - CenterX) * ScaleX;
  Vertex.Y := (Position.Y - CenterY) * ScaleY;
  Vertex.Z := (Position.Z - MinZ) * ScaleZ;
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
  const Skinned: TPmxSkinnedVertices; const BoundsMin, BoundsMax: TPmxVector3;
  CenterX, CenterY, ScaleX, ScaleY, ScaleZ: Single;
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
      SetVertex(Vertices[VertexIndex], Position, CenterX, CenterY, BoundsMin.Z,
        ScaleX, ScaleY, ScaleZ,
        EnsureRange(Material.Diffuse.X * Shade, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Y * Shade, 0.0, 1.0),
        EnsureRange(Material.Diffuse.Z * Shade, 0.0, 1.0), 1.0);
      Inc(VertexIndex);
    end;
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure BuildBoneLines(const Model: TPmxModel;
  const Transforms: TPmxBoneTransforms; const BoundsMin: TPmxVector3;
  CenterX, CenterY, ScaleX, ScaleY, ScaleZ: Single; SelectedBone: Integer;
  out Vertices: TMmdPreviewVertices);
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
      CenterX, CenterY, BoundsMin.Z, ScaleX, ScaleY, ScaleZ, R, G, B, 1.0);
    Inc(VertexIndex);
    SetVertex(Vertices[VertexIndex], Transforms[BoneIndex].Position,
      CenterX, CenterY, BoundsMin.Z, ScaleX, ScaleY, ScaleZ, R, G, B, 1.0);
    Inc(VertexIndex);
  end;
  SetLength(Vertices, VertexIndex);
end;

procedure BuildPreviewScene(Model: TPmxModel; const Poses: TPmxBonePoses;
  SelectedBone, ViewWidth, ViewHeight: Integer; out Scene: TMmdPreviewScene);
var
  BoundsMax, BoundsMin: TPmxVector3;
  CenterX, CenterY: Single;
  ModelHeight, ModelWidth: Single;
  PixelScale, ScaleX, ScaleY, ScaleZ: Single;
  Skinned: TPmxSkinnedVertices;
  Transforms: TPmxBoneTransforms;
begin
  Scene := Default(TMmdPreviewScene);
  if (Model = nil) or (Length(Model.Vertices) = 0) then
    Exit;
  CalculateBoneTransforms(Model, Poses, Transforms);
  SkinVerticesLinear(Model, Transforms, Skinned);
  CalculateBounds(Skinned, BoundsMin, BoundsMax);
  CenterX := (BoundsMin.X + BoundsMax.X) * 0.5;
  CenterY := (BoundsMin.Y + BoundsMax.Y) * 0.5;
  ModelWidth := Max(BoundsMax.X - BoundsMin.X, 0.001);
  ModelHeight := Max(BoundsMax.Y - BoundsMin.Y, 0.001);
  ViewWidth := Max(ViewWidth, 1);
  ViewHeight := Max(ViewHeight, 1);
  // NDCではなく実ピクセル上の縮尺を共通化し、縦長・横長でも体形を維持する。
  PixelScale := 0.9 * Min(ViewWidth / ModelWidth, ViewHeight / ModelHeight);
  ScaleX := 2.0 * PixelScale / ViewWidth;
  ScaleY := 2.0 * PixelScale / ViewHeight;
  ScaleZ := 0.9 / Max(BoundsMax.Z - BoundsMin.Z, 0.001);
  BuildTriangles(Model, Skinned, BoundsMin, BoundsMax, CenterX, CenterY,
    ScaleX, ScaleY, ScaleZ, Scene.Triangles);
  BuildBoneLines(Model, Transforms, BoundsMin, CenterX, CenterY, ScaleX,
    ScaleY, ScaleZ, SelectedBone, Scene.BoneLines);
end;

end.
