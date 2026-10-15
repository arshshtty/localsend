// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'diagnostics.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JoinResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JoinResult()';
}


}

/// @nodoc
class $JoinResultCopyWith<$Res>  {
$JoinResultCopyWith(JoinResult _, $Res Function(JoinResult) __);
}


/// Adds pattern-matching-related methods to [JoinResult].
extension JoinResultPatterns on JoinResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JoinResult_Ok value)?  ok,TResult Function( JoinResult_NotAttempted value)?  notAttempted,TResult Function( JoinResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JoinResult_Ok() when ok != null:
return ok(_that);case JoinResult_NotAttempted() when notAttempted != null:
return notAttempted(_that);case JoinResult_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JoinResult_Ok value)  ok,required TResult Function( JoinResult_NotAttempted value)  notAttempted,required TResult Function( JoinResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case JoinResult_Ok():
return ok(_that);case JoinResult_NotAttempted():
return notAttempted(_that);case JoinResult_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JoinResult_Ok value)?  ok,TResult? Function( JoinResult_NotAttempted value)?  notAttempted,TResult? Function( JoinResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case JoinResult_Ok() when ok != null:
return ok(_that);case JoinResult_NotAttempted() when notAttempted != null:
return notAttempted(_that);case JoinResult_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  ok,TResult Function()?  notAttempted,TResult Function( String field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JoinResult_Ok() when ok != null:
return ok();case JoinResult_NotAttempted() when notAttempted != null:
return notAttempted();case JoinResult_Failed() when failed != null:
return failed(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  ok,required TResult Function()  notAttempted,required TResult Function( String field0)  failed,}) {final _that = this;
switch (_that) {
case JoinResult_Ok():
return ok();case JoinResult_NotAttempted():
return notAttempted();case JoinResult_Failed():
return failed(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  ok,TResult? Function()?  notAttempted,TResult? Function( String field0)?  failed,}) {final _that = this;
switch (_that) {
case JoinResult_Ok() when ok != null:
return ok();case JoinResult_NotAttempted() when notAttempted != null:
return notAttempted();case JoinResult_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class JoinResult_Ok extends JoinResult {
  const JoinResult_Ok(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinResult_Ok);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JoinResult.ok()';
}


}




/// @nodoc


class JoinResult_NotAttempted extends JoinResult {
  const JoinResult_NotAttempted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinResult_NotAttempted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JoinResult.notAttempted()';
}


}




/// @nodoc


class JoinResult_Failed extends JoinResult {
  const JoinResult_Failed(this.field0): super._();
  

 final  String field0;

/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JoinResult_FailedCopyWith<JoinResult_Failed> get copyWith => _$JoinResult_FailedCopyWithImpl<JoinResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinResult_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'JoinResult.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $JoinResult_FailedCopyWith<$Res> implements $JoinResultCopyWith<$Res> {
  factory $JoinResult_FailedCopyWith(JoinResult_Failed value, $Res Function(JoinResult_Failed) _then) = _$JoinResult_FailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$JoinResult_FailedCopyWithImpl<$Res>
    implements $JoinResult_FailedCopyWith<$Res> {
  _$JoinResult_FailedCopyWithImpl(this._self, this._then);

  final JoinResult_Failed _self;
  final $Res Function(JoinResult_Failed) _then;

/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(JoinResult_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PortStatus {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PortStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PortStatus()';
}


}

/// @nodoc
class $PortStatusCopyWith<$Res>  {
$PortStatusCopyWith(PortStatus _, $Res Function(PortStatus) __);
}


/// Adds pattern-matching-related methods to [PortStatus].
extension PortStatusPatterns on PortStatus {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PortStatus_Free value)?  free,TResult Function( PortStatus_InUse value)?  inUse,TResult Function( PortStatus_Denied value)?  denied,TResult Function( PortStatus_HeldByThisApp value)?  heldByThisApp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PortStatus_Free() when free != null:
return free(_that);case PortStatus_InUse() when inUse != null:
return inUse(_that);case PortStatus_Denied() when denied != null:
return denied(_that);case PortStatus_HeldByThisApp() when heldByThisApp != null:
return heldByThisApp(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PortStatus_Free value)  free,required TResult Function( PortStatus_InUse value)  inUse,required TResult Function( PortStatus_Denied value)  denied,required TResult Function( PortStatus_HeldByThisApp value)  heldByThisApp,}){
final _that = this;
switch (_that) {
case PortStatus_Free():
return free(_that);case PortStatus_InUse():
return inUse(_that);case PortStatus_Denied():
return denied(_that);case PortStatus_HeldByThisApp():
return heldByThisApp(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PortStatus_Free value)?  free,TResult? Function( PortStatus_InUse value)?  inUse,TResult? Function( PortStatus_Denied value)?  denied,TResult? Function( PortStatus_HeldByThisApp value)?  heldByThisApp,}){
final _that = this;
switch (_that) {
case PortStatus_Free() when free != null:
return free(_that);case PortStatus_InUse() when inUse != null:
return inUse(_that);case PortStatus_Denied() when denied != null:
return denied(_that);case PortStatus_HeldByThisApp() when heldByThisApp != null:
return heldByThisApp(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  free,TResult Function( String? pidHint)?  inUse,TResult Function( String field0)?  denied,TResult Function()?  heldByThisApp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PortStatus_Free() when free != null:
return free();case PortStatus_InUse() when inUse != null:
return inUse(_that.pidHint);case PortStatus_Denied() when denied != null:
return denied(_that.field0);case PortStatus_HeldByThisApp() when heldByThisApp != null:
return heldByThisApp();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  free,required TResult Function( String? pidHint)  inUse,required TResult Function( String field0)  denied,required TResult Function()  heldByThisApp,}) {final _that = this;
switch (_that) {
case PortStatus_Free():
return free();case PortStatus_InUse():
return inUse(_that.pidHint);case PortStatus_Denied():
return denied(_that.field0);case PortStatus_HeldByThisApp():
return heldByThisApp();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  free,TResult? Function( String? pidHint)?  inUse,TResult? Function( String field0)?  denied,TResult? Function()?  heldByThisApp,}) {final _that = this;
switch (_that) {
case PortStatus_Free() when free != null:
return free();case PortStatus_InUse() when inUse != null:
return inUse(_that.pidHint);case PortStatus_Denied() when denied != null:
return denied(_that.field0);case PortStatus_HeldByThisApp() when heldByThisApp != null:
return heldByThisApp();case _:
  return null;

}
}

}

/// @nodoc


class PortStatus_Free extends PortStatus {
  const PortStatus_Free(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PortStatus_Free);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PortStatus.free()';
}


}




/// @nodoc


class PortStatus_InUse extends PortStatus {
  const PortStatus_InUse({this.pidHint}): super._();
  

 final  String? pidHint;

/// Create a copy of PortStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PortStatus_InUseCopyWith<PortStatus_InUse> get copyWith => _$PortStatus_InUseCopyWithImpl<PortStatus_InUse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PortStatus_InUse&&(identical(other.pidHint, pidHint) || other.pidHint == pidHint));
}


@override
int get hashCode => Object.hash(runtimeType,pidHint);

@override
String toString() {
  return 'PortStatus.inUse(pidHint: $pidHint)';
}


}

