unit MmdAiSchema;

// AIが姿勢を組み立てるためのPMXボーン構造をJSONへ変換する。

interface

function BuildMmdModelSchema(const ModelFile: string): string;

implementation

uses
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  PmxModel,
  PmxReader;

function VectorJson(const Value: TPmxVector3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(Value.X);
  Result.Add(Value.Y);
  Result.Add(Value.Z);
end;

function BuildMmdModelSchema(const ModelFile: string): string;
var
  BoneJson, LinkJson: TJSONObject;
  Bones, Links: TJSONArray;
  I, J: Integer;
  Model: TPmxModel;
  Root: TJSONObject;
begin
  Model := GetCachedPmxModel(ModelFile);
  Root := TJSONObject.Create;
  try
    Root.AddPair('status', 'ok');
    Root.AddPair('extension', 'mmd.pose');
    Root.AddPair('operation', 'get_model_schema');
    Root.AddPair('model_file', Model.SourcePath);
    Root.AddPair('model_path_hash', 'sha256:' + LowerCase(
      THashSHA2.GetHashString(LowerCase(TPath.GetFullPath(ModelFile)))));
    Root.AddPair('model_name', Model.Name);
    Bones := TJSONArray.Create;
    Root.AddPair('bones', Bones);
    for I := 0 to High(Model.Bones) do
    begin
      BoneJson := TJSONObject.Create;
      Bones.AddElement(BoneJson);
      BoneJson.AddPair('index', TJSONNumber.Create(I));
      BoneJson.AddPair('name', Model.Bones[I].Name);
      BoneJson.AddPair('parent_index', TJSONNumber.Create(
        Model.Bones[I].ParentIndex));
      BoneJson.AddPair('position', VectorJson(Model.Bones[I].Position));
      BoneJson.AddPair('deform_layer', TJSONNumber.Create(
        Model.Bones[I].DeformLayer));
      BoneJson.AddPair('flags', TJSONNumber.Create(Model.Bones[I].Flags));
      BoneJson.AddPair('is_ik', TJSONBool.Create(
        (Model.Bones[I].Flags and PMX_BONE_FLAG_IK) <> 0));
      BoneJson.AddPair('inherit_parent_index', TJSONNumber.Create(
        Model.Bones[I].InheritParentIndex));
      BoneJson.AddPair('inherit_weight', TJSONNumber.Create(
        Model.Bones[I].InheritWeight));
      if (Model.Bones[I].Flags and PMX_BONE_FLAG_IK) <> 0 then
      begin
        BoneJson.AddPair('ik_target_index', TJSONNumber.Create(
          Model.Bones[I].IkTargetIndex));
        BoneJson.AddPair('ik_loop_count', TJSONNumber.Create(
          Model.Bones[I].IkLoopCount));
        BoneJson.AddPair('ik_angle_limit', TJSONNumber.Create(
          Model.Bones[I].IkAngleLimit));
        Links := TJSONArray.Create;
        BoneJson.AddPair('ik_links', Links);
        for J := 0 to High(Model.Bones[I].IkLinks) do
        begin
          LinkJson := TJSONObject.Create;
          Links.AddElement(LinkJson);
          LinkJson.AddPair('bone_index', TJSONNumber.Create(
            Model.Bones[I].IkLinks[J].BoneIndex));
          LinkJson.AddPair('has_limits', TJSONBool.Create(
            Model.Bones[I].IkLinks[J].HasLimits));
          if Model.Bones[I].IkLinks[J].HasLimits then
          begin
            LinkJson.AddPair('limit_min', VectorJson(
              Model.Bones[I].IkLinks[J].LimitMin));
            LinkJson.AddPair('limit_max', VectorJson(
              Model.Bones[I].IkLinks[J].LimitMax));
          end;
        end;
      end;
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
