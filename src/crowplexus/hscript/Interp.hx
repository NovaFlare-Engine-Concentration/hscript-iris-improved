/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package crowplexus.hscript;

import crowplexus.hscript.proxy.ProxyType;
import crowplexus.hscript.proxy.ProxyReflect;
import crowplexus.hscript.proxy.ProxyStd;
import Type.ValueType;
import crowplexus.hscript.Expr;
import crowplexus.hscript.Tools;
import crowplexus.iris.Iris;
import crowplexus.iris.IrisUsingClass;
import crowplexus.iris.utils.UsingEntry;
import haxe.Constraints.IMap;
import haxe.PosInfos;

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

@:structInit
class LocalVar {
	public var r: Dynamic;
	public var const: Bool;
}

@:structInit
class DirectorField {
	public var value: Dynamic;
	public var type: String;
	public var const: Bool;
	public var isInline: Bool;
	@:optional public var isPublic: Bool;
}

@:structInit
class DeclaredVar {
	public var n: String;
	public var old: LocalVar;
}

@:allow(crowplexus.hscript.PropertyAccessor)
@:allow(crowplexus.hscript.scriptclass.ScriptClassInterp)
class Interp {
	/**
	 * 还是觉得直接包装成静态更好一点（不模仿）
	 */
	public static var staticVariables: #if haxe3 Map<String, DirectorField> = new Map() #else Hash<DirectorField> = new Hash() #end;

	public inline static function getStaticVariable(name: String): Dynamic {
		if (staticVariables.get(name) != null)
			return staticVariables.get(name).value;
		return null;
	}

	private static var scriptClasses: #if haxe3 Map<String,
		crowplexus.hscript.scriptclass.ScriptClass> = new Map() #else Hash<crowplexus.hscript.scriptclass.ScriptClass> = new Hash() #end;
	private static var scriptEnums: #if haxe3 Map<String,
		crowplexus.hscript.scriptenum.ScriptEnum> = new Map() #else Hash<crowplexus.hscript.scriptenum.ScriptEnum> = new Hash() #end;

	/**
	 * 指定script class是否存在
	 * @param path		指定script class路径
	 */
	public static inline function existsScriptClass(path: String): Bool {
		return scriptClasses.exists(path);
	}

	/**
	 * 通过路径获取script class
	 * @param path		指定script class路径
	 */
	public static function resolveScriptClass(path: String): crowplexus.hscript.scriptclass.ScriptClass {
		if (scriptClasses.exists(path)) {
			return scriptClasses.get(path);
		}

		return null;
	}

	/**
	 * 指定script enum是否存在
	 * @param path		指定script enum路径
	 */
	public static inline function existsScriptEnum(path: String): Bool {
		return scriptEnums.exists(path);
	}

	/**
	 * 通过路径获取script enum
	 * @param path		指定script enum路径
	 */
	public static function resolveScriptEnum(path: String): crowplexus.hscript.scriptenum.ScriptEnum {
		if (scriptEnums.exists(path)) {
			return scriptEnums.get(path);
		}

		return null;
	}

	/**
	 * 清除已捕获的静态变量、script class、script enum
	 */
	public static function clearCache(): Void {
		staticVariables = #if haxe3 new Map() #else new Hash() #end;
		scriptClasses = #if haxe3 new Map() #else new Hash() #end;
		scriptEnums = #if haxe3 new Map() #else new Hash() #end;
		unpackClassCache = #if haxe3 new Map() #else new Hash() #end;
	}

	/**
	 * 用于限制script class的创建
	 */
	public var allowScriptClass: Bool;

	/**
	 * 用于限制script enum的创建
	 */
	public var allowScriptEnum: Bool;

	/**
	 * 你用了就是这个👍
	 */
	public var allowAbstractHappened: Bool;

	/**
	 * 返回值将会决定是否会颠覆原有的import体系
	 */
	public var importHandler: (String, String, Null<Bool>) -> Bool;

	#if haxe3
	// 懒得直接在代码上区分了，不如多开一个图来的划算
	public var directorFields: Map<String, DirectorField>;
	public var variables: Map<String, Dynamic>;
	public var imports: Map<String, Dynamic>;

	var locals: Map<String, LocalVar>;
	var binops: Map<String, Expr->Expr->Dynamic>;
	var propertyLinks: Map<String, PropertyAccessor>;
	#else
	public var directorFields: Hash<DirectorField>;
	public var variables: Hash<Dynamic>;
	public var imports: Hash<Dynamic>;

	var locals: Hash<LocalVar>;
	var binops: Hash<Expr->Expr->Dynamic>;
	var propertyLinks: Hash<PropertyAccessor>;
	#end

	/**
	 * 我不知道这是什么
	 */
	public var parentInstance(default, set): Dynamic;

	var _parentFields: Array<String> = [];

	@:dox(hide) function set_parentInstance(val: Dynamic): Dynamic {
		if (val != null) {
			switch (Type.typeof(val)) {
				case Type.ValueType.TObject if (!(val is Enum)):
					_parentFields = if (val is Class) Type.getClassFields(val); else Reflect.fields(val);
				case Type.ValueType.TClass(_):
					_parentFields = Type.getInstanceFields(Type.getClass(val));
				case _:
					// nothing
			}
		}

		if (_parentFields == null)
			_parentFields = [];

		return parentInstance = val;
	}

	var depth: Int;
	var inTry: Bool;
	var declared: Array<DeclaredVar>;
	var returnValue: Dynamic;

	var inFunction: Null<String>;
	var callTP: Bool;
	var fieldDotRet: Array<String> = [];
	var metas: Metadata = [];
	var converted: Array<Dynamic> = [];

	// 当字段为_时将会识别此值并捕获它（
	var added_value: Void->Dynamic = null;

	#if hscriptPos
	var curExpr: Expr;
	#end

	public var showPosOnLog: Bool = false;

	public function new() {
		#if haxe3
		locals = new Map();
		#else
		locals = new Hash();
		#end
		declared = new Array();
		resetVariables();
		initOps();
	}

