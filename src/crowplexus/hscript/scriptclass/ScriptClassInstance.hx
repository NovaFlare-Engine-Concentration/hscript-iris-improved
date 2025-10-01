package crowplexus.hscript.scriptclass;

import crowplexus.hscript.Interp;
import crowplexus.hscript.Expr;
import crowplexus.iris.Iris;

@:allow(crowplexus.hscript.scriptclass.ScriptClassInterp)
@:access(crowplexus.hscript.scriptclass.ScriptClass)
class ScriptClassInstance extends BaseScriptClass {
	public var name: String;
	public var extend: String;
	public var superClass: Dynamic;

	private var constructorArgs: Array<Dynamic>;
	var __ogInterp: Interp;
	var __interp: Interp;
	var fields: Array<BydFieldDecl>;
	var overrides: Array<String> = [];
	var constructor: BydFieldDecl;
	var urDad: ScriptClass;

	private function new(ogInterp: Interp, name: String, extend: String, fields: Array<BydFieldDecl>, constructor: BydFieldDecl, parent: ScriptClass,
			?constructorArgs: Array<Dynamic>) {
		this.name = name;
		this.extend = extend;
		this.fields = fields;
		this.constructor = constructor;
		this.urDad = parent;
		this.constructorArgs = constructorArgs;
		__ogInterp = ogInterp;

		__interp = new ScriptClassInterp(this);
		syncParent(__interp);
		resolveSuperClass();
		parseConstructor();
		parseInstanceField();
		callConstructor();
	}

	public inline function superExistsFunction(f: String): Bool {
		return cacheSuperFieldsName.contains(crowplexus.iris.macro.ScriptedClassMacro.SUPER_FUNCTION_PREFIX + f);
	}

	public override function sc_exists(name: String): Bool {
		@:privateAccess return (superClass != null
			&& (cacheSuperFieldsName.contains(name) || cacheSuperFieldsName.contains("get_" + name)))
			|| __interp.propertyLinks.get(name) != null
			|| __interp.directorFields.get(name) != null
			|| __interp.variables.exists(name);
	}

	public override function sc_get(name: String, ?e:Expr, inClass:Bool = false): Dynamic {
		@:privateAccess {
			if (superClass != null) {
				if (!overrides.contains(name) && (cacheSuperFieldsName.contains(name) || cacheSuperFieldsName.contains("get_" + name))) {
					return Reflect.getProperty(this.superClass, name);
				}
			}

			if (__interp.propertyLinks.get(name) != null) {
				var l = __interp.propertyLinks.get(name);
				if (l.inState)
					return l.get(name);
				else
					return l.link_getFunc();
			}

			if (__interp.directorFields.get(name) != null)
				return __interp.directorFields.get(name).value;

			if (__interp.variables.exists(name)) {
				var v = __interp.variables.get(name);
				return v;
			}

			if(e != null) {
				if(!inClass) forceError(EUnknownVariable(name), e);
				else forceError(ECustom("ScriptClass<" + this.urDad.fullPath + "> has no field -> '" + name + "'"), e);
			}
			return null;
		}
	}

	public override function sc_set(name: String, value: Dynamic, ?e:Expr) {
		@:privateAccess {
			if (superClass != null) {
				if (!overrides.contains(name) && (cacheSuperFieldsName.contains(name) || cacheSuperFieldsName.contains("set_" + name))) {
					Reflect.setProperty(this.superClass, name, value);
					return;
				}
			}

			if (__interp.propertyLinks.get(name) != null) {
				var l = __interp.propertyLinks.get(name);
				if (l.inState)
					l.set(name, value);
				else
					l.link_setFunc(value);
				return;
			}

			if (__interp.directorFields.get(name) != null) {
				var l = __interp.directorFields.get(name);
				if (l.const) {
					if(e != null) forceWarn(ECustom("Cannot reassign final, for constant expression -> " + name), e);
				} else if (l.type == "func") {
					if(e != null) forceWarn(ECustom("Cannot reassign function, for constant expression -> " + name), e);
				} else if (l.isInline) {
					if(e != null) forceWarn(ECustom("Variables marked as inline cannot be rewritten -> " + name), e);
				} else {
					l.value = value;
				}
			} else
				__interp.variables.set(name, value);
		}
	}

