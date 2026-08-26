unit MmdAiProvider;

// AI MIRAIから呼び出す、Delphiランタイム非依存のUTF-8 JSON境界を提供する。

interface

const
  MMD_AI_PROVIDER_VERSION = 1;

function MmdAiProviderGetVersion: Cardinal; cdecl;
function MmdAiProviderInvoke(RequestUtf8, ResponseUtf8: PAnsiChar;
  ResponseCapacity: Cardinal): Integer; cdecl;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.Math,
  System.SysUtils,
  MmdAiSchema,
  PmxModel,
  PmxPose,
  PmxPoseCodec,
  PmxReader;

const
  MAX_REQUEST_CHARS = 1024 * 1024;
  MAX_POSE_BONES = 4096;

function ErrorJson(const Code, MessageText: string): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('status', 'error');
    Root.AddPair('code', Code);
    Root.AddPair('message', MessageText);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function VectorJson(const Value: TPmxVector3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(Value.X);
  Result.Add(Value.Y);
  Result.Add(Value.Z);
end;

function QuaternionJson(const Value: TPmxQuaternion): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(Value.X);
  Result.Add(Value.Y);
  Result.Add(Value.Z);
  Result.Add(Value.W);
end;

function ReadNumber(const Values: TJSONArray; Index: Integer;
  out Number: Single): Boolean;
begin
  Result := (Values <> nil) and (Index >= 0) and (Index < Values.Count) and
    (Values.Items[Index] is TJSONNumber);
  if not Result then
    Exit;
  Number := TJSONNumber(Values.Items[Index]).AsDouble;
  Result := not IsNan(Number) and not IsInfinite(Number);
end;

function ReadVector(const Value: TJSONValue; out Vector: TPmxVector3): Boolean;
var
  Values: TJSONArray;
begin
  Result := Value is TJSONArray;
  if not Result then
    Exit;
  Values := TJSONArray(Value);
  Result := (Values.Count = 3) and ReadNumber(Values, 0, Vector.X) and
    ReadNumber(Values, 1, Vector.Y) and ReadNumber(Values, 2, Vector.Z);
end;

function ReadQuaternion(const Value: TJSONValue;
  out Rotation: TPmxQuaternion): Boolean;
var
  Values: TJSONArray;
begin
  Result := Value is TJSONArray;
  if not Result then
    Exit;
  Values := TJSONArray(Value);
  Result := (Values.Count = 4) and ReadNumber(Values, 0, Rotation.X) and
    ReadNumber(Values, 1, Rotation.Y) and ReadNumber(Values, 2, Rotation.Z) and
    ReadNumber(Values, 3, Rotation.W) and
    ((Sqr(Rotation.X) + Sqr(Rotation.Y) + Sqr(Rotation.Z) +
      Sqr(Rotation.W)) > 0.000001);
  if Result then
    Rotation := NormalizeQuaternion(Rotation);
end;

function IsIdentityPose(const Pose: TPmxBonePose): Boolean;
begin
  Result := (Abs(Pose.Translation.X) < 0.000001) and
    (Abs(Pose.Translation.Y) < 0.000001) and
    (Abs(Pose.Translation.Z) < 0.000001) and
    (Abs(Pose.Rotation.X) < 0.000001) and
    (Abs(Pose.Rotation.Y) < 0.000001) and
    (Abs(Pose.Rotation.Z) < 0.000001) and
    (Abs(Abs(Pose.Rotation.W) - 1) < 0.000001);
end;

function EncodePoses(const Model: TPmxModel;
  const Poses: TPmxBonePoses): string;
var
  I, Count: Integer;
  Named: TPmxNamedBonePoses;
begin
  SetLength(Named, Length(Poses));
  Count := 0;
  for I := 0 to High(Poses) do
    if not IsIdentityPose(Poses[I]) then
    begin
      Named[Count].BoneName := Model.Bones[I].Name;
      Named[Count].Pose := Poses[I];
      Inc(Count);
    end;
  SetLength(Named, Count);
  Result := EncodePoseData(Named);
end;

function BuildCapabilities: string;
var
  Operations: TJSONArray;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('status', 'ok');
    Root.AddPair('extension', 'mmd.pose');
    Root.AddPair('provider_version', TJSONNumber.Create(MMD_AI_PROVIDER_VERSION));
    Operations := TJSONArray.Create;
    Operations.Add('get_model_schema');
    Operations.Add('preview_pose');
    Root.AddPair('operations', Operations);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function PreviewPose(const ModelFile, CurrentPose: string;
  Payload: TJSONObject): string;
var
  BoneArray, Euler: TJSONArray;
  BoneIndex, I: Integer;
  BoneObject, Resolved: TJSONObject;
  CurrentNamed: TPmxNamedBonePoses;
  Mode, Name, PoseData: string;
  Model: TPmxModel;
  Poses: TPmxBonePoses;
  ResolvedBones: TJSONArray;
  Root: TJSONObject;
  Touched: TArray<Boolean>;
  Transforms: TPmxBoneTransforms;
  Translation: TPmxVector3;
begin
  if Payload = nil then
    Exit(ErrorJson('invalid_payload', 'payload must be an object.'));
  Mode := 'replace';
  if Payload.GetValue('mode') is TJSONString then
    Mode := TJSONString(Payload.GetValue('mode')).Value;
  if not SameText(Mode, 'replace') and not SameText(Mode, 'merge') then
    Exit(ErrorJson('invalid_mode', 'mode must be replace or merge.'));
  if not (Payload.GetValue('bones') is TJSONArray) then
    Exit(ErrorJson('invalid_bones', 'payload.bones must be an array.'));
  BoneArray := TJSONArray(Payload.GetValue('bones'));
  if BoneArray.Count > MAX_POSE_BONES then
    Exit(ErrorJson('too_many_bones', 'payload.bones exceeds the limit.'));
  Model := GetCachedPmxModel(ModelFile);
  InitializeBonePoses(Model, Poses);
  if SameText(Mode, 'merge') and (CurrentPose <> '') then
  begin
    if not TryDecodePoseData(CurrentPose, CurrentNamed) then
      Exit(ErrorJson('invalid_current_pose', 'current_pose is invalid.'));
    for I := 0 to High(CurrentNamed) do
      if FindBoneIndex(Model, CurrentNamed[I].BoneName) < 0 then
        Exit(ErrorJson('current_pose_bone_not_found',
          'current_pose contains an unknown bone: ' +
          CurrentNamed[I].BoneName));
    ApplyNamedBonePoses(Model, CurrentNamed, Poses);
  end;
  SetLength(Touched, Length(Model.Bones));
  for I := 0 to BoneArray.Count - 1 do
  begin
    if not (BoneArray.Items[I] is TJSONObject) then
      Exit(ErrorJson('invalid_bone', Format('bones[%d] must be an object.', [I])));
    BoneObject := TJSONObject(BoneArray.Items[I]);
    if not (BoneObject.GetValue('name') is TJSONString) then
      Exit(ErrorJson('invalid_bone_name', Format('bones[%d].name is required.', [I])));
    Name := TJSONString(BoneObject.GetValue('name')).Value;
    BoneIndex := FindBoneIndex(Model, Name);
    if BoneIndex < 0 then
      Exit(ErrorJson('bone_not_found', 'Unknown bone: ' + Name));
    if Touched[BoneIndex] then
      Exit(ErrorJson('duplicate_bone', 'Bone is specified more than once: ' + Name));
    Touched[BoneIndex] := True;
    if BoneObject.GetValue('translation') <> nil then
    begin
      if not ReadVector(BoneObject.GetValue('translation'), Translation) then
        Exit(ErrorJson('invalid_translation', 'Invalid translation: ' + Name));
      Poses[BoneIndex].Translation := Translation;
    end;
    if (BoneObject.GetValue('rotation') <> nil) and
       (BoneObject.GetValue('rotation_euler_degrees') <> nil) then
      Exit(ErrorJson('ambiguous_rotation',
        'Specify rotation or rotation_euler_degrees, not both: ' + Name));
    if BoneObject.GetValue('rotation') <> nil then
    begin
      if not ReadQuaternion(BoneObject.GetValue('rotation'),
        Poses[BoneIndex].Rotation) then
        Exit(ErrorJson('invalid_rotation', 'Invalid rotation: ' + Name));
    end
    else if BoneObject.GetValue('rotation_euler_degrees') <> nil then
    begin
      if not (BoneObject.GetValue('rotation_euler_degrees') is TJSONArray) then
        Exit(ErrorJson('invalid_euler_rotation', 'Invalid Euler rotation: ' + Name));
      Euler := TJSONArray(BoneObject.GetValue('rotation_euler_degrees'));
      if not ReadVector(Euler, Translation) then
        Exit(ErrorJson('invalid_euler_rotation', 'Invalid Euler rotation: ' + Name));
      Poses[BoneIndex].Rotation := QuaternionFromEulerXYZ(
        DegToRad(Translation.X), DegToRad(Translation.Y),
        DegToRad(Translation.Z));
    end;
  end;
  PoseData := EncodePoses(Model, Poses);
  CalculateBoneTransforms(Model, Poses, Transforms);
  Root := TJSONObject.Create;
  try
    Root.AddPair('status', 'ok');
    Root.AddPair('extension', 'mmd.pose');
    Root.AddPair('operation', 'preview_pose');
    Root.AddPair('pose_data', PoseData);
    Root.AddPair('bone_count', TJSONNumber.Create(BoneArray.Count));
    ResolvedBones := TJSONArray.Create;
    Root.AddPair('resolved_bones', ResolvedBones);
    for I := 0 to High(Touched) do
      if Touched[I] then
      begin
        Resolved := TJSONObject.Create;
        ResolvedBones.AddElement(Resolved);
        Resolved.AddPair('index', TJSONNumber.Create(I));
        Resolved.AddPair('name', Model.Bones[I].Name);
        Resolved.AddPair('translation', VectorJson(Poses[I].Translation));
        Resolved.AddPair('rotation', QuaternionJson(Poses[I].Rotation));
        Resolved.AddPair('final_position', VectorJson(Transforms[I].Position));
      end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function HandleRequest(const RequestText: string): string;
var
  Json, PayloadValue: TJSONValue;
  ModelFile, Operation, CurrentPose: string;
  Root: TJSONObject;
begin
  if (RequestText = '') or (Length(RequestText) > MAX_REQUEST_CHARS) then
    Exit(ErrorJson('invalid_request', 'Request is empty or too large.'));
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    if not (Json is TJSONObject) then
      Exit(ErrorJson('invalid_json', 'Request must be a JSON object.'));
    Root := TJSONObject(Json);
    if not (Root.GetValue('operation') is TJSONString) then
      Exit(ErrorJson('invalid_operation', 'operation is required.'));
    Operation := TJSONString(Root.GetValue('operation')).Value;
    if SameText(Operation, 'get_capabilities') then
      Exit(BuildCapabilities);
    if not (Root.GetValue('model_file') is TJSONString) then
      Exit(ErrorJson('invalid_model_file', 'model_file is required.'));
    ModelFile := TJSONString(Root.GetValue('model_file')).Value;
    if ModelFile = '' then
      Exit(ErrorJson('invalid_model_file', 'model_file must not be empty.'));
    if SameText(Operation, 'get_model_schema') then
      Exit(BuildMmdModelSchema(ModelFile));
    if SameText(Operation, 'preview_pose') then
    begin
      CurrentPose := '';
      if Root.GetValue('current_pose') is TJSONString then
        CurrentPose := TJSONString(Root.GetValue('current_pose')).Value;
      PayloadValue := Root.GetValue('payload');
      if not (PayloadValue is TJSONObject) then
        Exit(ErrorJson('invalid_payload', 'payload must be an object.'));
      Exit(PreviewPose(ModelFile, CurrentPose, TJSONObject(PayloadValue)));
    end;
    Result := ErrorJson('unsupported_operation',
      'The requested MMD operation is not supported.');
  finally
    Json.Free;
  end;
end;

function MmdAiProviderGetVersion: Cardinal; cdecl;
begin
  Result := MMD_AI_PROVIDER_VERSION;
end;

function MmdAiProviderInvoke(RequestUtf8, ResponseUtf8: PAnsiChar;
  ResponseCapacity: Cardinal): Integer; cdecl;
var
  RequestText, ResponseText: string;
  Utf8: UTF8String;
begin
  try
    if RequestUtf8 = nil then
      ResponseText := ErrorJson('invalid_request', 'Request pointer is nil.')
    else
    begin
      RequestText := UTF8ToString(UTF8String(RequestUtf8));
      ResponseText := HandleRequest(RequestText);
    end;
  except
    on E: Exception do
      ResponseText := ErrorJson('provider_error', E.Message);
  end;
  Utf8 := UTF8String(ResponseText);
  Result := Length(Utf8);
  if (ResponseUtf8 = nil) or (ResponseCapacity <= Cardinal(Result)) then
    Exit;
  if Result > 0 then
    Move(PAnsiChar(Utf8)^, ResponseUtf8^, Result);
  ResponseUtf8[Result] := #0;
end;

end.
