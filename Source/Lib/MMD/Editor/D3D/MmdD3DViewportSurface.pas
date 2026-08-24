unit MmdD3DViewportSurface;

// VCL子ウィンドウとD3D Rendererの寿命を同期し、編集入力に依存しない描画面を提供する。

interface

uses
  System.Classes,
  Vcl.Controls,
  PmxModel,
  PmxPose,
  MmdD3DRenderer,
  MmdD3DScene;

type
  TMmdD3DViewportSurface = class(TCustomControl)
  private
    function GetErrorText: string;
    function GetLoadedTextureCount: Integer;
  protected
    FCamera: TMmdPreviewCamera;
    FHoverTarget: TMmdPreviewTarget;
    FModel: TPmxModel;
    FPoses: TPmxBonePoses;
    FRenderer: TMmdD3DRenderer;
    FSelectedTarget: TMmdPreviewTarget;
    // モデル本体を含む確定シーンを更新する。カメラ値と初回フレームはRendererが維持する。
    procedure RebuildScene;
    // モデル本体を維持し、ドラッグ中の骨格オーバーレイだけを更新する。
    procedure RebuildSkeleton;
    // 頂点を再生成せず、カメラ定数だけを更新する。
    procedure UpdateCamera;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Paint; override;
    procedure Resize; override;
  public
    // 子ウィンドウ生成前のカメラ、選択値、背景描画属性を初期化する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Camera: TMmdPreviewCamera read FCamera;
    property ErrorText: string read GetErrorText;
    property LoadedTextureCount: Integer read GetLoadedTextureCount;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Graphics;

constructor TMmdD3DViewportSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCamera := DefaultPreviewCamera;
  FSelectedTarget := EmptyPreviewTarget;
  FHoverTarget := EmptyPreviewTarget;
  Color := RGB(14, 15, 19);
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TMmdD3DViewportSurface.Destroy;
begin
  FRenderer.Free;
  inherited Destroy;
end;

procedure TMmdD3DViewportSurface.CreateWnd;
begin
  inherited CreateWnd;
  FreeAndNil(FRenderer);
  FRenderer := TMmdD3DRenderer.Create(Handle, ClientWidth, ClientHeight);
  RebuildScene;
end;

procedure TMmdD3DViewportSurface.DestroyWnd;
begin
  FreeAndNil(FRenderer);
  inherited DestroyWnd;
end;

procedure TMmdD3DViewportSurface.Resize;
begin
  inherited Resize;
  if FRenderer <> nil then
    FRenderer.Resize(ClientWidth, ClientHeight);
  Invalidate;
end;

procedure TMmdD3DViewportSurface.Paint;
var
  Message_: string;
begin
  if FRenderer <> nil then
  begin
    FRenderer.Render;
    Message_ := FRenderer.ErrorText;
  end
  else
    Message_ := 'Direct3Dを初期化できませんでした。';
  if Message_ <> '' then
  begin
    Canvas.Brush.Color := Color;
    Canvas.FillRect(ClientRect);
    Canvas.Font.Color := clSilver;
    Canvas.TextOut(12, 12, Message_);
  end;
end;

procedure TMmdD3DViewportSurface.RebuildScene;
begin
  if (FRenderer <> nil) and (FModel <> nil) then
  begin
    FRenderer.SetScene(FModel, FPoses, FSelectedTarget, FHoverTarget);
    FRenderer.SetCamera(FCamera);
  end;
  Invalidate;
end;

procedure TMmdD3DViewportSurface.RebuildSkeleton;
begin
  if (FRenderer <> nil) and (FModel <> nil) then
  begin
    FRenderer.SetSkeleton(FModel, FPoses, FSelectedTarget, FHoverTarget);
    FRenderer.SetCamera(FCamera);
  end;
  Invalidate;
end;

procedure TMmdD3DViewportSurface.UpdateCamera;
begin
  if FRenderer <> nil then
    FRenderer.SetCamera(FCamera);
  Invalidate;
end;

function TMmdD3DViewportSurface.GetErrorText: string;
begin
  if FRenderer = nil then
    Result := 'Direct3Dを初期化できませんでした。'
  else
    Result := FRenderer.ErrorText;
end;

function TMmdD3DViewportSurface.GetLoadedTextureCount: Integer;
begin
  if FRenderer = nil then
    Result := 0
  else
    Result := FRenderer.LoadedTextureCount;
end;

end.
