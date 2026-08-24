unit MmdD3DInteraction;

// 画面ドラッグをモデル空間へ戻し、関節を親関節中心で回す姿勢差分へ変換する。

interface

uses
  PmxModel,
  PmxPoseTypes,
  MmdD3DScene;

type
  TMmdDragAxis = (daFree, daX, daY, daZ);
  TMmdFixedView = (fvFront, fvSide, fvVertical);

// 現在押されているX、Y/C、Zキーから、ドラッグ中だけ使うローカル軸制限を返す。
function ActivePreviewDragAxis: TMmdDragAxis;
// ズームとパンを維持したまま、正面・側面・上下の固定カメラ角へ切り替える。
procedure ApplyFixedPreviewView(var Camera: TMmdPreviewCamera;
  View: TMmdFixedView; Opposite: Boolean);
// ボーン方向をローカルYとする操作座標で、自由回転または指定軸だけの回転を返す。
// ローカルY制限時は画面横方向のドラッグ量を長手方向のひねり角へ変換する。
function BoneDragLocalRotation(const StartDirection, ModelDelta: TPmxVector3;
  const ParentFrameRotation, StartLocalRotation: TPmxQuaternion;
  Axis: TMmdDragAxis; HorizontalPixels: Single): TPmxQuaternion;
// ドラッグ開始時からの回転差を、指定したラジアン刻みへ吸着させる。
function SnapLocalRotation(const StartRotation,
  CurrentRotation: TPmxQuaternion; StepRadians: Single): TPmxQuaternion;
// 画面上のピクセル差分を、カメラの向きを考慮したモデル空間の移動量へ変換する。
function PreviewScreenDeltaToModel(Dx, Dy: Single;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight: Integer): TPmxVector3;
// 関節方向へドラッグ差分を加え、長さを維持する親ボーンのローカル回転を返す。
function JointDragLocalRotation(const StartDirection, ModelDelta: TPmxVector3;
  const ParentFrameRotation, StartLocalRotation: TPmxQuaternion): TPmxQuaternion;

implementation

uses
  Winapi.Windows,
  System.Math,
  PmxPoseMath;

function ActivePreviewDragAxis: TMmdDragAxis;
begin
  if GetKeyState(Ord('X')) < 0 then
    Result := daX
  else if (GetKeyState(Ord('Y')) < 0) or (GetKeyState(Ord('C')) < 0) then
    Result := daY
  else if GetKeyState(Ord('Z')) < 0 then
    Result := daZ
  else
    Result := daFree;
end;

procedure ApplyFixedPreviewView(var Camera: TMmdPreviewCamera;
  View: TMmdFixedView; Opposite: Boolean);
begin
  case View of
    fvFront:
      begin
        Camera.Yaw := IfThen(Opposite, Pi, 0.0);
        Camera.Pitch := 0;
      end;
    fvSide:
      begin
        Camera.Yaw := IfThen(Opposite, -Pi * 0.5, Pi * 0.5);
        Camera.Pitch := 0;
      end;
    fvVertical:
      begin
        Camera.Yaw := 0;
        Camera.Pitch := IfThen(Opposite, Pi * 0.5, -Pi * 0.5);
      end;
  end;
end;

function PreviewScreenDeltaToModel(Dx, Dy: Single;
  const Projection: TMmdPreviewProjection; const Camera: TMmdPreviewCamera;
  ViewWidth, ViewHeight: Integer): TPmxVector3;
var
  CosPitch, CosYaw, PixelScale, SinPitch, SinYaw: Single;
  ViewX, ViewY, ViewZ: Single;
begin
  ViewWidth := Max(ViewWidth, 1);
  ViewHeight := Max(ViewHeight, 1);
  PixelScale := 0.9 * EnsureRange(Camera.Zoom, 0.2, 5.0) *
    Min(ViewWidth / Projection.ModelWidth, ViewHeight / Projection.ModelHeight);
  ViewX := Dx / Max(PixelScale, 0.000001);
  ViewY := -Dy / Max(PixelScale, 0.000001);
  ViewZ := 0;
  SinCos(Camera.Pitch, SinPitch, CosPitch);
  Result.Y := ViewY * CosPitch + ViewZ * SinPitch;
  ViewZ := -ViewY * SinPitch + ViewZ * CosPitch;
  SinCos(Camera.Yaw, SinYaw, CosYaw);
  Result.X := ViewX * CosYaw - ViewZ * SinYaw;
  Result.Z := ViewX * SinYaw + ViewZ * CosYaw;
end;

function RotationBetween(const FromDirection,
  ToDirection: TPmxVector3): TPmxQuaternion;
var
  Axis, From_, Reference, To_: TPmxVector3;
  Dot_: Single;
begin
  From_ := NormalizeVector(FromDirection);
  To_ := NormalizeVector(ToDirection);
  Dot_ := EnsureRange(DotVector(From_, To_), -1.0, 1.0);
  if Dot_ >= 0.999999 then
    Exit(IdentityQuaternion);
  Axis := CrossVector(From_, To_);
  if Dot_ <= -0.999999 then
  begin
    Reference := Default(TPmxVector3);
    if Abs(From_.Y) < 0.9 then
      Reference.Y := 1.0
    else
      Reference.X := 1.0;
    Axis := NormalizeVector(CrossVector(From_, Reference));
  end
  else
    Axis := NormalizeVector(Axis);
  Result := QuaternionFromAxisAngle(Axis, ArcCos(Dot_));
end;

