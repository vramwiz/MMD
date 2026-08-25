unit MmdD3DDeform;

// ポーズと一時モーフ係数を合成し、D3Dプレビュー用の変形結果を生成する。

interface

uses
  PmxModel,
  PmxMorph,
  PmxPose;

// モーフ済み頂点とボーン姿勢を使ってCPUスキニングする。
procedure DeformPreviewModel(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; out Transforms: TPmxBoneTransforms;
  out Skinned: TPmxSkinnedVertices);
// 本体と同じIK適用後の骨格計算へボーンモーフを含む作業姿勢を渡す。
procedure CalculatePreviewSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; out Transforms: TPmxBoneTransforms);

implementation

uses
  PmxBoneSolver;

procedure ApplyPreviewMorphs(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; out WorkPoses: TPmxBonePoses;
  out Positions: TPmxVertexPositions);
begin
  WorkPoses := Copy(Poses);
  ApplyMorphs(Model, MorphWeights, WorkPoses, Positions);
end;

procedure DeformPreviewModel(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; out Transforms: TPmxBoneTransforms;
  out Skinned: TPmxSkinnedVertices);
var
  Positions: TPmxVertexPositions;
  WorkPoses: TPmxBonePoses;
begin
  ApplyPreviewMorphs(Model, Poses, MorphWeights, WorkPoses, Positions);
  CalculateBoneTransforms(Model, WorkPoses, Transforms);
  SkinVerticesLinear(Model, Positions, Transforms, Skinned);
end;

procedure CalculatePreviewSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
  const MorphWeights: TPmxMorphWeights; out Transforms: TPmxBoneTransforms);
var
  UnusedPositions: TPmxVertexPositions;
  WorkPoses: TPmxBonePoses;
begin
  ApplyPreviewMorphs(Model, Poses, MorphWeights, WorkPoses, UnusedPositions);
  CalculateFinalBoneTransforms(Model, WorkPoses, Transforms);
end;

end.
