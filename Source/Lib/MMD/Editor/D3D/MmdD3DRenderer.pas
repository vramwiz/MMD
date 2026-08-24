unit MmdD3DRenderer;

// D3D11デバイス、SwapChain、描画先とGPU頂点バッファの寿命を管理する。

interface

uses
  Winapi.Windows,
  PmxModel,
  PmxPose,
  MmdD3DScene;

type
  TMmdD3DRenderer = class
  private
    FImpl: TObject;
    function GetErrorText: string;
    function GetLoadedTextureCount: Integer;
  public
    // 指定した子ウィンドウ専用のDeviceとSwapChainを生成する。失敗内容はErrorTextへ保持する。
    constructor Create(Window: HWND; Width, Height: Integer);
    destructor Destroy; override;
    // 保持中のGPUバッファを現在のRenderTargetへ描画してPresentする。
    procedure Render;
    // SwapChainと深度バッファを指定サイズへ作り直す。0以下のサイズは無視する。
    procedure Resize(Width, Height: Integer);
    // 姿勢からCPU頂点を再生成し、このRendererだけが所有するGPUバッファへ置き換える。
    procedure SetScene(Model: TPmxModel; const Poses: TPmxBonePoses; SelectedBone: Integer);
    // 頂点バッファを変更せず、シェーダーへ渡すカメラ定数だけを更新する。
    procedure SetCamera(const Camera: TMmdPreviewCamera);
    property ErrorText: string read GetErrorText;
    property LoadedTextureCount: Integer read GetLoadedTextureCount;
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
    FLineBuffer: ID3D11Buffer;
    FLineCount: Cardinal;
    FProjection: TMmdPreviewProjection;
    FRasterizerState: ID3D11RasterizerState;
    FRenderTarget: ID3D11RenderTargetView;
    FShaders: TMmdD3DShaders;
    FSwapChain: IDXGISwapChain;
    FTriangleBuffer: ID3D11Buffer;
    FTriangleBatches: TMmdPreviewBatches;
    FTriangleCount: Cardinal;
    FTextureModel: TPmxModel;
    FTextures: TMmdD3DTextures;
    FViewHeight: Integer;
    FViewWidth: Integer;
    procedure CreateDevice(Window: HWND);
    procedure CreateRenderTargets;
    function CreateVertexBuffer(const Vertices: TMmdPreviewVertices): ID3D11Buffer;
    procedure ReleaseRenderTargets;
  public
    constructor Create(Window: HWND; Width, Height: Integer);
    destructor Destroy; override;
    procedure Render;
    procedure Resize(Width, Height: Integer);
    procedure SetScene(Model: TPmxModel; const Poses: TPmxBonePoses; SelectedBone: Integer);
    procedure SetCamera(const Camera: TMmdPreviewCamera);
    function GetLoadedTextureCount: Integer;
    property ErrorText: string read FErrorText;
  end;

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [Operation, Cardinal(Value)]);
end;

constructor TMmdD3DRendererImpl.Create(Window: HWND; Width, Height: Integer);
begin
  inherited Create;
  FCamera := DefaultPreviewCamera;
  FViewWidth := Max(Width, 1);
  FViewHeight := Max(Height, 1);
  try
    CreateDevice(Window);
    FShaders := TMmdD3DShaders.Create(FDevice);
    CreateRenderTargets;
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

destructor TMmdD3DRendererImpl.Destroy;
begin
  if FContext <> nil then
    FContext.ClearState;
  ReleaseRenderTargets;
  FLineBuffer := nil;
  FTriangleBuffer := nil;
  FTextures.Free;
  FShaders.Free;
  FBlendState := nil;
  FRasterizerState := nil;
  FSwapChain := nil;
  FContext := nil;
  FDevice := nil;
  inherited Destroy;
end;

procedure TMmdD3DRendererImpl.CreateDevice(Window: HWND);
var
  Desc: TDXGISwapChainDesc;
  FeatureLevel: D3D_FEATURE_LEVEL;
  BlendDesc: TD3D11_BLEND_DESC;
  RasterDesc: TD3D11_RASTERIZER_DESC;
