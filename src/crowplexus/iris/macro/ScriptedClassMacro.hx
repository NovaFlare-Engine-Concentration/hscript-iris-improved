package crowplexus.iris.macro;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Printer;
import Type as OType;
#end

#if macro
/**
 * @see `懒得说`
 * 其实也没借鉴多少hah
 */
class ScriptedClassMacro {
	public static inline var SUPER_FUNCTION_PREFIX: String = "__SC_SUPER_";

	static var noOverrides: Array<String>;

	public static function build(): Array<Field> {
		var cls: ClassType = Context.getLocalClass().get();
		if (cls.superClass == null)
			throw "The specified class requires super class.";

		noOverrides = [];
		for (meta in cls.meta.get()) {
			if (meta.name == ":noOverride") {
				for (param in meta.params) {
					switch (param.expr) {
						case EConst(con):
							switch (con) {
								case CString(str, _):
									noOverrides.push(str);
								case _:
							}
						case _:
					}
				}
			}
		}
		var fields = Context.getBuildFields();
		var declaredConstructor = Lambda.find(fields, field -> field.name == "new");
		if (declaredConstructor == null) {
			var constructor = getConstructor(cls);
			if (constructor == null)
				throw "No constructor defined in super class.";
			declaredConstructor = buildConstructor(constructor);
			fields.push(declaredConstructor);
		}
		bindConstructor(declaredConstructor);
		var overrideFields = getOverrides(cls);
		fields = fields.concat(buildIDKField(Context.getLocalClass(), cls.superClass));
		buildMethodBridges(fields, overrideFields);
		return fields;
	}

	private static function buildIDKField(cls: Ref<ClassType>, superCls: Null<{t: Ref<ClassType>, params: Array<Type>}>): Array<Field> {
		var fields: Array<Field> = [];
		var f___e_standClass: Field = {
			name: "__sc_standClass",
			access: [APrivate],
			kind: FVar(toComplexType(Context.getType('crowplexus.hscript.scriptclass.ScriptClassInstance'))),
			pos: Context.currentPos(),
		}
		fields.push(f___e_standClass);

		var f___e_scriptClassLists: Field = {
			name: "__sc_scriptClassLists",
			access: [APublic, AStatic],
			kind: FFun({
				args: [],
				ret: macro : Array<String>,
				expr: macro {
					var grp: Array<String> = [];
					@:privateAccess
					for (path => sc in crowplexus.hscript.Interp.scriptClasses) {
						if (sc.superClassDecl == $i{cls.get().name}) {
							grp.push(path);
						}
					}
					return grp;
				}
			}),
			pos: Context.currentPos(),
			doc: "/**
 * @see [[链接已屏蔽]]
 * 总之就是可以通过这个获取继承了这玩意儿的所有脚本类（大概
 */"
		};
		fields.push(f___e_scriptClassLists);

		var f___e_createInstanceScriptClass: Field = {
			name: "createScriptClassInstance",
			access: [APublic, AStatic],
			kind: FFun({
				ret: Context.toComplexType(TInst(superCls.t, superCls.params)),
				args: cast [
					{
						name: "className",
						ret: macro : String
					},
					{
						name: "args",
						opt: true,
						ret: macro : Array<Dynamic>
					}
				],
				expr: macro {
					var cls: crowplexus.hscript.scriptclass.ScriptClass = crowplexus.hscript.Interp.resolveScriptClass(className);
					if (cls != null) {
						return cls.createInstance(args).superClass;
					}

					return null;
				}
			}),
			pos: Context.currentPos()
		};
		fields.push(f___e_createInstanceScriptClass);

		return fields;
	}

	private static function buildConstructor(con: ChouxiangFunction): Field {
		var fnargs = [for (arg in con.args) macro $i{arg.name}];
		return {
			name: con.name,
			kind: FFun({
				args: [for (arg in con.args) {type: arg.ret, name: arg.name, value: arg.value}],
				expr: macro super($a{fnargs}),
			}),
			pos: Context.currentPos()
		};
	}

	private static function bindConstructor(field: Field): Void {
		var method = switch (field.kind) {
			case FFun(method): method;
			case _: Context.error("Expected a constructor function.", field.pos);
		};
		method.args.unshift({name: "__sc_standClass", type: macro : crowplexus.hscript.scriptclass.ScriptClassInstance});
		method.expr = macro {
			this.__sc_standClass = __sc_standClass;
			if (__sc_standClass != null)
				__sc_standClass.superClass = this;
			$e{method.expr};
		};
	}

