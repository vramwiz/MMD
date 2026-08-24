unit PmxBinaryStream;

// PMXバイト列の境界検査、基本型、可変長Index、文字列の読取りを担当する。

interface

uses
  System.SysUtils,
  PmxModel;

type
  EPmxFormatError = class(Exception);

  TPmxBinaryStream = class
  private
    FAdditionalUVCount: Byte;
    FBoneIndexSize: Byte;
    FData: TBytes;
    FEncoding: TEncoding;
    FOffset: Integer;
    FTextureIndexSize: Byte;
    FVertexIndexSize: Byte;
  public
    // ファイル全体を読取専用バイト列へ読み込み、先頭位置で初期化する。
    constructor Create(const FileName: string);
    // 残量を検証し、不足時は読取位置を変えずEPmxFormatErrorを送出する。
    procedure EnsureAvailable(ByteCount: Integer);
    // 指定バイト数だけ読取位置を進める。範囲外はEPmxFormatErrorとなる。
    procedure Skip(ByteCount: Integer);
    // 以下のRead系メソッドは値を返した後、そのバイト数だけ読取位置を進める。
    function ReadAnsi(ByteCount: Integer): AnsiString;
    function ReadByte: Byte;
    function ReadUInt16: Word;
    function ReadInt16: SmallInt;
    function ReadInt32: Integer;
    function ReadSingle: Single;
    function ReadText: string;
    function ReadSignedIndex(IndexSize: Byte): Integer;
    function ReadVertexIndex: Integer;
    function ReadVector2: TPmxVector2;
    function ReadVector3: TPmxVector3;
    function ReadVector4: TPmxVector4;
    // ヘッダーから確定した可変長フィールド情報。後続Reader間で同じStreamを引き継ぐ。
    property AdditionalUVCount: Byte read FAdditionalUVCount write FAdditionalUVCount;
    property BoneIndexSize: Byte read FBoneIndexSize write FBoneIndexSize;
    property Encoding: TEncoding read FEncoding write FEncoding;
    property TextureIndexSize: Byte read FTextureIndexSize write FTextureIndexSize;
    property VertexIndexSize: Byte read FVertexIndexSize write FVertexIndexSize;
end;

// 外部入力由来の個数を0以上Maximum以下に制限し、違反時はEPmxFormatErrorを送出する。
procedure CheckPmxCount(Value, Maximum: Integer; const FieldName: string);

implementation

uses
  System.IOUtils;

procedure CheckPmxCount(Value, Maximum: Integer; const FieldName: string);
begin
  if (Value < 0) or (Value > Maximum) then
    raise EPmxFormatError.CreateFmt('Invalid PMX %s: %d', [FieldName, Value]);
end;

constructor TPmxBinaryStream.Create(const FileName: string);
begin
  inherited Create;
  FData := TFile.ReadAllBytes(FileName);
end;

procedure TPmxBinaryStream.EnsureAvailable(ByteCount: Integer);
begin
  if (ByteCount < 0) or (FOffset > Length(FData) - ByteCount) then
    raise EPmxFormatError.CreateFmt('Unexpected end of PMX at byte %d', [FOffset]);
end;

procedure TPmxBinaryStream.Skip(ByteCount: Integer);
begin
  EnsureAvailable(ByteCount);
  Inc(FOffset, ByteCount);
end;

function TPmxBinaryStream.ReadAnsi(ByteCount: Integer): AnsiString;
begin
  EnsureAvailable(ByteCount);
  SetLength(Result, ByteCount);
  if ByteCount > 0 then
    Move(FData[FOffset], Result[1], ByteCount);
  Inc(FOffset, ByteCount);
end;

function TPmxBinaryStream.ReadByte: Byte;
begin
  EnsureAvailable(SizeOf(Result));
  Result := FData[FOffset];
  Inc(FOffset);
end;

function TPmxBinaryStream.ReadUInt16: Word;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryStream.ReadInt16: SmallInt;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryStream.ReadInt32: Integer;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryStream.ReadSingle: Single;
begin
  EnsureAvailable(SizeOf(Result));
  Move(FData[FOffset], Result, SizeOf(Result));
  Inc(FOffset, SizeOf(Result));
end;

function TPmxBinaryStream.ReadText: string;
var
  ByteCount: Integer;
begin
  ByteCount := ReadInt32;
  CheckPmxCount(ByteCount, Length(FData), 'text length');
  EnsureAvailable(ByteCount);
  Result := FEncoding.GetString(FData, FOffset, ByteCount);
  Inc(FOffset, ByteCount);
end;

function TPmxBinaryStream.ReadSignedIndex(IndexSize: Byte): Integer;
begin
  case IndexSize of
    1: Result := ShortInt(ReadByte);
    2: Result := ReadInt16;
    4: Result := ReadInt32;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX index size: %d', [IndexSize]);
  end;
end;

function TPmxBinaryStream.ReadVertexIndex: Integer;
begin
  case FVertexIndexSize of
    1: Result := ReadByte;
    2: Result := ReadUInt16;
    4: Result := ReadInt32;
  else
    raise EPmxFormatError.CreateFmt('Unsupported PMX vertex index size: %d',
      [FVertexIndexSize]);
  end;
end;

function TPmxBinaryStream.ReadVector2: TPmxVector2;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
end;

function TPmxBinaryStream.ReadVector3: TPmxVector3;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
  Result.Z := ReadSingle;
end;

function TPmxBinaryStream.ReadVector4: TPmxVector4;
begin
  Result.X := ReadSingle;
  Result.Y := ReadSingle;
  Result.Z := ReadSingle;
  Result.W := ReadSingle;
end;

end.
