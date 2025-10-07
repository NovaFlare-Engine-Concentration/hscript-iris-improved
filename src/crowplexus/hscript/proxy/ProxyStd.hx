package crowplexus.hscript.proxy;

import crowplexus.hscript.scriptclass.*;
import crowplexus.hscript.scriptenum.*;

/**
	The Std class provides standard methods for manipulating basic types.
**/
class ProxyStd {
	#if !haxe4
	/**
		DEPRECATED. Use `Std.isOfType(v, t)` instead.

		Tells if a value `v` is of the type `t`. Returns `false` if `v` or `t` are null.

		If `t` is a class or interface with `@:generic` meta, the result is `false`.
	**/
	public static function is(v: Dynamic, t: Dynamic): Bool {
		if (v is ScriptClass)
			return (t == Class);
		if (v is ScriptEnum)
			return (t == Enum);
		@:privateAccess if (v is ScriptClassInstance) {
			if (t is ScriptClass) {
				return cast(t, ScriptClass) == cast(v, ScriptClassInstance).urDad;
			}
		}
		@:privateAccess
		if (v is IScriptedClass) {
			if (t is ScriptClass) {
				return v.__sc_standClass.urDad == cast(t, ScriptClass);
			}
		}
		@:privateAccess
		if (v is ScriptEnumValue) {
			if (t is ScriptEnum) {
				return cast(v, ScriptEnumValue).parent == cast(t, ScriptEnum);
			}
		}

		return Std.is(v, t);
	}
	#end

	/**
		Tells if a value `v` is of the type `t`. Returns `false` if `v` or `t` are null.

		If `t` is a class or interface with `@:generic` meta, the result is `false`.
	**/
	public static function isOfType(v: Dynamic, t: Dynamic): Bool {
		if (v is ScriptClass)
			return (t == Class);
		if (v is ScriptEnum)
			return (t == Enum);
		@:privateAccess if (v is ScriptClassInstance) {
			if (t is ScriptClass) {
				return cast(t, ScriptClass) == cast(v, ScriptClassInstance).urDad;
			}
		}
		@:privateAccess
		if (v is IScriptedClass) {
			if (t is ScriptClass) {
				return v.__sc_standClass.urDad == cast(t, ScriptClass);
			}
		}
		@:privateAccess
		if (v is ScriptEnumValue) {
			if (t is ScriptEnum) {
				return cast(v, ScriptEnumValue).parent == cast(t, ScriptEnum);
			}
		}

		return Std.isOfType(v, t);
	}

	/**
		Checks if object `value` is an instance of class or interface `c`.

		Compiles only if the type specified by `c` can be assigned to the type
		of `value`.

		This method checks if a downcast is possible. That is, if the runtime
		type of `value` is assignable to the type specified by `c`, `value` is
		returned. Otherwise null is returned.

		This method is not guaranteed to work with core types such as `String`,
		`Array` and `Date`.

		If `value` is null, the result is null. If `c` is null, the result is
		unspecified.
	**/
	public static function downcast<T: {}, S: T>(value: T, c: Class<S>): S {
		return Std.downcast(value, c);
	}

	#if !haxe4
	public static function instance<T: {}, S: T>(value: T, c: Class<S>): S {
		return Std.instance(value, c);
	}
	#end

	/**
		Converts any value to a String.

		If `s` is of `String`, `Int`, `Float` or `Bool`, its value is returned.

		If `s` is an instance of a class and that class or one of its parent classes has
		a `toString` method, that method is called. If no such method is present, the result
		is unspecified.

		If `s` is an enum constructor without argument, the constructor's name is returned. If
		arguments exists, the constructor's name followed by the String representations of
		the arguments is returned.

		If `s` is a structure, the field names along with their values are returned. The field order
		and the operator separating field names and values are unspecified.

		If s is null, "null" is returned.
	**/
	public static function string(s: Dynamic): String {
		return Std.string(s);
	}

	/**
		Converts a `Float` to an `Int`, rounded towards 0.

		If `x` is outside of the signed Int32 range, or is `NaN`, `NEGATIVE_INFINITY` or `POSITIVE_INFINITY`, the result is unspecified.
	**/
	public static function int(x: Float): Int {
		return Std.int(x);
	}

	/**
		Converts a `String` to an `Int`.

		Leading whitespaces are ignored.

		If `x` starts with 0x or 0X, hexadecimal notation is recognized where the following digits may
		contain 0-9 and A-F.

		Otherwise `x` is read as decimal number with 0-9 being allowed characters. `x` may also start with
		a - to denote a negative value.

		In decimal mode, parsing continues until an invalid character is detected, in which case the
		result up to that point is returned. For hexadecimal notation, the effect of invalid characters
		is unspecified.

		Leading 0s that are not part of the 0x/0X hexadecimal notation are ignored, which means octal
		notation is not supported.

		If `x` is null, the result is unspecified.
		If `x` cannot be parsed as integer, the result is `null`.
	**/
	public static function parseInt(x: String): Null<Int> {
		return Std.parseInt(x);
	}

	/**
		Converts a `String` to a `Float`.

		The parsing rules for `parseInt` apply here as well, with the exception of invalid input
		resulting in a `NaN` value instead of null.

		Additionally, decimal notation may contain a single `.` to denote the start of the fractions.
	**/
	public static function parseFloat(x: String): Float {
		return Std.parseFloat(x);
	}

	/**
		Return a random integer between 0 included and `x` excluded.

		If `x <= 1`, the result is always 0.
	**/
	public static function random(x: Int): Int {
		return Std.random(x);
	}
}