	private static function getConstructor(cls: ClassType): ChouxiangFunction {
		var superCls: ClassType = cls.superClass?.t.get();
		var func: ChouxiangFunction = null;
		while (superCls != null) {
			if (superCls.constructor != null) {
				final field = superCls.constructor.get();
				var tps: Array<TypeParamDecl> = [];
				if (field.params.length > 0) {
					final params = field.params;
					for (param in params) {
						var tp: TypeParamDecl = convertTypeParam(param);
						tps.push(tp);
					}
				}
				var myFunc = {
					name: field.name,
					args: [],
					typeParams: tps,
					ret: null,
					doThisReturn: false,
					meta: field.meta.get()
				};
				switch (field.kind) {
					case FMethod(pd) if (Type.enumEq(pd, MethNormal)):
					case _:
						break;
				}
				var expr = field.expr();
				if (expr != null) {
					switch (expr.expr) {
						case TFunction(pd):
							for (arg in pd.args) {
								var newArg = {
									name: arg.v.name,
									value: arg.value == null ? null : Context.getTypedExpr(arg.value),
									ret: toComplexType(arg.v.t)
								};
								myFunc.args.push(newArg);
							}
						case _:
							break;
					}
				}
				func = myFunc;
				break;
			} else
				break;
			superCls = cls.superClass?.t.get();
		}
		return func;
	}

	static function buildMethodBridges(fields: Array<Field>, methods: Array<ChouxiangFunction>): Void {
		var declaredFields = [for (field in fields) field.name => field];
		for (method in methods) {
			var declared = declaredFields.get(method.name);
			if (declared != null) {
				if (declared.access != null && declared.access.contains(AOverride))
					buildDeclaredOverride(fields, declared, method.doThisReturn);
				continue;
			}

			var bridge = buildInheritedOverride(method);
			fields.push(bridge.overrideField);
			fields.push(bridge.superField);
		}
	}

	static function buildDeclaredOverride(fields: Array<Field>, declared: Field, returnsValue: Bool): Void {
		var method = switch (declared.kind) {
			case FFun(method): method;
			case _: return;
		};
		var superName = SUPER_FUNCTION_PREFIX + declared.name;
		fields.push({
			name: superName,
			kind: FFun({args: method.args, params: method.params, ret: method.ret, expr: method.expr}),
			meta: declared.meta == null ? null : declared.meta.filter(entry -> entry.name == ":access"),
			pos: declared.pos
		});
		var args = [for (arg in method.args) macro $i{arg.name}];
		method.expr = buildDispatch(declared.name, args, macro this.$superName($a{args}), returnsValue);
	}

	static function buildInheritedOverride(method: ChouxiangFunction): {overrideField: Field, superField: Field} {
		var name = method.name;
		var args = [for (arg in method.args) macro $i{arg.name}];
		var parentCall = macro super.$name($a{args});
		var parameters = [for (arg in method.args) {type: arg.ret, name: arg.name, value: arg.value}];
		var pos = Context.currentPos();
		return {
			overrideField: {
				name: name,
				access: [AOverride],
				kind: FFun({args: parameters, params: method.typeParams, expr: buildDispatch(name, args, parentCall, method.doThisReturn)}),
				pos: pos
			},
			superField: {
				name: SUPER_FUNCTION_PREFIX + name,
				kind: FFun({args: parameters, params: method.typeParams, expr: method.doThisReturn ? macro return $e{parentCall} : parentCall}),
				pos: pos
			}
		};
	}

	static function buildDispatch(name: String, args: Array<Expr>, parentCall: Expr, returnsValue: Bool): Expr {
		var scriptCall = macro @:privateAccess __sc_standClass.sc_call($v{name}, [$a{args}]);
		var dispatch = returnsValue ? macro {
			var result: Dynamic = null;
			scripts.stages.modules.ModuleAgency.runThrow(() -> result = $e{scriptCall});
			return cast result;
		} : macro scripts.stages.modules.ModuleAgency.runThrow(() -> { $e{scriptCall}; });
		var fallback = returnsValue ? macro return $e{parentCall} : parentCall;
		return macro {
			@:privateAccess
			if (__sc_standClass != null && __sc_standClass.overrides.contains($v{name}))
				$e{dispatch};
			else
				$e{fallback};
		};
	}

	static function convertTypeParam(tpr: TypeParameter): TypeParamDecl {
		function parse(t: Type, tp: TypeParamDecl) {
			switch (t) {
				case TInst(ctrl, grp):
					if (grp.length > 0) {
						if (!Reflect.hasField(tp, "params"))
							Reflect.setField(tp, "params", []);
						for (b in grp) {
							var newTp: TypeParamDecl = {name: tpr.name};
							parse(b, newTp);
							tp.params.push(newTp);
						}
					}
					switch (ctrl.get().kind) {
						case KTypeParameter(csgo):
							if (csgo.length > 0) {
								for (c in csgo) {
									if (!Reflect.hasField(tp, "constraints"))
										Reflect.setField(tp, "constraints", []);
									tp.constraints.push(toComplexType(c));
								}
							}
						case _:
					}
				case _:
			}
		}

		var tp: TypeParamDecl = {name: tpr.name};
		parse(tpr.t, tp);
		return tp;
	}

