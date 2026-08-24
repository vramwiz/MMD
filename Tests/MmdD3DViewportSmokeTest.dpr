program MmdD3DViewportSmokeTest;

{$APPTYPE GUI}

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Math,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  PmxModel in 'Source\Lib\MMD\Core\PmxModel.pas',
  PmxPoseTypes in 'Source\Lib\MMD\Core\PmxPoseTypes.pas',
  PmxPoseMath in 'Source\Lib\MMD\Core\PmxPoseMath.pas',
  PmxMorph in 'Source\Lib\MMD\Core\PmxMorph.pas',
  PmxBoneSolver in 'Source\Lib\MMD\Core\PmxBoneSolver.pas',
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  PmxReader in 'Source\Lib\MMD\IO\PmxReader.pas',
  PmxBinaryStream in 'Source\Lib\MMD\IO\PmxBinaryStream.pas',
  PmxGeometryReader in 'Source\Lib\MMD\IO\PmxGeometryReader.pas',
  PmxMaterialReader in 'Source\Lib\MMD\IO\PmxMaterialReader.pas',
  PmxBoneReader in 'Source\Lib\MMD\IO\PmxBoneReader.pas',
  PmxMorphReader in 'Source\Lib\MMD\IO\PmxMorphReader.pas',
  MmdPoseHistory in 'Source\Lib\MMD\Editor\MmdPoseHistory.pas',
  MmdPoseEditOperations in 'Source\Lib\MMD\Editor\MmdPoseEditOperations.pas',
  MmdPoseSymmetry in 'Source\Lib\MMD\Editor\MmdPoseSymmetry.pas',
  MmdD3DScene in 'Source\Lib\MMD\Editor\D3D\MmdD3DScene.pas',
  MmdD3DSelection in 'Source\Lib\MMD\Editor\D3D\MmdD3DSelection.pas',
  MmdD3DInteraction in 'Source\Lib\MMD\Editor\D3D\MmdD3DInteraction.pas',
  MmdD3DShapes in 'Source\Lib\MMD\Editor\D3D\MmdD3DShapes.pas',
  MmdD3DBuffers in 'Source\Lib\MMD\Editor\D3D\MmdD3DBuffers.pas',
  MmdD3DOverlay in 'Source\Lib\MMD\Editor\D3D\MmdD3DOverlay.pas',
  MmdD3DShaders in 'Source\Lib\MMD\Editor\D3D\MmdD3DShaders.pas',
  MmdD3DTextures in 'Source\Lib\MMD\Editor\D3D\MmdD3DTextures.pas',
  MmdD3DDevice in 'Source\Lib\MMD\Editor\D3D\MmdD3DDevice.pas',
  MmdD3DDeform in 'Source\Lib\MMD\Editor\D3D\MmdD3DDeform.pas',
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
  MmdD3DViewportSurface in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewportSurface.pas',
  MmdD3DLiveDragTest in 'Source\Lib\MMD\Editor\D3D\Temporary\MmdD3DLiveDragTest.pas',
  MmdD3DViewport in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewport.pas';

var
  Form: TForm;
  Model: TPmxModel;
  Poses: TPmxBonePoses;
  Viewport: TMmdD3DViewport;

function ProjectVertex(const Vertex: TMmdPreviewVertex;
  const Scene: TMmdPreviewScene; const Camera: TMmdPreviewCamera;
  Width, Height: Integer): TPmxVector3;
var
  Position: TPmxVector3;
begin
  Position.X := Vertex.X;
  Position.Y := Vertex.Y;
  Position.Z := Vertex.Z;
  Result := ProjectPreviewPosition(Position, Scene.Projection, Camera,
    Width, Height);
end;

function PixelAspect(const Scene: TMmdPreviewScene;
  const Camera: TMmdPreviewCamera; Width, Height: Integer): Double;
var
  I: Integer;
  MaxX, MaxY, MinX, MinY: Single;
  Projected: TPmxVector3;
begin
  if Length(Scene.Triangles) = 0 then
    raise Exception.Create('preview scene has no triangles');
  Projected := ProjectVertex(Scene.Triangles[0], Scene, Camera, Width, Height);
  MinX := Projected.X;
  MaxX := MinX;
  MinY := Projected.Y;
  MaxY := MinY;
  for I := 1 to High(Scene.Triangles) do
  begin
    Projected := ProjectVertex(Scene.Triangles[I], Scene, Camera, Width, Height);
    MinX := Min(MinX, Projected.X);
    MaxX := Max(MaxX, Projected.X);
    MinY := Min(MinY, Projected.Y);
    MaxY := Max(MaxY, Projected.Y);
  end;
  Result := ((MaxX - MinX) * Width) / ((MaxY - MinY) * Height);
