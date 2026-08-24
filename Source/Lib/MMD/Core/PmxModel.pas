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

  TPmxIkLink = record
    BoneIndex: Integer;
    HasLimits: Boolean;
    LimitMin: TPmxVector3;
    LimitMax: TPmxVector3;
  end;
  TPmxIkLinks = array of TPmxIkLink;

  TPmxBone = record
    Name: string;
    Position: TPmxVector3;
    ParentIndex: Integer;
    DeformLayer: Integer;
    Flags: Word;
    InheritParentIndex: Integer;
    InheritWeight: Single;
    IkTargetIndex: Integer;
    IkLoopCount: Integer;
    IkAngleLimit: Single;
    IkLinks: TPmxIkLinks;
  end;

  TPmxMorphType = (
    pmtGroup,
    pmtVertex,
    pmtBone,
    pmtUV,
    pmtAdditionalUV1,
    pmtAdditionalUV2,
    pmtAdditionalUV3,
    pmtAdditionalUV4,
    pmtMaterial,
    pmtFlip,
    pmtImpulse
  );

  TPmxGroupMorphOffset = record
    MorphIndex: Integer;
    Weight: Single;
  end;

  TPmxVertexMorphOffset = record
    VertexIndex: Integer;
    Offset: TPmxVector3;
  end;

  TPmxBoneMorphOffset = record
    BoneIndex: Integer;
    Translation: TPmxVector3;
    Rotation: TPmxVector4;
  end;

  TPmxMorph = record
    Name: string;
    Panel: Byte;
    MorphType: TPmxMorphType;
    GroupOffsets: TArray<TPmxGroupMorphOffset>;
    VertexOffsets: TArray<TPmxVertexMorphOffset>;
    BoneOffsets: TArray<TPmxBoneMorphOffset>;
  end;

const
  PMX_BONE_FLAG_TAIL_IS_BONE = $0001;
  PMX_BONE_FLAG_IK = $0020;
  PMX_BONE_FLAG_LOCAL_APPEND = $0080;
  PMX_BONE_FLAG_INHERIT_ROTATION = $0100;
  PMX_BONE_FLAG_INHERIT_TRANSLATION = $0200;
  PMX_BONE_FLAG_FIXED_AXIS = $0400;
  PMX_BONE_FLAG_LOCAL_COORDINATE = $0800;
  PMX_BONE_FLAG_EXTERNAL_PARENT = $2000;

type
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
    Morphs: TArray<TPmxMorph>;
  end;

implementation

end.
