unit MmdD3DShaders;

// D3Dプレビューのシェーダーと、軽量なカメラ定数バッファを所有する。

interface

uses
  Winapi.D3D11,
  MmdD3DScene;

type
  TMmdD3DShaders = class
  private
    FCameraBuffer: ID3D11Buffer;
    FInputLayout: ID3D11InputLayout;
    FPixelShader: ID3D11PixelShader;
    FVertexShader: ID3D11VertexShader;
  public
    // シェーダーをコンパイルし、指定デバイス専用のカメラ定数バッファを生成する。
    constructor Create(const Device: ID3D11Device);
    // 描画に必要なシェーダー、入力形式、カメラ定数をContextへ設定する。
    procedure Bind(const Context: ID3D11DeviceContext);
    // PMX頂点を再生成せず、現在の視点を定数バッファだけへ転送する。
    procedure UpdateCamera(const Context: ID3D11DeviceContext;
      const Camera: TMmdPreviewCamera; const Projection: TMmdPreviewProjection;
      ViewWidth, ViewHeight: Integer);
  end;

implementation

uses
  Winapi.Windows,
  Winapi.D3DCommon,
  Winapi.D3DCompiler,
  Winapi.DxgiFormat,
  System.Math,
  System.SysUtils;

type
  TMmdCameraConstants = packed record
    SinYaw, CosYaw, SinPitch, CosPitch: Single;
    ScaleX, ScaleY, DepthScale, PanX: Single;
    PanY, Padding1, Padding2, Padding3: Single;
  end;

const
  SHADER_SOURCE: AnsiString =
    'cbuffer C:register(b0){float sy;float cy;float sp;float cp;' +
    'float sx;float scaleY;float ds;float px;' +
    'float py;float pad1;float pad2;float pad3;};' +
    'Texture2D tex:register(t0);SamplerState sam:register(s0);' +
    'struct I{float3 p:POSITION;float4 c:COLOR;float2 uv:TEXCOORD;' +
    'float3 n:NORMAL;float lighting:LIGHTFACTOR;};' +
    'struct O{float4 p:SV_POSITION;float4 c:COLOR;float2 uv:TEXCOORD;' +
    'float shade:LIGHTFACTOR;};' +
    'O VSMain(I v){O o;float x=v.p.x*cy+v.p.z*sy;' +
    'float z=-v.p.x*sy+v.p.z*cy;' +
    'float y=v.p.y*cp-z*sp;z=v.p.y*sp+z*cp;' +
    'float nx=v.n.x*cy+v.n.z*sy;float nz=-v.n.x*sy+v.n.z*cy;' +
    'float ny=v.n.y*cp-nz*sp;nz=v.n.y*sp+nz*cp;' +
    'float diffuse=saturate(dot(normalize(float3(nx,ny,nz)),' +
    'normalize(float3(0,0.28,-0.96))));' +
    'o.p=float4(x*sx+px,y*scaleY+py,0.5+z*ds,1);o.c=v.c;o.uv=v.uv;' +
    'o.shade=lerp(1.0,0.68+0.42*diffuse,saturate(v.lighting));return o;}' +
    'float4 PSMain(O i):SV_TARGET{float4 c=tex.Sample(sam,i.uv)*i.c;' +
    'c.rgb*=i.shade;' +
    'clip(c.a-0.01);return c;}';

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [Operation, Cardinal(Value)]);
end;

constructor TMmdD3DShaders.Create(const Device: ID3D11Device);
var
  BufferDesc: TD3D11_BUFFER_DESC;
  Errors: ID3DBlob;
  InputElements: array[0..4] of TD3D11_INPUT_ELEMENT_DESC;
  PixelCode: ID3DBlob;
  VertexCode: ID3DBlob;
