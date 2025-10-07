package crowplexus.hscript.proxy;

import crowplexus.hscript.scriptenum.*;
import crowplexus.hscript.scriptclass.*;
import scripts.stages.modules.ScriptedModuleNotify;

// TODO: for most of these, support hscript enums
// which don't quite work, but here we are
class ProxyType {
	/**
		Returns the class of `o`, if `o` is a class instance.

		If `o` is null or of a different type, null is returned.

		In general, type parameter information cannot be obtained at runtime.
	**/
	public inline static function getClass(o: Dynamic): Null<Dynamic> {
		if (o is ScriptClassInstance) {
			@:privateAccess return cast(o, ScriptClassInstance).urDad;
		}
		@:privateAccess if (o is IScriptedClass) {
			return o.__sc_standClass.urDad;
		}
		return Type.getClass(o);
	}

	/**
		Returns the enum of enum instance `o`.

		An enum instance is the result of using an enum constructor. Given an
		`enum Color { Red; }`, `getEnum(Red)` returns `Enum<Color>`.

		If `o` is null, null is returned.

		In general, type parameter information cannot be obtained at runtime.
	**/
	public inline static function getEnum(o: Dynamic): Dynamic {
		@:privateAccess if (o is ScriptEnumValue) {
			return cast(o, ScriptEnumValue).parent;
		}
		return Type.getEnum(o);
	}

	/**
		Returns the super-class of class `c`.

		If `c` has no super class, null is returned.

		If `c` is null, the result is unspecified.

		In general, type parameter information cannot be obtained at runtime.
	**/
	public inline static function getSuperClass(c: Class<Dynamic>): Class<Dynamic> {
		return Type.getSuperClass(c);
	}

	/**
		Returns the name of class `c`, including its path.

		If `c` is inside a package, the package structure is returned dot-
		separated, with another dot separating the class name:
		`pack1.pack2.(...).packN.ClassName`
		If `c` is a sub-type of a Haxe module, that module is not part of the
		package structure.

		If `c` has no package, the class name is returned.

		If `c` is null, the result is unspecified.

		The class name does not include any type parameters.
	**/
	public inline static function getClassName(c: Dynamic): String {
		if (c is ScriptClass) {
			return cast(c, ScriptClass).fullPath;
		}
		return Type.getClassName(c);
	}

	/**
		Returns the name of enum `e`, including its path.

		If `e` is inside a package, the package structure is returned dot-
		separated, with another dot separating the enum name:
		`pack1.pack2.(...).packN.EnumName`
		If `e` is a sub-type of a Haxe module, that module is not part of the
		package structure.

		If `e` has no package, the enum name is returned.

		If `e` is null, the result is unspecified.

		The enum name does not include any type parameters.
	**/
	public inline static function getEnumName(e: Dynamic): String {
		if (e is ScriptEnum)
			return e.fullPath;
		return Type.getEnumName(e);
	}

	/**
		Resolves a class by name.

		If `name` is the path of an existing class, that class is returned.

		Otherwise null is returned.

		If `name` is null or the path to a different type, the result is
		unspecified.

		The class name must not include any type parameters.
	**/
	public inline static function resolveClass(name: String): Dynamic {
		@:privateAccess if(ScriptedModuleNotify.unpackUnusedClasses.exists(name)) {
			final c = ScriptedModuleNotify.unpackUnusedClasses.get(name);
			ScriptedModuleNotify.unpackUnusedClasses.remove(name);
			c.m.__interp.execute(c.e);
		}

		if (crowplexus.iris.Iris.proxyImports.get(name) != null) {
			return crowplexus.iris.Iris.proxyImports.get(name);
		}
		if (Interp.existsScriptClass(name)) {
			return Interp.resolveScriptClass(name);
		}
		return Type.resolveClass(name);
	}

	/**
		Resolves an enum by name.

		If `name` is the path of an existing enum, that enum is returned.

		Otherwise null is returned.

		If `name` is null the result is unspecified.

		If `name` is the path to a different type, null is returned.

		The enum name must not include any type parameters.
	**/
	public inline static function resolveEnum(name: String): Dynamic {
		if (Interp.existsScriptEnum(name)) {
			return Interp.resolveScriptEnum(name);
		}
		return Type.resolveEnum(name);
	}

	/**
		Creates an instance of class `cl`, using `args` as arguments to the
		class constructor.

		This function guarantees that the class constructor is called.

		Default values of constructors arguments are not guaranteed to be
		taken into account.

		If `cl` or `args` are null, or if the number of elements in `args` does
		not match the expected number of constructor arguments, or if any
		argument has an invalid type,  or if `cl` has no own constructor, the
		result is unspecified.

		In particular, default values of constructor arguments are not
		guaranteed to be taken into account.
	**/
	public inline static function createInstance(cl: Dynamic, args: Array<Dynamic>): Dynamic {
		if (cl is ScriptClass) {
			return cast(cl, ScriptClass).createInstance(args);
		}
		return Type.createInstance(cl, args);
	}

	/**
		Creates an instance of class `cl`.

		This function guarantees that the class constructor is not called.

		If `cl` is null, the result is unspecified.
	**/
	public inline static function createEmptyInstance(cl: Dynamic): Dynamic {
		if (cl is ScriptClass) {
			throw "Cannot Create Empty Instance For Script Class.";
		}
		return Type.createEmptyInstance(cl);
	}

