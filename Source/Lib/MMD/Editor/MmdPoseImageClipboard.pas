unit MmdPoseImageClipboard;

// 参照画像機能のクリップボード境界。D3D RendererはClipboardへ依存させない。

interface

uses
  Vcl.Graphics,
  MmdD3DViewportSurface;

// 現在のViewportを骨格なしで取得し、Windows ClipboardへBitmapとして格納する。
function CopyModelImageToClipboard(
  Viewport: TMmdD3DViewportSurface): Boolean;
// Clipboard内のBitmap/DIBを、呼び出し側が所有するBitmapへコピーする。
function PasteImageFromClipboard(Bitmap: Vcl.Graphics.TBitmap): Boolean;

implementation

uses
  Winapi.Windows,
  Vcl.Clipbrd;

function CopyModelImageToClipboard(
  Viewport: TMmdD3DViewportSurface): Boolean;
var
  Bitmap: Vcl.Graphics.TBitmap;
begin
  Result := False;
  if Viewport = nil then
    Exit;
  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    if not Viewport.CaptureModelImage(Bitmap) then
      Exit;
    Clipboard.Assign(Bitmap);
    Result := True;
  finally
    Bitmap.Free;
  end;
end;

function PasteImageFromClipboard(Bitmap: Vcl.Graphics.TBitmap): Boolean;
begin
  Result := False;
  if (Bitmap = nil) or not (Clipboard.HasFormat(CF_BITMAP) or
    Clipboard.HasFormat(CF_DIB) or Clipboard.HasFormat(CF_DIBV5)) then
    Exit;
  Bitmap.Assign(Clipboard);
  Result := (Bitmap.Width > 0) and (Bitmap.Height > 0);
end;

end.
