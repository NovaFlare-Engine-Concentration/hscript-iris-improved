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

import crowplexus.hscript.Expr;
import crowplexus.hscript.scriptenum.ScriptEnumValue;
import crowplexus.hscript.proxy.ProxyType;
import Type.ValueType;

class Tools {
	public static function iter(e: Expr, f: Expr->Void) {
		switch (expr(e)) {
			case EConst(_), EIdent(_):
			case EVar(_, _, _, e, getter, setter, _, s):
				if (e != null)
					f(e);
			case EParent(e):
				f(e);
			case EBlock(el):
				for (e in el)
					f(e);
			case EField(e, _):
				f(e);
			case EBinop(_, e1, e2):
				f(e1);
				f(e2);
			case EUnop(_, _, e):
				f(e);
			case ECall(e, args):
				f(e);
				for (a in args)
					f(a);
			case EIf(c, e1, e2):
				f(c);
				f(e1);
				if (e2 != null)
					f(e2);
			case EWhile(c, e):
				f(c);
				f(e);
			case EDoWhile(c, e):
				f(c);
				f(e);
			case EFor(_, it, e):
				f(it);
				f(e);
			case EBreak, EContinue:
			case EFunction(_, e, _, _, _, s):
				f(e);
			case EReturn(e):
				if (e != null)
					f(e);
			case EArray(e, i):
				f(e);
				f(i);
			case EArrayDecl(el):
				for (e in el)
					f(e);
			case ENew(_, el):
				for (e in el)
					f(e);
			case EThrow(e):
				f(e);
			case ETry(e, _, _, c):
				f(e);
				f(c);
			case EObject(fl):
				for (fi in fl)
					f(fi.e);
			case ETernary(c, e1, e2):
				f(c);
				f(e1);
				f(e2);
			case ESwitch(e, cases, def):
				f(e);
				for (c in cases) {
					for (v in c.values)
						f(v);
					f(c.expr);
				}
				if (def != null)
					f(def);
			case EMeta(name, args, e):
				if (args != null)
					for (a in args)
						f(a);
				f(e);
			case ECheckType(e, _):
				f(e);
			default:
		}
	}

	public static function map(e: Expr, f: Expr->Expr) {
		var edef = switch (expr(e)) {
			case EConst(_), EIdent(_), EBreak, EContinue: expr(e);
			case EVar(n, d, t, e, c): EVar(n, d, t, if (e != null) f(e) else null, c);
			case EParent(e): EParent(f(e));
			case EBlock(el): EBlock([for (e in el) f(e)]);
			case EField(e, fi, s): EField(f(e), fi, s);
			case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
			case EUnop(op, pre, e): EUnop(op, pre, f(e));
			case ECall(e, args): ECall(f(e), [for (a in args) f(a)]);
			case EIf(c, e1, e2): EIf(f(c), f(e1), if (e2 != null) f(e2) else null);
			case EWhile(c, e): EWhile(f(c), f(e));
			case EDoWhile(c, e): EDoWhile(f(c), f(e));
			case EFor(v, it, e): EFor(v, f(it), f(e));
			case EFunction(args, e, de, name, t): EFunction(args, f(e), de, name, t);
			case EReturn(e): EReturn(if (e != null) f(e) else null);
			case EArray(e, i): EArray(f(e), f(i));
			case EArrayDecl(el): EArrayDecl([for (e in el) f(e)]);
			case ENew(cl, el): ENew(cl, [for (e in el) f(e)]);
			case EThrow(e): EThrow(f(e));
			case ETry(e, v, t, c): ETry(f(e), v, t, f(c));
			case EObject(fl): EObject([for (fi in fl) {name: fi.name, e: f(fi.e)}]);
			case ETernary(c, e1, e2): ETernary(f(c), f(e1), f(e2));
			case ESwitch(e, cases, def): ESwitch(f(e), [
					for (c in cases)
						{values: [for (v in c.values) f(v)], expr: f(c.expr), ifExpr: f(c.ifExpr)}
				], def == null ? null : f(def));
			case EMeta(name, args, e): EMeta(name, args == null ? null : [for (a in args) f(a)], f(e));
			case ECheckType(e, t): ECheckType(f(e), t);
			default: #if hscriptPos e.e #else e #end;
		}
		return mk(edef, e);
	}