	public override function sc_call(name: String, ?args: Array<Dynamic>): Dynamic {
		if (superClass != null && overrides.contains(name)) {
			var l = __interp.directorFields.get(name);
			if (l != null && l.type == "func") {
				return Reflect.callMethod(null, l.value, args ?? []);
			}
		}

		if (Reflect.isFunction(sc_get(name)))
			return Reflect.callMethod(null, sc_get(name), args ?? []);
		return null;
	}

	public inline override function getFields(): Array<String> {
		return [for (f in this.fields) f.name];
	}

	public inline override function getVars(): Array<String> {
		return [for (f in this.fields) if (f.kind.match(KVar(_))) f.name];
	}

	public inline override function getFunctions(): Array<String> {
		return [for (f in this.fields) if (f.kind.match(KFunction(_))) f.name];
	}

	private function callConstructor() {
		@:privateAccess
		if (sc_exists("new")) {
			this.sc_call("new", this.constructorArgs);
			if (needExtend()) {
				if (this.superClass == null)
					throw "Missing 'super()' Called";
			}
		} else if (needExtend()) {
			createSuperClassInstance(this.constructorArgs);
		}
	}

	private function resolveSuperClass() {
		cacheSuperClassField();
		@:privateAccess
		if (needExtend()) {
			for (field in fields) {
				if (field != null && field.access.contains(AOverride)) {
					if (!cacheSuperFieldsName.contains(field.name))
						forceError(ECustom("Cannot not override this field as Script Class '" + name + "' Super Class has not the field -> '"
							+ field.name + "'"));
					if (field.kind.match(KFunction(_))) {
						this.overrides.push(field.name);
					} else
						forceError(ECustom("Unexpected this field '" + field.name + "' as 'override' only applies to function"));
				}
			}
		} else if (extend != null && urDad.superClassDecl == null) {
			forceError(ECustom("Invalid Extended Class -> '" + extend + "'"));
		}
	}

	private var cacheSuperFieldsName: Array<String> = [];

	inline function cacheSuperClassField() {
		if (needExtend()) {
			cacheSuperFieldsName = Type.getInstanceFields(urDad.superClassDecl);
		}
	}

	private inline function needExtend(): Bool {
		return urDad.superClassDecl != null;
	}

	function parseInstanceField() {
		for (field in this.fields) {
			@:privateAccess
			if (field != null)
				switch (field.kind) {
					case KVar(decl):
						__interp.directorFields.set(field.name, {
							value: parseValDecl(decl),
							type: "var",
							const: decl.isConst,
							isInline: field.access.contains(AInline)
						});
						if ((decl.get != null && decl.get != "default") || (decl.set != null && decl.set != "default")) {
							if (decl.get == "get"
								&& Lambda.find(this.fields,
									(f) -> f.name == ("get_" + field.name) && !f.access.contains(AStatic) && f.kind.match(KFunction(_))) == null)
								forceError(ECustom("No getter function found for \"" + field.name + "\" -> \"get_" + field.name + "\""), field.pos);
							if (decl.set == "set"
								&& Lambda.find(this.fields,
									(f) -> f.name == ("set_" + field.name) && !f.access.contains(AStatic) && f.kind.match(KFunction(_))) == null)
								forceError(ECustom("No setter function found for \"" + field.name + "\" -> \"set_" + field.name + "\""), field.pos);
							__interp.propertyLinks.set(field.name, new PropertyAccessor(__interp, () -> {
								final n = field.name;
								if (__interp.directorFields.get(n) != null)
									return __interp.directorFields.get(n).value;
								else
									forceError(EUnknownVariable(n), field.pos);
								return null;
							}, (val) -> {
								final n = field.name;
								if (__interp.directorFields.get(n) != null)
									__interp.directorFields.get(n).value = val;
								else
									forceError(EUnknownVariable(n), field.pos);
								return val;
							}, decl.get ?? "default", decl.set ?? "default"));
						}
					case KFunction(decl):
						__interp.directorFields.set(field.name, {
							value: parseFuncDecl(decl, field.name),
							type: "func",
							const: true,
							isInline: field.access.contains(AInline)
						});
				}
		}
	}

	inline function sureScriptedClass(): Bool {
		return cacheSuperFieldsName.contains("__sc_standClass");
	}

