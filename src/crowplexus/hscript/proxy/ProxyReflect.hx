package crowplexus.hscript.proxy;

import crowplexus.hscript.scriptclass.*;
import crowplexus.hscript.scriptenum.*;

/**
	The Reflect API is a way to manipulate values dynamically through an
	abstract interface in an untyped manner. Use with care.

	@see https://haxe.org/manual/std-reflection.html
**/
class ProxyReflect {
	/**
		Tells if structure `o` has a field named `field`.

		This is only guaranteed to work for anonymous structures. Refer to
		`Type.getInstanceFields` for a function supporting class instances.

		If `o` or `field` are null, the result is unspecified.
	**/
	public static inline function hasField(o: Dynamic, field: String): Bool {
		if (o is BaseScriptClass) {
			return cast(o, BaseScriptClass).getVars().contains(field);
		}
		@:privateAccess
		if (o is IScriptedClass) {
			return o.__sc_standClass.getVars().contains(field);
		}
		return Reflect.hasField(o, field);
	}

	/**
		Returns the value of the field named `field` on object `o`.

		If `o` is not an object or has no field named `field`, the result is
		null.

		If the field is defined as a property, its accessors are ignored. Refer
		to `Reflect.getProperty` for a function supporting property accessors.

		If `field` is null, the result is unspecified.
	**/
	public static inline function field(o: Dynamic, field: String): Dynamic {
		if (o is BaseScriptClass) {
			if (cast(o, BaseScriptClass).getVars().contains(field))
				return cast(o, BaseScriptClass).sc_get(field);
			return null;
		}
		@:privateAccess
		if (o is IScriptedClass) {
			if (o.__sc_standClass.getVars().contains(field))
				return o.__sc_standClass.sc_get(field);
			return null;
		}
		return Reflect.field(o, field);
	}

	/**
		Sets the field named `field` of object `o` to value `value`.

		If `o` has no field named `field`, this function is only guaranteed to
		work for anonymous structures.

		If `o` or `field` are null, the result is unspecified.
	**/
	public static inline function setField(o: Dynamic, field: String, value: Dynamic): Void {
		if (o is BaseScriptClass) {
			if (cast(o, BaseScriptClass).getVars().contains(field))
				cast(o, BaseScriptClass).sc_set(field, value);
			else
				throw "Invalid field";
		}
		@:privateAccess
		if (o is IScriptedClass) {
			if (o.__sc_standClass.getVars().contains(field))
				o.__sc_standClass.sc_set(field, value);
			else
				throw "Invalid field";
		}
		Reflect.setField(o, field, value);
	}

	/**
		Returns the value of the field named `field` on object `o`, taking
		property getter functions into account.

		If the field is not a property, this function behaves like
		`Reflect.field`, but might be slower.

		If `o` or `field` are null, the result is unspecified.
	**/
	public static inline function getProperty(o: Dynamic, field: String): Dynamic {
		if (o is BaseScriptClass) {
			return cast(o, BaseScriptClass).sc_get(field);
		}
		@:privateAccess
		if (o is IScriptedClass) {
			return o.__sc_standClass.sc_get(field);
		}
		@:privateAccess
		if (o is ScriptEnum) {
			return cast(o, ScriptEnum).sm.get(field);
		}
		return Reflect.getProperty(o, field);
	}

	/**
		Sets the field named `field` of object `o` to value `value`, taking
		property setter functions into account.

		If the field is not a property, this function behaves like
		`Reflect.setField`, but might be slower.

		If `field` is null, the result is unspecified.
	**/
	public static inline function setProperty(o: Dynamic, field: String, value: Dynamic): Void {
		if (o is BaseScriptClass) {
			cast(o, BaseScriptClass).sc_set(field, value);
			return;
		}
		@:privateAccess
		if (o is IScriptedClass) {
			o.__sc_standClass.sc_set(field, value);
			return;
		}
		Reflect.setProperty(o, field, value);
	}

