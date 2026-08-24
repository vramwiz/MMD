program MmdRendererMaterialSelectionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PmxModel in 'Source\Lib\MMD\Core\PmxModel.pas',
  PmxPoseTypes in 'Source\Lib\MMD\Core\PmxPoseTypes.pas',
  PmxPoseMath in 'Source\Lib\MMD\Core\PmxPoseMath.pas',
  PmxMorph in 'Source\Lib\MMD\Core\PmxMorph.pas',
  PmxBoneSolver in 'Source\Lib\MMD\Core\PmxBoneSolver.pas',
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  MMD_Model_Renderer in 'Source\Plugin\Model\Render\MMD_Model_Renderer.pas';

procedure SetMaterialCounts(Model: TPmxModel; const Counts: array of Integer);
var
  I: Integer;
begin
  SetLength(Model.Materials, Length(Counts));
  for I := 0 to High(Counts) do
    Model.Materials[I].SurfaceCount := Counts[I];
end;

procedure CheckAllMaterialsAreSelected;
var
  DrawOrder: TArray<Integer>;
  I: Integer;
  Model: TPmxModel;
begin
  Model := TPmxModel.Create;
  try
    SetMaterialCounts(Model, [3000, 3000, 3000, 3000, 3000, 3000,
      3000, 3000, 3000, 3000, 3000, 3000]);
    DrawOrder := BuildPmxMaterialDrawOrder(Model);
    if Length(DrawOrder) <> 12 then
      raise Exception.Create('low polygon model did not select all materials');
    for I := 0 to High(DrawOrder) do
      if DrawOrder[I] <> I then
        raise Exception.CreateFmt('material %d was omitted', [I]);
  finally
    Model.Free;
  end;
end;

procedure CheckLargeModelFallback;
var
  DrawOrder: TArray<Integer>;
  Model: TPmxModel;
begin
  Model := TPmxModel.Create;
  try
    SetMaterialCounts(Model, [20000, 20000, 20000, 20000, 20000, 20000,
      20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000]);
    DrawOrder := BuildPmxMaterialDrawOrder(Model);
    if Length(DrawOrder) >= Length(Model.Materials) then
      raise Exception.Create('large model did not use the fallback order');
    if (Length(DrawOrder) < 8) or (DrawOrder[5] <> 6) or
      (DrawOrder[6] <> 12) then
      raise Exception.Create('fallback material priority changed');
  finally
    Model.Free;
  end;
end;

begin
  try
    CheckAllMaterialsAreSelected;
    CheckLargeModelFallback;
    Writeln('MmdRendererMaterialSelectionTest: PASS');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