begin
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.BufferDesc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
  Desc.BufferDesc.RefreshRate.Numerator := 60;
  Desc.BufferDesc.RefreshRate.Denominator := 1;
  Desc.SampleDesc.Count := 1;
  Desc.BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
  Desc.BufferCount := 2;
  Desc.OutputWindow := Window;
  Desc.Windowed := True;
  Desc.SwapEffect := DXGI_SWAP_EFFECT_DISCARD;
  CheckHR(D3D11CreateDeviceAndSwapChain(nil, D3D_DRIVER_TYPE_HARDWARE, 0, 0,
    nil, 0, D3D11_SDK_VERSION, @Desc, FSwapChain, FDevice, FeatureLevel,
    FContext), 'D3D11CreateDeviceAndSwapChain');
  FillChar(RasterDesc, SizeOf(RasterDesc), 0);
  RasterDesc.FillMode := D3D11_FILL_SOLID;
  RasterDesc.CullMode := D3D11_CULL_NONE;
  RasterDesc.DepthClipEnable := True;
  CheckHR(FDevice.CreateRasterizerState(RasterDesc, FRasterizerState),
    'CreateRasterizerState');
  FillChar(BlendDesc, SizeOf(BlendDesc), 0);
  BlendDesc.RenderTarget[0].BlendEnable := True;
  BlendDesc.RenderTarget[0].SrcBlend := D3D11_BLEND_SRC_ALPHA;
  BlendDesc.RenderTarget[0].DestBlend := D3D11_BLEND_INV_SRC_ALPHA;
  BlendDesc.RenderTarget[0].BlendOp := D3D11_BLEND_OP_ADD;
  BlendDesc.RenderTarget[0].SrcBlendAlpha := D3D11_BLEND_ONE;
  BlendDesc.RenderTarget[0].DestBlendAlpha := D3D11_BLEND_INV_SRC_ALPHA;
  BlendDesc.RenderTarget[0].BlendOpAlpha := D3D11_BLEND_OP_ADD;
  BlendDesc.RenderTarget[0].RenderTargetWriteMask :=
    Byte(D3D11_COLOR_WRITE_ENABLE_ALL);
  CheckHR(FDevice.CreateBlendState(BlendDesc, FBlendState),
    'CreateBlendState');
end;

procedure TMmdD3DRendererImpl.CreateRenderTargets;
var
  BackBuffer: ID3D11Texture2D;
  DepthDesc: TD3D11_TEXTURE2D_DESC;
  SwapDesc: TDXGISwapChainDesc;
begin
  if (FSwapChain = nil) or (FDevice = nil) then
    Exit;
  CheckHR(FSwapChain.GetDesc(SwapDesc), 'Get swap chain description');
  if (SwapDesc.BufferDesc.Width = 0) or (SwapDesc.BufferDesc.Height = 0) then
    Exit;
  CheckHR(FSwapChain.GetBuffer(0, ID3D11Texture2D, BackBuffer),
    'Get swap chain buffer');
  CheckHR(FDevice.CreateRenderTargetView(BackBuffer, nil, FRenderTarget),
    'CreateRenderTargetView');
  FillChar(DepthDesc, SizeOf(DepthDesc), 0);
  DepthDesc.Width := SwapDesc.BufferDesc.Width;
  DepthDesc.Height := SwapDesc.BufferDesc.Height;
  DepthDesc.MipLevels := 1;
  DepthDesc.ArraySize := 1;
  DepthDesc.Format := DXGI_FORMAT_D24_UNORM_S8_UINT;
  DepthDesc.SampleDesc.Count := 1;
  DepthDesc.Usage := D3D11_USAGE_DEFAULT;
  DepthDesc.BindFlags := UINT(D3D11_BIND_DEPTH_STENCIL);
  CheckHR(FDevice.CreateTexture2D(DepthDesc, nil, FDepthTexture),
    'Create depth texture');
  CheckHR(FDevice.CreateDepthStencilView(FDepthTexture, nil, FDepthView),
    'Create depth view');
