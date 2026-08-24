unit MmdMorphPreviewPanel;

// 保存データを変更せず、PMXモーフを一時的にD3Dプレビューで確認する欄を提供する。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  PmxModel,
  PmxMorph;

type
  TMmdMorphPreviewPanel = class(TPanel)
  private
    FClearButton: TButton;
    FList: TListBox;
    FModel: TPmxModel;
    FOnWeightsChanged: TNotifyEvent;
    FTrack: TTrackBar;
    FUpdating: Boolean;
    FValueLabel: TLabel;
    FWeights: TPmxMorphWeights;
    procedure ClearClick(Sender: TObject);
    procedure ListChanged(Sender: TObject);
    procedure TrackChanged(Sender: TObject);
    procedure UpdateControls;
  public
    constructor Create(AOwner: TComponent); override;
    // モデルの全モーフを列挙し、確認用係数を0へ初期化する。
    procedure SetModel(AModel: TPmxModel);
    // 現在の確認用係数を呼び出し側へコピーする。
    procedure CopyWeights(out AWeights: TPmxMorphWeights);
    property OnWeightsChanged: TNotifyEvent read FOnWeightsChanged
      write FOnWeightsChanged;
  end;

// 現在のプレビュー計算が適用できるモーフ種別かを返す。
function IsPreviewMorphSupported(MorphType: TPmxMorphType): Boolean;

implementation

uses
  System.SysUtils;

function IsPreviewMorphSupported(MorphType: TPmxMorphType): Boolean;
begin
  Result := MorphType in [pmtGroup, pmtVertex, pmtBone, pmtFlip];
end;

function MorphTypeText(MorphType: TPmxMorphType): string;
begin
  case MorphType of
    pmtGroup: Result := string('グループ');
    pmtVertex: Result := string('頂点');
    pmtBone: Result := string('ボーン');
    pmtUV, pmtAdditionalUV1, pmtAdditionalUV2, pmtAdditionalUV3,
    pmtAdditionalUV4: Result := string('UV・未対応');
    pmtMaterial: Result := string('材質・未対応');
    pmtFlip: Result := string('フリップ');
    pmtImpulse: Result := string('インパルス・未対応');
  else
    Result := string('未対応');
  end;
end;

constructor TMmdMorphPreviewPanel.Create(AOwner: TComponent);
var
  CaptionLabel: TLabel;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Height := 245;

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := Self;
  CaptionLabel.Caption := string('モーフ動作確認（保存されません）');
  CaptionLabel.SetBounds(8, 6, 225, 18);

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(8, 27, 229, 132);
  FList.OnClick := ListChanged;

  FTrack := TTrackBar.Create(Self);
  FTrack.Parent := Self;
  FTrack.Min := 0;
  FTrack.Max := 100;
  FTrack.Frequency := 10;
  FTrack.TickStyle := tsAuto;
  FTrack.SetBounds(4, 161, 174, 40);
  FTrack.OnChange := TrackChanged;

  FValueLabel := TLabel.Create(Self);
  FValueLabel.Parent := Self;
  FValueLabel.Alignment := taRightJustify;
  FValueLabel.SetBounds(180, 172, 55, 18);

  FClearButton := TButton.Create(Self);
  FClearButton.Parent := Self;
  FClearButton.Caption := '全て 0%';
  FClearButton.SetBounds(8, 205, 229, 30);
  FClearButton.OnClick := ClearClick;
  // Parent未設定のコンストラクタ中にItemIndexを読むとListBoxのHandle生成が
  // 先行し、VCLがInvalidControlOperationを送出する。SetModel後に同期する。
  FTrack.Enabled := False;
  FValueLabel.Caption := '0%';
  FClearButton.Enabled := False;
end;

procedure TMmdMorphPreviewPanel.SetModel(AModel: TPmxModel);
var
  I: Integer;
begin
  FModel := AModel;
  FList.Items.BeginUpdate;
  try
    FList.Clear;
    if FModel <> nil then
      for I := 0 to High(FModel.Morphs) do
        FList.Items.Add(Format('%s  [%s]', [FModel.Morphs[I].Name,
          MorphTypeText(FModel.Morphs[I].MorphType)]));
  finally
    FList.Items.EndUpdate;
  end;
  if FModel = nil then
    FWeights := nil
  else
    InitializeMorphWeights(FModel, FWeights);
  if FList.Count > 0 then
    FList.ItemIndex := 0;
  UpdateControls;
end;

procedure TMmdMorphPreviewPanel.CopyWeights(out AWeights: TPmxMorphWeights);
begin
  AWeights := Copy(FWeights);
end;

procedure TMmdMorphPreviewPanel.UpdateControls;
var
  Index: Integer;
begin
  Index := FList.ItemIndex;
  FUpdating := True;
  try
    FTrack.Enabled := (FModel <> nil) and (Index >= 0) and
      IsPreviewMorphSupported(FModel.Morphs[Index].MorphType);
    if (Index >= 0) and (Index < Length(FWeights)) then
      FTrack.Position := Round(FWeights[Index] * 100)
    else
      FTrack.Position := 0;
    FValueLabel.Caption := Format('%d%%', [FTrack.Position]);
    FClearButton.Enabled := Length(FWeights) > 0;
  finally
    FUpdating := False;
  end;
end;

procedure TMmdMorphPreviewPanel.ListChanged(Sender: TObject);
begin
  UpdateControls;
end;

procedure TMmdMorphPreviewPanel.TrackChanged(Sender: TObject);
var
  Index: Integer;
begin
  if FUpdating then
    Exit;
  Index := FList.ItemIndex;
  if (Index < 0) or (Index >= Length(FWeights)) or not FTrack.Enabled then
    Exit;
  FWeights[Index] := FTrack.Position / 100.0;
  FValueLabel.Caption := Format('%d%%', [FTrack.Position]);
  if Assigned(FOnWeightsChanged) then
    FOnWeightsChanged(Self);
end;

procedure TMmdMorphPreviewPanel.ClearClick(Sender: TObject);
begin
  if FModel = nil then
    Exit;
  InitializeMorphWeights(FModel, FWeights);
  UpdateControls;
  if Assigned(FOnWeightsChanged) then
    FOnWeightsChanged(Self);
end;

end.
