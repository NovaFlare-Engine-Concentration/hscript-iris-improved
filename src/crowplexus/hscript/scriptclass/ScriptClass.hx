package crowplexus.hscript.scriptclass;

import crowplexus.hscript.Interp;
import crowplexus.hscript.Expr;
import crowplexus.iris.Iris;

@:access(crowplexus.hscript.scriptclass.ScriptClassInstance)
class ScriptClass extends BaseScriptClass {
	public var name: String;
	public var extend: Null<String>;
	public var packages: Array<String>;
	public var superClassDecl: Class<Dynamic>;

	public var fullPath(get, never): String;

	// var clPath:TypePath;
	var exPath:Null<TypePath>;

	@:noCompletion inline function get_fullPath(): String {
		if (this.packages != null && this.packages.length > 0) {
			return this.packages.join(".") + "." + name;
		}
		return name;
	}

	public var overrideResolve:String->Bool = null;

	private var fields: Array<BydFieldDecl>;
	#if hscriptPos
	private var __forceExpr:Expr;
	#end

	var metas: Metadata;
	var staticInterp: Interp;
	var ogInterp: Interp;

	@:allow(crowplexus.hscript.Interp)
	private function new(ogInterp: Interp, cls: String, extendCls: TypePath, fields: Array<BydFieldDecl>, ?metas: Metadata, ?pkg: Array<String>) {
		this.ogInterp = ogInterp;
		#if hscriptPos
		@:privateAccess this.__forceExpr = ogInterp.curExpr;
		#end
		this.name = cls;

		this.exPath = extendCls;
		if(this.exPath != null) this.extend = (this.exPath.pack != null && this.exPath.pack.length > 0 ? this.exPath.pack.join(".") + "." : "") + this.exPath.name;

		if (metas != null)
			this.metas = metas;
		if (this.extend != null && ogInterp.imports.get(this.extend) is Class) {
			this.superClassDecl = cast ogInterp.imports.get(this.extend);
		} else if (this.extend != null && !(ogInterp.imports.get(this.extend) is Class)) {
			var ex = Type.resolveClass(this.extend);
			if(ex != null) {
				this.superClassDecl = ex;
			} else @:privateAccess forceError(ECustom("Invalid Extend Class -> '" + extendCls + "'"));
		}
		this.packages = pkg;

		if (fields == null)
			this.fields = [];
		else
			this.fields = fields;

		staticInterp = new Interp();
		syncParent(staticInterp);
		parseStaticFields();
	}

	public override function sc_exists(name: String): Bool {
		@:privateAccess return staticInterp.directorFields.get(name) != null
			|| staticInterp.propertyLinks.get(name) != null
			|| staticInterp.variables.exists(name);
	}

	public override function sc_get(name: String, ?e:Expr, inClass:Bool = false): Dynamic {
		@:privateAccess {
			if (staticInterp.propertyLinks.get(name) != null) {
				var l = staticInterp.propertyLinks.get(name);
				if (l.inState)
					return l.get(name);
				else
					return l.link_getFunc();
			}

			if (staticInterp.directorFields.get(name) != null)
				return staticInterp.directorFields.get(name).value;

			if (staticInterp.variables.exists(name)) {
				var v = staticInterp.variables.get(name);
				return v;
			}

			if(e != null) {
				if(!inClass) forceError(EUnknownVariable(name), e);
				else forceError(ECustom("ScriptClass<" + this.fullPath + "> has no field -> '" + name + "'"), e);
			}
			return null;
		}
	}