	/**
		Creates an instance of enum `e` by calling its constructor `constr` with
		arguments `params`.

		If `e` or `constr` is null, or if enum `e` has no constructor named
		`constr`, or if the number of elements in `params` does not match the
		expected number of constructor arguments, or if any argument has an
		invalid type, the result is unspecified.
	**/
	public inline static function createEnum(e: Dynamic, constr: String, ?params: Array<Dynamic>): Dynamic {
		@:privateAccess if (e is ScriptEnum) {
			var byd: Dynamic = cast(e, ScriptEnum).sm.get(constr);
			if (Reflect.isFunction(byd))
				return Reflect.callMethod(null, byd, params ?? []);
			return byd;
		}
		return Type.createEnum(e, constr, params);
	}

	/**
		Creates an instance of enum `e` by calling its constructor number
		`index` with arguments `params`.

		The constructor indices are preserved from Haxe syntax, so the first
		declared is index 0, the next index 1 etc.

		If `e` or `constr` is null, or if enum `e` has no constructor named
		`constr`, or if the number of elements in `params` does not match the
		expected number of constructor arguments, or if any argument has an
		invalid type, the result is unspecified.
	**/
	public inline static function createEnumIndex(e: Dynamic, index: Int, ?params: Array<Dynamic>): Dynamic {
		@:privateAccess if (e is ScriptEnum) {
			if (index > 0) {
				var i: Int = -1;
				for (v in cast(e, ScriptEnum).sm) {
					if ((++i) == index) {
						var byd: Dynamic = v;
						if (Reflect.isFunction(byd))
							return Reflect.callMethod(null, v, params ?? []);
						return byd;
					}
				}
			}
		}
		return Type.createEnumIndex(e, index, params);
	}

	/**
		Returns a list of the instance fields of class `c`, including
		inherited fields.

		This only includes fields which are known at compile-time. In
		particular, using `getInstanceFields(getClass(obj))` will not include
		any fields which were added to `obj` at runtime.

		The order of the fields in the returned Array is unspecified.

		If `c` is null, the result is unspecified.
	**/
	public inline static function getInstanceFields(c: Dynamic): Array<String> {
		@:privateAccess if (c is ScriptClass) {
			return cast(c, ScriptClass).getFieldsWithOverride();
		}
		return Type.getInstanceFields(c);
	}

	/**
		Returns a list of static fields of class `c`.

		This does not include static fields of parent classes.

		The order of the fields in the returned Array is unspecified.

		If `c` is null, the result is unspecified.
	**/
	public inline static function getClassFields(c: Dynamic): Array<String> {
		@:privateAccess if (c is ScriptClass) {
			return cast(c, ScriptClass).getFields();
		}
		return Type.getClassFields(c);
	}

	/**
		Returns a list of the names of all constructors of enum `e`.

		The order of the constructor names in the returned Array is preserved
		from the original syntax.

		If `e` is null, the result is unspecified.
	**/
	public inline static function getEnumConstructs(e: Enum<Dynamic>): Array<String> {
		@:privateAccess if (e is ScriptEnum) {
			return [for (f in cast(e, ScriptEnum).sm.keys()) f];
		}
		return Type.getEnumConstructs(e);
	}

	/**
		Returns the runtime type of value `v`.

		The result corresponds to the type `v` has at runtime, which may vary
		per platform. Assumptions regarding this should be minimized to avoid
		surprises.
	**/
	public inline static function typeof(v: Dynamic): Type.ValueType {
		return Type.typeof(v);
	}

	/**
		Recursively compares two enum instances `a` and `b` by value.

		Unlike `a == b`, this function performs a deep equality check on the
		arguments of the constructors, if exists.

		If `a` or `b` are null, the result is unspecified.
	**/
	public inline static function enumEq(a: Dynamic, b: Dynamic): Bool {
		if (a is ScriptEnumValue && b is ScriptEnumValue)
			return cast(a, ScriptEnumValue).compare(cast(b, ScriptEnumValue));
		return Type.enumEq(a, b);
	}

	/**
		Returns the constructor name of enum instance `e`.

		The result String does not contain any constructor arguments.

		If `e` is null, the result is unspecified.
	**/
	public inline static function enumConstructor(e: Dynamic): String {
		if (e is ScriptEnumValue)
			return cast(e, ScriptEnumValue).name;
		return Type.enumConstructor(e);
	}

	/**
		Returns a list of the constructor arguments of enum instance `e`.

		If `e` has no arguments, the result is [].

		Otherwise the result are the values that were used as arguments to `e`,
		in the order of their declaration.

		If `e` is null, the result is unspecified.
	**/
	public inline static function enumParameters(e: Dynamic): Array<Dynamic> {
		if (e is ScriptEnumValue)
			return cast(e, ScriptEnumValue).getConstructorArgs();
		return Type.enumParameters(e);
	}

	/**
		Returns the index of enum instance `e`.

		This corresponds to the original syntactic position of `e`. The index of
		the first declared constructor is 0, the next one is 1 etc.

		If `e` is null, the result is unspecified.
	**/
	public inline static function enumIndex(e: Dynamic): Int {
		if (e is ScriptEnumValue)
			return cast(e, ScriptEnumValue).index;
		return Type.enumIndex(e);
	}

	/**
		Returns a list of all constructors of enum `e` that require no
		arguments.

		This may return the empty Array `[]` if all constructors of `e` require
		arguments.

		Otherwise an instance of `e` constructed through each of its non-
		argument constructors is returned, in the order of the constructor
		declaration.

		If `e` is null, the result is unspecified.
	**/
	public inline static function allEnums<T>(e: Enum<T>): Array<T> {
		// TODO: SUPPORT HSCRIPT ENUMS
		return Type.allEnums(e);
	}
}
