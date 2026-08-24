library MMD_Model_Filter;

// MMDモデル表示フィルターのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PmxModel in 'Source\Lib\MMD\Core\PmxModel.pas',
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  PmxPoseCodec in 'Source\Lib\MMD\IO\PmxPoseCodec.pas',
  MmdPoseSharedMemory in 'Source\Lib\MMD\IPC\MmdPoseSharedMemory.pas',
  PmxReader in 'Source\Lib\MMD\IO\PmxReader.pas',
  PmxBinaryStream in 'Source\Lib\MMD\IO\PmxBinaryStream.pas',
  PmxGeometryReader in 'Source\Lib\MMD\IO\PmxGeometryReader.pas',
  PmxMaterialReader in 'Source\Lib\MMD\IO\PmxMaterialReader.pas',
  PmxBoneReader in 'Source\Lib\MMD\IO\PmxBoneReader.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  MMD_Model_FilterPlugin in 'Source\Plugin\Model\MMD_Model_FilterPlugin.pas',
  MMD_Model_Context in 'Source\Plugin\Model\Context\MMD_Model_Context.pas',
  MMD_Model_PoseInput in 'Source\Plugin\Model\Input\MMD_Model_PoseInput.pas',
  MMD_Model_Renderer in 'Source\Plugin\Model\Render\MMD_Model_Renderer.pas',
  MMD_Model_StandardPoseButton in 'Source\Plugin\Model\Editor\MMD_Model_StandardPoseButton.pas',
  MmdD3DScene in 'Source\Lib\MMD\Editor\D3D\MmdD3DScene.pas',
  MmdD3DShaders in 'Source\Lib\MMD\Editor\D3D\MmdD3DShaders.pas',
  MmdD3DTextures in 'Source\Lib\MMD\Editor\D3D\MmdD3DTextures.pas',
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
  MmdD3DViewport in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewport.pas',
  MmdPoseEditor in 'Source\Lib\MMD\Editor\MmdPoseEditor.pas';

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 1;
end;

procedure UninitializePlugin; cdecl;
begin
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := GetModelFilterTable;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