function JointDragLocalRotation(const StartDirection, ModelDelta: TPmxVector3;
  const ParentFrameRotation, StartLocalRotation: TPmxQuaternion): TPmxQuaternion;
var
  DeltaLocal, DeltaWorld: TPmxQuaternion;
  TargetDirection: TPmxVector3;
begin
  TargetDirection := NormalizeVector(AddVector(StartDirection, ModelDelta));
  if DotVector(TargetDirection, TargetDirection) <= 0.000001 then
    Exit(StartLocalRotation);
  DeltaWorld := RotationBetween(StartDirection, TargetDirection);
  DeltaLocal := NormalizeQuaternion(MultiplyQuaternion(
    MultiplyQuaternion(InverseQuaternion(ParentFrameRotation), DeltaWorld),
    ParentFrameRotation));
  Result := NormalizeQuaternion(MultiplyQuaternion(DeltaLocal,
    StartLocalRotation));
end;

function ProjectPerpendicular(const Value, Axis: TPmxVector3): TPmxVector3;
begin
  Result := SubtractVector(Value, ScaleVector(Axis, DotVector(Value, Axis)));
end;

function BoneDragLocalRotation(const StartDirection, ModelDelta: TPmxVector3;
  const ParentFrameRotation, StartLocalRotation: TPmxQuaternion;
  Axis: TMmdDragAxis; HorizontalPixels: Single): TPmxQuaternion;
const
  TWIST_RADIANS_PER_PIXEL = 0.01;
var
  AxisLocal, BoneX, BoneY, BoneZ, FromProjected, Reference: TPmxVector3;
  StartLocalDirection, TargetDirection, TargetLocalDirection: TPmxVector3;
  Angle, CosAngle, SinAngle: Single;
begin
  if Axis = daFree then
    Exit(JointDragLocalRotation(StartDirection, ModelDelta,
      ParentFrameRotation, StartLocalRotation));
  StartLocalDirection := NormalizeVector(RotateVector(
    InverseQuaternion(ParentFrameRotation), StartDirection));
  BoneY := StartLocalDirection;
  Reference := Default(TPmxVector3);
  Reference.Z := 1.0;
  if Abs(DotVector(BoneY, Reference)) > 0.95 then
  begin
    Reference := Default(TPmxVector3);
    Reference.X := 1.0;
  end;
  BoneX := NormalizeVector(CrossVector(BoneY, Reference));
  BoneZ := NormalizeVector(CrossVector(BoneX, BoneY));
  case Axis of
    daX: AxisLocal := BoneX;
    daY: AxisLocal := BoneY;
    daZ: AxisLocal := BoneZ;
  else
    AxisLocal := BoneY;
  end;
  if Axis = daY then
    Angle := HorizontalPixels * TWIST_RADIANS_PER_PIXEL
  else
  begin
    TargetDirection := NormalizeVector(AddVector(StartDirection, ModelDelta));
    if DotVector(TargetDirection, TargetDirection) <= 0.000001 then
      Exit(StartLocalRotation);
    TargetLocalDirection := NormalizeVector(RotateVector(
      InverseQuaternion(ParentFrameRotation), TargetDirection));
    FromProjected := ProjectPerpendicular(StartLocalDirection, AxisLocal);
    TargetLocalDirection := ProjectPerpendicular(TargetLocalDirection,
      AxisLocal);
    if (DotVector(FromProjected, FromProjected) <= 0.000001) or
      (DotVector(TargetLocalDirection, TargetLocalDirection) <= 0.000001) then
      Exit(StartLocalRotation);
    FromProjected := NormalizeVector(FromProjected);
    TargetLocalDirection := NormalizeVector(TargetLocalDirection);
    CosAngle := EnsureRange(DotVector(FromProjected, TargetLocalDirection),
      -1.0, 1.0);
    SinAngle := DotVector(AxisLocal,
      CrossVector(FromProjected, TargetLocalDirection));
    Angle := ArcTan2(SinAngle, CosAngle);
  end;
  Result := NormalizeQuaternion(MultiplyQuaternion(
    QuaternionFromAxisAngle(AxisLocal, Angle), StartLocalRotation));
end;

function SnapLocalRotation(const StartRotation,
  CurrentRotation: TPmxQuaternion; StepRadians: Single): TPmxQuaternion;
var
  Axis: TPmxVector3;
  Delta: TPmxQuaternion;
  Angle, AxisLength, SnappedAngle: Single;
begin
  if StepRadians <= 0.000001 then
    Exit(CurrentRotation);
  Delta := NormalizeQuaternion(MultiplyQuaternion(CurrentRotation,
    InverseQuaternion(StartRotation)));
  if Delta.W < 0 then
  begin
    Delta.X := -Delta.X;
    Delta.Y := -Delta.Y;
    Delta.Z := -Delta.Z;
    Delta.W := -Delta.W;
  end;
  Angle := 2 * ArcCos(EnsureRange(Delta.W, -1.0, 1.0));
  AxisLength := Sqrt(Delta.X * Delta.X + Delta.Y * Delta.Y +
    Delta.Z * Delta.Z);
  if AxisLength <= 0.000001 then
    Exit(StartRotation);
  Axis.X := Delta.X / AxisLength;
  Axis.Y := Delta.Y / AxisLength;
  Axis.Z := Delta.Z / AxisLength;
  SnappedAngle := Round(Angle / StepRadians) * StepRadians;
  Result := NormalizeQuaternion(MultiplyQuaternion(
    QuaternionFromAxisAngle(Axis, SnappedAngle), StartRotation));
end;

end.
