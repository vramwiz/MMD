unit MmdD3DTextures;

// PMX通常テクスチャをWICで読み込み、D3D11のSRVとSamplerを管理する。

interface

uses
  Winapi.D3D11,
  PmxModel;

type
  TMmdD3DTextures = class
  private
    FSampler: ID3D11SamplerState;
    FLoadedCount: Integer;
    FTextures: array of ID3D11ShaderResourceView;
    FWhiteTexture: ID3D11ShaderResourceView;
    function CreateTexture(const Device: ID3D11Device;
      const FileName: string): ID3D11ShaderResourceView;
    function CreateWhiteTexture(const Device: ID3D11Device): ID3D11ShaderResourceView;
  public
    // Modelが参照する通常テクスチャを読み込み、失敗した要素は白へフォールバックする。
    constructor Create(const Device: ID3D11Device; Model: TPmxModel);
    // 指定テクスチャと繰返しSamplerをPixel Shaderのslot 0へ設定する。
    procedure Bind(const Context: ID3D11DeviceContext; TextureIndex: Integer);
    property LoadedCount: Integer read FLoadedCount;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Wincodec,
  Winapi.DxgiFormat,
  System.SysUtils,
  Vcl.Graphics;

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [Operation, Cardinal(Value)]);
end;

function CreateTextureFromPixels(const Device: ID3D11Device; Width,
  Height: Cardinal; Pixels: Pointer): ID3D11ShaderResourceView;
var
  Desc: TD3D11_TEXTURE2D_DESC;
  Source: TD3D11_SUBRESOURCE_DATA;
  Texture: ID3D11Texture2D;
begin
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Width := Width;
  Desc.Height := Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Desc.SampleDesc.Count := 1;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := UINT(D3D11_BIND_SHADER_RESOURCE);
  FillChar(Source, SizeOf(Source), 0);
  Source.pSysMem := Pixels;
  Source.SysMemPitch := Width * 4;
  CheckHR(Device.CreateTexture2D(Desc, @Source, Texture),
    'Create preview texture');
  CheckHR(Device.CreateShaderResourceView(Texture, nil, Result),
    'Create preview texture view');
end;

function TMmdD3DTextures.CreateTexture(const Device: ID3D11Device;
  const FileName: string): ID3D11ShaderResourceView;
var
  Converted: IWICBitmapSource;
  Height: Cardinal;
  Image: TWICImage;
  Pixels: TBytes;
  Stride: Cardinal;
  Width: Cardinal;
begin
  Result := nil;
  Image := TWICImage.Create;
  try
    Image.LoadFromFile(FileName);
    CheckHR(WICConvertBitmapSource(GUID_WICPixelFormat32bppBGRA,
      Image.Handle, Converted), 'Convert preview texture');
    CheckHR(Converted.GetSize(Width, Height), 'Get preview texture size');
    if (Width = 0) or (Height = 0) then
      Exit;
    Stride := Width * 4;
    SetLength(Pixels, NativeInt(Stride) * Height);
    CheckHR(Converted.CopyPixels(nil, Stride, Length(Pixels), @Pixels[0]),
      'Copy preview texture pixels');
    Result := CreateTextureFromPixels(Device, Width, Height, @Pixels[0]);
  finally
    Image.Free;
  end;
end;

function TMmdD3DTextures.CreateWhiteTexture(
  const Device: ID3D11Device): ID3D11ShaderResourceView;
var
  White: Cardinal;
begin
  White := $FFFFFFFF;
  Result := CreateTextureFromPixels(Device, 1, 1, @White);
end;

constructor TMmdD3DTextures.Create(const Device: ID3D11Device;
  Model: TPmxModel);
var
  Index: Integer;
  SamplerDesc: TD3D11_SAMPLER_DESC;
begin
  inherited Create;
  FWhiteTexture := CreateWhiteTexture(Device);
  SetLength(FTextures, Length(Model.Textures));
  for Index := 0 to High(FTextures) do
    if Model.TextureAvailable[Index] then
      try
        FTextures[Index] := CreateTexture(Device, Model.Textures[Index]);
        if FTextures[Index] <> nil then
          Inc(FLoadedCount);
      except
        FTextures[Index] := nil;
      end;
  SamplerDesc := TD3D11_SAMPLER_DESC.Create(True);
  SamplerDesc.AddressU := D3D11_TEXTURE_ADDRESS_WRAP;
  SamplerDesc.AddressV := D3D11_TEXTURE_ADDRESS_WRAP;
  SamplerDesc.AddressW := D3D11_TEXTURE_ADDRESS_WRAP;
  CheckHR(Device.CreateSamplerState(SamplerDesc, FSampler),
    'Create preview texture sampler');
end;

procedure TMmdD3DTextures.Bind(const Context: ID3D11DeviceContext;
  TextureIndex: Integer);
var
  Texture: ID3D11ShaderResourceView;
begin
  Texture := nil;
  if (TextureIndex >= 0) and (TextureIndex < Length(FTextures)) then
    Texture := FTextures[TextureIndex];
  if Texture = nil then
    Texture := FWhiteTexture;
  Context.PSSetShaderResources(0, 1, Texture);
  Context.PSSetSamplers(0, 1, FSampler);
end;

end.
