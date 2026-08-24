unit PmxPoseMath;

// 付与変形、IK、スキニングで共有するベクトル・Quaternion演算を提供する。

interface

uses
  PmxModel,
  PmxPoseTypes;

function AddVector(const A, B: TPmxVector3): TPmxVector3;
function SubtractVector(const A, B: TPmxVector3): TPmxVector3;
function ScaleVector(const Value: TPmxVector3; Scale: Single): TPmxVector3;
function DotVector(const A, B: TPmxVector3): Single;
function CrossVector(const A, B: TPmxVector3): TPmxVector3;
function NormalizeVector(const Value: TPmxVector3): TPmxVector3;
function IdentityQuaternion: TPmxQuaternion;
function NormalizeQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
function MultiplyQuaternion(const A, B: TPmxQuaternion): TPmxQuaternion;
function InverseQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
function RotateVector(const Rotation: TPmxQuaternion;
  const Value: TPmxVector3): TPmxVector3;
function QuaternionFromAxisAngle(const Axis: TPmxVector3;
  AngleRadians: Single): TPmxQuaternion;
function QuaternionFromEulerXYZ(X, Y, Z: Single): TPmxQuaternion;
function QuaternionToEulerXYZ(const Value: TPmxQuaternion): TPmxVector3;
function ScaleQuaternionRotation(const Value: TPmxQuaternion;
  Scale: Single): TPmxQuaternion;

implementation

uses
  System.Math;

function AddVector(const A, B: TPmxVector3): TPmxVector3;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
  Result.Z := A.Z + B.Z;
end;

function SubtractVector(const A, B: TPmxVector3): TPmxVector3;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function ScaleVector(const Value: TPmxVector3; Scale: Single): TPmxVector3;
begin
  Result.X := Value.X * Scale;
  Result.Y := Value.Y * Scale;
  Result.Z := Value.Z * Scale;
end;

function DotVector(const A, B: TPmxVector3): Single;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function CrossVector(const A, B: TPmxVector3): TPmxVector3;
begin
  Result.X := A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.Z * B.X - A.X * B.Z;
  Result.Z := A.X * B.Y - A.Y * B.X;
end;

function NormalizeVector(const Value: TPmxVector3): TPmxVector3;
var
  Length_: Single;
begin
  Length_ := Sqrt(DotVector(Value, Value));
  if Length_ <= 0.000001 then
    Result := Default(TPmxVector3)
  else
    Result := ScaleVector(Value, 1.0 / Length_);
end;

function IdentityQuaternion: TPmxQuaternion;
begin
  Result := Default(TPmxQuaternion);
  Result.W := 1.0;
end;

function NormalizeQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
var
  Length_: Single;
begin
  Length_ := Sqrt(Value.X * Value.X + Value.Y * Value.Y +
    Value.Z * Value.Z + Value.W * Value.W);
  if Length_ <= 0.000001 then
    Result := IdentityQuaternion
  else
  begin
    Result.X := Value.X / Length_;
    Result.Y := Value.Y / Length_;
    Result.Z := Value.Z / Length_;
    Result.W := Value.W / Length_;
  end;
end;

function MultiplyQuaternion(const A, B: TPmxQuaternion): TPmxQuaternion;
begin
  Result.X := A.W * B.X + A.X * B.W + A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.W * B.Y - A.X * B.Z + A.Y * B.W + A.Z * B.X;
  Result.Z := A.W * B.Z + A.X * B.Y - A.Y * B.X + A.Z * B.W;
  Result.W := A.W * B.W - A.X * B.X - A.Y * B.Y - A.Z * B.Z;
end;

function InverseQuaternion(const Value: TPmxQuaternion): TPmxQuaternion;
begin
  Result := NormalizeQuaternion(Value);
  Result.X := -Result.X;
  Result.Y := -Result.Y;
  Result.Z := -Result.Z;
end;

