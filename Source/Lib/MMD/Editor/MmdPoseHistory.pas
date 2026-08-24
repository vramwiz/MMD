unit MmdPoseHistory;

// ポーズ編集GUIのUndo / Redo用に、姿勢全体の独立したスナップショットを保持する。

interface

uses
  PmxPoseTypes;

type
  TMmdPoseStacks = array of TPmxBonePoses;

  TMmdPoseHistory = class
  private
    FRedo: TMmdPoseStacks;
    FUndo: TMmdPoseStacks;
    procedure Push(var Stack: TMmdPoseStacks; const Poses: TPmxBonePoses);
  public
    // 編集直前の姿勢をUndoへ追加し、新しい編集系列としてRedoを破棄する。
    procedure RecordBeforeEdit(const Poses: TPmxBonePoses);
    // 現在姿勢をRedoへ保存して直前姿勢を返す。履歴がなければFalseを返す。
    function Undo(const Current: TPmxBonePoses;
      out Restored: TPmxBonePoses): Boolean;
    // 現在姿勢をUndoへ保存してやり直し姿勢を返す。履歴がなければFalseを返す。
    function Redo(const Current: TPmxBonePoses;
      out Restored: TPmxBonePoses): Boolean;
    // Undo可能な姿勢スナップショットがあるかを返す。
    function CanUndo: Boolean;
    // Redo可能な姿勢スナップショットがあるかを返す。
    function CanRedo: Boolean;
  end;

implementation

const
  MAX_HISTORY_COUNT = 100;

procedure TMmdPoseHistory.Push(var Stack: TMmdPoseStacks;
  const Poses: TPmxBonePoses);
var
  Index: Integer;
begin
  if Length(Stack) >= MAX_HISTORY_COUNT then
  begin
    for Index := 1 to High(Stack) do
      Stack[Index - 1] := Stack[Index];
    SetLength(Stack, MAX_HISTORY_COUNT - 1);
  end;
  SetLength(Stack, Length(Stack) + 1);
  Stack[High(Stack)] := Copy(Poses);
end;

procedure TMmdPoseHistory.RecordBeforeEdit(const Poses: TPmxBonePoses);
begin
  Push(FUndo, Poses);
  SetLength(FRedo, 0);
end;

function TMmdPoseHistory.Undo(const Current: TPmxBonePoses;
  out Restored: TPmxBonePoses): Boolean;
begin
  Result := Length(FUndo) > 0;
  if not Result then
    Exit;
  Push(FRedo, Current);
  Restored := Copy(FUndo[High(FUndo)]);
  SetLength(FUndo, Length(FUndo) - 1);
end;

function TMmdPoseHistory.Redo(const Current: TPmxBonePoses;
  out Restored: TPmxBonePoses): Boolean;
begin
  Result := Length(FRedo) > 0;
  if not Result then
    Exit;
  Push(FUndo, Current);
  Restored := Copy(FRedo[High(FRedo)]);
  SetLength(FRedo, Length(FRedo) - 1);
end;

function TMmdPoseHistory.CanUndo: Boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TMmdPoseHistory.CanRedo: Boolean;
begin
  Result := Length(FRedo) > 0;
end;

end.
