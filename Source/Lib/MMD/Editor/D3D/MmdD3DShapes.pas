unit MmdD3DShapes;

// 骨格編集用の関節球と、選択・ホバー中の四角錐ボーンを生成する。

interface

uses
  MmdD3DScene;

// モデル中心基準の関節・区間から、前面表示用の三角形頂点を構築する。
procedure BuildPreviewBoneShapes(const Joints: TMmdPreviewJoints;
  const Segments: TMmdPreviewBoneSegments; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget; ModelHeight: Single;
  out Vertices: TMmdPreviewVertices);

implementation

uses
  System.Math,
  PmxModel,
  PmxPoseMath;

procedure SetShapeVertex(var Vertex: TMmdPreviewVertex;
  const Position, Normal: TPmxVector3; R, G, B: Single);
begin
  Vertex := Default(TMmdPreviewVertex);
  Vertex.X := Position.X;
  Vertex.Y := Position.Y;
  Vertex.Z := Position.Z;
  Vertex.R := R;
  Vertex.G := G;
  Vertex.B := B;
  Vertex.A := 1.0;
  Vertex.NormalX := Normal.X;
  Vertex.NormalY := Normal.Y;
  Vertex.NormalZ := Normal.Z;
  Vertex.Lighting := 1.0;
end;

function SphereOffset(Latitude, Longitude, Radius: Single): TPmxVector3;
var
  CosLatitude: Single;
begin
  CosLatitude := Cos(Latitude);
  Result.X := CosLatitude * Cos(Longitude) * Radius;
  Result.Y := Sin(Latitude) * Radius;
  Result.Z := CosLatitude * Sin(Longitude) * Radius;
end;

procedure AppendSpherePoint(const Center, Offset: TPmxVector3;
  R, G, B: Single; var Vertices: TMmdPreviewVertices;
  var VertexIndex: Integer);
var
  Position: TPmxVector3;
begin
  Position := AddVector(Center, Offset);
  SetShapeVertex(Vertices[VertexIndex], Position, NormalizeVector(Offset),
    R, G, B);
  Inc(VertexIndex);
end;

procedure AppendSphere(const Center: TPmxVector3; Radius, R, G, B: Single;
  var Vertices: TMmdPreviewVertices; var VertexIndex: Integer);
const
  LATITUDE_BANDS = 4;
  LONGITUDE_BANDS = 8;
var
  A, B_, C, D: TPmxVector3;
  LatitudeIndex, LongitudeIndex: Integer;
  Latitude0, Latitude1, Longitude0, Longitude1: Single;
begin
  for LatitudeIndex := 0 to LATITUDE_BANDS - 1 do
  begin
    Latitude0 := -Pi * 0.5 + Pi * LatitudeIndex / LATITUDE_BANDS;
    Latitude1 := -Pi * 0.5 + Pi * (LatitudeIndex + 1) / LATITUDE_BANDS;
    for LongitudeIndex := 0 to LONGITUDE_BANDS - 1 do
    begin
      Longitude0 := 2 * Pi * LongitudeIndex / LONGITUDE_BANDS;
      Longitude1 := 2 * Pi * (LongitudeIndex + 1) / LONGITUDE_BANDS;
      A := SphereOffset(Latitude0, Longitude0, Radius);
      B_ := SphereOffset(Latitude1, Longitude0, Radius);
      C := SphereOffset(Latitude1, Longitude1, Radius);
      D := SphereOffset(Latitude0, Longitude1, Radius);
      AppendSpherePoint(Center, A, R, G, B, Vertices, VertexIndex);
      AppendSpherePoint(Center, B_, R, G, B, Vertices, VertexIndex);
      AppendSpherePoint(Center, C, R, G, B, Vertices, VertexIndex);
      AppendSpherePoint(Center, A, R, G, B, Vertices, VertexIndex);
      AppendSpherePoint(Center, C, R, G, B, Vertices, VertexIndex);
      AppendSpherePoint(Center, D, R, G, B, Vertices, VertexIndex);
    end;
  end;
end;

procedure AppendTriangle(const A, B, C: TPmxVector3; R, G, Blue: Single;
  var Vertices: TMmdPreviewVertices; var VertexIndex: Integer);
var
  Normal: TPmxVector3;
begin
  Normal := NormalizeVector(CrossVector(SubtractVector(B, A),
    SubtractVector(C, A)));
  SetShapeVertex(Vertices[VertexIndex], A, Normal, R, G, Blue);
  Inc(VertexIndex);
  SetShapeVertex(Vertices[VertexIndex], B, Normal, R, G, Blue);
  Inc(VertexIndex);
  SetShapeVertex(Vertices[VertexIndex], C, Normal, R, G, Blue);
  Inc(VertexIndex);
