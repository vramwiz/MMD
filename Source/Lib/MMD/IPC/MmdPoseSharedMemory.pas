unit MmdPoseSharedMemory;

// ポーズレイヤーから表示モデルへ、レイヤー単位の姿勢スナップショットを安全に渡す。

interface

uses
  AviUtl2FilterTypes;

type
  TMmdPoseSharedSnapshot = record
    WriterObjectID: Int64;
    WriterEffectID: Int64;
    TimelineFrame: Integer;
    ModelPathHash: UInt64;
    PoseData: string;
  end;

// 両プラグインで同じ絶対PMXパスを照合するための安定したハッシュを返す。
function HashModelPath(const FileName: string): UInt64;
// 指定レイヤーの現フレーム姿勢を共有メモリへ発行する。
function PublishPoseSnapshot(Layer: Integer; const Snapshot: TMmdPoseSharedSnapshot): Boolean;
// 指定レイヤーから姿勢を取得し、フレームとモデルが一致した場合だけ成功する。
function TryReadPoseSnapshot(Layer, TimelineFrame: Integer; ModelPathHash: UInt64;
  out Snapshot: TMmdPoseSharedSnapshot): Boolean;
// AviUtl2のオブジェクト相対フレームからタイムライン上のフレームを得る。
function GetTimelineFrame(const ObjectInfo: POBJECT_INFO): Integer;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils;

const
  MMD_POSE_SHARED_MAGIC = $4D4D4450; // MMDP
  MMD_POSE_SHARED_VERSION = 1;
  MMD_POSE_SHARED_DATA_SIZE = 1024 * 1024;

type
  PMmdPoseSharedBlock = ^TMmdPoseSharedBlock;
  TMmdPoseSharedBlock = packed record
    Magic: Cardinal;
    Version: Cardinal;
    Sequence: UInt64;
    WriterProcessID: Cardinal;
    WriterObjectID: Int64;
    WriterEffectID: Int64;
    TimelineFrame: Integer;
    ModelPathHash: UInt64;
    DataLength: Cardinal;
    Data: array[0..MMD_POSE_SHARED_DATA_SIZE - 1] of Byte;
  end;

  TMmdPoseSharedChannel = class
  private
    FMapping: THandle;
    FMutex: THandle;
    FView: PMmdPoseSharedBlock;
    function Lock: Boolean;
    procedure Unlock;
  public
    constructor Create(Layer: Integer);
    destructor Destroy; override;
    function Publish(const Snapshot: TMmdPoseSharedSnapshot): Boolean;
    function TryRead(TimelineFrame: Integer; ModelPathHash: UInt64;
      out Snapshot: TMmdPoseSharedSnapshot): Boolean;
  end;

var
  ChannelLock: TObject;
  Channels: TObjectDictionary<Integer, TMmdPoseSharedChannel>;

function ChannelName(const Kind: string; Layer: Integer): string;
begin
  Result := Format('Local\MMD.Pose.%s.Layer.%d', [Kind, Layer]);
end;

constructor TMmdPoseSharedChannel.Create(Layer: Integer);
var
  IsOwner: Boolean;
begin
  inherited Create;
  FMutex := CreateMutex(nil, False, PChar(ChannelName('Mutex', Layer)));
  if FMutex = 0 then
    RaiseLastOSError;
  FMapping := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0,
    SizeOf(TMmdPoseSharedBlock), PChar(ChannelName('Memory', Layer)));
  if FMapping = 0 then
    RaiseLastOSError;
  IsOwner := GetLastError <> ERROR_ALREADY_EXISTS;
  FView := MapViewOfFile(FMapping, FILE_MAP_ALL_ACCESS, 0, 0,
    SizeOf(TMmdPoseSharedBlock));
  if FView = nil then
    RaiseLastOSError;
  if IsOwner then
    FillChar(FView^, SizeOf(FView^), 0);
end;

destructor TMmdPoseSharedChannel.Destroy;
begin
  if FView <> nil then
    UnmapViewOfFile(FView);
  if FMapping <> 0 then
    CloseHandle(FMapping);
  if FMutex <> 0 then
    CloseHandle(FMutex);
  inherited Destroy;
end;

function TMmdPoseSharedChannel.Lock: Boolean;
begin
  Result := (FMutex <> 0) and
    (WaitForSingleObject(FMutex, 1000) in [WAIT_OBJECT_0, WAIT_ABANDONED]);
end;

procedure TMmdPoseSharedChannel.Unlock;
begin
  ReleaseMutex(FMutex);
end;

function TMmdPoseSharedChannel.Publish(
  const Snapshot: TMmdPoseSharedSnapshot): Boolean;
var
  Bytes: TBytes;
