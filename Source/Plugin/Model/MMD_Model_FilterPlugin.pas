unit MMD_Model_FilterPlugin;

// モデル表示Filterの登録と、未実装段階のパススルー処理を担当する。

interface

uses
  AviUtl2FilterTypes;

// AviUtl2へ登録するFilterテーブルを返し、設定項目配列を初回取得時に確定する。
function GetModelFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  PluginFilterTable;

var
  ModelFileItem: TFILTER_ITEM_FILE;
  PluginTableInitialized: Boolean;

function ModelProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  // モデル処理を実装するまでは入力画像を変更しない。
  Result := 1;
end;

function GetModelFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,
      'モデル表示', 'MMD', 'MMDモデルを表示するフィルター',
      ModelProcVideo, nil);
    AddFile(ModelFileItem, 'モデルファイル', '',
      'MMDモデル (*.pmx;*.pmd)'#0'*.pmx;*.pmd'#0 +
      'すべてのファイル (*.*)'#0'*.*'#0#0);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