	function parseConstructor() {
		@:privateAccess if (this.constructor != null) {
			final field = this.constructor;
			switch (field.kind) {
				case KFunction(decl):
					__interp.directorFields.set(field.name, {
						value: parseFuncDecl(decl, field.name),
						type: "func",
						const: true,
						isInline: field.access.contains(AInline)
					});
				case _:
			}
		} else if (!needExtend()) {
			throw "ScriptClass '" + name + "' has not constructor.";
		}
	}

	private function syncParent(s: Interp) {
		@:privateAccess s.imports = __ogInterp.imports;
	}

	private function parseValDecl(decl: VarDecl) {
		@:privateAccess
		return if (decl.expr == null) {
			null;
		} else {
			__interp.convertSimgle(__interp.expr(decl.expr));
		}
	}

	private function parseFuncDecl(decl: FunctionDecl, name: String) {
		@:privateAccess {
			var capturedLocals = __interp.duplicate(__interp.locals);
			if (decl.args == null)
				decl.args = [];
			var minParams = decl.args.length;
			var paramDefs = [];
			for (param in decl.args) {
				if (param.opt || param.value != null)
					minParams--;
				if (param.value != null) {
					paramDefs.push({
						__interp.expr(param.value);
					});
				} else
					paramDefs.push(null);
			}
			var func = function(args: Array<Dynamic>) {
				if (args.length < minParams) {
					throw "Invalid number of parameters. Got " + args.length + ", required " + minParams + " for function '" + this.name
						+ "." + name + "'";
				}

				// make sure mandatory args are forced
				var args2 = [];
				var extraParams = args.length - minParams;
				var pos = 0;
				for (index => p in decl.args) {
					if (p.opt) {
						if (extraParams > 0) {
							if (args[pos] == null && paramDefs[index] != null)
								args2.push(paramDefs[index]);
							else
								args2.push(args[pos]);
							extraParams--;
							pos++;
						} else
							args2.push(paramDefs[index]);
					} else {
						if (args[pos] == null && paramDefs[index] != null)
							args2.push(paramDefs[index]);
						else
							args2.push(args[pos]);
						pos++;
					}
				}
				args = args2;
				var old = __interp.locals, depth = __interp.depth;
				__interp.depth++;
				__interp.locals = __interp.duplicate(capturedLocals);
				for (i in 0...decl.args.length)
					__interp.locals.set(decl.args[i].name, {r: __interp.convertSimgle(args[i]), const: false});

				var r = null;
				var oldDecl = __interp.declared.length;

				final of: Null<String> = __interp.inFunction;
				if (name != null)
					__interp.inFunction = name;
				else
					__interp.inFunction = "(*unamed)";
				if (__interp.inTry)
					try {
						r = __interp.exprReturn(decl.expr, false);
					} catch (e:Dynamic) {
						__interp.locals = old;
						__interp.depth = depth;
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else {
					r = __interp.exprReturn(decl.expr, false);
				}
				__interp.inFunction = of;

				__interp.restore(oldDecl);
				__interp.locals = old;
				__interp.depth = depth;
				return r;
			};
			return Reflect.makeVarArgs(func);
		}
	}

	@:access(crowplexus.hscript.Interp)
	private function forceError(err: #if hscriptPos ErrorDef #else Error #end, ?e:Expr) {
		#if hscriptPos
		final old = __interp.curExpr;
		__interp.curExpr = (e != null ? e : urDad.__forceExpr);
		#end
		__interp.error(err);
		#if hscriptPos
		__interp.curExpr = old;
		#end
	}

	@:access(crowplexus.hscript.Interp)
	private function forceWarn(err: #if hscriptPos ErrorDef #else Error #end, ?e:Expr) {
		#if hscriptPos
		final old = __interp.curExpr;
		__interp.curExpr = (e != null ? e : urDad.__forceExpr);
		#end
		__interp.warn(err);
		#if hscriptPos
		__interp.curExpr = old;
		#end
	}

	private function createSuperClassInstance(args: Array<Dynamic>) {
		if (sureScriptedClass())
			Type.createInstance(urDad.superClassDecl, [cast this].concat(args));
		else
			this.superClass = Type.createInstance(urDad.superClassDecl, args);
	}

	public function toString(): String {
		if (sc_exists("toString")) {
			var result: Dynamic = sc_call("toString");
			return Std.string(result);
		}

		return name;
	}
}