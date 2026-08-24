unit PmxMorph;

// モーフ係数のグループ展開と、頂点・ボーン変位の合成を担当する。

interface

uses
  PmxModel,
  PmxPoseTypes;

type
  TPmxMorphWeights = array of Single;
  TPmxVertexPositions = array of TPmxVector3;

// Modelのモーフ数に合わせ、全要素が0の係数配列を作る。
procedure InitializeMorphWeights(const Model: TPmxModel; var Weights: TPmxMorphWeights);
// 日本語名に一致するモーフIndexを返す。見つからない場合は-1を返す。
function FindMorphIndex(const Model: TPmxModel; const MorphName: string): Integer;
// グループ・フリップ参照を再帰展開し、実際に適用するモーフ別係数へ変換する。
procedure ResolveMorphWeights(const Model: TPmxModel; const Input: TPmxMorphWeights;
  var Effective: TPmxMorphWeights);
// 係数を初期頂点位置と既存ローカル姿勢へ合成する。Model自体は変更しない。
procedure ApplyMorphs(const Model: TPmxModel; const Weights: TPmxMorphWeights;
  var Poses: TPmxBonePoses; var Positions: TPmxVertexPositions);

implementation

uses
  System.Math,
  System.SysUtils,
  PmxPoseMath;

type
  TExpansionStack = array of Boolean;

procedure ExpandMorph(const Model: TPmxModel; MorphIndex: Integer; Weight: Single;
  var Stack: TExpansionStack; var Effective: TPmxMorphWeights);
var
  Offset: TPmxGroupMorphOffset;
begin
  if Abs(Weight) <= 0.000001 then
    Exit;
  if Stack[MorphIndex] then
    raise EInvalidOpException.CreateFmt('PMX morph reference cycle at index %d',
      [MorphIndex]);
  if Model.Morphs[MorphIndex].MorphType in [pmtGroup, pmtFlip] then
  begin
    Stack[MorphIndex] := True;
    try
      for Offset in Model.Morphs[MorphIndex].GroupOffsets do
        ExpandMorph(Model, Offset.MorphIndex, Weight * Offset.Weight,
          Stack, Effective);
    finally
      Stack[MorphIndex] := False;
    end;
  end
  else
    Effective[MorphIndex] := Effective[MorphIndex] + Weight;
end;

procedure InitializeMorphWeights(const Model: TPmxModel; var Weights: TPmxMorphWeights);
begin
  SetLength(Weights, Length(Model.Morphs));
  if Length(Weights) > 0 then
    FillChar(Weights[0], Length(Weights) * SizeOf(Single), 0);
end;

function FindMorphIndex(const Model: TPmxModel; const MorphName: string): Integer;
begin
  for Result := 0 to High(Model.Morphs) do
    if SameText(Model.Morphs[Result].Name, MorphName) then
      Exit;
  Result := -1;
end;

procedure ResolveMorphWeights(const Model: TPmxModel; const Input: TPmxMorphWeights;
  var Effective: TPmxMorphWeights);
var
  I: Integer;
  Stack: TExpansionStack;
begin
  InitializeMorphWeights(Model, Effective);
  SetLength(Stack, Length(Model.Morphs));
  for I := 0 to Min(High(Input), High(Model.Morphs)) do
    ExpandMorph(Model, I, Input[I], Stack, Effective);
end;

function MorphQuaternion(const Value: TPmxVector4): TPmxQuaternion;
begin
  Result.X := Value.X;
  Result.Y := Value.Y;
  Result.Z := Value.Z;
  Result.W := Value.W;
end;

procedure ApplyMorphs(const Model: TPmxModel; const Weights: TPmxMorphWeights;
  var Poses: TPmxBonePoses; var Positions: TPmxVertexPositions);
var
  BoneOffset: TPmxBoneMorphOffset;
  Effective: TPmxMorphWeights;
  I: Integer;
  Rotation: TPmxQuaternion;
  VertexOffset: TPmxVertexMorphOffset;
begin
  SetLength(Positions, Length(Model.Vertices));
  for I := 0 to High(Model.Vertices) do
    Positions[I] := Model.Vertices[I].Position;
  ResolveMorphWeights(Model, Weights, Effective);
  for I := 0 to High(Model.Morphs) do
    if Abs(Effective[I]) > 0.000001 then
    begin
      for VertexOffset in Model.Morphs[I].VertexOffsets do
        Positions[VertexOffset.VertexIndex] := AddVector(
          Positions[VertexOffset.VertexIndex],
          ScaleVector(VertexOffset.Offset, Effective[I]));
      for BoneOffset in Model.Morphs[I].BoneOffsets do
      begin
        if BoneOffset.BoneIndex >= Length(Poses) then
          Continue;
        Poses[BoneOffset.BoneIndex].Translation := AddVector(
          Poses[BoneOffset.BoneIndex].Translation,
          ScaleVector(BoneOffset.Translation, Effective[I]));
        Rotation := ScaleQuaternionRotation(MorphQuaternion(BoneOffset.Rotation),
          Effective[I]);
        Poses[BoneOffset.BoneIndex].Rotation := NormalizeQuaternion(
          MultiplyQuaternion(Poses[BoneOffset.BoneIndex].Rotation, Rotation));
      end;
    end;
end;

end.
