unit MMD_Model_FilterPlugin;

// モデル表示Filterの登録と、draw_polyによる3D描画経路の検証を担当する。

interface

uses
  AviUtl2FilterTypes;

// AviUtl2へ登録するFilterテーブルを返し、設定項目配列を初回取得時に確定する。
function GetModelFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Math,
  PluginFilterTable;

var
  ModelFileItem: TFILTER_ITEM_FILE;
  PluginTableInitialized: Boolean;

type
  TTestCubeVertices = array[0..23] of TVERTEX_COLOR;

const
  WHITE_PIXEL: TPIXEL_RGBA = (R: 255; G: 255; B: 255; A: 255);
  TEST_CUBE: TTestCubeVertices = (
    // 手前面: 赤
    (X: -150; Y: -150; Z: -150; R: 1; G: 0; B: 0; A: 1),
    (X:  150; Y: -150; Z: -150; R: 1; G: 0; B: 0; A: 1),
    (X:  150; Y:  150; Z: -150; R: 1; G: 0; B: 0; A: 1),
    (X: -150; Y:  150; Z: -150; R: 1; G: 0; B: 0; A: 1),
    // 奥面: 緑
    (X:  150; Y: -150; Z:  150; R: 0; G: 1; B: 0; A: 1),
    (X: -150; Y: -150; Z:  150; R: 0; G: 1; B: 0; A: 1),
    (X: -150; Y:  150; Z:  150; R: 0; G: 1; B: 0; A: 1),
    (X:  150; Y:  150; Z:  150; R: 0; G: 1; B: 0; A: 1),
    // 左面: 青
    (X: -150; Y: -150; Z:  150; R: 0; G: 0; B: 1; A: 1),
    (X: -150; Y: -150; Z: -150; R: 0; G: 0; B: 1; A: 1),
    (X: -150; Y:  150; Z: -150; R: 0; G: 0; B: 1; A: 1),
    (X: -150; Y:  150; Z:  150; R: 0; G: 0; B: 1; A: 1),
    // 右面: 黄
    (X: 150; Y: -150; Z: -150; R: 1; G: 1; B: 0; A: 1),
    (X: 150; Y: -150; Z:  150; R: 1; G: 1; B: 0; A: 1),
    (X: 150; Y:  150; Z:  150; R: 1; G: 1; B: 0; A: 1),
    (X: 150; Y:  150; Z: -150; R: 1; G: 1; B: 0; A: 1),
    // 上面: マゼンタ
    (X: -150; Y: -150; Z:  150; R: 1; G: 0; B: 1; A: 1),
    (X:  150; Y: -150; Z:  150; R: 1; G: 0; B: 1; A: 1),
    (X:  150; Y: -150; Z: -150; R: 1; G: 0; B: 1; A: 1),
    (X: -150; Y: -150; Z: -150; R: 1; G: 0; B: 1; A: 1),
    // 下面: シアン
    (X: -150; Y: 150; Z: -150; R: 0; G: 1; B: 1; A: 1),
    (X:  150; Y: 150; Z: -150; R: 0; G: 1; B: 1; A: 1),
    (X:  150; Y: 150; Z:  150; R: 0; G: 1; B: 1; A: 1),
    (X: -150; Y: 150; Z:  150; R: 0; G: 1; B: 1; A: 1)
  );

procedure BuildRotatedTestCube(out Vertices: TTestCubeVertices);
var
  CosX: Single;
  CosY: Single;
  I: Integer;
  SinX: Single;
  SinY: Single;
  X1: Single;
  Z1: Single;
begin
  CosX := Cos(DegToRad(25.0));
  SinX := Sin(DegToRad(25.0));
  CosY := Cos(DegToRad(-35.0));
  SinY := Sin(DegToRad(-35.0));
  for I := 0 to High(Vertices) do
  begin
    Vertices[I] := TEST_CUBE[I];
    X1 := CosY * TEST_CUBE[I].X + SinY * TEST_CUBE[I].Z;
    Z1 := -SinY * TEST_CUBE[I].X + CosY * TEST_CUBE[I].Z;
    Vertices[I].X := X1;
    Vertices[I].Y := CosX * TEST_CUBE[I].Y - SinX * Z1;
    Vertices[I].Z := SinX * TEST_CUBE[I].Y + CosX * Z1;
  end;
end;

function ModelProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Vertices: TTestCubeVertices;
begin
  Result := 1;
  try
    if (Video = nil) or not Assigned(Video^.SetImageData) or
      not Assigned(Video^.DrawPoly) then
      Exit;
    // v2.1.6aは頂点カラーでもnilの画像リソースを拒否するため、
    // 1x1の白画像を現在オブジェクトへ用意してdraw_polyへ渡す。
    Video^.SetImageData(@WHITE_PIXEL, 1, 1);
    if Assigned(Video^.SetCullingState) then
      Video^.SetCullingState(0);
    BuildRotatedTestCube(Vertices);
    Video^.DrawPoly(VERTEX_TYPE_QUAD_COLOR, @Vertices[0],
      Length(Vertices), 'object');
    if Assigned(Video^.SetDefaultAnchor) then
      Video^.SetDefaultAnchor(400, 300);
    // フレームバッファへ直接描画した後は、空のオブジェクト画像を描く後続処理を中断する。
    Result := 0;
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
end;

function GetModelFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT,
      'モデル表示', 'MMD', 'MMDモデルの3D表示を検証するフィルター',
      ModelProcVideo, nil);
    AddFile(ModelFileItem, 'モデルファイル', '',
      'MMDモデル (*.pmx;*.pmd)'#0'*.pmx;*.pmd'#0 +
      'すべてのファイル (*.*)'#0'*.*'#0#0);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