begin
  Result := False;
  Bytes := TEncoding.UTF8.GetBytes(Snapshot.PoseData);
  if Length(Bytes) > MMD_POSE_SHARED_DATA_SIZE then
    Exit;
  if not Lock then
    Exit;
  try
    // 奇数は書込途中を表す。所有プロセス停止でMutexが放棄されても読取側は受理しない。
    Inc(FView^.Sequence);
    FView^.Magic := MMD_POSE_SHARED_MAGIC;
    FView^.Version := MMD_POSE_SHARED_VERSION;
    FView^.WriterProcessID := GetCurrentProcessId;
    FView^.WriterObjectID := Snapshot.WriterObjectID;
    FView^.WriterEffectID := Snapshot.WriterEffectID;
    FView^.TimelineFrame := Snapshot.TimelineFrame;
    FView^.ModelPathHash := Snapshot.ModelPathHash;
    FView^.DataLength := Length(Bytes);
    if Length(Bytes) > 0 then
      Move(Bytes[0], FView^.Data[0], Length(Bytes));
    Inc(FView^.Sequence);
    Result := True;
  finally
    Unlock;
  end;
end;

function TMmdPoseSharedChannel.TryRead(TimelineFrame: Integer;
  ModelPathHash: UInt64; out Snapshot: TMmdPoseSharedSnapshot): Boolean;
var
  Bytes: TBytes;
begin
  Snapshot := Default(TMmdPoseSharedSnapshot);
  Result := False;
  if not Lock then
    Exit;
  try
    if (FView^.Magic <> MMD_POSE_SHARED_MAGIC) or
      (FView^.Version <> MMD_POSE_SHARED_VERSION) or
      ((FView^.Sequence and 1) <> 0) or
      (FView^.TimelineFrame <> TimelineFrame) or
      (FView^.ModelPathHash <> ModelPathHash) or
      (FView^.DataLength > MMD_POSE_SHARED_DATA_SIZE) then
      Exit;
    Snapshot.WriterObjectID := FView^.WriterObjectID;
    Snapshot.WriterEffectID := FView^.WriterEffectID;
    Snapshot.TimelineFrame := FView^.TimelineFrame;
    Snapshot.ModelPathHash := FView^.ModelPathHash;
    SetLength(Bytes, FView^.DataLength);
    if Length(Bytes) > 0 then
      Move(FView^.Data[0], Bytes[0], Length(Bytes));
    Snapshot.PoseData := TEncoding.UTF8.GetString(Bytes);
    Result := True;
  finally
    Unlock;
  end;
end;

function GetChannel(Layer: Integer): TMmdPoseSharedChannel;
begin
  TMonitor.Enter(ChannelLock);
  try
    if not Channels.TryGetValue(Layer, Result) then
    begin
      Result := TMmdPoseSharedChannel.Create(Layer);
      Channels.Add(Layer, Result);
    end;
  finally
    TMonitor.Exit(ChannelLock);
  end;
end;

function HashModelPath(const FileName: string): UInt64;
const
  HASH_SEED: UInt64 = $9E3779B97F4A7C15;
var
  Character: Char;
  Normalized: string;
begin
  Result := 0;
  if FileName = '' then
    Exit;
  try
    Normalized := UpperCase(TPath.GetFullPath(FileName));
  except
    Exit;
  end;
  Result := HASH_SEED;
  for Character in Normalized do
  begin
    // 乗算オーバーフローに依存せず、Debugの範囲検査中も同じ値を得る。
    Result := (Result shl 5) or (Result shr 59);
    Result := Result xor Ord(Character);
  end;
end;

function PublishPoseSnapshot(Layer: Integer;
  const Snapshot: TMmdPoseSharedSnapshot): Boolean;
begin
  Result := (Layer >= 0) and GetChannel(Layer).Publish(Snapshot);
end;

function TryReadPoseSnapshot(Layer, TimelineFrame: Integer;
  ModelPathHash: UInt64; out Snapshot: TMmdPoseSharedSnapshot): Boolean;
begin
  Result := (Layer >= 0) and (ModelPathHash <> 0) and
    GetChannel(Layer).TryRead(TimelineFrame, ModelPathHash, Snapshot);
end;

function GetTimelineFrame(const ObjectInfo: POBJECT_INFO): Integer;
begin
  if ObjectInfo = nil then
    Exit(Low(Integer));
  Result := ObjectInfo^.OriginFrame + ObjectInfo^.Frame;
end;

initialization
  ChannelLock := TObject.Create;
  Channels := TObjectDictionary<Integer, TMmdPoseSharedChannel>.Create([doOwnsValues]);

finalization
  Channels.Free;
  ChannelLock.Free;

end.
