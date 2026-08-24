unit MmdD3DSelection;

// D3Dプレビューと同じ投影を使い、ボーン区間の画面ヒット判定を行う。

interface

uses
  MmdD3DScene;

// 現在は関節を選択対象にせず、画面座標にあるボーンだけを返す。
function HitTestPreviewTarget(const Joints: TMmdPreviewJoints;
  const Segments: TMmdPreviewBoneSegments; const Projection: TMmdPreviewProjection;
  const Camera: TMmdPreviewCamera; ViewWidth, ViewHeight, MouseX,
  MouseY: Integer): TMmdPreviewTarget;

implementation

uses
  System.Math,
  PmxModel;

const
  // Trueへ変更すれば、関節優先の選択方式を再開できる。
  ENABLE_JOINT_SELECTION = False;

function HitTestPreviewJoint(const Joints: TMmdPreviewJoints;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight, MouseX, MouseY: Integer; MaxDistance: Single): Integer;
var
  BestDepth, BestDistance, Depth, Distance, Dx, Dy: Single;
  Joint: TMmdPreviewJoint;
  Point: TPmxVector3;
begin
  Result := -1;
  BestDistance := Sqr(MaxDistance);
  BestDepth := MaxSingle;
  for Joint in Joints do
  begin
    Point := ProjectPreviewPosition(Joint.Position, Projection, Camera,
      ViewWidth, ViewHeight);
    Point.X := (Point.X + 1) * ViewWidth * 0.5;
    Point.Y := (1 - Point.Y) * ViewHeight * 0.5;
    Dx := MouseX - Point.X;
    Dy := MouseY - Point.Y;
    Distance := Dx * Dx + Dy * Dy;
    Depth := Point.Z;
    if (Distance < BestDistance - 0.01) or
      ((Abs(Distance - BestDistance) <= 0.01) and (Depth < BestDepth)) then
    begin
      BestDistance := Distance;
      BestDepth := Depth;
      Result := Joint.BoneIndex;
    end;
  end;
end;

function HitTestPreviewBone(const Segments: TMmdPreviewBoneSegments;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight, MouseX, MouseY: Integer; MaxDistance: Single): Integer;
var
  BestDepth, BestDistance, Depth, Distance, Dx, Dy, LengthSquared: Single;
  EndPoint, StartPoint: TPmxVector3;
  Segment: TMmdPreviewBoneSegment;
  T: Single;
begin
  Result := -1;
  BestDistance := Sqr(MaxDistance);
  BestDepth := MaxSingle;
  for Segment in Segments do
  begin
    StartPoint := ProjectPreviewPosition(Segment.StartPosition, Projection,
      Camera, ViewWidth, ViewHeight);
    EndPoint := ProjectPreviewPosition(Segment.EndPosition, Projection,
      Camera, ViewWidth, ViewHeight);
    StartPoint.X := (StartPoint.X + 1) * ViewWidth * 0.5;
    StartPoint.Y := (1 - StartPoint.Y) * ViewHeight * 0.5;
    EndPoint.X := (EndPoint.X + 1) * ViewWidth * 0.5;
    EndPoint.Y := (1 - EndPoint.Y) * ViewHeight * 0.5;
    Dx := EndPoint.X - StartPoint.X;
    Dy := EndPoint.Y - StartPoint.Y;
    LengthSquared := Dx * Dx + Dy * Dy;
    if LengthSquared <= 0.0001 then
      T := 0
    else
      T := EnsureRange(((MouseX - StartPoint.X) * Dx +
        (MouseY - StartPoint.Y) * Dy) / LengthSquared, 0.0, 1.0);
    Dx := MouseX - (StartPoint.X + Dx * T);
    Dy := MouseY - (StartPoint.Y + Dy * T);
    Distance := Dx * Dx + Dy * Dy;
    Depth := StartPoint.Z + (EndPoint.Z - StartPoint.Z) * T;
    if (Distance < BestDistance - 0.01) or
      ((Abs(Distance - BestDistance) <= 0.01) and (Depth < BestDepth)) then
    begin
      BestDistance := Distance;
      BestDepth := Depth;
      Result := Segment.BoneIndex;
    end;
  end;
end;

function HitTestPreviewTarget(const Joints: TMmdPreviewJoints;
  const Segments: TMmdPreviewBoneSegments; const Projection: TMmdPreviewProjection;
  const Camera: TMmdPreviewCamera; ViewWidth, ViewHeight, MouseX,
  MouseY: Integer): TMmdPreviewTarget;
var
  BoneIndex: Integer;
  BoneDistance: Single;
  Segment: TMmdPreviewBoneSegment;
begin
  Result := EmptyPreviewTarget;
  if ENABLE_JOINT_SELECTION then
  begin
    Result.JointIndex := HitTestPreviewJoint(Joints, Projection, Camera,
      ViewWidth, ViewHeight, MouseX, MouseY, 7.0);
    if Result.JointIndex >= 0 then
    begin
      Result.Kind := ptJoint;
      Exit;
    end;
  end;
  BoneDistance := EnsureRange(11.0 * Sqrt(EnsureRange(Camera.Zoom, 0.2, 5.0)),
    5.0, 25.0);
  BoneIndex := HitTestPreviewBone(Segments, Projection, Camera, ViewWidth,
    ViewHeight, MouseX, MouseY, BoneDistance);
  if BoneIndex < 0 then
    Exit;
  for Segment in Segments do
    if Segment.BoneIndex = BoneIndex then
    begin
      Result.Kind := ptBone;
      Result.BoneIndex := BoneIndex;
      Result.JointIndex := Segment.StartBoneIndex;
      Exit;
    end;
end;

end.
