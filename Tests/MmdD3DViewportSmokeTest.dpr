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
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  PmxReader in 'Source\Lib\MMD\IO\PmxReader.pas',
  PmxBinaryStream in 'Source\Lib\MMD\IO\PmxBinaryStream.pas',
  PmxGeometryReader in 'Source\Lib\MMD\IO\PmxGeometryReader.pas',
  PmxMaterialReader in 'Source\Lib\MMD\IO\PmxMaterialReader.pas',
  PmxBoneReader in 'Source\Lib\MMD\IO\PmxBoneReader.pas',
  MmdD3DScene in 'Source\Lib\MMD\Editor\D3D\MmdD3DScene.pas',
  MmdD3DShaders in 'Source\Lib\MMD\Editor\D3D\MmdD3DShaders.pas',
  MmdD3DTextures in 'Source\Lib\MMD\Editor\D3D\MmdD3DTextures.pas',
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
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
  BuildPreviewScene(Model, Poses, 0, Scene);
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
  BaseCamera, RotatedCamera, ZoomCamera: TMmdPreviewCamera;
  BaseProjected, RotatedProjected: TPmxVector3;
  Scene: TMmdPreviewScene;
begin
  BaseCamera := DefaultPreviewCamera;
  RotatedCamera := BaseCamera;
  RotatedCamera.Yaw := DegToRad(35);
  RotatedCamera.Pitch := DegToRad(-20);
  ZoomCamera := BaseCamera;
  ZoomCamera.Zoom := 1.5;
  BuildPreviewScene(Model, Poses, 0, Scene);
  BaseProjected := ProjectVertex(Scene.Triangles[0], Scene, BaseCamera, 315, 315);
  RotatedProjected := ProjectVertex(Scene.Triangles[0], Scene, RotatedCamera, 315, 315);
  if (Abs(BaseProjected.X - RotatedProjected.X) < 0.001) and
    (Abs(BaseProjected.Y - RotatedProjected.Y) < 0.001) then
    raise Exception.Create('camera rotation did not change projection');
  if Abs(PixelHeight(Scene, ZoomCamera, 315, 315) /
    PixelHeight(Scene, BaseCamera, 315, 315) - 1.5) > 0.001 then
    raise Exception.Create('camera zoom scale failed');
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

begin
  Application.Initialize;
  try
    Form := TForm.Create(nil);
    try
      Form.SetBounds(100, 100, 720, 720);
      Viewport := TMmdD3DViewport.Create(Form);
      Viewport.Parent := Form;
      Viewport.Align := alClient;
      Model := GetCachedPmxModel(
        'D:\DelphiProg\test\MMD\Model\ふらすこ式風きりたん_ver0.05\ふらすこ式風きりたん_ver0.05.pmx');
      InitializeBonePoses(Model, Poses);
      CheckAspectCorrection(Model, Poses);
      CheckCameraProjection(Model, Poses);
      Viewport.SetScene(Model, Poses, 0);
      Form.Show;
      Application.ProcessMessages;
      CheckCameraInteractionPerformance(Viewport);
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