	static var curTps: Array<TypeParamDecl> = null;

	private static function getOverrides(cls: ClassType): Array<ChouxiangFunction> {
		var funcs: Array<ChouxiangFunction> = [];
		var superCls: ClassType = cls.superClass?.t.get();
		// 禁止黑名单参赛者复赛
		var blacklist: Array<String> = [];
		// var pause:Bool = false;

		while (superCls != null) {
			// if(!pause && superCls != null && superCls.params.length > 0) {
			//	pause = true;
			//	for(param in superCls.params) {
			//		var tp:TypeParamDecl = convertTypeParam(param);
			//		tpss.push(tp);
			//	}
			// }
			var overrides: Array<ClassField> = [for (o in superCls.overrides) o.get()];
			for (f in overrides.concat(superCls.fields.get())) {
				if (Lambda.find(funcs, (field) -> field.name == f.name) != null
					|| blacklist.contains(f.name)
					|| noOverrides.contains(f.name)) {
					continue;
				}
				var tps: Array<TypeParamDecl> = [];
				if (f.params.length > 0) {
					final params = f.params;
					for (param in params) {
						var tp: TypeParamDecl = convertTypeParam(param);
						tps.push(tp);
					}
				}
				curTps = tps;
				switch (f.kind) {
					case FMethod(mk) if (Type.enumEq(mk, MethNormal)):
						if (Lambda.find(funcs, (fun) -> fun.name == f.name) == null) {
							var func = {
								name: f.name,
								args: [],
								typeParams: tps,
								ret: toComplexType(f.type),
								doThisReturn: true,
								meta: f.meta.get()
							};
							var expr = f.expr();
							if (expr != null) {
								switch (expr.expr) {
									case TFunction(fd):
										func.ret = toComplexType(fd.t);
										switch (fd.t) {
											case TAbstract(sb, _) if (sb.toString() == "Void"):
												func.doThisReturn = false;
											case _:
										}
										for (arg in fd.args) {
											var newArg = {
												name: arg.v.name,
												value: arg.value == null ? null : Context.getTypedExpr(arg.value),
												ret: toComplexType(arg.v.t)
											};
											func.args.push(newArg);
										}
									case _:
								}
							}
							funcs.push(func);
						}
					case _:
						blacklist.push(f.name);
				}
				curTps = null;
			}
			superCls = superCls.superClass?.t.get();
		}
		return funcs;
	}

	private static function toComplexType(t: Type): ComplexType {
		switch (t) {
			case TAbstract(ctrl, grp):
				final cp = ctrl.get();
				var np: TypePath = {
					pack: cp.pack,
					name: cp.module.substring(cp.module.lastIndexOf(".") + 1),
					sub: cp.name,
					params: [for (g in grp) toTypeParam(g)]
				};
				return TPath(np);
			case TInst(ctrl, grp):
				switch (ctrl.get().kind) {
					case KTypeParameter(idks):
						for (idk in idks) {
							return toComplexType(idk);
						}
						if (curTps != null && curTps.length > 0)
							for (ct in curTps) {
								if (ct.name == ctrl.get().name)
									return Context.toComplexType(t);
							}
						return toComplexType(TDynamic(null));
					case _:
						return TPath(toTypePath(ctrl.get(), grp));
				}
			case TLazy(f):
				return toComplexType(f());
			case TFun(args, ret):
				var newArgs: Array<ComplexType> = [];
				var newRet: ComplexType = toComplexType(ret);
				for (arg in args) {
					newArgs.push((arg.opt ? TOptional(toComplexType(arg.t)) : toComplexType(arg.t)));
				}
				return TFunction(newArgs, newRet);
			default:
		}
		return Context.toComplexType(t);
	}

	static function toTypeParam(type: Type): TypeParam
		return {
			switch (type) {
				case TInst(_.get() => {kind: KExpr(e)}, _): TPExpr(e);
				case _: TPType(toComplexType(type));
			}
		}

	static function toTypePath(baseType: BaseType, params: Array<Type>): TypePath
		return {
			var module = baseType.module;
			{
				pack: baseType.pack,
				name: module.substring(module.lastIndexOf(".") + 1),
				sub: baseType.name,
				params: [for (t in params) toTypeParam(t)],
			}
		}
}

typedef ChouxiangFunction = {
	var name: String;
	var args: Array<ChouxiangArg>;
	var typeParams: Array<TypeParamDecl>;
	var ret: ComplexType;
	var doThisReturn: Bool;
	var meta: Metadata;
}

typedef ChouxiangArg = {
	var name: String;
	var value: Null<Expr>;
	var ret: ComplexType;
}
#else
class ScriptedClassMacro {
	public static inline var SUPER_FUNCTION_PREFIX: String = "__SC_SUPER_";
}
#end