/// @nodoc
abstract mixin class $PortStatus_InUseCopyWith<$Res> implements $PortStatusCopyWith<$Res> {
  factory $PortStatus_InUseCopyWith(PortStatus_InUse value, $Res Function(PortStatus_InUse) _then) = _$PortStatus_InUseCopyWithImpl;
@useResult
$Res call({
 String? pidHint
});




}
/// @nodoc
class _$PortStatus_InUseCopyWithImpl<$Res>
    implements $PortStatus_InUseCopyWith<$Res> {
  _$PortStatus_InUseCopyWithImpl(this._self, this._then);

  final PortStatus_InUse _self;
  final $Res Function(PortStatus_InUse) _then;

/// Create a copy of PortStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pidHint = freezed,}) {
  return _then(PortStatus_InUse(
pidHint: freezed == pidHint ? _self.pidHint : pidHint // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class PortStatus_Denied extends PortStatus {
  const PortStatus_Denied(this.field0): super._();
  

 final  String field0;

/// Create a copy of PortStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PortStatus_DeniedCopyWith<PortStatus_Denied> get copyWith => _$PortStatus_DeniedCopyWithImpl<PortStatus_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PortStatus_Denied&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PortStatus.denied(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PortStatus_DeniedCopyWith<$Res> implements $PortStatusCopyWith<$Res> {
  factory $PortStatus_DeniedCopyWith(PortStatus_Denied value, $Res Function(PortStatus_Denied) _then) = _$PortStatus_DeniedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PortStatus_DeniedCopyWithImpl<$Res>
    implements $PortStatus_DeniedCopyWith<$Res> {
  _$PortStatus_DeniedCopyWithImpl(this._self, this._then);

  final PortStatus_Denied _self;
  final $Res Function(PortStatus_Denied) _then;

/// Create a copy of PortStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PortStatus_Denied(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PortStatus_HeldByThisApp extends PortStatus {
  const PortStatus_HeldByThisApp(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PortStatus_HeldByThisApp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PortStatus.heldByThisApp()';
}


}




/// @nodoc
mixin _$StartError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartError()';
}


}

/// @nodoc
class $StartErrorCopyWith<$Res>  {
$StartErrorCopyWith(StartError _, $Res Function(StartError) __);
}


/// Adds pattern-matching-related methods to [StartError].
extension StartErrorPatterns on StartError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartError_PortInUse value)?  portInUse,TResult Function( StartError_PermissionDenied value)?  permissionDenied,TResult Function( StartError_NoInterface value)?  noInterface,TResult Function( StartError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartError_PortInUse() when portInUse != null:
return portInUse(_that);case StartError_PermissionDenied() when permissionDenied != null:
return permissionDenied(_that);case StartError_NoInterface() when noInterface != null:
return noInterface(_that);case StartError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartError_PortInUse value)  portInUse,required TResult Function( StartError_PermissionDenied value)  permissionDenied,required TResult Function( StartError_NoInterface value)  noInterface,required TResult Function( StartError_Other value)  other,}){
final _that = this;
switch (_that) {
case StartError_PortInUse():
return portInUse(_that);case StartError_PermissionDenied():
return permissionDenied(_that);case StartError_NoInterface():
return noInterface(_that);case StartError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartError_PortInUse value)?  portInUse,TResult? Function( StartError_PermissionDenied value)?  permissionDenied,TResult? Function( StartError_NoInterface value)?  noInterface,TResult? Function( StartError_Other value)?  other,}){
final _that = this;
switch (_that) {
case StartError_PortInUse() when portInUse != null:
return portInUse(_that);case StartError_PermissionDenied() when permissionDenied != null:
return permissionDenied(_that);case StartError_NoInterface() when noInterface != null:
return noInterface(_that);case StartError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int port)?  portInUse,TResult Function()?  permissionDenied,TResult Function()?  noInterface,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartError_PortInUse() when portInUse != null:
return portInUse(_that.port);case StartError_PermissionDenied() when permissionDenied != null:
return permissionDenied();case StartError_NoInterface() when noInterface != null:
return noInterface();case StartError_Other() when other != null:
return other(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int port)  portInUse,required TResult Function()  permissionDenied,required TResult Function()  noInterface,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case StartError_PortInUse():
return portInUse(_that.port);case StartError_PermissionDenied():
return permissionDenied();case StartError_NoInterface():
return noInterface();case StartError_Other():
return other(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int port)?  portInUse,TResult? Function()?  permissionDenied,TResult? Function()?  noInterface,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case StartError_PortInUse() when portInUse != null:
return portInUse(_that.port);case StartError_PermissionDenied() when permissionDenied != null:
return permissionDenied();case StartError_NoInterface() when noInterface != null:
return noInterface();case StartError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class StartError_PortInUse extends StartError {
  const StartError_PortInUse({required this.port}): super._();
  

 final  int port;

/// Create a copy of StartError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartError_PortInUseCopyWith<StartError_PortInUse> get copyWith => _$StartError_PortInUseCopyWithImpl<StartError_PortInUse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartError_PortInUse&&(identical(other.port, port) || other.port == port));
}


@override
int get hashCode => Object.hash(runtimeType,port);

@override
String toString() {
  return 'StartError.portInUse(port: $port)';
}


}