end;

procedure CheckAspectCorrection(Model: TPmxModel; const Poses: TPmxBonePoses);
var
  Camera: TMmdPreviewCamera;
  Scene: TMmdPreviewScene;
begin
  Camera := DefaultPreviewCamera;
  BuildPreviewScene(Model, Poses, nil, EmptyPreviewTarget, EmptyPreviewTarget,
    Scene);
  if Abs(PixelAspect(Scene, Camera, 160, 315) -
    PixelAspect(Scene, Camera, 315, 315)) > 0.001 then
    raise Exception.Create('viewport aspect correction failed');
end;

function PixelHeight(const Scene: TMmdPreviewScene;
  const Camera: TMmdPreviewCamera; Width, Height: Integer): Double;
var
  I: Integer;
  MaxY, MinY: Single;
  Projected: TPmxVector3;
begin
  Projected := ProjectVertex(Scene.Triangles[0], Scene, Camera, Width, Height);
  MinY := Projected.Y;
  MaxY := MinY;
  for I := 1 to High(Scene.Triangles) do
  begin
    Projected := ProjectVertex(Scene.Triangles[I], Scene, Camera, Width, Height);
    MinY := Min(MinY, Projected.Y);
    MaxY := Max(MaxY, Projected.Y);
  end;
  Result := (MaxY - MinY) * Height;
end;

procedure CheckCameraProjection(Model: TPmxModel; const Poses: TPmxBonePoses);
var
  BaseCamera, PanCamera, RotatedCamera, ZoomCamera: TMmdPreviewCamera;
  BaseProjected, PanProjected, RotatedProjected: TPmxVector3;
  Scene: TMmdPreviewScene;
begin
  BaseCamera := DefaultPreviewCamera;
  RotatedCamera := BaseCamera;
  RotatedCamera.Yaw := DegToRad(35);
  RotatedCamera.Pitch := DegToRad(-20);
  ZoomCamera := BaseCamera;
  ZoomCamera.Zoom := 1.5;
  PanCamera := BaseCamera;
  PanCamera.PanX := 40;
  PanCamera.PanY := 25;
  BuildPreviewScene(Model, Poses, nil, EmptyPreviewTarget, EmptyPreviewTarget,
    Scene);
  BaseProjected := ProjectVertex(Scene.Triangles[0], Scene, BaseCamera, 315, 315);
  RotatedProjected := ProjectVertex(Scene.Triangles[0], Scene, RotatedCamera, 315, 315);
  PanProjected := ProjectVertex(Scene.Triangles[0], Scene, PanCamera, 315, 315);
  if (Abs(BaseProjected.X - RotatedProjected.X) < 0.001) and
    (Abs(BaseProjected.Y - RotatedProjected.Y) < 0.001) then
    raise Exception.Create('camera rotation did not change projection');
  if Abs(PixelHeight(Scene, ZoomCamera, 315, 315) /
    PixelHeight(Scene, BaseCamera, 315, 315) - 1.5) > 0.001 then
    raise Exception.Create('camera zoom scale failed');
  if (Abs((PanProjected.X - BaseProjected.X) * 315 * 0.5 - 40) > 0.001) or
    (Abs((PanProjected.Y - BaseProjected.Y) * 315 * 0.5 + 25) > 0.001) then
    raise Exception.Create('preview pan projection failed');
end;

procedure CheckFixedViewMath;
var
  Camera: TMmdPreviewCamera;
begin
  Camera := DefaultPreviewCamera;
  Camera.Zoom := 1.7;
  Camera.PanX := 25;
  Camera.PanY := -12;
  ApplyFixedPreviewView(Camera, fvSide, False);
  if (Abs(Camera.Yaw - Pi * 0.5) > 0.0001) or
    (Abs(Camera.Pitch) > 0.0001) then
    raise Exception.Create('right fixed preview view failed');
  ApplyFixedPreviewView(Camera, fvSide, True);
  if Abs(Camera.Yaw + Pi * 0.5) > 0.0001 then
    raise Exception.Create('left fixed preview view failed');
  ApplyFixedPreviewView(Camera, fvVertical, False);
  if Abs(Camera.Pitch + Pi * 0.5) > 0.0001 then
    raise Exception.Create('top fixed preview view failed');
  ApplyFixedPreviewView(Camera, fvFront, True);
  if (Abs(Camera.Yaw - Pi) > 0.0001) or
    (Abs(Camera.Zoom - 1.7) > 0.0001) or
    (Abs(Camera.PanX - 25) > 0.0001) or
    (Abs(Camera.PanY + 12) > 0.0001) then
    raise Exception.Create('back view did not preserve zoom and pan');
