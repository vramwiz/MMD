unit MmdD3DRenderer;

// D3D11デバイス、SwapChain、描画先とGPU頂点バッファの寿命を管理する。

interface

uses
  Winapi.Windows,
  PmxModel,
  PmxMorph,
  PmxPose,
  MmdD3DScene;

type
  TMmdD3DRenderer = class
  private
    FImpl: TObject;
    function GetErrorText: string;
    function GetLoadedTextureCount: Integer;
    function GetProjection: TMmdPreviewProjection;
  public
    // 指定した子ウィンドウ専用のDeviceとSwapChainを生成する。失敗内容はErrorTextへ保持する。
    constructor Create(Window: HWND; Width, Height: Integer);
    destructor Destroy; override;
    // 保持中のGPUバッファを現在のRenderTargetへ描画してPresentする。
    procedure Render;
    // SwapChainと深度バッファを指定サイズへ作り直す。0以下のサイズは無視する。
    procedure Resize(Width, Height: Integer);
    // 姿勢からCPU頂点を再生成し、このRendererだけが所有するGPUバッファへ置き換える。
    procedure SetScene(Model: TPmxModel; const Poses: TPmxBonePoses;
      const MorphWeights: TPmxMorphWeights; const SelectedTarget,
      HoverTarget: TMmdPreviewTarget);
    // モデル三角形を維持し、ドラッグ中の骨格と選択形状だけを更新する。
    procedure SetSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
      const MorphWeights: TPmxMorphWeights; const SelectedTarget,
      HoverTarget: TMmdPreviewTarget);
    // 頂点バッファを変更せず、シェーダーへ渡すカメラ定数だけを更新する。
    procedure SetCamera(const Camera: TMmdPreviewCamera);
    // 現在のカメラ投影で指定画面座標にある関節またはボーン区間を返す。
    function HitTestTarget(X, Y: Integer): TMmdPreviewTarget;
    property ErrorText: string read GetErrorText;
    property LoadedTextureCount: Integer read GetLoadedTextureCount;
    property Projection: TMmdPreviewProjection read GetProjection;
  end;

implementation
uses
  Winapi.D3D11,
  Winapi.D3DCommon,
  Winapi.DXGI,
  Winapi.DxgiFormat,
  Winapi.DxgiType,
  System.Math,
  System.SysUtils,
  MmdD3DBuffers,
  MmdD3DDevice,
  MmdD3DOverlay,
  MmdD3DShapes,
  MmdD3DShaders,
  MmdD3DTextures;

type
  TMmdD3DRendererImpl = class
  private
    FContext: ID3D11DeviceContext;
    FBlendState: ID3D11BlendState;
    FCamera: TMmdPreviewCamera;
    FDepthTexture: ID3D11Texture2D;
    FDepthView: ID3D11DepthStencilView;
    FDevice: ID3D11Device;
    FErrorText: string;
    FFrameModel: TPmxModel;
    FHasFrame: Boolean;
    FTriangleBuffer: ID3D11Buffer;
    FTriangleCapacity: Integer;
    FTriangleCount: Cardinal;
    FCenter: TPmxVector3;
    FOverlay: TMmdD3DOverlay;
    FProjection: TMmdPreviewProjection;
    FRasterizerState: ID3D11RasterizerState;
    FRenderTarget: ID3D11RenderTargetView;
    FShaders: TMmdD3DShaders;
    FSwapChain: IDXGISwapChain;
    FTriangleBatches: TMmdPreviewBatches;
    FTextureModel: TPmxModel;
    FTextures: TMmdD3DTextures;
    FViewHeight, FViewWidth: Integer;
  public
    constructor Create(Window: HWND; Width, Height: Integer);
    destructor Destroy; override;
    procedure Render;
    procedure Resize(Width, Height: Integer);
    procedure SetScene(Model: TPmxModel; const Poses: TPmxBonePoses;
      const MorphWeights: TPmxMorphWeights; const SelectedTarget,
      HoverTarget: TMmdPreviewTarget);
    procedure SetSkeleton(Model: TPmxModel; const Poses: TPmxBonePoses;
      const MorphWeights: TPmxMorphWeights; const SelectedTarget,
      HoverTarget: TMmdPreviewTarget);
    procedure SetCamera(const Camera: TMmdPreviewCamera);
    function GetLoadedTextureCount: Integer;
    function GetProjection: TMmdPreviewProjection;
    function HitTestTarget(X, Y: Integer): TMmdPreviewTarget;
    property ErrorText: string read FErrorText;
  end;

