package psychlua.stages.modules;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Tools;
import crowplexus.hscript.Interp;
import crowplexus.hscript.Printer;
import crowplexus.hscript.proxy.ProxyType;
import crowplexus.hscript.scriptclass.*;
import crowplexus.iris.Iris;

@:allow(psychlua.stages.modules.ModuleInterp)
class ModuleAgency {
	public var pack(default, null):String;
	public var origin(default, null):String;
	public var classes:Array<Dynamic>;

	private var _expr:Expr;
	private var __interp:ModuleInterp;

	@:noCompletion private var _preClassesName:Array<String> = [];

	var imports:Array<Expr> = [];
	var loadClasses:Array<Expr> = [];
	var unusedClasses:Map<String, Expr> = [];

	@:allow(psychlua.stages.modules.ScriptedModuleNotify)
	private function new(expr:Expr, pack:String, origin:String) {
		this._expr = expr;
		this.pack = pack;
		this.origin = origin;

		__interp = new ModuleInterp(this);
		for(k=>cl in ScriptedModuleNotify._specifyClasses) {
			__interp.imports.set(ScriptedModuleNotify._specifyClassNames[k], cl);
		}
		for(k=>v in ScriptedModuleNotify._presets) {
			__interp.imports.set(k, v);
		}
		__interp.importHandler = _importHandler;

		classes = [];
		if(Tools.expr(this._expr).match(EBlock(_))) {
			Tools.iter(this._expr, function(e:Expr) {
				this.addClasses(e);
			});
		} else this.addClasses(this._expr);
	}

	function _importHandler(v:String, ?as:String, ?star:Bool):Bool {
		final last = v.lastIndexOf(".");
		final p = v.substr(0, last > -1 ? last : 0);
		final cn = v.substr(last > -1 ? last + 1 : 0);
		if(ScriptedModuleNotify.classSystems.exists(p)) {
			for(m in ScriptedModuleNotify.classSystems.get(p)) {
				if(m.unusedClasses.exists(cn)) {
					runThrow(() -> m.__interp.execute(m.unusedClasses.get(cn)), m.origin);
					break;
				}
			}
		}
		return false;
	}

	@:allow(psychlua.stages.modules.ScriptedModuleNotify)
	function execute() {
		for(e in imports) runThrow(() -> {__interp.execute(e);}, this.origin);
		for(e in loadClasses) runThrow(() -> {
			__interp.execute(e);
		}, this.origin);
	}