end;

procedure CheckFixedViewKeyboard(Viewport: TMmdD3DViewport);
begin
  SendMessage(Viewport.Handle, WM_KEYDOWN, Ord('S'), 0);
  if Abs(Viewport.Camera.Yaw - Pi * 0.5) > 0.0001 then
    raise Exception.Create('S key did not select right view');
  SendMessage(Viewport.Handle, WM_KEYDOWN, Ord('S'), 0);
  if Abs(Viewport.Camera.Yaw - Pi * 0.5) > 0.0001 then
    raise Exception.Create('held fixed-view key toggled repeatedly');
  SendMessage(Viewport.Handle, WM_KEYUP, Ord('S'), 0);
  SendMessage(Viewport.Handle, WM_KEYDOWN, Ord('S'), 0);
  if Abs(Viewport.Camera.Yaw + Pi * 0.5) > 0.0001 then
    raise Exception.Create('second S key did not select left view');
  SendMessage(Viewport.Handle, WM_KEYUP, Ord('S'), 0);
end;

procedure CheckFixedPreviewFrame(Model: TPmxModel; const Poses: TPmxBonePoses);
var
  AutoScene, FixedScene, InitialScene: TMmdPreviewScene;
  WorkPoses: TPmxBonePoses;
begin
  BuildPreviewScene(Model, Poses, nil, EmptyPreviewTarget, EmptyPreviewTarget,
    InitialScene);
  WorkPoses := Copy(Poses);
  WorkPoses[0].Translation.X := WorkPoses[0].Translation.X + 10;
  BuildPreviewScene(Model, WorkPoses, nil, EmptyPreviewTarget, EmptyPreviewTarget,
    AutoScene);
  if Abs(AutoScene.Center.X - InitialScene.Center.X) < 0.1 then
    raise Exception.Create('fixed-frame test pose did not move model bounds');
  BuildPreviewSceneWithFrame(Model, WorkPoses, nil, EmptyPreviewTarget,
    EmptyPreviewTarget, InitialScene.Center, InitialScene.Projection,
    FixedScene);
  if (Abs(FixedScene.Center.X - InitialScene.Center.X) > 0.0001) or
    (Abs(FixedScene.Center.Y - InitialScene.Center.Y) > 0.0001) or
    (Abs(FixedScene.Center.Z - InitialScene.Center.Z) > 0.0001) or
    (Abs(FixedScene.Projection.ModelWidth -
      InitialScene.Projection.ModelWidth) > 0.0001) or
    (Abs(FixedScene.Projection.ModelHeight -
      InitialScene.Projection.ModelHeight) > 0.0001) or
    (Abs(FixedScene.Projection.Radius -
      InitialScene.Projection.Radius) > 0.0001) then
    raise Exception.Create('preview frame changed after pose update');
end;

procedure CheckCameraInteractionPerformance(Viewport: TMmdD3DViewport);
const
  MOVE_COUNT = 200;
var
  Elapsed: UInt64;
  I: Integer;
  Started: UInt64;
begin
  Started := GetTickCount64;
  SendMessage(Viewport.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(10, 10));
  for I := 1 to MOVE_COUNT do
    SendMessage(Viewport.Handle, WM_MOUSEMOVE, MK_LBUTTON,
      MakeLParam(10 + I, 10 + I div 2));
  SendMessage(Viewport.Handle, WM_LBUTTONUP, 0,
    MakeLParam(10 + MOVE_COUNT, 10 + MOVE_COUNT div 2));
  Elapsed := GetTickCount64 - Started;
  if Elapsed > 2000 then
    raise Exception.CreateFmt('camera interaction is too slow: %d ms', [Elapsed]);
end;

procedure CheckJointMouseInteraction(Viewport: TMmdD3DViewport;
  Model: TPmxModel; const Poses: TPmxBonePoses);
var
  Camera: TMmdPreviewCamera;
  Found: Boolean;
  Joint: TMmdPreviewJoint;
  MouseX, MouseY, ParentIndex: Integer;
  Projected: TPmxVector3;
  Scene: TMmdPreviewScene;
  Target: TMmdPreviewTarget;
  WorkPoses: TPmxBonePoses;
