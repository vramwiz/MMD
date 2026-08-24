unit MmdD3DDevice;

// D3D11デバイス、SwapChain、固定描画状態、サイズ依存RenderTargetの生成破棄を行う。

interface

uses
  Winapi.Windows,
  Winapi.D3D11,
  Winapi.DXGI;

// 失敗HRESULTを操作名付きDelphi例外へ変換する。
procedure CheckD3DResult(Value: HRESULT; const Operation: string);
// 子ウィンドウ用デバイス一式と、プレビュー共通のBlend / Rasterizer状態を生成する。
procedure CreatePreviewDevice(Window: HWND; out SwapChain: IDXGISwapChain;
  out Device: ID3D11Device; out Context: ID3D11DeviceContext;
  out BlendState: ID3D11BlendState; out RasterizerState: ID3D11RasterizerState);
// 現在のSwapChain寸法に対応するRenderTargetと深度バッファを生成する。
procedure CreatePreviewRenderTargets(const SwapChain: IDXGISwapChain;
  const Device: ID3D11Device; out RenderTarget: ID3D11RenderTargetView;
  out DepthTexture: ID3D11Texture2D; out DepthView: ID3D11DepthStencilView);
// Contextから描画先を外し、サイズ依存資源を解放する。
procedure ReleasePreviewRenderTargets(const Context: ID3D11DeviceContext;
  var RenderTarget: ID3D11RenderTargetView; var DepthTexture: ID3D11Texture2D;
  var DepthView: ID3D11DepthStencilView);

implementation

uses
  Winapi.D3DCommon,
  Winapi.DxgiFormat,
  Winapi.DxgiType,
  System.SysUtils;

procedure CheckD3DResult(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [Operation, Cardinal(Value)]);
end;

procedure CreatePreviewDevice(Window: HWND; out SwapChain: IDXGISwapChain;
  out Device: ID3D11Device; out Context: ID3D11DeviceContext;
  out BlendState: ID3D11BlendState; out RasterizerState: ID3D11RasterizerState);
var
  BlendDesc: TD3D11_BLEND_DESC;
  Desc: TDXGISwapChainDesc;
  FeatureLevel: D3D_FEATURE_LEVEL;
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
  CheckD3DResult(D3D11CreateDeviceAndSwapChain(nil, D3D_DRIVER_TYPE_HARDWARE,
    0, 0, nil, 0, D3D11_SDK_VERSION, @Desc, SwapChain, Device,
    FeatureLevel, Context), 'D3D11CreateDeviceAndSwapChain');
  FillChar(RasterDesc, SizeOf(RasterDesc), 0);
  RasterDesc.FillMode := D3D11_FILL_SOLID;
  RasterDesc.CullMode := D3D11_CULL_NONE;
  RasterDesc.DepthClipEnable := True;
  CheckD3DResult(Device.CreateRasterizerState(RasterDesc, RasterizerState),
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
  CheckD3DResult(Device.CreateBlendState(BlendDesc, BlendState),
    'CreateBlendState');
end;

procedure CreatePreviewRenderTargets(const SwapChain: IDXGISwapChain;
  const Device: ID3D11Device; out RenderTarget: ID3D11RenderTargetView;
  out DepthTexture: ID3D11Texture2D; out DepthView: ID3D11DepthStencilView);
var
  BackBuffer: ID3D11Texture2D;
  DepthDesc: TD3D11_TEXTURE2D_DESC;
  SwapDesc: TDXGISwapChainDesc;
begin
  if (SwapChain = nil) or (Device = nil) then
    Exit;
  CheckD3DResult(SwapChain.GetDesc(SwapDesc), 'Get swap chain description');
  if (SwapDesc.BufferDesc.Width = 0) or (SwapDesc.BufferDesc.Height = 0) then
    Exit;
  CheckD3DResult(SwapChain.GetBuffer(0, ID3D11Texture2D, BackBuffer),
    'Get swap chain buffer');
  CheckD3DResult(Device.CreateRenderTargetView(BackBuffer, nil, RenderTarget),
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
  CheckD3DResult(Device.CreateTexture2D(DepthDesc, nil, DepthTexture),
    'Create depth texture');
  CheckD3DResult(Device.CreateDepthStencilView(DepthTexture, nil, DepthView),
    'Create depth view');
end;

procedure ReleasePreviewRenderTargets(const Context: ID3D11DeviceContext;
  var RenderTarget: ID3D11RenderTargetView; var DepthTexture: ID3D11Texture2D;
  var DepthView: ID3D11DepthStencilView);
begin
  if Context <> nil then
    Context.OMSetRenderTargets(0, ID3D11RenderTargetView(nil), nil);
  DepthView := nil;
  DepthTexture := nil;
  RenderTarget := nil;
end;

end.
