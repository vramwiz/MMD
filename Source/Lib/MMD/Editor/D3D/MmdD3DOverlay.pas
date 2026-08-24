unit MmdD3DOverlay;

// 骨格線、関節球、選択ボーン形状のGPUバッファとヒット判定をまとめて管理する。

interface

uses
  Winapi.D3D11,
  MmdD3DScene;

type
  TMmdD3DOverlay = class
  private
    FJoints: TMmdPreviewJoints;
    FLineBuffer, FShapeBuffer: ID3D11Buffer;
    FLineCapacity, FShapeCapacity: Integer;
    FLineCount, FShapeCount: Cardinal;
    FSegments: TMmdPreviewBoneSegments;
  public
    // 骨格形状だけを新しいGPUバッファへ置き換え、モデル三角形には触れない。
    procedure Update(const Device: ID3D11Device;
      const Context: ID3D11DeviceContext;
      const BoneLines, BoneShapes: TMmdPreviewVertices;
      const Segments: TMmdPreviewBoneSegments; const Joints: TMmdPreviewJoints);
    // 三角形形状を先に、骨格線を後に描き、形状内部の線は深度で隠す。
    procedure Render(const Context: ID3D11DeviceContext;
      Stride, Offset: Cardinal);
    // 現在の骨格位置とカメラからボーンのヒット対象を返す。
    function HitTest(const Projection: TMmdPreviewProjection;
      const Camera: TMmdPreviewCamera; ViewWidth, ViewHeight,
      X, Y: Integer): TMmdPreviewTarget;
    function HasVertices: Boolean;
  end;

implementation

uses
  Winapi.D3DCommon,
  MmdD3DBuffers,
  MmdD3DSelection;

procedure TMmdD3DOverlay.Update(const Device: ID3D11Device;
  const Context: ID3D11DeviceContext;
  const BoneLines, BoneShapes: TMmdPreviewVertices;
  const Segments: TMmdPreviewBoneSegments; const Joints: TMmdPreviewJoints);
begin
  UpdatePreviewVertexBuffer(Device, Context, BoneLines, FLineBuffer,
    FLineCapacity);
  FLineCount := Length(BoneLines);
  UpdatePreviewVertexBuffer(Device, Context, BoneShapes, FShapeBuffer,
    FShapeCapacity);
  FShapeCount := Length(BoneShapes);
  FSegments := Copy(Segments);
  FJoints := Copy(Joints);
end;

procedure TMmdD3DOverlay.Render(const Context: ID3D11DeviceContext;
  Stride, Offset: Cardinal);
begin
  if (FShapeBuffer <> nil) and (FShapeCount > 0) then
  begin
    Context.IASetVertexBuffers(0, 1, FShapeBuffer, @Stride, @Offset);
    Context.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    Context.Draw(FShapeCount, 0);
  end;
  if (FLineBuffer <> nil) and (FLineCount > 0) then
  begin
    Context.IASetVertexBuffers(0, 1, FLineBuffer, @Stride, @Offset);
    Context.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_LINELIST);
    Context.Draw(FLineCount, 0);
  end;
end;

function TMmdD3DOverlay.HitTest(const Projection: TMmdPreviewProjection;
  const Camera: TMmdPreviewCamera; ViewWidth, ViewHeight,
  X, Y: Integer): TMmdPreviewTarget;
begin
  Result := HitTestPreviewTarget(FJoints, FSegments, Projection, Camera,
    ViewWidth, ViewHeight, X, Y);
end;

function TMmdD3DOverlay.HasVertices: Boolean;
begin
  Result := (FShapeCount > 0) or (FLineCount > 0);
end;

end.
