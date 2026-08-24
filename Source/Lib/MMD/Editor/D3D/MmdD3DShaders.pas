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
    ScaleX, ScaleY, DepthScale, Padding: Single;
  end;

const
  SHADER_SOURCE: AnsiString =
    'cbuffer C:register(b0){float sy;float cy;float sp;float cp;' +
    'float sx;float scaleY;float ds;float pad;};' +
    'struct I{float3 p:POSITION;float4 c:COLOR;};' +
    'struct O{float4 p:SV_POSITION;float4 c:COLOR;};' +
    'O VSMain(I v){O o;float x=v.p.x*cy+v.p.z*sy;' +
    'float z=-v.p.x*sy+v.p.z*cy;' +
    'float y=v.p.y*cp-z*sp;z=v.p.y*sp+z*cp;' +
    'o.p=float4(x*sx,y*scaleY,0.5+z*ds,1);o.c=v.c;return o;}' +
    'float4 PSMain(O i):SV_TARGET{return i.c;}';

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [Operation, Cardinal(Value)]);
end;

constructor TMmdD3DShaders.Create(const Device: ID3D11Device);
var
  BufferDesc: TD3D11_BUFFER_DESC;
  Errors: ID3DBlob;
  InputElements: array[0..1] of TD3D11_INPUT_ELEMENT_DESC;
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
  Constants.Padding := 0;
  Context.UpdateSubresource(FCameraBuffer, 0, nil, @Constants, 0, 0);
end;

end.