	/**
		Call a method `func` with the given arguments `args`.

		The object `o` is ignored in most cases. It serves as the `this`-context in the following
		situations:

		* (neko) Allows switching the context to `o` in all cases.
		* (macro) Same as neko for Haxe 3. No context switching in Haxe 4.
		* (js, lua) Require the `o` argument if `func` does not, but should have a context.
			This can occur by accessing a function field natively, e.g. through `Reflect.field`
			or by using `(object : Dynamic).field`. However, if `func` has a context, `o` is
			ignored like on other targets.
	**/
	public static inline function callMethod(o: Dynamic, func: haxe.Constraints.Function, args: Array<Dynamic>): Dynamic {
		return Reflect.callMethod(o, func, args);
	}

	/**
		Returns the fields of structure `o`.

		This method is only guaranteed to work on anonymous structures. Refer to
		`Type.getInstanceFields` for a function supporting class instances.

		If `o` is null, the result is unspecified.
	**/
	public static inline function fields(o: Dynamic): Array<String> {
		if (o is BaseScriptClass) {
			cast(o, BaseScriptClass).getVars();
		}
		@:privateAccess
		if (o is IScriptedClass) {
			return o.__sc_standClass.getVars();
		}
		return Reflect.fields(o);
	}

	/**
		Returns true if `f` is a function, false otherwise.

		If `f` is null, the result is false.
	**/
	public static inline function isFunction(f: Dynamic): Bool {
		return Reflect.isFunction(f);
	}

	/**
		Compares `a` and `b`.

		If `a` is less than `b`, the result is negative. If `b` is less than
		`a`, the result is positive. If `a` and `b` are equal, the result is 0.

		This function is only defined if `a` and `b` are of the same type.

		If that type is a function, the result is unspecified and
		`Reflect.compareMethods` should be used instead.

		For all other types, the result is 0 if `a` and `b` are equal. If they
		are not equal, the result depends on the type and is negative if:

		- Numeric types: a is less than b
		- String: a is lexicographically less than b
		- Other: unspecified

		If `a` and `b` are null, the result is 0. If only one of them is null,
		the result is unspecified.
	**/
	public static inline function compare<T>(a: T, b: T): Int {
		return Reflect.compare(a, b);
	}

	/**
		Compares the functions `f1` and `f2`.

		If `f1` or `f2` are null, the result is false.
		If `f1` or `f2` are not functions, the result is unspecified.

		Otherwise the result is true if `f1` and the `f2` are physically equal,
		false otherwise.

		If `f1` or `f2` are member method closures, the result is true if they
		are closures of the same method on the same object value, false otherwise.
	**/
	public static inline function compareMethods(f1: Dynamic, f2: Dynamic): Bool {
		return Reflect.compareMethods(f1, f2);
	}

	/**
		Tells if `v` is an object.

		The result is true if `v` is one of the following:

		- class instance
		- structure
		- `Class<T>`
		- `Enum<T>`

		Otherwise, including if `v` is null, the result is false.
	**/
	public static inline function isObject(v: Dynamic): Bool {
		if (v is ScriptEnumValue)
			return false;
		return Reflect.isObject(v);
	}

	/**
		Tells if `v` is an enum value.

		The result is true if `v` is of type EnumValue, i.e. an enum
		constructor.

		Otherwise, including if `v` is null, the result is false.
	**/
	public static inline function isEnumValue(v: Dynamic): Bool {
		if (v is ScriptEnumValue)
			return true;
		return Reflect.isEnumValue(v);
	}

	/**
		Removes the field named `field` from structure `o`.

		This method is only guaranteed to work on anonymous structures.

		If `o` or `field` are null, the result is unspecified.
	**/
	public static inline function deleteField(o: Dynamic, field: String): Bool {
		return Reflect.deleteField(o, field);
	}

	/**
		Copies the fields of structure `o`.

		This is only guaranteed to work on anonymous structures.

		If `o` is null, the result is `null`.
	**/
	public static inline function copy<T>(o: Null<T>): Null<T> {
		return Reflect.copy(o);
	}

	/**
		Transform a function taking an array of arguments into a function that can
		be called with any number of arguments.
	**/
	public static inline function makeVarArgs(f: Array<Dynamic>->Dynamic): Dynamic {
		return Reflect.makeVarArgs(f);
	}
}
