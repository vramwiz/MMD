unit PmxPoseTypes;

// 姿勢計算ユニット間で共有するQuaternion、ローカル姿勢、グローバル変換型。

interface

uses
  PmxModel;

type
  TPmxQuaternion = record
    X, Y, Z, W: Single;
  end;
  TPmxBonePose = record
    Translation: TPmxVector3;
    Rotation: TPmxQuaternion;
  end;
  TPmxBoneTransform = record
    Position: TPmxVector3;
    Rotation: TPmxQuaternion;
  end;
  TPmxBonePoses = array of TPmxBonePose;
  TPmxBoneTransforms = array of TPmxBoneTransform;

implementation

end.