	public static function runThrow(func:Void->Void, ?failedFunc:Dynamic->Void, origin:String = "hscript") {
		try {
			func();
		} catch(err:Error) {
			Iris.error(Printer.errorToString(err, false), cast {#if hscriptPos fileName: err.origin, lineNumber: err.line #else fileName: "hscript", lineNumber: 0 #end});
			if(failedFunc != null) failedFunc(err);
		} catch(e:Dynamic) {
			Iris.error(Std.string(e), cast {lineNumber: 0, fileName: #if hscriptPos origin #else "hscript" #end});
			if(failedFunc != null) failedFunc(e);
		}
	}

	function addClasses(e:Expr) {
		switch(Tools.expr(e)) {
			case EClass(cls, ex, _, _):
				for(k => cl in ScriptedModuleNotify._specifyClasses) {
					if(cl != null && (ex != null && ex.name == ScriptedModuleNotify._specifyClassNames[k])) {
						loadClasses.push(e);
						_preClassesName.push(cls);
						break;
					}
				}
				unusedClasses.set(cls, e);
				if(pack == "") ScriptedModuleNotify.unpackUnusedClasses.set(cls, {m: this, e: e});
			case EImport(_):
				imports.push(e);
			case EEnum(name, _, _), ETypedef(name, _):
				unusedClasses.set(name, e);
				if(pack == "") ScriptedModuleNotify.unpackUnusedClasses.set(name, {m: this, e: e});
			case _:
		}
	}

	public function toString() {
		return Std.string({
			classes: this.classes,
			pack: this.pack,
			origin: origin,
		});
	}
}

class ModuleInterp extends Interp {
	public var module:ModuleAgency;

	public function new(m:ModuleAgency) {
		module = m;
		super();
		this.allowScriptEnum = this.allowScriptClass = true;
	}

	public override function execute(expr:Expr):Dynamic {
		ModuleCheckClass.check(expr, function(id, ?pack) {
			if(pack != null && pack != "") {
				if(ScriptedModuleNotify.classSystems.exists(pack)) {
					for(m in ScriptedModuleNotify.classSystems.get(pack)) {
						if(m.unusedClasses.exists(id)) {
							m.__interp.execute(m.unusedClasses.get(id));
							break;
						}
					}
				}
				return;
			}
			if(this.module.unusedClasses.exists(id)) {
				final e = this.module.unusedClasses.get(id);
				if(this.module._preClassesName.contains(id)) this.module.unusedClasses.remove(id);
				this.execute(e);
			} else if(this.module.pack != "" && ScriptedModuleNotify.classSystems.exists(this.module.pack)) {
				final m:ModuleAgency = Lambda.find(ScriptedModuleNotify.classSystems.get(this.module.pack), function(m) {
					return m.unusedClasses.exists(id);
				});
				if(m != null) {
					final e = m.unusedClasses.get(id);
					if(m._preClassesName.contains(id)) m.unusedClasses.remove(id);
					m.__interp.execute(e);
				}
			} else if(ScriptedModuleNotify.unpackUnusedClasses.exists(id)) {
				final c = ScriptedModuleNotify.unpackUnusedClasses.get(id);
				ScriptedModuleNotify.unpackUnusedClasses.remove(id);
				c.m.__interp.execute(c.e);
			}
		});
		return super.execute(expr);
	}

	override function registerScriptClass(cl:String, ex:Null<TypePath>, fields:Array<BydFieldDecl>, metas:Metadata, ?pkg:Array<String>) {
		var cls = new crowplexus.hscript.scriptclass.ScriptClass(this, cl, ex, fields, metas, pkg);
		Interp.scriptClasses.set(cls.fullPath, cls);
		if(this.module.pack == "") {
			Interp.unpackClassCache.set(cl, cls);
		} else {
			if(ScriptedModuleNotify.classSystems.exists(this.module.pack)) {
				for(m in ScriptedModuleNotify.classSystems.get(this.module.pack)) {
					m.__interp.imports.set(cl, cls);
				}
			}
			this.module.classes.push(cls);
		}
	}

	override function registerTypeAlias(name:String, p:TypePath, ?pkg:Array<String>) {
		final cn = (p.pack != null && p.pack.length > 0 ? p.pack.join(".") + "." : "") + p.name;
		var v:Dynamic = imports.get(cn) ?? ProxyType.resolveClass(cn) ?? ProxyType.resolveEnum(cn);
		Interp.typesAlias.set((pkg != null && pkg.length > 0 ? pkg.join(".") + "." : "") + name, v);
		imports.set(name + "_Typedef", v);
		if(this.module.pack == "") {
			Interp.unpackClassCache.set(name, v);
		} else {
			if(ScriptedModuleNotify.classSystems.exists(this.module.pack)) {
				for(m in ScriptedModuleNotify.classSystems.get(this.module.pack)) {
					m.__interp.imports.set(name + "_Typedef", v);
				}
			}
		}
	}

	override function registerScriptEnum(enumName:String, fields:Array<EnumType>, ?pkg:Array<String>) {
		var obj: crowplexus.hscript.scriptenum.ScriptEnum = new crowplexus.hscript.scriptenum.ScriptEnum(enumName, pkg);
		for (index => field in fields) {
			switch (field) {
				case ESimple(name):
					obj.sm.set(name, new crowplexus.hscript.scriptenum.ScriptEnumValue(obj, enumName, name, index, null));
				case EConstructor(name, params):
					var hasOpt = false, minParams = 0;
					for (p in params)
						if (p.opt)
							hasOpt = true;
						else
							minParams++;
					var f = function(args: Array<Dynamic>) {
						if (((args == null) ? 0 : args.length) != params.length) {
							if (args.length < minParams) {
								var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
								if (enumName != null)
									str += " for enum '" + enumName + "'";
								error(ECustom(str));
							}
							// make sure mandatory args are forced
							var args2 = [];
							var extraParams = args.length - minParams;
							var pos = 0;
							for (p in params)
								if (p.opt) {
									if (extraParams > 0) {
										args2.push(args[pos++]);
										extraParams--;
									} else
										args2.push(null);
								} else
									args2.push(args[pos++]);
							args = args2;
						}
						return new crowplexus.hscript.scriptenum.ScriptEnumValue(obj, enumName, name, index, args);
					};
					var f = Reflect.makeVarArgs(f);

					obj.sm.set(name, f);
			}
		}
		Interp.scriptEnums.set(obj.fullPath, obj);
		if(this.module.pack == "") {
			Interp.unpackClassCache.set(enumName, obj);
		} else {
			imports.set(enumName, obj);
			this.module.classes.push(obj);
		}
	}
}

class ModuleCheckClass {

	static var savedId:Array<String>;
	public static function check(e:Expr, f:String->?String->Void) {
		if(e == null) return;
		savedId = [];
		_check(e, f);
	}

	private static function _check(e:Expr, f:String->?String->Void) {
		switch(Tools.expr(e)) {
			case EClass(cl, ex, _, fields):
				if(ex != null && !savedId.contains(ex.name)) f(ex.name);
				savedId.push(cl);
				for(fu in fields) {
					switch(fu.kind) {
						case KVar(decl):
							if(decl.expr != null) _check(decl.expr, f);
							savedId.push(fu.name);
						case KFunction(decl):
							savedId.push(fu.name);
							_check(decl.expr, f);
					}
				}
			case EConst(c):
				switch(c) {
					case CString(s, ea):
						if(ea != null) for(e in ea) {
							_check(e.e, f);
						}
					case _:
				}
			case EIdent(id):
				if(!savedId.contains(id)) f(id);
			case EVar(n, _, _, e, getter, setter, _, s):
				savedId.push(n);
				if (e != null)
					_check(e, f);
			case EParent(e):
				_check(e, f);
			case EBlock(el):
				for (e in el)
					_check(e, f);
			case EField(e, _):
				_check(e, f);
			case EBinop(_, e1, e2):
				_check(e1, f);
				_check(e2, f);
			case EUnop(_, _, e):
				_check(e, f);
			case ECall(e, args):
				_check(e, f);
				for (a in args)
					_check(a, f);
			case EIf(c, e1, e2):
				_check(c, f);
				_check(e1, f);
				if (e2 != null)
					_check(e2, f);
			case EWhile(c, e):
				_check(c, f);
				_check(e, f);
			case EDoWhile(c, e):
				_check(c, f);
				_check(e, f);
			case EFor(_, it, e):
				_check(it, f);
				_check(e, f);
			case EBreak, EContinue:
			case EFunction(_, e, _, _, _, s):
				_check(e, f);
			case EReturn(e):
				if (e != null)
					_check(e, f);
			case EArray(e, i):
				_check(e, f);
				_check(i, f);
			case EArrayDecl(el):
				for (e in el)
					_check(e, f);
			case ENew(t, el):
				if(!savedId.contains(t.name)) f(t.name);
				for (e in el)
					_check(e, f);
			case EThrow(e):
				_check(e, f);
			case ETry(e, _, _, c):
				_check(e, f);
				_check(c, f);
			case EObject(fl):
				for (fi in fl)
					_check(fi.e, f);
			case ETernary(c, e1, e2):
				_check(c, f);
				_check(e1, f);
				_check(e2, f);
			case ESwitch(e, cases, def):
				_check(e, f);
				for (c in cases) {
					for (v in c.values)
						_check(v, f);
					_check(c.expr, f);
				}
				if (def != null)
					_check(def, f);
			case EMeta(name, args, e):
				if (args != null)
					for (a in args)
						_check(a, f);
				_check(e, f);
			case ECheckType(e, _):
				_check(e, f);
			case ETypedef(name, t):
				savedId.push(name);
				switch(t) {
					case CTPath(p): f(p.name, p.pack?.join("."));
					case _:
				}
			default:
		}
	}
}