begin
  Viewport.SetScene(Model, Poses, 0);
  Camera := DefaultPreviewCamera;
  Found := False;
  BuildPreviewScene(Model, Poses, nil, EmptyPreviewTarget, EmptyPreviewTarget,
    Scene);
  MouseX := -1;
  MouseY := -1;
  for Joint in Scene.Joints do
  begin
    Projected := ProjectPreviewPosition(Joint.Position, Scene.Projection,
      Camera, Viewport.ClientWidth, Viewport.ClientHeight);
    MouseX := Round((Projected.X + 1) * Viewport.ClientWidth * 0.5);
    MouseY := Round((1 - Projected.Y) * Viewport.ClientHeight * 0.5);
    Target := HitTestPreviewTarget(Scene.Joints, Scene.BoneSegments,
      Scene.Projection, Camera, Viewport.ClientWidth, Viewport.ClientHeight,
      MouseX, MouseY);
    if (Target.Kind = ptJoint) and (Target.JointIndex >= 0) and
      (Model.Bones[Target.JointIndex].ParentIndex >= 0) then
    begin
      Found := True;
      Break;
    end;
  end;
  if not Found then
    raise Exception.Create('no draggable preview joint found');
  ParentIndex := Model.Bones[Target.JointIndex].ParentIndex;
  SendMessage(Viewport.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    MakeLParam(MouseX, MouseY));
  SendMessage(Viewport.Handle, WM_MOUSEMOVE, MK_LBUTTON,
    MakeLParam(MouseX + 25, MouseY + 10));
  SendMessage(Viewport.Handle, WM_LBUTTONUP, 0,
    MakeLParam(MouseX + 25, MouseY + 10));
  Viewport.CopyPoses(WorkPoses);
  if (Abs(WorkPoses[ParentIndex].Rotation.X) +
    Abs(WorkPoses[ParentIndex].Rotation.Y) +
    Abs(WorkPoses[ParentIndex].Rotation.Z)) < 0.00001 then
    raise Exception.Create('joint mouse drag did not update its parent pose');
end;

procedure CheckBoneMouseInteraction(Viewport: TMmdD3DViewport;
  Model: TPmxModel; const Poses: TPmxBonePoses);
const
  MOVE_COUNT = 100;
var
  AfterPoses, BeforePoses, LockedPoses: TPmxBonePoses;
  Camera: TMmdPreviewCamera;
  Dx, Dy: Single;
  Elapsed, MaxElapsed, Started: UInt64;
  EndPoint, StartPoint: TPmxVector3;
  Found: Boolean;
  I, MouseX, MouseY, PoseBoneIndex: Integer;
  Scene: TMmdPreviewScene;
  Segment: TMmdPreviewBoneSegment;
  Target: TMmdPreviewTarget;