/// @nodoc
abstract mixin class $StartError_PortInUseCopyWith<$Res> implements $StartErrorCopyWith<$Res> {
  factory $StartError_PortInUseCopyWith(StartError_PortInUse value, $Res Function(StartError_PortInUse) _then) = _$StartError_PortInUseCopyWithImpl;
@useResult
$Res call({
 int port
});




}
/// @nodoc
class _$StartError_PortInUseCopyWithImpl<$Res>
    implements $StartError_PortInUseCopyWith<$Res> {
  _$StartError_PortInUseCopyWithImpl(this._self, this._then);

  final StartError_PortInUse _self;
  final $Res Function(StartError_PortInUse) _then;

/// Create a copy of StartError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? port = null,}) {
  return _then(StartError_PortInUse(
port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class StartError_PermissionDenied extends StartError {
  const StartError_PermissionDenied(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartError_PermissionDenied);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartError.permissionDenied()';
}


}




/// @nodoc


class StartError_NoInterface extends StartError {
  const StartError_NoInterface(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartError_NoInterface);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartError.noInterface()';
}


}




/// @nodoc


class StartError_Other extends StartError {
  const StartError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of StartError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartError_OtherCopyWith<StartError_Other> get copyWith => _$StartError_OtherCopyWithImpl<StartError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'StartError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $StartError_OtherCopyWith<$Res> implements $StartErrorCopyWith<$Res> {
  factory $StartError_OtherCopyWith(StartError_Other value, $Res Function(StartError_Other) _then) = _$StartError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$StartError_OtherCopyWithImpl<$Res>
    implements $StartError_OtherCopyWith<$Res> {
  _$StartError_OtherCopyWithImpl(this._self, this._then);

  final StartError_Other _self;
  final $Res Function(StartError_Other) _then;

/// Create a copy of StartError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(StartError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