constructor TMmdD3DRendererImpl.Create(Window: HWND; Width, Height: Integer);
begin
  inherited Create;
  FOverlay := TMmdD3DOverlay.Create;
  FCamera := DefaultPreviewCamera;
  FViewWidth := Max(Width, 1);
  FViewHeight := Max(Height, 1);
  try
    CreatePreviewDevice(Window, FSwapChain, FDevice, FContext, FBlendState,
      FRasterizerState);
    FShaders := TMmdD3DShaders.Create(FDevice);
    CreatePreviewRenderTargets(FSwapChain, FDevice, FRenderTarget,
      FDepthTexture, FDepthView);
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

destructor TMmdD3DRendererImpl.Destroy;
begin
  if FContext <> nil then
    FContext.ClearState;
  ReleasePreviewRenderTargets(FContext, FRenderTarget, FDepthTexture,
    FDepthView);
  FTriangleBuffer := nil;
  FOverlay.Free;
  FTextures.Free;
  FShaders.Free;
  FBlendState := nil;
  FRasterizerState := nil;
  FSwapChain := nil;
  FContext := nil;
  FDevice := nil;
  inherited Destroy;
end;

procedure TMmdD3DRendererImpl.Resize(Width, Height: Integer);
begin
  if (FSwapChain = nil) or (Width <= 0) or (Height <= 0) then
    Exit;
  try
    FViewWidth := Width;
    FViewHeight := Height;
    ReleasePreviewRenderTargets(FContext, FRenderTarget, FDepthTexture,
      FDepthView);
    CheckD3DResult(FSwapChain.ResizeBuffers(0, Width, Height,
      DXGI_FORMAT_UNKNOWN, 0), 'ResizeBuffers');
    CreatePreviewRenderTargets(FSwapChain, FDevice, FRenderTarget,
      FDepthTexture, FDepthView);
    if FShaders <> nil then
      FShaders.UpdateCamera(FContext, FCamera, FProjection, FViewWidth,
        FViewHeight);
    FErrorText := '';
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

procedure TMmdD3DRendererImpl.SetScene(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget);
var
  InitialFrame: Boolean;
  Scene: TMmdPreviewScene;
begin
  if FDevice = nil then
    Exit;
  try
    InitialFrame := (not FHasFrame) or (FFrameModel <> Model);
    if InitialFrame then
      BuildPreviewScene(Model, Poses, MorphWeights, SelectedTarget,
        HoverTarget, Scene)
    else
      BuildPreviewSceneWithFrame(Model, Poses, MorphWeights, SelectedTarget,
        HoverTarget, FCenter, FProjection, Scene);
    BuildPreviewBoneShapes(Scene.Joints, Scene.BoneSegments, SelectedTarget,
      HoverTarget, Scene.Projection.ModelHeight, Scene.BoneShapes);
    UpdatePreviewVertexBuffer(FDevice, FContext, Scene.Triangles,
      FTriangleBuffer, FTriangleCapacity);
    FTriangleCount := Length(Scene.Triangles);
    FTriangleBatches := Copy(Scene.Batches);
    FOverlay.Update(FDevice, FContext, Scene.BoneLines, Scene.BoneShapes,
      Scene.BoneSegments, Scene.Joints);
    if InitialFrame then
    begin
      FCenter := Scene.Center;
      FProjection := Scene.Projection;
      FFrameModel := Model;
      FHasFrame := True;
    end;
    if FTextureModel <> Model then
    begin
      FreeAndNil(FTextures);
      FTextures := TMmdD3DTextures.Create(FDevice, Model);
      FTextureModel := Model;
    end;
    FShaders.UpdateCamera(FContext, FCamera, FProjection, FViewWidth,
      FViewHeight);
    FErrorText := '';
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

procedure TMmdD3DRendererImpl.SetSkeleton(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget);
var
  BoneLines, BoneShapes: TMmdPreviewVertices;
  Joints: TMmdPreviewJoints;
  Segments: TMmdPreviewBoneSegments;
begin
  if FDevice = nil then
    Exit;
  try
    BuildPreviewSkeleton(Model, Poses, MorphWeights, SelectedTarget,
      HoverTarget, FCenter, BoneLines, Segments, Joints);
    BuildPreviewBoneShapes(Joints, Segments, SelectedTarget, HoverTarget,
      FProjection.ModelHeight, BoneShapes);
    FOverlay.Update(FDevice, FContext, BoneLines, BoneShapes, Segments, Joints);
    FErrorText := '';
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

procedure TMmdD3DRendererImpl.SetCamera(const Camera: TMmdPreviewCamera);
begin
  FCamera := Camera;
  if FShaders <> nil then
    FShaders.UpdateCamera(FContext, FCamera, FProjection, FViewWidth,
      FViewHeight);
end;

function TMmdD3DRendererImpl.GetLoadedTextureCount: Integer;
begin
  if FTextures = nil then
    Result := 0
  else
    Result := FTextures.LoadedCount;
