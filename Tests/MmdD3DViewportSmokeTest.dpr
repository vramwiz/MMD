program MmdD3DViewportSmokeTest;

{$APPTYPE GUI}

uses
  Winapi.Windows,
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
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
  MmdD3DViewport in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewport.pas';

var
  Form: TForm;
  Model: TPmxModel;
  Poses: TPmxBonePoses;
  Viewport: TMmdD3DViewport;

function PixelAspect(const Scene: TMmdPreviewScene; Width, Height: Integer): Double;
var
  I: Integer;
  MaxX, MaxY, MinX, MinY: Single;
begin
  if Length(Scene.Triangles) = 0 then
    raise Exception.Create('preview scene has no triangles');
  MinX := Scene.Triangles[0].X;
  MaxX := MinX;
  MinY := Scene.Triangles[0].Y;
  MaxY := MinY;
  for I := 1 to High(Scene.Triangles) do
  begin
    MinX := Min(MinX, Scene.Triangles[I].X);
    MaxX := Max(MaxX, Scene.Triangles[I].X);
    MinY := Min(MinY, Scene.Triangles[I].Y);
    MaxY := Max(MaxY, Scene.Triangles[I].Y);
  end;
  Result := ((MaxX - MinX) * Width) / ((MaxY - MinY) * Height);
end;

procedure CheckAspectCorrection(Model: TPmxModel; const Poses: TPmxBonePoses);
var
  Narrow, Square: TMmdPreviewScene;
begin
  BuildPreviewScene(Model, Poses, 0, 160, 315, Narrow);
  BuildPreviewScene(Model, Poses, 0, 315, 315, Square);
  if Abs(PixelAspect(Narrow, 160, 315) - PixelAspect(Square, 315, 315)) > 0.001 then
    raise Exception.Create('viewport aspect correction failed');
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
      Viewport.SetScene(Model, Poses, 0);
      Form.Show;
      Application.ProcessMessages;
      Sleep(250);
      Application.ProcessMessages;
      if Viewport.ErrorText <> '' then
        raise Exception.Create(Viewport.ErrorText);
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