function RotateVector(const Rotation: TPmxQuaternion;
  const Value: TPmxVector3): TPmxVector3;
var
  Cross1, Cross2: TPmxVector3;
  RotationVector: TPmxVector3;
begin
  RotationVector.X := Rotation.X;
  RotationVector.Y := Rotation.Y;
  RotationVector.Z := Rotation.Z;
  Cross1 := CrossVector(RotationVector, Value);
  Cross2 := CrossVector(RotationVector, Cross1);
  Result := AddVector(Value, ScaleVector(AddVector(
    ScaleVector(Cross1, Rotation.W), Cross2), 2.0));
end;

function QuaternionFromAxisAngle(const Axis: TPmxVector3;
  AngleRadians: Single): TPmxQuaternion;
var
  HalfAngle, SinHalfAngle: Single;
  NormalizedAxis: TPmxVector3;
begin
  NormalizedAxis := NormalizeVector(Axis);
  if DotVector(NormalizedAxis, NormalizedAxis) <= 0.000001 then
    Exit(IdentityQuaternion);
  HalfAngle := AngleRadians * 0.5;
  SinHalfAngle := Sin(HalfAngle);
  Result.X := NormalizedAxis.X * SinHalfAngle;
  Result.Y := NormalizedAxis.Y * SinHalfAngle;
  Result.Z := NormalizedAxis.Z * SinHalfAngle;
  Result.W := Cos(HalfAngle);
end;

function QuaternionFromEulerXYZ(X, Y, Z: Single): TPmxQuaternion;
var
  Axis: TPmxVector3;
  RotationX, RotationY, RotationZ: TPmxQuaternion;
begin
  Axis := Default(TPmxVector3);
  Axis.X := 1;
  RotationX := QuaternionFromAxisAngle(Axis, X);
  Axis.X := 0;
  Axis.Y := 1;
  RotationY := QuaternionFromAxisAngle(Axis, Y);
  Axis.Y := 0;
  Axis.Z := 1;
  RotationZ := QuaternionFromAxisAngle(Axis, Z);
  Result := NormalizeQuaternion(MultiplyQuaternion(RotationZ,
    MultiplyQuaternion(RotationY, RotationX)));
end;

function QuaternionToEulerXYZ(const Value: TPmxQuaternion): TPmxVector3;
var
  Q: TPmxQuaternion;
  SinPitch: Single;
begin
  Q := NormalizeQuaternion(Value);
  Result.X := ArcTan2(2 * (Q.W * Q.X + Q.Y * Q.Z),
    1 - 2 * (Q.X * Q.X + Q.Y * Q.Y));
  SinPitch := EnsureRange(2 * (Q.W * Q.Y - Q.Z * Q.X), -1.0, 1.0);
  Result.Y := ArcSin(SinPitch);
  Result.Z := ArcTan2(2 * (Q.W * Q.Z + Q.X * Q.Y),
    1 - 2 * (Q.Y * Q.Y + Q.Z * Q.Z));
end;

function ScaleQuaternionRotation(const Value: TPmxQuaternion;
  Scale: Single): TPmxQuaternion;
var
  Angle, SinHalf: Single;
  Axis: TPmxVector3;
  Q: TPmxQuaternion;
begin
  Q := NormalizeQuaternion(Value);
  if Q.W < 0 then
  begin
    Q.X := -Q.X;
    Q.Y := -Q.Y;
    Q.Z := -Q.Z;
    Q.W := -Q.W;
  end;
  Angle := 2 * ArcCos(EnsureRange(Q.W, -1.0, 1.0));
  SinHalf := Sqrt(Max(1 - Q.W * Q.W, 0.0));
  if SinHalf <= 0.000001 then
    Exit(IdentityQuaternion);
  Axis.X := Q.X / SinHalf;
  Axis.Y := Q.Y / SinHalf;
  Axis.Z := Q.Z / SinHalf;
  Result := QuaternionFromAxisAngle(Axis, Angle * Scale);
end;

end.
