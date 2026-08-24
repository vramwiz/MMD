unit PmxModel;

// PMXの描画・姿勢計算で共有する、依存を持たないコアデータ型。

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

  TPmxVertexDeformType = (
    pdtBdef1,
    pdtBdef2,
    pdtBdef4,
    pdtSdef,
    pdtQdef
  );

  TPmxBoneIndices = array[0..3] of Integer;
  TPmxBoneWeights = array[0..3] of Single;

  TPmxVertex = record
    Position: TPmxVector3;
    Normal: TPmxVector3;
    UV: TPmxVector2;
    DeformType: TPmxVertexDeformType;
    BoneIndices: TPmxBoneIndices;
    BoneWeights: TPmxBoneWeights;
    SdefC: TPmxVector3;
    SdefR0: TPmxVector3;
    SdefR1: TPmxVector3;
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

  TPmxBone = record
    Name: string;
    Position: TPmxVector3;
    ParentIndex: Integer;
    Flags: Word;
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
    Bones: TArray<TPmxBone>;
  end;

implementation

end.
