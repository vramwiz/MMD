unit MmdD3DViewport;

// D3D描画面へマウス・キー操作を接続し、選択、カメラ、作業用姿勢を管理する。

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  PmxModel,
  PmxPose,
  MmdD3DScene,
  MmdD3DViewportSurface;

type
  TMmdPressedViewKeys = set of Byte;
  TMmdD3DViewport = class(TMmdD3DViewportSurface)
  private
    FDragDirection: TPmxVector3;
    FDragParentFrameRotation: TPmxQuaternion;
    FDragPoseBone: Integer;
    FDragMirrorBone: Integer;
    FDragProjection: TMmdPreviewProjection;
    FDragStartLocalRotation: TPmxQuaternion;
    FDragging: Boolean;
    FCameraRotating: Boolean;
    FLastFixedViewKey: Word;
    FLastMouse: TPoint;
    FLockedBones: array of Boolean;
    FMouseDown: TPoint;
    FMouseDownTarget: TMmdPreviewTarget;
    FTargetDragging: Boolean;
    FTargetEditStarted: Boolean;
    FSelectedBone: Integer;
    FSymmetricEditing: Boolean;
    FOnBoneSelected: TNotifyEvent;
    FOnPoseChanged: TNotifyEvent;
    FOnPoseEditFinished: TNotifyEvent;
    FOnPoseEditStarted: TNotifyEvent;
    FPressedViewKeys: TMmdPressedViewKeys;
    FFixedViewOpposite: Boolean;
    FReferenceImage: Vcl.Graphics.TBitmap;
    procedure DrawReferenceImage;
    procedure BeginTargetDrag(const Target: TMmdPreviewTarget);
    function GetSelectedBoneLocked: Boolean;
    procedure SelectTarget(const Target: TMmdPreviewTarget);
    procedure SetFixedView(Key: Word);
    procedure ToggleSelectedBoneLock;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    // 描画面へ編集用カーソル、ヒント、キーフォーカスを追加したControlを生成する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // モデルと姿勢の作業用コピーを設定し、GPU頂点を再構築する。
    procedure SetScene(AModel: TPmxModel; const APoses: TPmxBonePoses;
      ASelectedBone: Integer);
    // 編集中の姿勢作業用コピーを呼び出し側へ返す。
    procedure CopyPoses(out APoses: TPmxBonePoses);
    // 貼り付け画像をフォーム内の独立コピーとして保持し、半透明で重ねる。
    procedure SetReferenceImage(Bitmap: Vcl.Graphics.TBitmap);
    function HasReferenceImage: Boolean;
    // 参照画像を現在のViewportと同じ寸法・投影基準へ変換してコピーする。
    procedure CopyReferenceImageForViewport(Bitmap: Vcl.Graphics.TBitmap);
    function IsBoneLocked(BoneIndex: Integer): Boolean;
    property SelectedBoneLocked: Boolean read GetSelectedBoneLocked;
    property SelectedBone: Integer read FSelectedBone;
    property SelectedTarget: TMmdPreviewTarget read FSelectedTarget;
    property SymmetricEditing: Boolean read FSymmetricEditing write FSymmetricEditing;
    property OnBoneSelected: TNotifyEvent read FOnBoneSelected write FOnBoneSelected;
    property OnPoseChanged: TNotifyEvent read FOnPoseChanged write FOnPoseChanged;
    property OnPoseEditFinished: TNotifyEvent read FOnPoseEditFinished
      write FOnPoseEditFinished;
    property OnPoseEditStarted: TNotifyEvent read FOnPoseEditStarted
      write FOnPoseEditStarted;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  MmdD3DInteraction,
  MmdD3DLiveDragTest,
  MmdPoseSymmetry,
  PmxPoseMath;

constructor TMmdD3DViewport.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FReferenceImage := Vcl.Graphics.TBitmap.Create;
  FSelectedBone := -1;
  FMouseDownTarget := EmptyPreviewTarget;
  FDragMirrorBone := -1;
  Cursor := crSizeAll;
  Hint := '関節・ボーン左ドラッグ: 回転  /  空白左ドラッグ: プレビュー移動  /  右ドラッグ: カメラ回転';
  Hint := Hint + '  /  操作中X・Y(C)・Z: ローカル軸制限';
  Hint := Hint + '  /  操作中G: 5°スナップ';
  Hint := Hint + '  /  L: 選択ボーン固定';
  ShowHint := True;
  TabStop := True;
end;

