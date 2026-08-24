unit MmdD3DViewport;

// 専用ポーズGUIとD3Dレンダラーを接続する薄いVCLコントロール。

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  PmxModel,
  PmxPose,
  MmdD3DScene,
  MmdD3DRenderer;

type
  TMmdD3DViewport = class(TCustomControl)
  private
    FModel: TPmxModel;
    FCamera: TMmdPreviewCamera;
    FDragging: Boolean;
    FLastMouse: TPoint;
    FPoses: TPmxBonePoses;
    FRenderer: TMmdD3DRenderer;
    FSelectedBone: Integer;
    function GetErrorText: string;
    function GetLoadedTextureCount: Integer;
    procedure RebuildScene;
    procedure UpdateCamera;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    // VCLウィンドウHandleの生成・破棄にD3D Rendererの寿命を追従させるControlを生成する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // モデルと姿勢の作業用コピーを設定し、GPU頂点を再構築する。
    procedure SetScene(AModel: TPmxModel; const APoses: TPmxBonePoses;
      ASelectedBone: Integer);
    property ErrorText: string read GetErrorText;
    property LoadedTextureCount: Integer read GetLoadedTextureCount;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.SysUtils,
  Vcl.Graphics;

constructor TMmdD3DViewport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCamera := DefaultPreviewCamera;
  FSelectedBone := -1;
  Color := RGB(14, 15, 19);
  Cursor := crSizeAll;
  Hint := '左ドラッグ: カメラ回転  /  マウスホイール: 拡大縮小';
  ShowHint := True;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TMmdD3DViewport.Destroy;
begin
  FRenderer.Free;
  inherited Destroy;
end;

procedure TMmdD3DViewport.CreateWnd;
begin
  inherited CreateWnd;
  FreeAndNil(FRenderer);
  FRenderer := TMmdD3DRenderer.Create(Handle, ClientWidth, ClientHeight);
  RebuildScene;
end;

procedure TMmdD3DViewport.DestroyWnd;
begin
  FreeAndNil(FRenderer);
  inherited DestroyWnd;
end;

procedure TMmdD3DViewport.Resize;
begin
  inherited Resize;
  if FRenderer <> nil then
    FRenderer.Resize(ClientWidth, ClientHeight);
  Invalidate;
end;

procedure TMmdD3DViewport.Paint;
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

procedure TMmdD3DViewport.RebuildScene;
begin
  if (FRenderer <> nil) and (FModel <> nil) then
  begin
    FRenderer.SetScene(FModel, FPoses, FSelectedBone);
    FRenderer.SetCamera(FCamera);
  end;
  Invalidate;
end;

procedure TMmdD3DViewport.UpdateCamera;
begin
  if FRenderer <> nil then
    // ドラッグ中は定数バッファだけを更新し、スキニング済み頂点を再利用する。
    FRenderer.SetCamera(FCamera);
  Invalidate;
end;

procedure TMmdD3DViewport.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  FDragging := True;
  FLastMouse := Point(X, Y);
  MouseCapture := True;
end;

procedure TMmdD3DViewport.MouseMove(Shift: TShiftState; X, Y: Integer);
const
  ROTATION_PER_PIXEL = 0.01;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
    Exit;
  FCamera.Yaw := FCamera.Yaw + (X - FLastMouse.X) * ROTATION_PER_PIXEL;
  FCamera.Pitch := EnsureRange(FCamera.Pitch +
    (Y - FLastMouse.Y) * ROTATION_PER_PIXEL, -Pi * 0.47, Pi * 0.47);
  FLastMouse := Point(X, Y);
  UpdateCamera;
end;

procedure TMmdD3DViewport.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  FDragging := False;
  MouseCapture := False;
end;

function TMmdD3DViewport.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FCamera.Zoom := EnsureRange(FCamera.Zoom * Power(1.1,
    WheelDelta / WHEEL_DELTA), 0.2, 5.0);
  UpdateCamera;
  Result := True;
end;

procedure TMmdD3DViewport.SetScene(AModel: TPmxModel;
  const APoses: TPmxBonePoses; ASelectedBone: Integer);
begin
  FModel := AModel;
  FPoses := Copy(APoses);
  FSelectedBone := ASelectedBone;
  RebuildScene;
end;

function TMmdD3DViewport.GetErrorText: string;
begin
  if FRenderer = nil then
    Result := 'Direct3Dを初期化できませんでした。'
  else
    Result := FRenderer.ErrorText;
end;

function TMmdD3DViewport.GetLoadedTextureCount: Integer;
begin
  if FRenderer = nil then
    Result := 0
  else
    Result := FRenderer.LoadedTextureCount;
end;

end.