begin
  Viewport.SetScene(Model, Poses, 0);
  Viewport.CopyPoses(BeforePoses);
  Camera := DefaultPreviewCamera;
  BuildPreviewScene(Model, BeforePoses, nil, EmptyPreviewTarget,
    EmptyPreviewTarget, Scene);
  Found := False;
  MouseX := -1;
  MouseY := -1;
  for Segment in Scene.BoneSegments do
  begin
    StartPoint := ProjectPreviewPosition(Segment.StartPosition,
      Scene.Projection, Camera, Viewport.ClientWidth, Viewport.ClientHeight);
    EndPoint := ProjectPreviewPosition(Segment.EndPosition, Scene.Projection,
      Camera, Viewport.ClientWidth, Viewport.ClientHeight);
    Dx := (EndPoint.X - StartPoint.X) * Viewport.ClientWidth * 0.5;
    Dy := (EndPoint.Y - StartPoint.Y) * Viewport.ClientHeight * 0.5;
    if Dx * Dx + Dy * Dy < 1600 then
      Continue;
    MouseX := Round((StartPoint.X + EndPoint.X + 2) *
      Viewport.ClientWidth * 0.25);
    MouseY := Round((2 - StartPoint.Y - EndPoint.Y) *
      Viewport.ClientHeight * 0.25);
    Target := HitTestPreviewTarget(Scene.Joints, Scene.BoneSegments,
      Scene.Projection, Camera, Viewport.ClientWidth, Viewport.ClientHeight,
      MouseX, MouseY);
    if Target.Kind = ptBone then
    begin
      Found := True;
      Break;
    end;
  end;
  if not Found then
    raise Exception.Create('no draggable preview bone found');
  PoseBoneIndex := Target.JointIndex;
  SendMessage(Viewport.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    MakeLParam(MouseX, MouseY));
  SendMessage(Viewport.Handle, WM_LBUTTONUP, 0, MakeLParam(MouseX, MouseY));
  SendMessage(Viewport.Handle, WM_KEYDOWN, Ord('L'), 0);
  SendMessage(Viewport.Handle, WM_KEYUP, Ord('L'), 0);
  if not Viewport.SelectedBoneLocked then
    raise Exception.Create('L key did not lock selected bone');
  SendMessage(Viewport.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    MakeLParam(MouseX, MouseY));
  SendMessage(Viewport.Handle, WM_MOUSEMOVE, MK_LBUTTON,
    MakeLParam(MouseX + 25, MouseY + 10));
  SendMessage(Viewport.Handle, WM_LBUTTONUP, 0,
    MakeLParam(MouseX + 25, MouseY + 10));
  Viewport.CopyPoses(LockedPoses);
  if (Abs(LockedPoses[PoseBoneIndex].Rotation.X -
    BeforePoses[PoseBoneIndex].Rotation.X) +
    Abs(LockedPoses[PoseBoneIndex].Rotation.Y -
    BeforePoses[PoseBoneIndex].Rotation.Y) +
    Abs(LockedPoses[PoseBoneIndex].Rotation.Z -
    BeforePoses[PoseBoneIndex].Rotation.Z) +
    Abs(LockedPoses[PoseBoneIndex].Rotation.W -
    BeforePoses[PoseBoneIndex].Rotation.W)) > 0.00001 then
    raise Exception.Create('locked bone changed during mouse drag');
  SendMessage(Viewport.Handle, WM_KEYDOWN, Ord('L'), 0);
  SendMessage(Viewport.Handle, WM_KEYUP, Ord('L'), 0);
  if Viewport.SelectedBoneLocked then
    raise Exception.Create('second L key did not unlock selected bone');
  Started := GetTickCount64;
  SendMessage(Viewport.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    MakeLParam(MouseX, MouseY));
  for I := 1 to MOVE_COUNT do
    SendMessage(Viewport.Handle, WM_MOUSEMOVE, MK_LBUTTON,
      MakeLParam(MouseX + I div 4, MouseY + I div 10));
  SendMessage(Viewport.Handle, WM_LBUTTONUP, 0,
    MakeLParam(MouseX + 25, MouseY + 10));
  Elapsed := GetTickCount64 - Started;
  if TEMPORARY_LIVE_MODEL_DRAG_TEST then
    MaxElapsed := 10000
  else
    MaxElapsed := 500;
  if Elapsed > MaxElapsed then
    raise Exception.CreateFmt('bone drag is too slow: %d ms', [Elapsed]);
  Viewport.CopyPoses(AfterPoses);
  if (Abs(AfterPoses[PoseBoneIndex].Rotation.X -
    BeforePoses[PoseBoneIndex].Rotation.X) +
    Abs(AfterPoses[PoseBoneIndex].Rotation.Y -
    BeforePoses[PoseBoneIndex].Rotation.Y) +
    Abs(AfterPoses[PoseBoneIndex].Rotation.Z -
    BeforePoses[PoseBoneIndex].Rotation.Z)) < 0.00001 then
    raise Exception.Create('bone mouse drag did not update its local pose');
end;

procedure CheckBoneHitTesting;
var
  Camera: TMmdPreviewCamera;
  Projection: TMmdPreviewProjection;
  Joints: TMmdPreviewJoints;
  Segments: TMmdPreviewBoneSegments;
  Target: TMmdPreviewTarget;