end;

procedure AppendPyramid(const Segment: TMmdPreviewBoneSegment;
  ModelHeight, R, G, B: Single; var Vertices: TMmdPreviewVertices;
  var VertexIndex: Integer);
var
  Base: array[0..3] of TPmxVector3;
  Direction, Reference, Right, Up: TPmxVector3;
  BoneLength, Radius: Single;
begin
  Direction := SubtractVector(Segment.EndPosition, Segment.StartPosition);
  BoneLength := Sqrt(DotVector(Direction, Direction));
  if BoneLength <= 0.000001 then
    Exit;
  Direction := ScaleVector(Direction, 1.0 / BoneLength);
  Reference := Default(TPmxVector3);
  if Abs(Direction.Y) < 0.9 then
    Reference.Y := 1.0
  else
    Reference.X := 1.0;
  Right := NormalizeVector(CrossVector(Direction, Reference));
  Up := NormalizeVector(CrossVector(Right, Direction));
  Radius := EnsureRange(BoneLength * 0.14, ModelHeight * 0.006,
    ModelHeight * 0.022);
  Base[0] := AddVector(Segment.StartPosition,
    AddVector(ScaleVector(Right, Radius), ScaleVector(Up, Radius)));
  Base[1] := AddVector(Segment.StartPosition,
    AddVector(ScaleVector(Right, -Radius), ScaleVector(Up, Radius)));
  Base[2] := AddVector(Segment.StartPosition,
    AddVector(ScaleVector(Right, -Radius), ScaleVector(Up, -Radius)));
  Base[3] := AddVector(Segment.StartPosition,
    AddVector(ScaleVector(Right, Radius), ScaleVector(Up, -Radius)));
  AppendTriangle(Base[0], Base[1], Segment.EndPosition, R, G, B,
    Vertices, VertexIndex);
  AppendTriangle(Base[1], Base[2], Segment.EndPosition, R, G, B,
    Vertices, VertexIndex);
  AppendTriangle(Base[2], Base[3], Segment.EndPosition, R, G, B,
    Vertices, VertexIndex);
  AppendTriangle(Base[3], Base[0], Segment.EndPosition, R, G, B,
    Vertices, VertexIndex);
  AppendTriangle(Base[0], Base[3], Base[2], R, G, B, Vertices, VertexIndex);
  AppendTriangle(Base[0], Base[2], Base[1], R, G, B, Vertices, VertexIndex);
end;

procedure AppendTargetPyramid(const Segments: TMmdPreviewBoneSegments;
  const Target: TMmdPreviewTarget; ModelHeight, R, G, B: Single;
  var Vertices: TMmdPreviewVertices; var VertexIndex: Integer);
var
  Segment: TMmdPreviewBoneSegment;
begin
  if Target.Kind <> ptBone then
    Exit;
  for Segment in Segments do
    if Segment.BoneIndex = Target.BoneIndex then
    begin
      AppendPyramid(Segment, ModelHeight, R, G, B, Vertices, VertexIndex);
      Exit;
    end;
end;

procedure BuildPreviewBoneShapes(const Joints: TMmdPreviewJoints;
  const Segments: TMmdPreviewBoneSegments; const SelectedTarget,
  HoverTarget: TMmdPreviewTarget; ModelHeight: Single;
  out Vertices: TMmdPreviewVertices);
const
  SPHERE_VERTEX_COUNT = 4 * 8 * 6;
var
  B, G, R: Single;
  Joint: TMmdPreviewJoint;
  Radius: Single;
  VertexIndex: Integer;
begin
  SetLength(Vertices, SPHERE_VERTEX_COUNT + 36);
  VertexIndex := 0;
  Radius := ModelHeight * 0.012;
  if SelectedTarget.Locked then
  begin
    R := 0.55;
    G := 0.03;
    B := 0.06;
  end
  else
  begin
    R := 1.0;
    G := 0.25;
    B := 0.1;
  end;
  if SelectedTarget.JointIndex >= 0 then
    for Joint in Joints do
      if Joint.BoneIndex = SelectedTarget.JointIndex then
    begin
      AppendSphere(Joint.Position, Radius, R, G, B,
        Vertices, VertexIndex);
      Break;
    end;
  AppendTargetPyramid(Segments, SelectedTarget, ModelHeight,
    R, G, B, Vertices, VertexIndex);
  if (HoverTarget.Kind <> SelectedTarget.Kind) or
    (HoverTarget.BoneIndex <> SelectedTarget.BoneIndex) then
    AppendTargetPyramid(Segments, HoverTarget, ModelHeight,
      1.0, 0.85, 0.15, Vertices, VertexIndex);
  SetLength(Vertices, VertexIndex);
end;

end.
