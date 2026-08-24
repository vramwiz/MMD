program MmdMorphTest;

{$APPTYPE CONSOLE}

uses
  System.IOUtils,
  System.Math,
  System.SysUtils,
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
  PmxMorphReader in 'Source\Lib\MMD\IO\PmxMorphReader.pas';

procedure CheckNear(Actual, Expected: Single; const Name: string);
begin
  if Abs(Actual - Expected) > 0.0001 then
    raise Exception.CreateFmt('%s: expected %.6f, got %.6f',
      [Name, Expected, Actual]);
end;

procedure TestGroupedVertexAndBoneMorph;
var
  Model: TPmxModel;
  Positions: TPmxVertexPositions;
  Poses: TPmxBonePoses;
  Skinned: TPmxSkinnedVertices;
  Transforms: TPmxBoneTransforms;
  Weights: TPmxMorphWeights;
begin
  Model := TPmxModel.Create;
  try
    SetLength(Model.Vertices, 1);
    Model.Vertices[0].DeformType := pdtBdef1;
    Model.Vertices[0].BoneIndices[0] := 0;
    Model.Vertices[0].BoneWeights[0] := 1;
    SetLength(Model.Bones, 1);
    Model.Bones[0].ParentIndex := -1;
    SetLength(Model.Morphs, 3);
    Model.Morphs[0].MorphType := pmtVertex;
    SetLength(Model.Morphs[0].VertexOffsets, 1);
    Model.Morphs[0].VertexOffsets[0].Offset.X := 2;
    Model.Morphs[1].MorphType := pmtBone;
    SetLength(Model.Morphs[1].BoneOffsets, 1);
    Model.Morphs[1].BoneOffsets[0].Translation.Y := 3;
    Model.Morphs[1].BoneOffsets[0].Rotation.W := Cos(Pi / 4);
    Model.Morphs[1].BoneOffsets[0].Rotation.Z := Sin(Pi / 4);
    Model.Morphs[2].MorphType := pmtGroup;
    SetLength(Model.Morphs[2].GroupOffsets, 2);
    Model.Morphs[2].GroupOffsets[0].MorphIndex := 0;
    Model.Morphs[2].GroupOffsets[0].Weight := 0.4;
    Model.Morphs[2].GroupOffsets[1].MorphIndex := 1;
    Model.Morphs[2].GroupOffsets[1].Weight := 0.4;
    InitializeBonePoses(Model, Poses);
    InitializeMorphWeights(Model, Weights);
    Weights[2] := 0.5;
    ApplyMorphs(Model, Weights, Poses, Positions);
    CheckNear(Positions[0].X, 0.4, 'grouped vertex');
    CheckNear(Poses[0].Translation.Y, 0.6, 'grouped bone translation');
    CheckNear(Poses[0].Rotation.W, Cos(Pi / 20), 'grouped bone rotation');
    CalculateBoneTransforms(Model, Poses, Transforms);
    SkinVerticesLinear(Model, Positions, Transforms, Skinned);
    CheckNear(Skinned[0].Position.X, 0.4 * Cos(Pi / 10), 'morphed skin x');
    CheckNear(Skinned[0].Position.Y, 0.6 + 0.4 * Sin(Pi / 10),
      'morphed skin y');
  finally
    Model.Free;
  end;
end;

procedure TestRealModel;
var
  FileNames: TArray<string>;
  Model: TPmxModel;
begin
  FileNames := TDirectory.GetFiles(TPath.Combine(GetCurrentDir, 'Model'),
    '*.pmx', TSearchOption.soAllDirectories);
  if Length(FileNames) = 0 then
    raise Exception.Create('real PMX test model was not found');
  Model := GetCachedPmxModel(FileNames[0]);
  if Length(Model.Morphs) = 0 then
    raise Exception.Create('real PMX has no morphs');
  Writeln(Format('Real model: morphs=%d', [Length(Model.Morphs)]));
end;

begin
  try
    TestGroupedVertexAndBoneMorph;
    TestRealModel;
    Writeln('MmdMorphTest: PASS');
  except
    on E: Exception do
    begin
      Writeln('MmdMorphTest: FAIL: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