	private function resetVariables() {
		#if haxe3
		propertyLinks = new Map();
		variables = new Map<String, Dynamic>();
		directorFields = new Map();
		imports = new Map<String, Dynamic>();
		#else
		propertyLinks = new Hash();
		variables = new Hash();
		directorFields = new Hash();
		imports = new Hash();
		#end

		variables.set("null", null);
		variables.set("true", true);
		variables.set("false", false);
		variables.set("trace", Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if (el.length > 0)
				inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos(): PosInfos {
		#if hscriptPos
		if (curExpr != null)
			return cast {fileName: curExpr.origin, lineNumber: curExpr.line};
		#end
		return cast {fileName: "hscript", lineNumber: 0};
	}

	function initOps() {
		var me = this;
		#if haxe3
		binops = new Map();
		#else
		binops = new Hash();
		#end
		binops.set("+", function(e1, e2) return me.expr(e1) + me.expr(e2));
		binops.set("-", function(e1, e2) return me.expr(e1) - me.expr(e2));
		binops.set("*", function(e1, e2) return me.expr(e1) * me.expr(e2));
		binops.set("/", function(e1, e2) return me.expr(e1) / me.expr(e2));
		binops.set("%", function(e1, e2) return me.expr(e1) % me.expr(e2));
		binops.set("&", function(e1, e2) return me.expr(e1) & me.expr(e2));
		binops.set("|", function(e1, e2) return me.expr(e1) | me.expr(e2));
		binops.set("^", function(e1, e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<", function(e1, e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>", function(e1, e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>", function(e1, e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==", function(e1, e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=", function(e1, e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=", function(e1, e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=", function(e1, e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">", function(e1, e2) return me.expr(e1) > me.expr(e2));
		binops.set("<", function(e1, e2) return me.expr(e1) < me.expr(e2));
		binops.set("is", function(e1, e2) {
			if (Tools.expr(e2).match(EIdent("Class")))
				return ProxyStd.isOfType(me.expr(e1), Class);
			if (Tools.expr(e2).match(EIdent("Enum")))
				return ProxyStd.isOfType(me.expr(e1), Enum);
			return ProxyStd.isOfType(me.expr(e1), me.expr(e2));
		});
		binops.set("||", function(e1, e2) return me.expr(e1) == true || me.expr(e2) == true);
		binops.set("&&", function(e1, e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("=", assign);
		binops.set("??", function(e1, e2) {
			var expr1: Dynamic = me.expr(e1);
			return expr1 == null ? me.expr(e2) : expr1;
		});
		binops.set("...", function(e1, e2) return new InterpIterator(me, e1, e2));
		assignOp("+=", function(v1: Dynamic, v2: Dynamic) return v1 + v2);
		assignOp("-=", function(v1: Float, v2: Float) return v1 - v2);
		assignOp("*=", function(v1: Float, v2: Float) return v1 * v2);
		assignOp("/=", function(v1: Float, v2: Float) return v1 / v2);
		assignOp("%=", function(v1: Float, v2: Float) return v1 % v2);
		assignOp("&=", function(v1, v2) return v1 & v2);
		assignOp("|=", function(v1, v2) return v1 | v2);
		assignOp("^=", function(v1, v2) return v1 ^ v2);
		assignOp("<<=", function(v1, v2) return v1 << v2);
		assignOp(">>=", function(v1, v2) return v1 >> v2);
		assignOp(">>>=", function(v1, v2) return v1 >>> v2);
		assignOp("??" + "=", function(v1, v2) return v1 == null ? v2 : v1);
	}

	public function setVar(name: String, v: Dynamic) {
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
		} else if (staticVariables.get(name) != null) {
			var l = staticVariables.get(name);
			if (l.const) {
				warn(ECustom("Cannot reassign final, for constant expression -> " + name));
			} else if (l.type == "func") {
				warn(ECustom("Cannot reassign function, for constant expression -> " + name));
			} else if (l.isInline) {
				warn(ECustom("Variables marked as inline cannot be rewritten -> " + name));
			} else {
				l.value = v;
			}
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

	function assign(e1: Expr, e2: Expr): Dynamic {
		var v = expr(e2);
		switch (Tools.expr(e1)) {
			case EIdent(id):
				var l = locals.get(id);
				if (l == null)
					setVar(id, v);
				else {
					if (l.const != true)
						l.r = v;
					else
						warn(ECustom("Cannot reassign final, for constant expression -> " + id));
				}
			case EField(e, f, s):
				fieldDotRet.push(f);
				var e = expr(e);
				fieldDotRet.pop();
				if (e == null)
					if (!s)
						error(EInvalidAccess(f));
					else
						return null;
				v = set(e, f, v);
			case EArray(e, index):
				var arr: Dynamic = expr(e);
				var index: Dynamic = expr(index);
				if (isMap(arr)) {
					setMapValue(arr, index, v);
				} else {
					arr[index] = v;
				}

			default:
				error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp(op, fop: Dynamic->Dynamic->Dynamic) {
		var me = this;
		binops.set(op, function(e1, e2) return me.evalAssignOp(op, fop, e1, e2));
	}

	function evalAssignOp(op, fop, e1, e2): Dynamic {
		var v;
		switch (Tools.expr(e1)) {
			case EIdent(id):
				var l = locals.get(id);
				v = fop(expr(e1), expr(e2));
				if (l == null)
					setVar(id, v)
				else {
					if (l.const != true)
						l.r = v;
					else
						warn(ECustom("Cannot reassign final, for constant expression -> " + id));
				}
			case EField(e, f, s):
				fieldDotRet.push(f);
				var obj = expr(e);
				fieldDotRet.pop();
				if (obj == null)
					if (!s)
						error(EInvalidAccess(f));
					else
						return null;
				v = fop(get(obj, f), expr(e2));
				v = set(obj, f, v);
			case EArray(e, index):
				var arr: Dynamic = expr(e);
				var index: Dynamic = expr(index);
				if (isMap(arr)) {
					v = fop(getMapValue(arr, index), expr(e2));
					setMapValue(arr, index, v);
				} else {
					v = fop(arr[index], expr(e2));
					arr[index] = v;
				}
			default:
				return error(EInvalidOp(op));
		}
		return v;
	}

	function increment(e: Expr, prefix: Bool, delta: Int): Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EIdent(id):
				var l = locals.get(id);
				var v: Dynamic = (l == null) ? resolve(id) : l.r;
				function setTo(a) {
					if (l == null)
						setVar(id, a)
					else {
						if (l.const != true)
							l.r = a;
						else
							error(ECustom("Cannot reassign final, for constant expression -> " + id));
					}
				}
				if (l == null) {
					if (prefix) {
						v += delta;
						setTo(v);
					} else
						setTo(v + delta);
				}
				return v;
			case EField(e, f, s):
				fieldDotRet.push(f);
				var obj = expr(e);
				fieldDotRet.pop();
				if (obj == null)
					if (!s)
						error(EInvalidAccess(f));
					else
						return null;
				var v: Dynamic = get(obj, f);
				if (prefix) {
					v += delta;
					set(obj, f, v);
				} else
					set(obj, f, v + delta);
				return v;
			case EArray(e, index):
				var arr: Dynamic = expr(e);
				var index: Dynamic = expr(index);
				if (isMap(arr)) {
					var v = getMapValue(arr, index);
					if (prefix) {
						v += delta;
						setMapValue(arr, index, v);
					} else {
						setMapValue(arr, index, v + delta);
					}
					return v;
				} else {
					var v = arr[index];
					if (prefix) {
						v += delta;
						arr[index] = v;
					} else
						arr[index] = v + delta;
					return v;
				}
			default:
				return error(EInvalidOp((delta > 0) ? "++" : "--"));
		}
	}

	public function execute(expr: Expr): Dynamic {
		added_value = null;
		metas = new Metadata();
		fieldDotRet = new Array<String>();
		converted = new Array<Dynamic>();
		callTP = false;
		depth = 0;
		#if haxe3
		locals = new Map();
		#else
		locals = new Hash();
		#end
		declared = new Array();
		return exprReturn(expr);
	}

	function exprReturn(e, returnDef: Bool = true): Dynamic {
		try {
			var dvalue = expr(e);
			if (returnDef)
				return dvalue;
		} catch (e:Stop) {
			switch (e) {
				case SBreak:
					throw "Invalid break";
				case SContinue:
					throw "Invalid continue";
				case SReturn:
					var v = returnValue;
					returnValue = null;
					return v;
			}
		}
		return null;
	}

	function duplicate<T>(h: #if haxe3 Map<String, T> #else Hash<T> #end) {
		#if haxe3
		var h2 = new Map();
		#else
		var h2 = new Hash();
		#end
		for (k in h.keys())
			h2.set(k, h.get(k));
		return h2;
	}

	function restore(old: Int) {
		while (declared.length > old) {
			var d = declared.pop();
			locals.set(d.n, d.old);
		}
	}

	inline function error(e: #if hscriptPos ErrorDef #else Error #end, rethrow = false): Dynamic {
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
		if (rethrow)
			this.rethrow(e)
		else
			throw e;
		return null;
	}

	inline function warn(e: #if hscriptPos ErrorDef #else Error #end): Dynamic {
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
		Iris.warn(Printer.errorToString(e, showPosOnLog), #if hscriptPos posInfos() #else null #end);
		return null;
	}

	inline function rethrow(e: Dynamic) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	@:noCompletion static var unpackClassCache: #if haxe3 Map<String, Dynamic> = new Map() #else Hash<Dynamic> = new Hash() #end;

	function resolve(id: String): Dynamic {
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

		if (staticVariables.get(id) != null)
			return staticVariables.get(id).value;

		if (variables.exists(id)) {
			var v = variables.get(id);
			return v;
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

		if (unpackClassCache.get(id) != null) {
			return unpackClassCache.get(id);
		} else {
			final cl = ProxyType.resolveClass(id);
			if (cl != null) {
				unpackClassCache.set(id, cl);
				return cl;
			}
		}

		error(EUnknownVariable(id));

		return null;
	}

	public function getOrImportClass(name: String): Dynamic {
		if (Iris.proxyImports.exists(name))
			return Iris.proxyImports.get(name);
		return Tools.getClass(name);
	}

	public function expr(e: Expr): Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EIgnore(_):
			case EConst(c):
				return switch (c) {
					case CInt(v): v;
					case CFloat(f): f;
					case CString(s, sm):
						if (sm != null && sm.length > 0) {
							var inPos = 0;
							for (m in sm) {
								if (m != null) {
									var ret = Std.string(expr(m.e));
									s = Printer.stringInsert(s, m.pos + inPos, ret);
									inPos += ret.length;
								}
							}
						}
						s;
					case CEReg(i, opt):
						new EReg(i, (opt != null ? opt : ""));
					case CSuper:
						if (fieldDotRet.length > 0)
							error(ECustom("Normal variables cannot be accessed with 'super', use 'this' instead"));
						else
							error(ECustom("Cannot use super as value"));
						null;
					#if !haxe3
					case CInt32(v): v;
					#end
				}
			case EIdent(id):
				if (id == "_" && added_value != null)
					return added_value();
				if (id == "false" && id == "true" && id == "null")
					return variables.get(id);
				return convertDouble(resolve(id));
			case EVar(n, de, _, v, getter, setter, isConst, ass):
				final me:Interp = this;

				if (getter == null)
					getter = "default";
				if (setter == null)
					setter = "default";

				var v = (v == null ? null : convertSimgle(expr(v)));
				if (ass != null && ass.contains("inline")) {
					var tv = Type.typeof(v);
					switch (tv) {
						case Type.ValueType.TNull | Type.ValueType.TFloat | Type.ValueType.TInt | Type.ValueType.TBool | Type.ValueType.TClass(String) | Type.ValueType.TClass(crowplexus.hscript.scriptenum.ScriptEnumValue) | Type.ValueType.TEnum(_):
						default:
							error(ECustom("Inline variable initialization must be a constant value"));
					}
			}
				if (ass != null && ass.contains("static")) {
					if (staticVariables.get(n) == null) {
						if (isConst)
							staticVariables.set(n, {
								value: v,
								type: "var",
								const: isConst,
								isInline: ass != null && ass.contains("inline")
							});
						else {
							staticVariables.set(n, {
								value: v,
								type: "var",
								const: isConst,
								isInline: ass != null && ass.contains("inline")
							});
							if (getter != "default" || setter != "default") {
								propertyLinks.set(n, new PropertyAccessor(this, () -> {
									if (staticVariables.get(n) != null)
										return staticVariables.get(n).value;
									else
										throw me.error(EUnknownVariable(n));
									return null;
								}, (val) -> {
									if (staticVariables.get(n) != null)
										staticVariables.get(n).value = val;
									else
										throw me.error(EUnknownVariable(n));
									return val;
								}, getter, setter, true));
							}
						}
					}
				} else {
					if (!isConst && de == 0 && (getter != "default" || setter != "default")) {
						directorFields.set(n, {
							value: v,
							const: isConst,
							type: "var",
							isInline: ass != null && ass.contains("inline"),
							isPublic: ass != null && ass.contains("public")
						});
						propertyLinks.set(n, new PropertyAccessor(this, () -> {
							if (directorFields.get(n) != null)
								return directorFields.get(n).value;
							else
								throw me.error(EUnknownVariable(n));
							return null;
						}, (val) -> {
							if (directorFields.get(n) != null)
								directorFields.get(n).value = val;
							else
								throw me.error(EUnknownVariable(n));
							return val;
						}, getter, setter));
					} else {
						if (de == 0) {
							directorFields.set(n, {
								value: v,
								const: isConst,
								type: "var",
								isInline: ass != null && ass.contains("inline"),
								isPublic: ass != null && ass.contains("public")
							});
						} else {
							declared.push({n: n, old: locals.get(n)});
							locals.set(n, {r: v, const: isConst});
						}
					}
				}
				return null;
			case ECast(e, t):
				return expr(e);
			case EParent(e):
				return expr(e);
			case EBlock(exprs):
				var old = declared.length;
				var v = null;
				for (e in exprs)
					v = expr(e);
				restore(old);
				return v;
			case EField(e, f, true):
				fieldDotRet.push(f);
				var e = expr(e);
				fieldDotRet.pop();
				if (e == null)
					return null;
				return convertDouble(get(e, f));
			case EField(e, f, false):
				fieldDotRet.push(f);
				var e = expr(e);
				fieldDotRet.pop();
				return convertDouble(get(e, f));
			case EBinop(op, e1, e2):
				var fop = binops.get(op);
				if (fop == null)
					error(EInvalidOp(op));
				return fop(e1, e2);
			case EUnop(op, prefix, e):
				return switch (op) {
					case "!":
						expr(e) != true;
					case "-":
						-expr(e);
					case "++":
						increment(e, prefix, 1);
					case "--":
						increment(e, prefix, -1);
					case "~":
						#if (neko && !haxe3)
						haxe.Int32.complement(expr(e));
						#else
						~expr(e);
						#end
					default:
						error(EInvalidOp(op));
						null;
				}
			case ECall(e, params):
				var args = new Array();

				callTP = true;
				var re: Dynamic = null;
				switch (Tools.expr(e)) {
					case EField(e, f, s):
						final sureSuper = Tools.expr(e).match(EConst(CSuper));
						var obj: Dynamic = null;
						if (!sureSuper) {
							fieldDotRet.push(f);
							obj = expr(e);
							fieldDotRet.pop();
						}
						if (obj == null && !sureSuper)
							if (!s)
								error(EInvalidAccess(f));
						if (sureSuper) {
							for (p in params) {
								args.push(expr(p));
							}
							re = super_field_call(f, args);
						} else if (f == "bind" && Reflect.isFunction(obj)) {
							var devs: Array<String> = [];
							var minParams: Int = 0;
							for (i => p in params) {
								args[i] = if (Tools.expr(p).match(EIdent("_"))) {
									devs[i] = "_";
									minParams++;
									null;
								} else {
									expr(p);
								}
							}
							re = Reflect.makeVarArgs(function(params: Array<Dynamic>) {
								if (params.length < minParams) {
									var str = "Invalid number of parameters. Got " + params.length + ", required " + minParams + " for function 'bind'";
									error(ECustom(str));
								}
								var forceArgs: Array<Dynamic> = [];
								for (i => arg in args) {
									if (devs[i] != null) {
										forceArgs.push(params.shift());
									} else {
										forceArgs.push(arg);
									}
								}
								return Reflect.callMethod(null, obj, forceArgs);
							});
						} else if (f == "match" && (Reflect.isEnumValue(obj) || obj is crowplexus.hscript.scriptenum.ScriptEnumValue)) {
							if (params.length != 1)
								error(ECustom("Invalid number of parameters. Got " + params.length + ", required " + 1 + " for function 'match'"));

							final scripting = (obj is crowplexus.hscript.scriptenum.ScriptEnumValue);
							re = doEnumMatch(obj, params[0], scripting);
						} else {
							for (p in params) {
								args.push(expr(p));
							}
							re = fcall(obj, f, args);
						}
					case EConst(CSuper):
						for (p in params)
							args.push(expr(p));
						re = super_call(args);
					default:
						for (p in params)
							args.push(expr(p));
						re = call(null, expr(e), args);
				}
				callTP = false;
				return convertDouble(re);
			case EIf(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else if (e2 == null) null else expr(e2);
			case EWhile(econd, e):
				whileLoop(econd, e);
				return null;
			case EDoWhile(econd, e):
				doWhileLoop(econd, e);
				return null;
			case EFor(v, it, e):
				forLoop(v, it, e);
				return null;
			case EForGen(it, e):
				Tools.getKeyIterator(it, function(vk, vv, it) {
					if (vk == null) {
						#if hscriptPos
						curExpr = it;
						#end
						error(ECustom("Invalid for expression"));
						return;
					}
					forKeyValueLoop(vk, vv, it, e);
				});
				return null;
			case EBreak:
				throw SBreak;
			case EContinue:
				throw SContinue;
			case EReturn(e):
				returnValue = e == null ? null : expr(e);
				throw SReturn;
			case EImport(v, as, star):
				if (importHandler != null && importHandler(v, as, star))
					return null;

				#if STAR_CLASSES
				if(star == true) {
					for(pa=>cl in Interp.scriptClasses) {
						final last = pa.lastIndexOf(".");
						final p = pa.substr(0, last > -1 ? last : 0);
						final cn = pa.substr(last > -1 ? last + 1 : 0);
						if(p == v) {
							if (Iris.blocklistImports.contains(cn)) {
								error(ECustom("You cannot add a blacklisted import, for class " + cn));
								return null;
							}

							if (!imports.exists(cn))
								imports.set(cn, cl);
						}
					}
					if(Iris.starPackageClasses.exists(v)) for(v in Iris.starPackageClasses[v]) {
						if (Iris.blocklistImports.contains(v.name)) {
							error(ECustom("You cannot add a blacklisted import, for class " + v.name));
							return null;
						}

						if (!imports.exists(v.name))
							imports.set(v.name, v.value);
					}
				} else
				#end
				{

					final aliasStr = (as != null ? " named " + as : ""); // for errors
					if (Iris.blocklistImports.contains(v)) {
						error(ECustom("You cannot add a blacklisted import, for class " + v + aliasStr));
						return null;
					}

					var n = Tools.last(v.split("."));
					if (imports.exists(n))
						return imports.get(n);

					var c: Dynamic = getOrImportClass(v);
					if (c == null) {
						if (allowAbstractHappened && v.lastIndexOf(".") > 0) {
							var subv: String = v.substr(0, v.lastIndexOf("."));
							var suffix: Array<String> = [v.substr(v.lastIndexOf(".") + 1)];
							var subc: Dynamic = getOrImportClass(subv);
							while (subv.lastIndexOf(".") > 0 && subc == null) {
								suffix.push(subv.substr(subv.lastIndexOf(".") + 1));
								subv = subv.substr(0, subv.lastIndexOf("."));
								subc = ProxyType.resolveClass(subv);
							}

							if (subc != null) {
								if (suffix.length > 1)
									return warn(ECustom("Class '" + subv + "' does not define field -> '" + suffix.join(".") + "'"));

								var fields: Array<String> = ProxyType.getClassFields(subc).concat(ProxyReflect.fields(subc));
								var fv: Dynamic = ProxyReflect.getProperty(subc, suffix[0]);
								if (fields.contains(suffix[0])
									|| (!(subc is crowplexus.hscript.scriptclass.ScriptClass) && fields.contains("get_" + suffix[0]))
									|| fv != null) {
									imports.set((as != null ? as : suffix[0]), fv);
									return null;
								} else {
									return warn(ECustom("Class '" + subv + "' does not define field -> '" + suffix.join(".") + "'"));
								}
							}
						}
						return warn(ECustom("Import" + aliasStr + " of class " + v + " could not be added"));
					} else {
						imports.set(n, c);
						if (as != null)
							imports.set(as, c);
						// resembles older haxe versions where you could use both the alias and the import
						// for all the "Colour" enjoyers :D
					}
					return null; // yeah. -Crow
				}

			case EFunction(params, fexpr, _, name, _, ass):
				var capturedLocals = duplicate(locals);
				var me = this;
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
							if (name != null)
								str += " for function '" + name + "'";
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
					var old = me.locals, depth = me.depth;
					me.depth++;
					me.locals = me.duplicate(capturedLocals);
					for (i in 0...params.length)
						me.locals.set(params[i].name, {r: convertSimgle(args[i]), const: false});
					var r = null;
					var oldDecl = declared.length;

					final of: Null<String> = inFunction;
					if (name != null)
						inFunction = name;
					else
						inFunction = "(*unamed)";
					if (inTry)
						try {
							r = me.exprReturn(fexpr, false);
						} catch (e:Dynamic) {
							me.locals = old;
							me.depth = depth;
							#if neko
							neko.Lib.rethrow(e);
							#else
							throw e;
							#end
						}
					else {
						r = me.exprReturn(fexpr, false);
					}
					inFunction = of;

					restore(oldDecl);
					me.locals = old;
					me.depth = depth;
					return r;
				};
				var f = Reflect.makeVarArgs(f);
				if (name != null) {
					if (depth == 0) {
						// global function
						if (ass != null && ass.contains("static")) {
							if (staticVariables.get(name) == null)
								staticVariables.set(name, {
									value: f,
									type: "func",
									const: false,
									isInline: ass != null && ass.contains("inline")
								});
						} else {
							directorFields.set(name, {
								value: f,
								type: "func",
								const: false,
								isInline: ass != null && ass.contains("inline")
							});
						}
					} else {
						// function-in-function is a local function
						declared.push({n: name, old: locals.get(name)});
						var ref: LocalVar = {r: f, const: false};
						locals.set(name, ref);
						capturedLocals.set(name, ref); // allow self-recursion
					}
				}
				return f;
			case EArrayDecl(arr):
				if (arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _))) {
					var keys = [];
					var values = [];
					for (e in arr) {
						switch (Tools.expr(e)) {
							case EBinop("=>", eKey, eValue):
								keys.push(expr(eKey));
								values.push(expr(eValue));
							default:
								#if hscriptPos
								curExpr = e;
								#end
								error(ECustom("Invalid map key=>value expression"));
						}
					}
					return makeMap(keys, values);
				} else {
					var a = new Array();
					for (e in arr)
						a.push(expr(e));
					return a;
				}
			case EArray(e, index):
				var arr: Dynamic = expr(e);
				var index: Dynamic = expr(index);
				var re: Dynamic = if (isMap(arr)) {
					getMapValue(arr, index);
				} else {
					arr[index];
				};
				return convertDouble(re);
			case ENew(cl, params):
				var a = new Array();
				for (e in params) {
					a.push(expr(e));
				}
				var re = cnew((cl.pack != null && cl.pack.length > 0 ? cl.pack.join(".") + "." : "") + cl.name, a);
				return convertDouble(re);
			case EThrow(e):
				throw expr(e);
			case ETry(e, n, _, ecatch):
				var old = declared.length;
				var oldTry = inTry;
				try {
					inTry = true;
					var v: Dynamic = expr(e);
					restore(old);
					inTry = oldTry;
					return v;
				} catch (err:Stop) {
					inTry = oldTry;
					throw err;
				} catch (err:Dynamic) {
					// restore vars
					restore(old);
					inTry = oldTry;
					// declare 'v'
					declared.push({n: n, old: locals.get(n)});
					locals.set(n, {r: err, const: false});
					var v: Dynamic = expr(ecatch);
					restore(old);
					return v;
				}
			case EObject(fl):
				var o = {};
				for (f in fl) {
					set(o, f.name, expr(f.e));
				}
				return o;
			case ETernary(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else expr(e2);
			case ESwitch(e, cases, def):
				var val: Dynamic = expr(e);
				final typeof: Type.ValueType = Type.typeof(val);
				var match = false;
				var old = duplicate(locals);

				for (c in cases) {
					for (v in c.values) {
						var cond: Bool = stackPatternMatch(val, v, c, typeof);
						if (cond) {
							match = true;
							break;
						}
					}
					if (match) {
						val = expr(c.expr);
						locals = old;
						break;
					}
					locals = old;
				}
				if (!match)
					val = def == null ? null : expr(def);
				return val;
			case EMeta(n, params, e):
				metas.push(cast {name: n, params: params});
				var e = expr(e);
				metas.pop();
				return e;
			case ECheckType(e, _):
				return expr(e);
			case EClass(clName, exName, imName, fields, pkg):
				if (!allowScriptClass) {
					warn(ECustom("Cannot create class because it is not supported"));
					return null;
				}
				var fullPath = (pkg != null && pkg.length > 0 ? pkg.join(".") + "." + clName : clName);
				if (!scriptClasses.exists(fullPath))
					registerScriptClass(clName, exName, fields, metas, pkg);
			case EEnum(enumName, fields, pkg):
				if (!this.allowScriptEnum) {
					warn(ECustom("Cannot create enum because it is not supported"));
					return null;
				}
				var fullPath = (pkg != null && pkg.length > 0 ? pkg.join(".") + "." + enumName : enumName);
				if (!scriptEnums.exists(fullPath))
					registerScriptEnum(enumName, fields, pkg);
			case EDirectValue(value):
				return value;
			case EUsing(name):
				useUsing(name);
		}
		return null;
	}

	private function stackPatternMatch(matched: Dynamic, match: Expr, casse: SwitchCase, typeof: Type.ValueType, ?inArg: Bool = false): Bool {
		if (matched == null || match == null)
			return false;

		var realMatch = false;
		switch (typeof) {
			case Type.ValueType.TClass(Array):
				switch (Tools.expr(match)) {
					case EParent(e):
						realMatch = stackPatternMatch(matched, e, casse, typeof, inArg);
					case EArrayDecl(es):
						if (es.length == matched.length) {
							realMatch = true;
							for (i => e in es) {
								switch (Tools.expr(e)) {
									case EIdent(id) if (id != "false" && id != "true" && id != "trace"):
										if (id != "_") {
											locals.set(id, {r: matched[i], const: false});
										}
									case _:
										if (!stackPatternMatch(matched[i], e, casse, Type.typeof(matched[i]), true)) {
											realMatch = false;
										}
								}
							}
						}
					case _:
						if ((!Type.enumEq(Tools.expr(match), EIdent("_")) && Tools.valueSwitchMatch(expr(match), matched))
							&& (casse.ifExpr == null || expr(casse.ifExpr) == true)) return true;
				}
				if (realMatch && (casse.ifExpr == null || expr(casse.ifExpr) == true)) {
					return true;
				}
			case Type.ValueType.TObject if (!(matched is Class || matched is Enum)):
				switch (Tools.expr(match)) {
					case EParent(e):
						realMatch = stackPatternMatch(matched, e, casse, typeof, inArg);
					case EObject(obs):
						var fields: Array<String> = Reflect.fields(matched);
						fields.sort((o, t) -> Reflect.compare(o, t));

						final mfields: Array<String> = [for (ob in obs) ob.name];
						mfields.sort((o, t) -> Reflect.compare(o, t));
						if (Tools.valueSwitchMatch(fields, mfields)) {
							realMatch = true;
							for (ob in obs) {
								switch (Tools.expr(ob.e)) {
									case EIdent(id) if (id != "false" && id != "true" && id != "trace"):
										if (id != "_") {
											locals.set(id, {r: Reflect.getProperty(matched, ob.name), const: false});
										}
									case _:
										var med: Dynamic = Reflect.getProperty(matched, ob.name);
										if (!stackPatternMatch(med, ob.e, casse, Type.typeof(med), true)) {
											realMatch = false;
										}
								}
							}
						}
					case _:
						if ((!Type.enumEq(Tools.expr(match), EIdent("_")) && Tools.valueSwitchMatch(expr(match), matched))
							&& (casse.ifExpr == null || expr(casse.ifExpr) == true)) return true;
				}
				if (realMatch && (casse.ifExpr == null || expr(casse.ifExpr) == true)) {
					return true;
				}
			case Type.ValueType.TEnum(_):
				switch (Tools.expr(match)) {
					case EParent(e):
						realMatch = stackPatternMatch(matched, e, casse, typeof, inArg);
					case ECall(e, args):
						final matchedRootEnum: Enum<Dynamic> = Type.getEnum(matched);
						final matchedRoot: Dynamic = Reflect.getProperty(matchedRootEnum, Type.enumConstructor(matched));
						var matchedArgs: Array<Dynamic> = Type.enumParameters(matched) ?? [];

						var ne: Dynamic = expr(e);
						final kindFunction: Bool = (Reflect.isFunction(ne) && Reflect.isFunction(matchedRoot));
						if (matchedArgs.length > 0 && kindFunction && Reflect.compareMethods(ne, matchedRoot)) {
							realMatch = true;
							if (args != null) {
								for (i => arg in args) {
									switch (Tools.expr(arg)) {
										case EIdent(id) if (id != "false" && id != "true" && id != "trace"):
											if (id != "_") {
												locals.set(id, {r: matchedArgs[i], const: false});
											}
										case _:
											if (!stackPatternMatch(matchedArgs[i], arg, casse, Type.typeof(matchedArgs[i]), true)) {
												realMatch = false;
											}
									}
								}
							}
						}
					case _:
						if ((!Type.enumEq(Tools.expr(match), EIdent("_")) && Tools.valueSwitchMatch(expr(match), matched))
							&& (casse.ifExpr == null || expr(casse.ifExpr) == true)) return true;
				}
				if (realMatch && (casse.ifExpr == null || expr(casse.ifExpr) == true)) {
					return true;
				}
			case Type.ValueType.TClass(crowplexus.hscript.scriptenum.ScriptEnumValue):
				switch (Tools.expr(match)) {
					case EParent(e):
						realMatch = stackPatternMatch(matched, e, casse, typeof, inArg);
					case ECall(e, args):
						final matchedRootEnum: crowplexus.hscript.scriptenum.ScriptEnum = ProxyType.getEnum(matched);
						final matchedRoot: Dynamic = ProxyReflect.getProperty(matchedRootEnum, ProxyType.enumConstructor(matched));
						var matchedArgs: Array<Dynamic> = matched.getConstructorArgs();

						var ne: Dynamic = expr(e);
						final kindFunction: Bool = (Reflect.isFunction(ne) && Reflect.isFunction(matchedRoot));
						if (matchedArgs.length > 0 && kindFunction && Reflect.compareMethods(ne, matchedRoot)) {
							realMatch = true;
							if (args != null) {
								for (i => arg in args) {
									switch (Tools.expr(arg)) {
										case EIdent(id) if (id != "false" && id != "true" && id != "trace"):
											if (id != "_") {
												locals.set(id, {r: matchedArgs[i], const: false});
											}
										case _:
											if (!stackPatternMatch(matchedArgs[i], arg, casse, Type.typeof(matchedArgs[i]), true)) {
												realMatch = false;
											}
									}
								}
							}
						}
					case _:
						if ((!Type.enumEq(Tools.expr(match), EIdent("_")) && Tools.valueSwitchMatch(expr(match), matched))
							&& (casse.ifExpr == null || expr(casse.ifExpr) == true)) return true;
				}
				if (realMatch && (casse.ifExpr == null || expr(casse.ifExpr) == true)) {
					return true;
				}
			default:
				if (inArg)
					switch (Tools.expr(match)) {
						case EBinop("=>", e1, e2):
							added_value = () -> matched;
							var value: Dynamic = expr(e1);
							added_value = null;
							switch (Tools.expr(e2)) {
								case EIdent(id) if (id != "false" && id != "true" && id != "trace"):
									if (id != "_") {
										locals.set(id, {r: value, const: false});
									}
								case _:
							}
							return true;
						case _:
					}
				if ((!Type.enumEq(Tools.expr(match), EIdent("_")) && Tools.valueSwitchMatch(expr(match), matched))
					&& (casse.ifExpr == null || expr(casse.ifExpr) == true))
					return true;
		}

		return false;
	}

	function convertSimgle(v: Dynamic): Dynamic {
		if (converted.length > 0) {
			var sb: Dynamic = converted.pop();
			if (sb is ISharedScript) {
				if (v == cast(sb, ISharedScript).standard)
					v = sb;
			} else if (sb is crowplexus.hscript.scriptclass.ScriptClassInstance) {
				if (v == cast(sb, crowplexus.hscript.scriptclass.ScriptClassInstance).superClass)
					v = sb;
			}
		}

		var i: Int = -1;
		while (i++ < converted.length - 1) {
			converted.pop();
		}
		return v;
	}

	function convertDouble(re: Dynamic): Dynamic {
		if (fieldDotRet.length == 0) {
			if (re is crowplexus.hscript.scriptclass.ScriptClassInstance) {
				var cls: crowplexus.hscript.scriptclass.ScriptClassInstance = cast(re, crowplexus.hscript.scriptclass.ScriptClassInstance);
				if (cls.superClass != null) {
					converted.push(cls);
					return cls.superClass;
				}
			} else if (re is ISharedScript) {
				converted.push(re);
				return cast(re, ISharedScript).standard;
			}
		}
		return re;
	}

	function registerScriptClass(clName:String, exName:Null<String>, fields:Array<BydFieldDecl>, metas:Metadata, ?pkg:Array<String>) {
		var cl = new crowplexus.hscript.scriptclass.ScriptClass(this, clName, exName, fields, metas, pkg);
		scriptClasses.set(cl.fullPath, cl);
		imports.set(clName, cl);
	}

	function registerScriptEnum(enumName:String, fields:Array<EnumType>, ?pkg:Array<String>) {
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
		scriptEnums.set(obj.fullPath, obj);
		imports.set(enumName, obj);
	}

	function super_call(args: Array<Dynamic>): Dynamic {
		error(ECustom("invalid super()"));
		return null;
	}

	function super_field_call(field: String, args: Array<Dynamic>): Dynamic {
		error(ECustom("invalid super." + field + "()"));
		return null;
	}

	function doWhileLoop(econd, e) {
		var old = declared.length;
		do {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		} while (expr(econd) == true);
		restore(old);
	}

	function whileLoop(econd, e) {
		var old = declared.length;
		while (expr(econd) == true) {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		}
		restore(old);
	}

	/**
	 * 点击输入文本
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L568
	 */
	function makeIterator(v: Dynamic): Iterator<Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if (v is Array)
			return (v : Array<Dynamic>).iterator();
		if (v.iterator != null)
			v = v.iterator();
		#else
		try
			v = v.iterator()
		catch (e:Dynamic) {};
		#end
		if (v.hasNext == null || v.next == null)
			error(EInvalidIterator(v));
		return v;
	}

	/**
	 * 点击输入文本
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L581
	 */
	function makeKeyValueIterator(v: Dynamic): KeyValueIterator<Dynamic, Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if (v is Array)
			return (v : Array<Dynamic>).keyValueIterator();
		if (v.keyValueIterator != null)
			v = v.keyValueIterator();
		#else
		#if cpp
		// i need convert type to get map's keyValueIterator in cpp. (yeh
		if (isMap(v)) {
			v = cast(v, IMap<Dynamic, Dynamic>).keyValueIterator();
		} else
		#end
		try
			v = v.keyValueIterator()
		catch (e:Dynamic) {};
		#end
		if (v.hasNext == null || v.next == null)
			error(EInvalidIterator(v));
		return v;
	}

	/**
	 * 点击输入文本
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L594
	 */
	function forLoop(n, it, e) {
		var old = declared.length;
		declared.push({n: n, old: locals.get(n)});
		var it = makeIterator(expr(it));
		while (it.hasNext()) {
			locals.set(n, {r: it.next(), const: false});
			if (!loopRun(() -> expr(e)))
				break;
		}
		restore(old);
	}

	/**
	 * 点击输入文本
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L606
	 */
	function forKeyValueLoop(vk, vv, it, e) {
		var old = declared.length;
		declared.push({n: vk, old: locals.get(vk)});
		declared.push({n: vv, old: locals.get(vv)});
		var it = makeKeyValueIterator(expr(it));
		while (it.hasNext()) {
			var v = it.next();
			locals.set(vk, {r: v.key, const: false});
			locals.set(vv, {r: v.value, const: false});
			if (!loopRun(() -> expr(e)))
				break;
		}
		restore(old);
	}

	/**
	 * 点击输入文本
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L621
	 */
	inline function loopRun(f: Void->Void) {
		var cont = true;
		try {
			f();
		} catch (err:Stop) {
			switch (err) {
				case SContinue:
				case SBreak:
					cont = false;
				case SReturn:
					throw err;
			}
		}
		return cont;
	}

	inline function isMap(o: Dynamic): Bool {
		return (o is IMap);
	}

	inline function getMapValue(map: Dynamic, key: Dynamic): Dynamic {
		return cast(map, IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map: Dynamic, key: Dynamic, value: Dynamic): Void {
		cast(map, IMap<Dynamic, Dynamic>).set(key, value);
	}

	/**
	 * 对不起，我又干了（
	 * @see https://github.com/HaxeFoundation/hscript/blob/master/hscript/Interp.hx#L649
	 */
	function makeMap(keys: Array<Dynamic>, values: Array<Dynamic>): Dynamic {
		var isAllString: Bool = true;
		var isAllInt: Bool = true;
		var isAllObject: Bool = true;
		var isAllEnum: Bool = true;
		for (key in keys) {
			isAllString = isAllString && (key is String);
			isAllInt = isAllInt && (key is Int);
			isAllObject = isAllObject && Reflect.isObject(key);
			isAllEnum = isAllEnum && Reflect.isEnumValue(key);
		}
		if (isAllInt) {
			var m = new Map<Int, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllString) {
			var m = new Map<String, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllEnum) {
			var m = new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllObject) {
			var m = new Map<{}, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		error(ECustom("Invalid map keys " + keys));
		return null;
	}

	function doEnumMatch(matched: Dynamic, match: Expr, scripted: Bool): Bool {
		if (matched == null || match == null)
			return false;
		switch (Tools.expr(match)) {
			case EParent(e):
				return doEnumMatch(matched, e, scripted);
			case ECall(e, args):
				var oargs: Array<Dynamic> = ProxyType.enumParameters(matched) ?? [];
				var e = expr(e);
				var obj: Dynamic = ProxyReflect.getProperty(ProxyType.getEnum(matched), ProxyType.enumConstructor(matched));
				if (Reflect.compareMethods(e, obj)) {
					var ids: Array<Bool> = [];
					for (i => arg in args) {
						switch (Tools.expr(arg)) {
							case EIdent(id) if (id == "_"):
								ids.push(true);
							case _:
								ids.push(doEnumMatch(oargs[i], arg, (oargs[i] is crowplexus.hscript.scriptenum.ScriptEnumValue)));
						}
					}
					return !ids.contains(false);
				}
				return false;
			case _:
				var arg: Dynamic = expr(match);
				return if (scripted) cast(matched, crowplexus.hscript.scriptenum.ScriptEnumValue).compare(arg); else Type.enumEq(matched, arg);
		}
	}

	function get(o: Dynamic, f: String): Dynamic {
		if (o == null)
			error(EInvalidAccess(f));
		if (o is crowplexus.hscript.scriptclass.BaseScriptClass)
			return cast(o, crowplexus.hscript.scriptclass.BaseScriptClass).sc_get(f, true, true);
		/*@:privateAccess if (o is crowplexus.hscript.scriptclass.IScriptedClass)
			return o.__sc_standClass.sc_get(f); */
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

	function set(o: Dynamic, f: String, v: Dynamic): Dynamic {
		if (o == null)
			error(EInvalidAccess(f));
		@:privateAccess
		if (o is crowplexus.hscript.scriptclass.BaseScriptClass)
			cast(o, crowplexus.hscript.scriptclass.BaseScriptClass).sc_set(f, v);
		else if (o is ISharedScript)
			cast(o, ISharedScript).hset(f, v);
		else
			Reflect.setProperty(o, f, v);
		return v;
	}

	/**
	 * Meant for people to add their own usings.
	**/
	function registerUsingLocal(name: String, call: UsingCall): UsingEntry {
		var entry = new UsingEntry(name, call);
		usings.push(entry);
		return entry;
	}

	function useUsing(name: String): Void {
		for (us in Iris.registeredUsingEntries) {
			if (us.name == name) {
				if (usings.indexOf(us) == -1)
					usings.push(us);
				return;
			}
		}

		var cls = Tools.getClass(name);
		if (cls != null) {
			var fieldName = '__irisUsing_' + StringTools.replace(name, ".", "_");
			if (Reflect.hasField(cls, fieldName)) {
				var fields = Reflect.field(cls, fieldName);
				if (fields == null)
					return;

				var entry = new UsingEntry(name, function(o: Dynamic, f: String, args: Array<Dynamic>): IrisCall {
					if (!fields.exists(f))
						return null;
					var type: ValueType = Type.typeof(o);
					var valueType: ValueType = fields.get(f);

					// If we figure out a better way to get the types as the real ValueType, we can use this instead
					// if (Type.enumEq(valueType, type))
					//	return Reflect.callMethod(cls, Reflect.field(cls, f), [o].concat(args));

					var canCall = valueType == null ? true : switch (valueType) {
						case TEnum(null):
							type.match(TEnum(_));
						case TClass(null):
							type.match(TClass(_));
						case TClass(IMap): // if we don't check maps like this, it just doesn't work
							type.match(TClass(IMap) | TClass(haxe.ds.ObjectMap) | TClass(haxe.ds.StringMap) | TClass(haxe.ds.IntMap) | TClass(haxe.ds.EnumValueMap));
						default:
							Type.enumEq(type, valueType);
					}

					return canCall ? {funName: f, signature: cls, returnValue: Reflect.callMethod(cls, Reflect.getProperty(cls, f), [o].concat(args))} : null;
				});

				#if IRIS_DEBUG
				trace("Registered macro based using entry for " + name);
				#end

				Iris.registeredUsingEntries.push(entry);
				usings.push(entry);
				return;
			}

			// Use reflection to generate the using entry
			var entry = new UsingEntry(name, function(o: Dynamic, f: String, args: Array<Dynamic>): Dynamic {
				if (!Reflect.hasField(cls, f))
					return null;
				var field = Reflect.field(cls, f);
				if (!Reflect.isFunction(field))
					return null;

				// invalid if the function has no arguments
				var totalArgs = Tools.argCount(field);
				if (totalArgs == 0)
					return null;

				// todo make it check if the first argument is the correct type

				return Reflect.callMethod(cls, field, [o].concat(args));
			});

			#if IRIS_DEBUG
			trace("Registered reflection based using entry for " + name);
			#end

			Iris.registeredUsingEntries.push(entry);
			usings.push(entry);
			return;
		}
		warn(ECustom("Unknown using class " + name));
	}

	/**
	 * List of components that allow using static methods on objects.
	 * This only works if you do
	 * ```haxe
	 * var result = "Hello ".trim();
	 * ```
	 * and not
	 * ```haxe
	 * var trim = "Hello ".trim;
	 * var result = trim();
	 * ```
	 */
	var usings: Array<UsingEntry> = [];

	function fcall(o: Dynamic, f: String, args: Array<Dynamic>): Dynamic {
		for (_using in usings) {
			var v = _using.call(o, f, args);
			if (v != null) {
				return v.returnValue;
			}
		}

		return {
			final func: Dynamic = get(o, f);
			if (!Reflect.isFunction(func))
				error(ECustom("Invalid Function -> '" + f + "'"));
			call(o, func, args);
		}
	}

	function call(o: Dynamic, f: Dynamic, args: Array<Dynamic>): Dynamic {
		return Reflect.callMethod(o, f, args);
	}

	function cnew(cl: String, args: Array<Dynamic>): Dynamic {
		var c: Null<Dynamic> = ProxyType.resolveClass(cl);
		if (c == null)
			c = resolve(cl);
		if (c == null)
			error(ECustom("Cannot Create Instance By '" + cl + "', Invlalid Class."));
		return ProxyType.createInstance(c, args);
	}
}