begin
  Camera := DefaultPreviewCamera;
  Projection.ModelWidth := 2;
  Projection.ModelHeight := 2;
  Projection.Radius := 2;
  SetLength(Segments, 2);
  Segments[0].BoneIndex := 10;
  Segments[0].StartBoneIndex := 9;
  Segments[0].StartPosition.X := -0.5;
  Segments[0].StartPosition.Z := 0.5;
  Segments[0].EndPosition.X := 0.5;
  Segments[0].EndPosition.Z := 0.5;
  Segments[1] := Segments[0];
  Segments[1].BoneIndex := 20;
  Segments[1].StartBoneIndex := 19;
  Segments[1].StartPosition.Z := -0.5;
  Segments[1].EndPosition.Z := -0.5;
  Target := HitTestPreviewTarget(Joints, Segments, Projection, Camera,
    200, 200, 100, 100);
  if (Target.Kind <> ptBone) or (Target.BoneIndex <> 20) or
    (Target.JointIndex <> 19) then
    raise Exception.Create('front bone hit priority failed');
  Camera.Zoom := 0.2;
  Target := HitTestPreviewTarget(Joints, Segments, Projection, Camera,
    200, 200, 100, 109);
  if Target.Kind <> ptNone then
    raise Exception.Create('zoomed-out bone hit range did not shrink');
  Camera.Zoom := 4.0;
  Target := HitTestPreviewTarget(Joints, Segments, Projection, Camera,
    200, 200, 100, 109);
  if Target.Kind <> ptBone then
    raise Exception.Create('zoomed-in bone hit range did not expand');
  Camera := DefaultPreviewCamera;
  Target := HitTestPreviewTarget(Joints, Segments, Projection, Camera,
    200, 200, 10, 10);
  if Target.Kind <> ptNone then
    raise Exception.Create('bone hit distance rejection failed');
  SetLength(Joints, 1);
  Joints[0].BoneIndex := 30;
  Target := HitTestPreviewTarget(Joints, Segments, Projection, Camera,
    200, 200, 100, 100);
  if (Target.Kind <> ptBone) or (Target.BoneIndex <> 20) then
    raise Exception.Create('joint must not intercept bone selection');
end;

procedure CheckJointDragMath;
var
  Camera: TMmdPreviewCamera;
  Delta, Direction, Rotated: TPmxVector3;
  Projection: TMmdPreviewProjection;
  Rotation: TPmxQuaternion;
begin
  Camera := DefaultPreviewCamera;
  Projection.ModelWidth := 2;
  Projection.ModelHeight := 2;
  Projection.Radius := 2;
  Delta := PreviewScreenDeltaToModel(90, 0, Projection, Camera, 200, 200);
  Direction := Default(TPmxVector3);
  Direction.Y := 1;
  Rotation := JointDragLocalRotation(Direction, Delta, IdentityQuaternion,
    IdentityQuaternion);
  Rotated := RotateVector(Rotation, Direction);
  if (Abs(Rotated.X - Sqrt(0.5)) > 0.001) or
    (Abs(Rotated.Y - Sqrt(0.5)) > 0.001) or
    (Abs(Sqrt(DotVector(Rotated, Rotated)) - 1.0) > 0.001) then
    raise Exception.Create('joint drag rotation or length preservation failed');
end;

procedure CheckBoneAxisDragMath;
var
  Delta, Direction, Rotated: TPmxVector3;
  Rotation: TPmxQuaternion;
begin
  Direction := Default(TPmxVector3);
  Direction.Y := 1;
  Delta := Default(TPmxVector3);
  Delta.Z := 1;
  Rotation := BoneDragLocalRotation(Direction, Delta, IdentityQuaternion,
    IdentityQuaternion, daX, 0);
  Rotated := RotateVector(Rotation, Direction);
  if (Rotated.Z < 0.6) or (Abs(Rotated.X) > 0.001) then
    raise Exception.Create('local X bone drag constraint failed');
  Rotation := BoneDragLocalRotation(Direction, Default(TPmxVector3),
    IdentityQuaternion, IdentityQuaternion, daY, 90);
  Rotated := RotateVector(Rotation, Direction);
  if (Abs(Rotation.Y) < 0.1) or (Abs(Rotated.Y - 1.0) > 0.001) then
    raise Exception.Create('local Y bone twist constraint failed');
  Delta := Default(TPmxVector3);
  Delta.X := -1;
  Rotation := BoneDragLocalRotation(Direction, Delta, IdentityQuaternion,
    IdentityQuaternion, daZ, 0);
  Rotated := RotateVector(Rotation, Direction);
  if (Rotated.X > -0.6) or (Abs(Rotated.Z) > 0.001) then
    raise Exception.Create('local Z bone drag constraint failed');
end;

procedure CheckBoneRotationSnapMath;
var
  Axis, Direction, Rotated: TPmxVector3;
  Rotation, Snapped: TPmxQuaternion;
begin
  Axis := Default(TPmxVector3);
  Axis.X := 1;
  Direction := Default(TPmxVector3);
  Direction.Y := 1;
  Rotation := QuaternionFromAxisAngle(Axis, DegToRad(12));
  Snapped := SnapLocalRotation(IdentityQuaternion, Rotation, DegToRad(5));
  Rotated := RotateVector(Snapped, Direction);
  if Abs(ArcTan2(Rotated.Z, Rotated.Y) - DegToRad(10)) > 0.001 then
    raise Exception.Create('five-degree bone rotation snap failed');
end;

procedure CheckPoseSymmetry(Model: TPmxModel);
var
  BoneIndex, MirrorIndex: Integer;
  Mirrored, Pose, Restored: TPmxBonePose;