	public static inline function expr(e: Expr): ExprDef {
		return #if hscriptPos e.e #else e #end;
	}

	public static inline function mk(e: ExprDef, p: Expr) {
		#if hscriptPos
		return {
			e: e,
			pmin: p.pmin,
			pmax: p.pmax,
			origin: p.origin,
			line: p.line
		};
		#else
		return e;
		#end
	}

	public static inline function uppercased(sb: String, pos: Int = 0): Bool {
		return sb.charAt(pos) == sb.charAt(pos).toUpperCase();
	}

	public static function removeInnerClass(name: String): String {
		var ll = name.lastIndexOf(".");
		if (name.indexOf(".") != ll) { // checks if there are 2 or more dots
			// wtf did i make -neo
			// this is awesome -crow
			return name.substr(0, name.lastIndexOf(".", ll - 1)) + "." + name.substr(ll + 1);
		}
		// only one dot or no dots (will work since -1 + 1 = 0)
		return name.substr(ll + 1);
	}

	public static function getClass(name: String): Dynamic {
		var c: Dynamic = ProxyType.resolveClass(name);
		if (c == null) // try importing as enum
			c = ProxyType.resolveEnum(name);
		if(c == null)
			c = Interp.typesAlias.get(name);

		if (c == null) {
			// lastly try removing any inner class from it
			// this allows you to import stuff like
			// flixel.text.FlxText.FlxTextBorderStyle
			// without the script crashing immediately
			var className = removeInnerClass(name);
			if (className != name) {
				c = ProxyType.resolveClass(className);
				if (c == null)
					c = ProxyType.resolveEnum(className);
				if (c == null) c = Interp.typesAlias.get(name);
			}
		}
		return c;
	}

	// SwitchMatch过法写意居权
	public static function valueSwitchMatch(val1: Dynamic, val2: Dynamic): Bool {
		return switch ([Type.typeof(val1), Type.typeof(val2)]) {
			case [TClass(Array), TClass(Array)]:
				var pass: Bool = false;
				if (val1.length == val2.length) {
					pass = true;
					var i = -1;
					while (i++ < val1.length - 1) {
						final bean = valueSwitchMatch(val1[i], val2[i]);
						if (!bean) {
							pass = false;
							break;
						}
					}
				}
				pass;
			case [TClass(ScriptEnumValue), TClass(ScriptEnumValue)]:
				ProxyType.enumEq(val1, val2);
			case [TObject, TObject] if (!(val1 is Class || val1 is Enum) && !(val2 is Class || val2 is Enum)):
				var pass: Bool = false;
				if (valueSwitchMatch(Reflect.fields(val1), Reflect.fields(val2))) {
					pass = true;
					for (field in Reflect.fields(val1)) {
						final bean = valueSwitchMatch(Reflect.getProperty(val1, field), Reflect.getProperty(val2, field));
						if (!bean) {
							pass = false;
							break;
						}
					}
				}
				pass;
			case [TFunction, TFunction]:
				Reflect.compareMethods(val1, val2);
			case [TEnum(a), TEnum(b)] if (a == b):
				Type.enumEq(val1, val2);
			case _:
				val1 == val2;
		};
	}

	public static inline function getKeyIterator<T>(e: Expr, callb: String->String->Expr->T) {
		var key = null, value = null, it = e;
		switch (expr(it)) {
			case EBinop("in", ekv, eiter):
				switch (expr(ekv)) {
					case EBinop("=>", v1, v2):
						switch ([expr(v1), expr(v2)]) {
							case [EIdent(v1), EIdent(v2)]:
								key = v1;
								value = v2;
								it = eiter;
							default:
						}
					default:
				}
			default:
		}
		return callb(key, value, it);
	}

	public inline static function last(arr: Array<String>): String
		return arr[arr.length - 1];

	public static function isIterable(v: Dynamic): Bool {
		// TODO: test for php and lua, they might have issues with this check
		return v != null && v.iterator != null;
	}

	/**
	 * DO NOT USE INLINE ON THIS FUNCTION
	**/
	public static function argCount(func: haxe.Constraints.Function): Int {
		#if cpp
		return untyped __cpp__("{0}->__ArgCount()", func);
		#elseif js
		return untyped js.Syntax.code("{0}.length", func);
		#else
		return -1;
		#end
	}
}