end;

function TMmdD3DRendererImpl.GetProjection: TMmdPreviewProjection;
begin
  Result := FProjection;
end;

function TMmdD3DRendererImpl.HitTestTarget(X, Y: Integer): TMmdPreviewTarget;
begin
  Result := FOverlay.HitTest(FProjection, FCamera, FViewWidth, FViewHeight,
    X, Y);
end;

procedure TMmdD3DRendererImpl.Render;
var
  ClearColor: TFourSingleArray;
  BlendFactor: TFourSingleArray;
  Batch: TMmdPreviewBatch;
  Offset: Cardinal;
  Stride: Cardinal;
  Viewport: TD3D11_VIEWPORT;
begin
  if (FContext = nil) or (FRenderTarget = nil) then
    Exit;
  ClearColor[0] := 0.055;
  ClearColor[1] := 0.06;
  ClearColor[2] := 0.075;
  ClearColor[3] := 1.0;
  FContext.ClearRenderTargetView(FRenderTarget, ClearColor);
  FContext.ClearDepthStencilView(FDepthView, D3D11_CLEAR_DEPTH, 1.0, 0);
  FContext.OMSetRenderTargets(1, FRenderTarget, FDepthView);
  FillChar(BlendFactor, SizeOf(BlendFactor), 0);
  FContext.OMSetBlendState(FBlendState, BlendFactor, $FFFFFFFF);
  Viewport := TD3D11_VIEWPORT.Create(FDepthTexture, FRenderTarget);
  FContext.RSSetViewports(1, @Viewport);
  FContext.RSSetState(FRasterizerState);
  FShaders.Bind(FContext);
  Stride := SizeOf(TMmdPreviewVertex);
  Offset := 0;
  if (FTriangleBuffer <> nil) and (FTriangleCount > 0) then
  begin
    FContext.IASetVertexBuffers(0, 1, FTriangleBuffer, @Stride, @Offset);
    FContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    for Batch in FTriangleBatches do
    begin
      FTextures.Bind(FContext, Batch.TextureIndex);
      FContext.Draw(Batch.VertexCount, Batch.FirstVertex);
    end;
  end;
  if FOverlay.HasVertices then
  begin
    // 編集対象の確認を優先し、モデルに隠れる骨格形状も常に前面へ重ねる。
    FContext.ClearDepthStencilView(FDepthView, D3D11_CLEAR_DEPTH, 1.0, 0);
    FTextures.Bind(FContext, -1);
  end;
  FOverlay.Render(FContext, Stride, Offset);
  FSwapChain.Present(1, 0);
end;

constructor TMmdD3DRenderer.Create(Window: HWND; Width, Height: Integer);
begin
  inherited Create;
  FImpl := TMmdD3DRendererImpl.Create(Window, Width, Height);
end;

destructor TMmdD3DRenderer.Destroy;
begin
  FImpl.Free;
  inherited Destroy;
end;

function TMmdD3DRenderer.GetErrorText: string;
begin
  Result := TMmdD3DRendererImpl(FImpl).ErrorText;
end;

function TMmdD3DRenderer.GetLoadedTextureCount: Integer;
begin
  Result := TMmdD3DRendererImpl(FImpl).GetLoadedTextureCount;
end;

function TMmdD3DRenderer.GetProjection: TMmdPreviewProjection;
begin
  Result := TMmdD3DRendererImpl(FImpl).GetProjection;
end;

procedure TMmdD3DRenderer.Render;
begin
  TMmdD3DRendererImpl(FImpl).Render;
end;

procedure TMmdD3DRenderer.Resize(Width, Height: Integer);
begin
  TMmdD3DRendererImpl(FImpl).Resize(Width, Height);
end;

procedure TMmdD3DRenderer.SetScene(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget);
begin
  TMmdD3DRendererImpl(FImpl).SetScene(Model, Poses, MorphWeights,
    SelectedTarget, HoverTarget);
end;

procedure TMmdD3DRenderer.SetCamera(const Camera: TMmdPreviewCamera);
begin
  TMmdD3DRendererImpl(FImpl).SetCamera(Camera);
end;

procedure TMmdD3DRenderer.SetSkeleton(Model: TPmxModel;
  const Poses: TPmxBonePoses; const MorphWeights: TPmxMorphWeights;
  const SelectedTarget,
  HoverTarget: TMmdPreviewTarget);
begin
  TMmdD3DRendererImpl(FImpl).SetSkeleton(Model, Poses, MorphWeights,
    SelectedTarget, HoverTarget);
end;

function TMmdD3DRenderer.HitTestTarget(X, Y: Integer): TMmdPreviewTarget;
begin
  Result := TMmdD3DRendererImpl(FImpl).HitTestTarget(X, Y);
end;

end.
