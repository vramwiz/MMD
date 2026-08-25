unit MmdD3DCapture;

// D3D11 SwapChainの表示内容をCPU側のVCL Bitmapへ変換する。

interface

uses
  Winapi.D3D11,
  Winapi.DXGI,
  Vcl.Graphics;

// Present前のBackBufferを読み戻す。出力はRGBA/BGRA差を補正したpf32bit。
procedure ReadSwapChainToBitmap(const SwapChain: IDXGISwapChain;
  const Device: ID3D11Device; const Context: ID3D11DeviceContext;
  Bitmap: Vcl.Graphics.TBitmap);

implementation

uses
  MmdD3DDevice;

procedure ReadSwapChainToBitmap(const SwapChain: IDXGISwapChain;
  const Device: ID3D11Device; const Context: ID3D11DeviceContext;
  Bitmap: Vcl.Graphics.TBitmap);
var
  BackBuffer, Staging: ID3D11Texture2D;
  Blue, Green, Red: Byte;
  Desc: TD3D11_TEXTURE2D_DESC;
  Dest, Source: PByte;
  Mapped: TD3D11_MAPPED_SUBRESOURCE;
  X, Y: Integer;
begin
  CheckD3DResult(SwapChain.GetBuffer(0, ID3D11Texture2D, BackBuffer),
    'Get capture back buffer');
  BackBuffer.GetDesc(Desc);
  Desc.Usage := D3D11_USAGE_STAGING;
  Desc.BindFlags := 0;
  Desc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
  Desc.MiscFlags := 0;
  CheckD3DResult(Device.CreateTexture2D(Desc, nil, Staging),
    'Create capture staging texture');
  Context.CopyResource(Staging, BackBuffer);
  CheckD3DResult(Context.Map(Staging, 0, D3D11_MAP_READ, 0, Mapped),
    'Map captured model image');
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Desc.Width, Desc.Height);
    for Y := 0 to Integer(Desc.Height) - 1 do
    begin
      Source := PByte(NativeUInt(Mapped.pData) + NativeUInt(Y) *
        Mapped.RowPitch);
      // ScanLineとD3D BackBufferの行方向をそのまま対応させる。
      // ここでさらに反転するとClipboard上では上下逆になる。
      Dest := Bitmap.ScanLine[Y];
      for X := 0 to Integer(Desc.Width) - 1 do
      begin
        // SwapChainはRGBA、VCLのpf32bit BitmapはBGRA順。
        Red := Source^;
        Inc(Source);
        Green := Source^;
        Inc(Source);
        Blue := Source^;
        Inc(Source, 2);
        Dest^ := Blue;
        Inc(Dest);
        Dest^ := Green;
        Inc(Dest);
        Dest^ := Red;
        Inc(Dest);
        Dest^ := $FF;
        Inc(Dest);
      end;
    end;
  finally
    Context.Unmap(Staging, 0);
  end;
end;

end.
