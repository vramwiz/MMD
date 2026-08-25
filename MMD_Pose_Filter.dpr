library MMD_Pose_Filter;

// MMDポーズレイヤーのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  MmdPoseSharedMemory in 'Source\Lib\MMD\IPC\MmdPoseSharedMemory.pas',
  PmxModel in 'Source\Lib\MMD\Core\PmxModel.pas',
  PmxPoseTypes in 'Source\Lib\MMD\Core\PmxPoseTypes.pas',
  PmxPoseMath in 'Source\Lib\MMD\Core\PmxPoseMath.pas',
  PmxMorph in 'Source\Lib\MMD\Core\PmxMorph.pas',
  PmxBoneSolver in 'Source\Lib\MMD\Core\PmxBoneSolver.pas',
  PmxPose in 'Source\Lib\MMD\Core\PmxPose.pas',
  PmxPoseCodec in 'Source\Lib\MMD\IO\PmxPoseCodec.pas',
  PmxReader in 'Source\Lib\MMD\IO\PmxReader.pas',
  PmxBinaryStream in 'Source\Lib\MMD\IO\PmxBinaryStream.pas',
  PmxGeometryReader in 'Source\Lib\MMD\IO\PmxGeometryReader.pas',
  PmxMaterialReader in 'Source\Lib\MMD\IO\PmxMaterialReader.pas',
  PmxBoneReader in 'Source\Lib\MMD\IO\PmxBoneReader.pas',
  PmxMorphReader in 'Source\Lib\MMD\IO\PmxMorphReader.pas',
  MmdD3DScene in 'Source\Lib\MMD\Editor\D3D\MmdD3DScene.pas',
  MmdD3DSelection in 'Source\Lib\MMD\Editor\D3D\MmdD3DSelection.pas',
  MmdD3DInteraction in 'Source\Lib\MMD\Editor\D3D\MmdD3DInteraction.pas',
  MmdD3DShapes in 'Source\Lib\MMD\Editor\D3D\MmdD3DShapes.pas',
  MmdD3DBuffers in 'Source\Lib\MMD\Editor\D3D\MmdD3DBuffers.pas',
  MmdD3DCapture in 'Source\Lib\MMD\Editor\D3D\MmdD3DCapture.pas',
  MmdD3DOverlay in 'Source\Lib\MMD\Editor\D3D\MmdD3DOverlay.pas',
  MmdD3DShaders in 'Source\Lib\MMD\Editor\D3D\MmdD3DShaders.pas',
  MmdD3DTextures in 'Source\Lib\MMD\Editor\D3D\MmdD3DTextures.pas',
  MmdD3DDevice in 'Source\Lib\MMD\Editor\D3D\MmdD3DDevice.pas',
  MmdD3DDeform in 'Source\Lib\MMD\Editor\D3D\MmdD3DDeform.pas',
  MmdD3DRenderer in 'Source\Lib\MMD\Editor\D3D\MmdD3DRenderer.pas',
  MmdPoseSymmetry in 'Source\Lib\MMD\Editor\MmdPoseSymmetry.pas',
  MmdD3DViewportSurface in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewportSurface.pas',
  MmdD3DLiveDragTest in 'Source\Lib\MMD\Editor\D3D\Temporary\MmdD3DLiveDragTest.pas',
  MmdD3DViewport in 'Source\Lib\MMD\Editor\D3D\MmdD3DViewport.pas',
  MmdPoseHistory in 'Source\Lib\MMD\Editor\MmdPoseHistory.pas',
  MmdPoseEditOperations in 'Source\Lib\MMD\Editor\MmdPoseEditOperations.pas',
  MmdMorphPreviewPanel in 'Source\Lib\MMD\Editor\MmdMorphPreviewPanel.pas',
  MmdPoseImageAutoFit in 'Source\Lib\MMD\Editor\MmdPoseImageAutoFit.pas',
  MmdPoseImageClipboard in 'Source\Lib\MMD\Editor\MmdPoseImageClipboard.pas',
  MmdPoseEditorLayout in 'Source\Lib\MMD\Editor\MmdPoseEditorLayout.pas',
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