procedure TMmdD3DViewport.SetFixedView(Key: Word);
var
  View: TMmdFixedView;
begin
  if Key = FLastFixedViewKey then
    FFixedViewOpposite := not FFixedViewOpposite
  else
  begin
    FLastFixedViewKey := Key;
    FFixedViewOpposite := False;
  end;
  case Key of
    Ord('A'): View := fvFront;
    Ord('S'): View := fvSide;
    Ord('D'): View := fvVertical;
  else
    Exit;
  end;
  ApplyFixedPreviewView(FCamera, View, FFixedViewOpposite);
  UpdateCamera;
end;

procedure TMmdD3DViewport.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if FTargetDragging or
    not (Key in [Ord('A'), Ord('S'), Ord('D'), Ord('L')]) then
    Exit;
  if Byte(Key) in FPressedViewKeys then
  begin
    Key := 0;
    Exit;
  end;
  Include(FPressedViewKeys, Byte(Key));
  if Key = Ord('L') then
    ToggleSelectedBoneLock
  else
    SetFixedView(Key);
  Key := 0;
end;

procedure TMmdD3DViewport.KeyUp(var Key: Word; Shift: TShiftState);
begin
  if Key in [Ord('A'), Ord('S'), Ord('D'), Ord('L')] then
    Exclude(FPressedViewKeys, Byte(Key));
  inherited KeyUp(Key, Shift);
end;

function TMmdD3DViewport.GetSelectedBoneLocked: Boolean;
begin
  Result := (FSelectedBone >= 0) and
    (FSelectedBone < Length(FLockedBones)) and FLockedBones[FSelectedBone];
end;

procedure TMmdD3DViewport.ToggleSelectedBoneLock;
begin
  if (FSelectedBone < 0) or (FSelectedBone >= Length(FLockedBones)) then
    Exit;
  FLockedBones[FSelectedBone] := not FLockedBones[FSelectedBone];
  FSelectedTarget.Locked := FLockedBones[FSelectedBone];
  RebuildSkeleton;
end;

procedure TMmdD3DViewport.SelectTarget(const Target: TMmdPreviewTarget);
var
  Selected: TMmdPreviewTarget;
begin
  Selected := Target;
  Selected.Locked := (Selected.JointIndex >= 0) and
    (Selected.JointIndex < Length(FLockedBones)) and
    FLockedBones[Selected.JointIndex];
  if (Selected.Kind = FSelectedTarget.Kind) and
    (Selected.JointIndex = FSelectedTarget.JointIndex) and
    (Selected.BoneIndex = FSelectedTarget.BoneIndex) and
    (Selected.Locked = FSelectedTarget.Locked) then
    Exit;
  FSelectedTarget := Selected;
  FSelectedBone := Selected.JointIndex;
  RebuildSkeleton;
  if Assigned(FOnBoneSelected) then
    FOnBoneSelected(Self);
end;

procedure TMmdD3DViewport.BeginTargetDrag(const Target: TMmdPreviewTarget);
var
  EndJointIndex, GrandParentIndex, PoseBoneIndex: Integer;
  Transforms: TPmxBoneTransforms;
begin
  FTargetDragging := False;
  FTargetEditStarted := False;
  FDragMirrorBone := -1;
  if (FModel = nil) or (Target.JointIndex < 0) then
    Exit;
  if Target.Kind = ptJoint then
  begin
    EndJointIndex := Target.JointIndex;
    PoseBoneIndex := FModel.Bones[EndJointIndex].ParentIndex;
  end
  else if Target.Kind = ptBone then
  begin
    EndJointIndex := Target.BoneIndex;
    PoseBoneIndex := Target.JointIndex;
  end
  else
    Exit;
  if (PoseBoneIndex < 0) or (EndJointIndex < 0) then
    Exit;
  if (PoseBoneIndex < Length(FLockedBones)) and FLockedBones[PoseBoneIndex] then
    Exit;
  if FSymmetricEditing then
  begin
    FDragMirrorBone := FindSymmetricBone(FModel, PoseBoneIndex);
    if (FDragMirrorBone >= 0) and
      (FDragMirrorBone < Length(FLockedBones)) and
      FLockedBones[FDragMirrorBone] then
      FDragMirrorBone := -1;
  end;
  CalculateBoneTransforms(FModel, FPoses, Transforms);
  FDragDirection := SubtractVector(Transforms[EndJointIndex].Position,
    Transforms[PoseBoneIndex].Position);
  if DotVector(FDragDirection, FDragDirection) <= 0.000001 then
    Exit;
  FDragPoseBone := PoseBoneIndex;
  FDragStartLocalRotation := FPoses[PoseBoneIndex].Rotation;
  GrandParentIndex := FModel.Bones[PoseBoneIndex].ParentIndex;
  if GrandParentIndex < 0 then
    FDragParentFrameRotation := IdentityQuaternion
  else
    FDragParentFrameRotation := Transforms[GrandParentIndex].Rotation;
  FDragProjection := FRenderer.Projection;
  FTargetDragging := True;
