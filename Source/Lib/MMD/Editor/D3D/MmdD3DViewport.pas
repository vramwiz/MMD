unit MmdD3DViewport;

// 専用ポーズGUIとD3Dレンダラーを接続する薄いVCLコントロール。

interface

uses
  System.Classes,
  Vcl.Controls,
  PmxModel,
  PmxPose,
  MmdD3DRenderer;

type
  TMmdD3DViewport = class(TCustomControl)
  private
    FModel: TPmxModel;
    FPoses: TPmxBonePoses;
    FRenderer: TMmdD3DRenderer;
    FSelectedBone: Integer;
    function GetErrorText: string;
    procedure RebuildScene;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Paint; override;
    procedure Resize; override;
  public
    // VCLウィンドウHandleの生成・破棄にD3D Rendererの寿命を追従させるControlを生成する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // モデルと姿勢の作業用コピーを設定し、GPU頂点を再構築する。
    procedure SetScene(AModel: TPmxModel; const APoses: TPmxBonePoses;
      ASelectedBone: Integer);
    property ErrorText: string read GetErrorText;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Graphics;

constructor TMmdD3DViewport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedBone := -1;
  Color := RGB(14, 15, 19);
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
  begin
    FRenderer.Resize(ClientWidth, ClientHeight);
    // Resize後の縦横比でNDC座標を作り直す。
    RebuildScene;
  end;
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
    FRenderer.SetScene(FModel, FPoses, FSelectedBone);
  Invalidate;
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

end.