end;

procedure TMmdD3DRendererImpl.ReleaseRenderTargets;
begin
  if FContext <> nil then
    FContext.OMSetRenderTargets(0, ID3D11RenderTargetView(nil), nil);
  FDepthView := nil;
  FDepthTexture := nil;
  FRenderTarget := nil;
end;

procedure TMmdD3DRendererImpl.Resize(Width, Height: Integer);
begin
  if (FSwapChain = nil) or (Width <= 0) or (Height <= 0) then
    Exit;
  try
    FViewWidth := Width;
    FViewHeight := Height;
    ReleaseRenderTargets;
    CheckHR(FSwapChain.ResizeBuffers(0, Width, Height, DXGI_FORMAT_UNKNOWN, 0),
      'ResizeBuffers');
    CreateRenderTargets;
    if FShaders <> nil then
      FShaders.UpdateCamera(FContext, FCamera, FProjection, FViewWidth,
        FViewHeight);
    FErrorText := '';
  except
    on E: Exception do
      FErrorText := E.Message;
  end;
end;

function TMmdD3DRendererImpl.CreateVertexBuffer(
  const Vertices: TMmdPreviewVertices): ID3D11Buffer;
var
  BufferDesc: TD3D11_BUFFER_DESC;
  Subresource: TD3D11_SUBRESOURCE_DATA;
begin
  Result := nil;
  if Length(Vertices) = 0 then
    Exit;
  FillChar(BufferDesc, SizeOf(BufferDesc), 0);
  BufferDesc.ByteWidth := Length(Vertices) * SizeOf(TMmdPreviewVertex);
  BufferDesc.Usage := D3D11_USAGE_DEFAULT;
  BufferDesc.BindFlags := UINT(D3D11_BIND_VERTEX_BUFFER);
  FillChar(Subresource, SizeOf(Subresource), 0);
  Subresource.pSysMem := @Vertices[0];
  CheckHR(FDevice.CreateBuffer(BufferDesc, @Subresource, Result),
    'Create preview vertex buffer');
end;

procedure TMmdD3DRendererImpl.SetScene(Model: TPmxModel;
  const Poses: TPmxBonePoses; SelectedBone: Integer);
var
  Scene: TMmdPreviewScene;
begin
  if FDevice = nil then
    Exit;
  try
    BuildPreviewScene(Model, Poses, SelectedBone, Scene);
    FTriangleBuffer := CreateVertexBuffer(Scene.Triangles);
    FTriangleCount := Length(Scene.Triangles);
    FTriangleBatches := Copy(Scene.Batches);
    FLineBuffer := CreateVertexBuffer(Scene.BoneLines);
    FLineCount := Length(Scene.BoneLines);
    FProjection := Scene.Projection;
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
  if (FLineBuffer <> nil) and (FLineCount > 0) then
  begin
    // 編集対象の確認を優先し、モデルに隠れる骨格も常に前面へ重ねる。
    FContext.ClearDepthStencilView(FDepthView, D3D11_CLEAR_DEPTH, 1.0, 0);
    FTextures.Bind(FContext, -1);
    FContext.IASetVertexBuffers(0, 1, FLineBuffer, @Stride, @Offset);
    FContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_LINELIST);
    FContext.Draw(FLineCount, 0);
  end;
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

procedure TMmdD3DRenderer.Render;
begin
  TMmdD3DRendererImpl(FImpl).Render;
end;

procedure TMmdD3DRenderer.Resize(Width, Height: Integer);
begin
  TMmdD3DRendererImpl(FImpl).Resize(Width, Height);
end;

procedure TMmdD3DRenderer.SetScene(Model: TPmxModel;
  const Poses: TPmxBonePoses; SelectedBone: Integer);
begin
  TMmdD3DRendererImpl(FImpl).SetScene(Model, Poses, SelectedBone);
end;

procedure TMmdD3DRenderer.SetCamera(const Camera: TMmdPreviewCamera);
begin
  TMmdD3DRendererImpl(FImpl).SetCamera(Camera);
end;

end.
