library MMD_Pose_Filter;

// MMDポーズレイヤーのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  MmdPoseSharedMemory in 'Source\Lib\MMD\IPC\MmdPoseSharedMemory.pas',
  PmxModel in 'Source\Lib\MMD\Core\PmxModel.pas',
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  PmxPoseCodec in 'Source\Lib\MMD\IO\PmxPoseCodec.pas',
  PmxReader in 'Source\Lib\MMD\IO\PmxReader.pas',
  PmxBinaryStream in 'Source\Lib\MMD\IO\PmxBinaryStream.pas',
  PmxGeometryReader in 'Source\Lib\MMD\IO\PmxGeometryReader.pas',
  PmxMaterialReader in 'Source\Lib\MMD\IO\PmxMaterialReader.pas',
  PmxBoneReader in 'Source\Lib\MMD\IO\PmxBoneReader.pas',
  MmdD3DScene in 'Source\Lib\MMD\Editor\D3D\MmdD3DScene.pas',
  MmdD3DShaders in 'Source\Lib\MMD\Editor\D3D\MmdD3DShaders.pas',
  MmdD3DTextures in 'Source\Lib\MMD\Editor\D3D\MmdD3DTextures.pas',
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
  MmdD3DViewport in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewport.pas',
  MmdPoseEditor in 'Source\Lib\MMD\Editor\MmdPoseEditor.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  MMD_Pose_FilterPlugin in 'Source\Plugin\Pose\MMD_Pose_FilterPlugin.pas';

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 1;
end;

procedure UninitializePlugin; cdecl;
begin
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := GetPoseFilterTable;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