end;

procedure TMmdD3DViewport.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
  if not (Button in [mbLeft, mbRight]) then
    Exit;
  if FRenderer = nil then
    FMouseDownTarget := EmptyPreviewTarget
  else
    FMouseDownTarget := FRenderer.HitTestTarget(X, Y);
  FDragging := (Button = mbRight) or
    ((Button = mbLeft) and (FMouseDownTarget.Kind = ptNone));
  FCameraRotating := Button = mbRight;
  FMouseDown := Point(X, Y);
  FLastMouse := Point(X, Y);
  FTargetDragging := False;
  if (Button = mbLeft) and
    (FMouseDownTarget.Kind in [ptJoint, ptBone]) then
  begin
    SelectTarget(FMouseDownTarget);
    BeginTargetDrag(FMouseDownTarget);
  end;
  MouseCapture := True;
end;

procedure TMmdD3DViewport.MouseMove(Shift: TShiftState; X, Y: Integer);
const
  ROTATION_PER_PIXEL = 0.01;
var
  ModelDelta: TPmxVector3;
  HoverTarget: TMmdPreviewTarget;
  Rotation: TPmxQuaternion;
begin
  inherited MouseMove(Shift, X, Y);
  if FTargetDragging then
  begin
    if not FTargetEditStarted then
    begin
      FTargetEditStarted := True;
      if Assigned(FOnPoseEditStarted) then
        FOnPoseEditStarted(Self);
    end;
    ModelDelta := PreviewScreenDeltaToModel(X - FMouseDown.X,
      Y - FMouseDown.Y, FDragProjection, FCamera, ClientWidth, ClientHeight);
    Rotation := BoneDragLocalRotation(FDragDirection,
      ModelDelta, FDragParentFrameRotation, FDragStartLocalRotation,
      ActivePreviewDragAxis, X - FMouseDown.X);
    if GetKeyState(Ord('G')) < 0 then
      Rotation := SnapLocalRotation(FDragStartLocalRotation, Rotation,
        DegToRad(5));
    FPoses[FDragPoseBone].Rotation := Rotation;
    if FDragMirrorBone >= 0 then
      FPoses[FDragMirrorBone] := MirrorBonePose(FPoses[FDragPoseBone]);
    if TEMPORARY_LIVE_MODEL_DRAG_TEST then
    begin
      RebuildScene;
      Update;
    end
    else
      RebuildSkeleton;
    if Assigned(FOnPoseChanged) then
      FOnPoseChanged(Self);
    Exit;
  end;
  if not FDragging then
  begin
    if FRenderer = nil then
      Exit;
    HoverTarget := FRenderer.HitTestTarget(X, Y);
    if (HoverTarget.Kind <> FHoverTarget.Kind) or
      (HoverTarget.JointIndex <> FHoverTarget.JointIndex) or
      (HoverTarget.BoneIndex <> FHoverTarget.BoneIndex) then
    begin
      FHoverTarget := HoverTarget;
      RebuildSkeleton;
    end;
    Exit;
  end;
  if FCameraRotating then
  begin
    FCamera.Yaw := FCamera.Yaw + (X - FLastMouse.X) * ROTATION_PER_PIXEL;
    FCamera.Pitch := EnsureRange(FCamera.Pitch +
      (Y - FLastMouse.Y) * ROTATION_PER_PIXEL, -Pi * 0.47, Pi * 0.47);
  end
  else
  begin
    FCamera.PanX := FCamera.PanX + X - FLastMouse.X;
    FCamera.PanY := FCamera.PanY + Y - FLastMouse.Y;
  end;
  FLastMouse := Point(X, Y);
  UpdateCamera;
end;