	public override function sc_set(name: String, value: Dynamic, ?e:Expr) {
		@:privateAccess {
			if (staticInterp.propertyLinks.get(name) != null) {
				var l = staticInterp.propertyLinks.get(name);
				if (l.inState)
					l.set(name, value);
				else
					l.link_setFunc(value);
				return;
			}

			if (staticInterp.directorFields.get(name) != null) {
				var l = staticInterp.directorFields.get(name);
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
				staticInterp.variables.set(name, value);
		}
	}

	public override function sc_call(name: String, ?args: Array<Dynamic>): Dynamic {
		if (Reflect.isFunction(sc_get(name)))
			return Reflect.callMethod(null, sc_get(name), args ?? []);
		return null;
	}

	public inline override function getFields(): Array<String> {
		return [for (f in this.fields) if (f.access.contains(AStatic)) f.name];
	}

	public inline override function getVars(): Array<String> {
		return [
			for (f in this.fields)
				if (f.access.contains(AStatic) && f.kind.match(KVar(_))) f.name
		];
	}

	public inline override function getFunctions(): Array<String> {
		return [
			for (f in this.fields)
				if (f.access.contains(AStatic) && f.kind.match(KFunction(_))) f.name
		];
	}

	public inline override function getFieldsWithOverride(): Array<String> {
		if (superClassDecl != null) {
			var classFields = Type.getInstanceFields(superClassDecl);
			if (classFields.contains("__sc_standClass"))
				classFields = classFields.filter(f -> !StringTools.startsWith(f, crowplexus.iris.macro.ScriptedClassMacro.SUPER_FUNCTION_PREFIX)
					&& f != "__sc_standClass");
			return [
				for (f in this.fields)
					if (!f.access.contains(AStatic) && !f.access.contains(AOverride)) f.name
			].concat(classFields);
		}
		return [
			for (f in this.fields)
				if (!f.access.contains(AStatic) && !f.access.contains(AOverride)) f.name
		];
	}

	private function parseStaticFields() {
		@:privateAccess
		for (field in this.fields) {
			staticInterp.expr(field.pos);
			if (field.access != null && field.access.contains(AStatic)) {
				switch (field.kind) {
					case KVar(decl):
						staticInterp.directorFields.set(field.name, {
							value: parseValDecl(decl),
							type: "var",
							const: decl.isConst,
							isInline: field.access.contains(AInline)
						});
						if ((decl.get != null && decl.get != "default") || (decl.set != null && decl.set != "default")) {
							if (decl.get == "get"
								&& Lambda.find(this.fields,
									(f) -> f.name == ("get_" + field.name) && f.access.contains(AStatic) && f.kind.match(KFunction(_))) == null)
								forceError(ECustom("No getter function found for \"" + field.name + "\" -> \"get_" + field.name + "\""));
							if (decl.set == "set"
								&& Lambda.find(this.fields,
									(f) -> f.name == ("set_" + field.name) && f.access.contains(AStatic) && f.kind.match(KFunction(_))) == null)
								forceError(ECustom("No setter function found for \"" + field.name + "\" -> \"set_" + field.name + "\""));
							staticInterp.propertyLinks.set(field.name, new PropertyAccessor(staticInterp, () -> {
								final n = field.name;
								if (staticInterp.directorFields.get(n) != null)
									return staticInterp.directorFields.get(n).value;
								forceError(EUnknownVariable(n));
								return null;
							}, (val) -> {
								final n = field.name;
								if (staticInterp.directorFields.get(n) != null)
									staticInterp.directorFields.get(n).value = val;
								forceError(EUnknownVariable(n));
								return val;
							}, decl.get ?? "default", decl.set ?? "default"));
						}
					case KFunction(decl):
						staticInterp.directorFields.set(field.name, {
							value: parseFuncDecl(decl, field.name),
							type: "func",
							const: true,
							isInline: field.access.contains(AInline)
						});
				}
			}
		}
	}

	private function parseValDecl(decl: VarDecl): Dynamic {
		@:privateAccess
		return if (decl.expr == null) {
			null;
		} else {
			staticInterp.convertSimgle(staticInterp.expr(decl.expr));
		}
	}

	private function parseFuncDecl(decl: FunctionDecl, name: String) {
		@:privateAccess {
			var capturedLocals = staticInterp.duplicate(staticInterp.locals);
			if (decl.args == null)
				decl.args = [];
			var minParams = decl.args.length;
			var paramDefs = [];
			for (param in decl.args) {
				if (param.opt || param.value != null)
					minParams--;
				if (param.value != null) {
					paramDefs.push({
						staticInterp.expr(param.value);
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
				var old = staticInterp.locals, depth = staticInterp.depth;
				staticInterp.depth++;
				staticInterp.locals = staticInterp.duplicate(capturedLocals);
				for (i in 0...decl.args.length)
					staticInterp.locals.set(decl.args[i].name, {r: staticInterp.convertSimgle(args[i]), const: false});

				var r = null;
				var oldDecl = staticInterp.declared.length;
				final of: Null<String> = staticInterp.inFunction;
				if (name != null)
					staticInterp.inFunction = name;
				else
					staticInterp.inFunction = "(*unamed)";
				if (staticInterp.inTry)
					try {
						r = staticInterp.exprReturn(decl.expr, false);
					} catch (e:Dynamic) {
						staticInterp.locals = old;
						staticInterp.depth = depth;
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else {
					r = staticInterp.exprReturn(decl.expr, false);
				}
				staticInterp.inFunction = of;
				staticInterp.restore(oldDecl);
				staticInterp.locals = old;
				staticInterp.depth = depth;
				return r;
			};
			return Reflect.makeVarArgs(func);
		}
	}

	public function createInstance(?args: Array<Dynamic>) {
		var instance = new ScriptClassInstance(this.ogInterp, name, extend, this.fields.filter((f) -> !f.access.contains(AStatic) && f.name != "new"),
			Lambda.find(this.fields, (f) -> f.name == "new"), this, args ?? []);
		return instance;
	}

	@:access(crowplexus.hscript.Interp)
	private function forceError(err: #if hscriptPos ErrorDef #else Error #end, ?e:Expr) {
		#if hscriptPos
		final old = staticInterp.curExpr;
		staticInterp.curExpr = (e != null ? e : __forceExpr);
		#end
		staticInterp.error(err);
		#if hscriptPos
		staticInterp.curExpr = old;
		#end
	}

	@:access(crowplexus.hscript.Interp)
	private function forceWarn(err: #if hscriptPos ErrorDef #else Error #end, ?e:Expr) {
		#if hscriptPos
		final old = staticInterp.curExpr;
		staticInterp.curExpr = (e != null ? e : __forceExpr);
		#end
		staticInterp.warn(err);
		#if hscriptPos
		staticInterp.curExpr = old;
		#end
	}

	private function syncParent(s: Interp) {
		s.imports = ogInterp.imports;
	}

	public function toString(): String {
		return "ScriptClass<" + this.fullPath + ">";
	}
}