unit PmxModel;

interface

type
  TPmxVector2 = record
    X, Y: Single;
  end;

  TPmxVector3 = record
    X, Y, Z: Single;
  end;

  TPmxVector4 = record
    X, Y, Z, W: Single;
  end;

  TPmxVertex = record
    Position: TPmxVector3;
    Normal: TPmxVector3;
    UV: TPmxVector2;
  end;

  TPmxMaterial = record
    Name: string;
    Diffuse: TPmxVector4;
    SpecularStrength: Single;
    Flags: Byte;
    TextureIndex: Integer;
    SurfaceStart: Integer;
    SurfaceCount: Integer;
  end;

  TPmxModel = class
  public
    SourcePath: string;
    Name: string;
    Vertices: TArray<TPmxVertex>;
    Indices: TArray<Integer>;
    Textures: TArray<string>;
    TextureAvailable: TArray<Boolean>;
    Materials: TArray<TPmxMaterial>;
  end;

implementation

end.