begin
  MirrorIndex := -1;
  for BoneIndex := 0 to High(Model.Bones) do
  begin
    MirrorIndex := FindSymmetricBone(Model, BoneIndex);
    if MirrorIndex >= 0 then
      Break;
  end;
  if MirrorIndex < 0 then
    raise Exception.Create('model has no left/right bone name pair');
  if FindSymmetricBone(Model, MirrorIndex) <> BoneIndex then
    raise Exception.Create('left/right bone mapping is not reversible');
  Pose := Default(TPmxBonePose);
  Pose.Translation.X := 1;
  Pose.Translation.Y := 2;
  Pose.Translation.Z := 3;
  Pose.Rotation.X := 0.1;
  Pose.Rotation.Y := 0.2;
  Pose.Rotation.Z := 0.3;
  Pose.Rotation.W := 0.9;
  Mirrored := MirrorBonePose(Pose);
  if (Abs(Mirrored.Translation.X + 1) > 0.0001) or
    (Abs(Mirrored.Translation.Y - 2) > 0.0001) or
    (Abs(Mirrored.Translation.Z - 3) > 0.0001) or
    (Abs(Mirrored.Rotation.X - 0.1) > 0.0001) or
    (Abs(Mirrored.Rotation.Y + 0.2) > 0.0001) or
    (Abs(Mirrored.Rotation.Z + 0.3) > 0.0001) or
    (Abs(Mirrored.Rotation.W - 0.9) > 0.0001) then
    raise Exception.Create('mirrored bone pose axes failed');
  Restored := MirrorBonePose(Mirrored);
  if (Abs(Restored.Translation.X - Pose.Translation.X) > 0.0001) or
    (Abs(Restored.Rotation.X - Pose.Rotation.X) > 0.0001) or
    (Abs(Restored.Rotation.Y - Pose.Rotation.Y) > 0.0001) or
    (Abs(Restored.Rotation.Z - Pose.Rotation.Z) > 0.0001) then
    raise Exception.Create('double mirrored bone pose did not restore source');
end;

procedure CheckPoseHistory;
var
  Current, Restored: TPmxBonePoses;
  History: TMmdPoseHistory;
begin
  History := TMmdPoseHistory.Create;
  try
    SetLength(Current, 1);
    Current[0].Rotation := IdentityQuaternion;
    History.RecordBeforeEdit(Current);
    Current[0].Translation.X := 12;
    if not History.Undo(Current, Restored) or
      (Abs(Restored[0].Translation.X) > 0.0001) or not History.CanRedo then
      raise Exception.Create('pose undo did not restore previous snapshot');
    if not History.Redo(Restored, Current) or
      (Abs(Current[0].Translation.X - 12) > 0.0001) then
      raise Exception.Create('pose redo did not restore edited snapshot');
    if not History.Undo(Current, Restored) then
      raise Exception.Create('second pose undo failed');
    History.RecordBeforeEdit(Restored);
    if History.CanRedo then
      raise Exception.Create('new pose edit did not clear redo history');
  finally
    History.Free;
  end;
end;

procedure CheckResetBoneBranch;
var
  BoneIndex, ResetCount: Integer;
  Model: TPmxModel;
  Poses: TPmxBonePoses;
begin
  Model := TPmxModel.Create;
  try
    SetLength(Model.Bones, 5);
    Model.Bones[0].ParentIndex := -1;
    Model.Bones[1].ParentIndex := 0;
    Model.Bones[2].ParentIndex := 1;
    Model.Bones[3].ParentIndex := 0;
    Model.Bones[4].ParentIndex := -1;
    SetLength(Poses, 5);
    for BoneIndex := 0 to High(Poses) do
    begin
      Poses[BoneIndex].Translation.X := BoneIndex + 1;
      Poses[BoneIndex].Rotation := IdentityQuaternion;
    end;
    ResetCount := ResetBoneBranch(Model, 1, Poses);
    if ResetCount <> 2 then
      raise Exception.CreateFmt('bone branch reset count failed: %d',
        [ResetCount]);
    if (Abs(Poses[1].Translation.X) > 0.0001) or
      (Abs(Poses[2].Translation.X) > 0.0001) or
      (Abs(Poses[0].Translation.X - 1) > 0.0001) or
      (Abs(Poses[3].Translation.X - 4) > 0.0001) or
      (Abs(Poses[4].Translation.X - 5) > 0.0001) then
      raise Exception.Create('bone branch reset changed another hierarchy');
  finally
    Model.Free;
  end;