procedure TMmdD3DViewport.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Target: TMmdPreviewTarget;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not (Button in [mbLeft, mbRight]) then
    Exit;
  FDragging := False;
  MouseCapture := False;
  if FTargetDragging then
  begin
    FTargetDragging := False;
    RebuildScene;
    if FTargetEditStarted and Assigned(FOnPoseEditFinished) then
      FOnPoseEditFinished(Self);
    FTargetEditStarted := False;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  if (Abs(X - FMouseDown.X) > 3) or (Abs(Y - FMouseDown.Y) > 3) or
    (FRenderer = nil) then
    Exit;
  Target := FRenderer.HitTestTarget(X, Y);
  SelectTarget(Target);
end;

procedure TMmdD3DViewport.CopyPoses(out APoses: TPmxBonePoses);
begin
  APoses := Copy(FPoses);
end;

destructor TMmdD3DViewport.Destroy;
begin
  FReferenceImage.Free;
  inherited Destroy;
end;

function TMmdD3DViewport.HasReferenceImage: Boolean;
begin
  Result := (FReferenceImage.Width > 0) and (FReferenceImage.Height > 0);
end;

function TMmdD3DViewport.IsBoneLocked(BoneIndex: Integer): Boolean;
begin
  Result := (BoneIndex >= 0) and (BoneIndex < Length(FLockedBones)) and
    FLockedBones[BoneIndex];
end;

procedure TMmdD3DViewport.SetReferenceImage(Bitmap: Vcl.Graphics.TBitmap);
begin
  if Bitmap = nil then
    FReferenceImage.SetSize(0, 0)
  else
    FReferenceImage.Assign(Bitmap);
  Invalidate;
end;

procedure TMmdD3DViewport.CopyReferenceImageForViewport(
  Bitmap: Vcl.Graphics.TBitmap);
var
  DestLeft, DestWidth: Integer;
begin
  Bitmap.PixelFormat := pf32bit;
  Bitmap.SetSize(ClientWidth, ClientHeight);
  Bitmap.Canvas.Brush.Color := RGB(14, 15, 19);
  Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
  if not HasReferenceImage or (ClientHeight <= 0) then
    Exit;
  DestWidth := MulDiv(FReferenceImage.Width, ClientHeight,
    FReferenceImage.Height);
  DestLeft := (ClientWidth - DestWidth) div 2;
  Bitmap.Canvas.StretchDraw(Rect(DestLeft, 0, DestLeft + DestWidth,
    ClientHeight), FReferenceImage);
end;

procedure TMmdD3DViewport.DrawReferenceImage;
const
  REFERENCE_ALPHA = 112;
var
  Blend: TBlendFunction;
  DestLeft, DestWidth: Integer;
  OldBitmap: HGDIOBJ;
  SourceDC: HDC;
begin
  if not HasReferenceImage or (ClientHeight <= 0) then
    Exit;
  // 投影上のモデル寸法はViewport高さに比例するため、参照画像も高さ基準で
  // 拡大縮小する。横幅差は中央寄せし、縦横比を変えない。
  DestWidth := MulDiv(FReferenceImage.Width, ClientHeight,
    FReferenceImage.Height);
  DestLeft := (ClientWidth - DestWidth) div 2;
  SourceDC := CreateCompatibleDC(Canvas.Handle);
  if SourceDC = 0 then
    Exit;
  OldBitmap := SelectObject(SourceDC, FReferenceImage.Handle);
  try
    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := REFERENCE_ALPHA;
    Blend.AlphaFormat := 0;
    AlphaBlend(Canvas.Handle, DestLeft, 0, DestWidth, ClientHeight,
      SourceDC, 0, 0, FReferenceImage.Width, FReferenceImage.Height, Blend);
  finally
    SelectObject(SourceDC, OldBitmap);
    DeleteDC(SourceDC);
  end;
end;

procedure TMmdD3DViewport.Paint;
begin
  inherited Paint;
  DrawReferenceImage;
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
  if AModel <> FModel then
  begin
    SetLength(FLockedBones, 0);
    if AModel <> nil then
      SetLength(FLockedBones, Length(AModel.Bones));
  end;
  FModel := AModel;
  FPoses := Copy(APoses);
  if ASelectedBone = FSelectedBone then
  begin
    RebuildScene;
    Exit;
  end;
  FSelectedBone := ASelectedBone;
  FSelectedTarget := EmptyPreviewTarget;
  if ASelectedBone >= 0 then
  begin
    FSelectedTarget.Kind := ptJoint;
    FSelectedTarget.JointIndex := ASelectedBone;
    FSelectedTarget.Locked := GetSelectedBoneLocked;
  end;
  RebuildScene;
end;

end.
