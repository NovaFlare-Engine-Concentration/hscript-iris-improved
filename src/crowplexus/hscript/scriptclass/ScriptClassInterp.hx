package crowplexus.hscript.scriptclass;

import crowplexus.hscript.Interp;
import crowplexus.iris.Iris;
import crowplexus.hscript.proxy.ProxyType;
import crowplexus.hscript.ISharedScript;

@:access(crowplexus.hscript.Interp)
class ScriptClassInterp extends Interp {
	var scriptClass: ScriptClassInstance;

	public function new(scriptClass: ScriptClassInstance) {
		super();
		this.scriptClass = scriptClass;
		this.variables.set("this", scriptClass);
	}

	override function get(o: Dynamic, f: String): Dynamic {
		if (o == null)
			error(EInvalidAccess(f));
		if (o is IScriptedClass) {
			if (scriptClass.superExistsFunction(f)) {
				return Reflect.getProperty(o, crowplexus.iris.macro.ScriptedClassMacro.SUPER_FUNCTION_PREFIX + f);
			}
		}
		if (o is crowplexus.hscript.scriptclass.BaseScriptClass)
			return cast(o, crowplexus.hscript.scriptclass.BaseScriptClass).sc_get(f, #if hscriptPos curExpr, #end true);
		if (o is ISharedScript)
			return cast(o, ISharedScript).hget(f #if hscriptPos, this.curExpr #end);
		return {
			#if php
			// https://github.com/HaxeFoundation/haxe/issues/4915
			try {
				Reflect.getProperty(o, f);
			} catch (e:Dynamic) {
				Reflect.field(o, f);
			}
			#else
			Reflect.getProperty(o, f);
			#end
		}
	}

	override function setVar(name: String, v: Dynamic) {
		if (propertyLinks.get(name) != null) {
			var l = propertyLinks.get(name);
			if (l.inState)
				l.set(name, v);
			else
				l.link_setFunc(v);
			return;
		}

		if (directorFields.get(name) != null) {
			var l = directorFields.get(name);
			if (l.const) {
				warn(ECustom("Cannot reassign final, for constant expression -> " + name));
			} else if (l.type == "func") {
				warn(ECustom("Cannot reassign function, for constant expression -> " + name));
			} else if (l.isInline) {
				warn(ECustom("Variables marked as inline cannot be rewritten -> " + name));
			} else {
				l.value = v;
			}
		} else if (scriptClass.sc_exists(name)) {
			scriptClass.sc_set(name, v, #if hscriptPos curExpr #end);
		} else if (scriptClass.urDad.sc_exists(name)) {
			scriptClass.urDad.sc_set(name, v, #if hscriptPos curExpr #end);
		}
		/*if (directorFields.exists(name)) {
				directorFields.set(name, v);
			} else if (directorFields.exists('$name;const')) {
				warn(ECustom("Cannot reassign final, for constant expression -> " + name));
			} else if (staticVariables.exists(name)) {
				staticVariables.set(name, v);
			} else if (staticVariables.exists('$name;const')) {
				warn(ECustom("Cannot reassign final, for constant expression -> " + name));
		}*/
		else if (parentInstance != null) {
			if (_parentFields.contains(name) || _parentFields.contains('set_$name')) {
				Reflect.setProperty(parentInstance, name, v);
			}
		} else
			variables.set(name, v);
	}

	override function resolve(id: String): Dynamic {
		var l = locals.get(id);
		if (l != null)
			return l.r;

		if (propertyLinks.get(id) != null) {
			var l = propertyLinks.get(id);
			if (l.inState)
				return l.get(id);
			else
				return l.link_getFunc();
		}

		if (directorFields.get(id) != null)
			return directorFields.get(id).value;

		if (Interp.staticVariables.get(id) != null)
			return Interp.staticVariables.get(id).value;

		if (variables.exists(id)) {
			var v = variables.get(id);
			return v;
		}

		if (this.scriptClass.sc_exists(id)) {
			return this.scriptClass.sc_get(id, true);
		} else if (this.scriptClass.urDad.sc_exists(id)) {
			return this.scriptClass.urDad.sc_get(id, true);
		}

		if (parentInstance != null) {
			if (id == "this")
				return parentInstance;
			if (_parentFields.contains(id) || _parentFields.contains('get_$id')) {
				return Reflect.getProperty(parentInstance, id);
			}
		}

		if (imports.exists(id)) {
			var v = imports.get(id);
			return v;
		}

		if (Iris.proxyImports.get(id) != null)
			return Iris.proxyImports.get(id);

		if (Interp.unpackClassCache.get(id) != null) {
			return Interp.unpackClassCache.get(id);
		} else {
			final cl = ProxyType.resolveClass(id);
			if (cl != null) {
				Interp.unpackClassCache.set(id, cl);
				return cl;
			}
		}

		error(EUnknownVariable(id));

		return null;
	}

	override function super_call(args: Array<Dynamic>): Dynamic {
		if (scriptClass.needExtend()) {
			if (this.inFunction == "new") {
				if (scriptClass.superClass == null) {
					scriptClass.createSuperClassInstance(args);
				} else
					warn(ECustom("Cannot reuse to call 'super()'."));
			} else
				error(ECustom("Cannot call 'super()' outside of constructor"));
		} else
			error(ECustom("Current class does not have a super"));
		return null;
	}

	override function super_field_call(field: String, args: Array<Dynamic>): Dynamic {
		if (scriptClass.superClass != null) {
			if (scriptClass.superClass is IScriptedClass) {
				if (scriptClass.superExistsFunction(field)) {
					return call(null, Reflect.getProperty(scriptClass.superClass, crowplexus.iris.macro.ScriptedClassMacro.SUPER_FUNCTION_PREFIX + field),
						args);
				} else
					error(ECustom("Invalid Calling -> super." + field + "()"));
			} else {
				return call(null, get(scriptClass.superClass, field), args);
			}
		} else
			error(ECustom("Current class does not have a super"));
		return null;
	}
}