begin
  inherited Create;
  CheckHR(D3DCompile(PAnsiChar(SHADER_SOURCE), Length(SHADER_SOURCE), nil, nil,
    nil, 'VSMain', 'vs_4_0', D3DCOMPILE_ENABLE_STRICTNESS, 0, VertexCode,
    Errors), 'Compile vertex shader');
  CheckHR(Device.CreateVertexShader(VertexCode.GetBufferPointer,
    VertexCode.GetBufferSize, nil, @FVertexShader), 'CreateVertexShader');
  FillChar(InputElements, SizeOf(InputElements), 0);
  InputElements[0].SemanticName := 'POSITION';
  InputElements[0].Format := DXGI_FORMAT_R32G32B32_FLOAT;
  InputElements[0].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  InputElements[1].SemanticName := 'COLOR';
  InputElements[1].Format := DXGI_FORMAT_R32G32B32A32_FLOAT;
  InputElements[1].AlignedByteOffset := 12;
  InputElements[1].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  InputElements[2].SemanticName := 'TEXCOORD';
  InputElements[2].Format := DXGI_FORMAT_R32G32_FLOAT;
  InputElements[2].AlignedByteOffset := 28;
  InputElements[2].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  InputElements[3].SemanticName := 'NORMAL';
  InputElements[3].Format := DXGI_FORMAT_R32G32B32_FLOAT;
  InputElements[3].AlignedByteOffset := 36;
  InputElements[3].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  InputElements[4].SemanticName := 'LIGHTFACTOR';
  InputElements[4].Format := DXGI_FORMAT_R32_FLOAT;
  InputElements[4].AlignedByteOffset := 48;
  InputElements[4].InputSlotClass := D3D11_INPUT_PER_VERTEX_DATA;
  CheckHR(Device.CreateInputLayout(@InputElements[0], Length(InputElements),
    VertexCode.GetBufferPointer, VertexCode.GetBufferSize, FInputLayout),
    'CreateInputLayout');
  CheckHR(D3DCompile(PAnsiChar(SHADER_SOURCE), Length(SHADER_SOURCE), nil, nil,
    nil, 'PSMain', 'ps_4_0', D3DCOMPILE_ENABLE_STRICTNESS, 0, PixelCode,
    Errors), 'Compile pixel shader');
  CheckHR(Device.CreatePixelShader(PixelCode.GetBufferPointer,
    PixelCode.GetBufferSize, nil, FPixelShader), 'CreatePixelShader');
  FillChar(BufferDesc, SizeOf(BufferDesc), 0);
  BufferDesc.ByteWidth := SizeOf(TMmdCameraConstants);
  BufferDesc.Usage := D3D11_USAGE_DEFAULT;
  BufferDesc.BindFlags := UINT(D3D11_BIND_CONSTANT_BUFFER);
  CheckHR(Device.CreateBuffer(BufferDesc, nil, FCameraBuffer),
    'Create camera constant buffer');
end;

procedure TMmdD3DShaders.Bind(const Context: ID3D11DeviceContext);
begin
  Context.IASetInputLayout(FInputLayout);
  Context.VSSetShader(FVertexShader, ID3D11ClassInstance(nil), 0);
  Context.VSSetConstantBuffers(0, 1, FCameraBuffer);
  Context.PSSetShader(FPixelShader, ID3D11ClassInstance(nil), 0);
end;

procedure TMmdD3DShaders.UpdateCamera(const Context: ID3D11DeviceContext;
  const Camera: TMmdPreviewCamera; const Projection: TMmdPreviewProjection;
  ViewWidth, ViewHeight: Integer);
var
  Constants: TMmdCameraConstants;
  PixelScale: Single;
begin
  if (Context = nil) or (Projection.ModelWidth <= 0) then
    Exit;
  ViewWidth := Max(ViewWidth, 1);
  ViewHeight := Max(ViewHeight, 1);
  SinCos(Camera.Yaw, Constants.SinYaw, Constants.CosYaw);
  SinCos(Camera.Pitch, Constants.SinPitch, Constants.CosPitch);
  PixelScale := 0.9 * EnsureRange(Camera.Zoom, 0.2, 5.0) *
    Min(ViewWidth / Projection.ModelWidth, ViewHeight / Projection.ModelHeight);
  Constants.ScaleX := 2.0 * PixelScale / ViewWidth;
  Constants.ScaleY := 2.0 * PixelScale / ViewHeight;
  Constants.DepthScale := 0.45 / Max(Projection.Radius, 0.001);
  Constants.PanX := Camera.PanX * 2.0 / ViewWidth;
  Constants.PanY := -Camera.PanY * 2.0 / ViewHeight;
  Constants.Padding1 := 0;
  Constants.Padding2 := 0;
  Constants.Padding3 := 0;
  Context.UpdateSubresource(FCameraBuffer, 0, nil, @Constants, 0, 0);
end;

end.
