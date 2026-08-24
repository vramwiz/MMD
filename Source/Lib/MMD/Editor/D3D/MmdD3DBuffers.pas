unit MmdD3DBuffers;

// D3Dプレビュー頂点配列からGPUバッファを生成し、容量内の再利用更新も行う。

interface

uses
  Winapi.D3D11,
  MmdD3DScene;

// 空配列にはnilを返し、それ以外はDevice専用の頂点バッファへ全頂点を転送する。
function CreatePreviewVertexBuffer(const Device: ID3D11Device;
  const Vertices: TMmdPreviewVertices): ID3D11Buffer;
// 容量内では既存バッファを部分更新し、不足時だけ2倍単位で作り直す。
procedure UpdatePreviewVertexBuffer(const Device: ID3D11Device;
  const Context: ID3D11DeviceContext; const Vertices: TMmdPreviewVertices;
  var Buffer: ID3D11Buffer; var Capacity: Integer);

implementation

uses
  Winapi.Windows,
  System.Math,
  System.SysUtils;

function CreatePreviewVertexBuffer(const Device: ID3D11Device;
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
  if Device.CreateBuffer(BufferDesc, @Subresource, Result) < 0 then
    raise Exception.Create('Create preview vertex buffer failed');
end;

procedure UpdatePreviewVertexBuffer(const Device: ID3D11Device;
  const Context: ID3D11DeviceContext; const Vertices: TMmdPreviewVertices;
  var Buffer: ID3D11Buffer; var Capacity: Integer);
var
  Box: TD3D11_BOX;
  BufferDesc: TD3D11_BUFFER_DESC;
  RequiredCount: Integer;
begin
  RequiredCount := Length(Vertices);
  if RequiredCount = 0 then
    Exit;
  if (Buffer = nil) or (Capacity < RequiredCount) then
  begin
    Capacity := Max(Capacity, 256);
    while Capacity < RequiredCount do
      Capacity := Capacity * 2;
    FillChar(BufferDesc, SizeOf(BufferDesc), 0);
    BufferDesc.ByteWidth := Capacity * SizeOf(TMmdPreviewVertex);
    BufferDesc.Usage := D3D11_USAGE_DEFAULT;
    BufferDesc.BindFlags := UINT(D3D11_BIND_VERTEX_BUFFER);
    if Device.CreateBuffer(BufferDesc, nil, Buffer) < 0 then
      raise Exception.Create('Create reusable preview vertex buffer failed');
  end;
  Box := TD3D11_BOX.Create(0, 0, 0,
    RequiredCount * SizeOf(TMmdPreviewVertex), 1, 1);
  Context.UpdateSubresource(Buffer, 0, @Box, @Vertices[0], 0, 0);
end;

end.