end;

function IsSelectedColor(const Vertex: TMmdPreviewVertex): Boolean;
begin
  Result := (Abs(Vertex.R - 1.0) < 0.001) and
    (Abs(Vertex.G - 0.25) < 0.001) and
    (Abs(Vertex.B - 0.1) < 0.001);
end;

function IsLockedColor(const Vertex: TMmdPreviewVertex): Boolean;
begin
  Result := (Abs(Vertex.R - 0.55) < 0.001) and
    (Abs(Vertex.G - 0.03) < 0.001) and
    (Abs(Vertex.B - 0.06) < 0.001);
end;

procedure CheckSelectionAppearance(Model: TPmxModel; const Poses: TPmxBonePoses);
var
  BoneIndex, LockedCount, OrangeCount: Integer;
  HoverTarget, SelectedTarget: TMmdPreviewTarget;
  Scene: TMmdPreviewScene;
  Vertex: TMmdPreviewVertex;
begin
  BoneIndex := 0;
  while (BoneIndex <= High(Model.Bones)) and
    (Model.Bones[BoneIndex].ParentIndex < 0) do
    Inc(BoneIndex);
  if BoneIndex > High(Model.Bones) then
    raise Exception.Create('model has no selectable bone segment');
  SelectedTarget := EmptyPreviewTarget;
  SelectedTarget.Kind := ptBone;
  SelectedTarget.BoneIndex := BoneIndex;
  SelectedTarget.JointIndex := Model.Bones[BoneIndex].ParentIndex;
  HoverTarget := EmptyPreviewTarget;
  BuildPreviewScene(Model, Poses, nil, SelectedTarget, HoverTarget, Scene);
  BuildPreviewBoneShapes(Scene.Joints, Scene.BoneSegments, SelectedTarget,
    HoverTarget, Scene.Projection.ModelHeight, Scene.BoneShapes);
  OrangeCount := 0;
  for Vertex in Scene.BoneShapes do
    if IsSelectedColor(Vertex) then
      Inc(OrangeCount);
  if OrangeCount <> 210 then
    raise Exception.CreateFmt(
      'bone selection must show one pyramid and its start joint sphere: %d vertices',
      [OrangeCount]);
  SelectedTarget.Locked := True;
  BuildPreviewBoneShapes(Scene.Joints, Scene.BoneSegments, SelectedTarget,
    HoverTarget, Scene.Projection.ModelHeight, Scene.BoneShapes);
  LockedCount := 0;
  for Vertex in Scene.BoneShapes do
    if IsLockedColor(Vertex) then
      Inc(LockedCount);
  if LockedCount <> 210 then
    raise Exception.CreateFmt(
      'locked bone must show a red pyramid and joint sphere: %d vertices',
      [LockedCount]);
end;

begin
  Application.Initialize;
  try
    CheckBoneHitTesting;
    CheckJointDragMath;
    CheckBoneAxisDragMath;
    CheckBoneRotationSnapMath;
    CheckFixedViewMath;
    CheckPoseHistory;
    CheckResetBoneBranch;
    Form := TForm.Create(nil);
    try
      Form.SetBounds(100, 100, 720, 720);
      Viewport := TMmdD3DViewport.Create(Form);
      Viewport.Parent := Form;
      Viewport.Align := alClient;
      Model := GetCachedPmxModel(
        'D:\VoiceroidProj\MMD\ふらすこ式風きりたん_ver0.05\ふらすこ式風きりたん_ver0.05.pmx');
      InitializeBonePoses(Model, Poses);
      CheckPoseSymmetry(Model);
      CheckSelectionAppearance(Model, Poses);
      CheckAspectCorrection(Model, Poses);
      CheckCameraProjection(Model, Poses);
      CheckFixedPreviewFrame(Model, Poses);
      Viewport.SetScene(Model, Poses, 0);
      Form.Show;
      Application.ProcessMessages;
      CheckBoneMouseInteraction(Viewport, Model, Poses);
      CheckCameraInteractionPerformance(Viewport);
      CheckFixedViewKeyboard(Viewport);
      Sleep(250);
      Application.ProcessMessages;
      if Viewport.ErrorText <> '' then
        raise Exception.Create(Viewport.ErrorText);
      if Viewport.LoadedTextureCount = 0 then
        raise Exception.Create('preview textures were not loaded');
    finally
      Form.Free;
    end;
  except
    on E: Exception do
    begin
      OutputDebugString(PChar(E.Message));
      ExitCode := 1;
    end;
  end;
end.
