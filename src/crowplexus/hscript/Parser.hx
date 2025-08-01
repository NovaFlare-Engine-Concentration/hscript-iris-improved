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
import crowplexus.hscript.Tools;

using StringTools;

enum Token {
	TEof;
	TConst(c: Const);
	TId(s: String);
	TOp(s: String);
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TComma;
	TSemicolon;
	TBkOpen;
	TBkClose;
	TQuestion;
	TDoubleDot;
	TMeta(s: String);
	TPrepro(s: String);
	TRegex(i: String, ?opt: String);
	TQuestionDot;
}

#if hscriptPos
class TokenPos {
	public var t: Token;
	public var min: Int;
	public var max: Int;

	public function new(t, min, max) {
		this.t = t;
		this.min = min;
		this.max = max;
	}
}
#end

class Parser {
	// config / variables
	public var line: Int;
	public var opChars: String;
	public var identChars: String;
	#if haxe3
	public var opPriority: Map<String, Int>;
	public var opRightAssoc: Map<String, Bool>;
	#else
	public var opPriority: Hash<Int>;
	public var opRightAssoc: Hash<Bool>;
	#end

	/**
		allows to check for #if / #else in code
	**/
	public var preprocesorValues: Map<String, Dynamic> = new Map();

	/**
		activate JSON compatiblity
	**/
	public var allowJSON: Bool;

	/**
		allow types declarations
	**/
	public var allowTypes: Bool;

	/**
		allow haxe metadata declarations
	**/
	public var allowMetadata: Bool;

	/**
	 * 是否允许单引号进行$插值
	 */
	public var allowInterpolation: Bool;

	/**
		resume from parsing errors (when parsing incomplete code, during completion for example)
	**/
	public var resumeErrors: Bool;

	/*
		package name, set when using "package;" in your script.
	 */
	public var packageName: String = null;

	// implementation
	var input: String;
	var readPos: Int;

	var char: Int;
	var ops: Array<Bool>;
	var idents: Array<Bool>;
	var uid: Int = 0;
	var abductCount: Int = 0;
	var abducts = ["if", "for", "while", "try", "switch", "do"];
	@:noCompletion var sureStaticModifier: Bool = false;
	@:noCompletion var interpolationState: Bool = false;
	@:noCompletion var lastInjectors: Array<String>;
	var compatibles: Array<Bool> = [];

	#if hscriptPos
	var origin: String;
	var tokenMin: Int;
	var tokenMax: Int;
	var oldTokenMin: Int;
	var oldTokenMax: Int;
	var tokens: List<TokenPos>;
	#else
	static inline var p1 = 0;
	static inline var tokenMin = 0;
	static inline var tokenMax = 0;

	#if haxe3
	var tokens: haxe.ds.GenericStack<Token>;
	#else
	var tokens: haxe.FastList<Token>;
	#end
	#end
	public function new() {
		line = 1;
		opChars = "+*/-=!><&|^%~";
		identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		var priorities = [
			["%"],
			["*", "/"],
			["+", "-"],
			["<<", ">>", ">>>"],
			["|", "&", "^"],
			["==", "!=", ">", "<", ">=", "<="],
			["..."],
			["is"],
			["&&"],
			["||"],
			[
				"=",
				"+=",
				"-=",
				"*=",
				"/=",
				"%=",
				"??" + "=",
				"<<=",
				">>=",
				">>>=",
				"|=",
				"&=",
				"^=",
				"=>"
			],
			["->"]
		];
		#if haxe3
		opPriority = new Map();
		opRightAssoc = new Map();
		#else
		opPriority = new Hash();
		opRightAssoc = new Hash();
		#end
		for (i in 0...priorities.length)
			for (x in priorities[i]) {
				opPriority.set(x, i);
				if (i == 9)
					opRightAssoc.set(x, true);
			}
		for (x in ["!", "++", "--", "~"]) // unary "-" handled in parser directly!
			opPriority.set(x, x == "++" || x == "--" ? -1 : -2);
	}

	public inline function error(err, pmin, pmax) {
		if (sureStaticModifier)
			sureStaticModifier = false;
		if (abductCount > 0)
			abductCount = 0;

		if (!resumeErrors)
			#if hscriptPos
			throw new Error(err, pmin, pmax, origin, line);
			#else
			throw err;
			#end
	}

	public function invalidChar(c) {
		error(EInvalidChar(c), readPos - 1, readPos - 1);
	}

	function initParser(origin) {
		// line=1 - don't reset line : it might be set manualy
		preprocStack = [];
		#if hscriptPos
		this.origin = origin;
		readPos = 0;
		tokenMin = oldTokenMin = 0;
		tokenMax = oldTokenMax = 0;
		tokens = new List();
		#elseif haxe3
		tokens = new haxe.ds.GenericStack<Token>();
		#else
		tokens = new haxe.FastList<Token>();
		#end
		char = -1;
		ops = new Array();
		idents = new Array();
		uid = 0;
		for (i in 0...opChars.length)
			ops[opChars.charCodeAt(i)] = true;
		for (i in 0...identChars.length)
			idents[identChars.charCodeAt(i)] = true;
	}

	public function parseString(s: String, ?origin: String = "hscript") {
		initParser(origin);
		input = s;
		compatibles = [];
		readPos = 0;
		var a = new Array();
		while (true) {
			var tk = token();
			if (tk == TEof)
				break;
			push(tk);
			parseFullExpr(a);
		}
		return if (a.length == 1) a[0] else mk(EBlock(a), 0);
	}

	function unexpected(tk): Dynamic {
		error(EUnexpected(tokenString(tk)), tokenMin, tokenMax);
		return null;
	}

	inline function push(tk) {
		#if hscriptPos
		tokens.push(new TokenPos(tk, tokenMin, tokenMax));
		tokenMin = oldTokenMin;
		tokenMax = oldTokenMax;
		#else
		tokens.add(tk);
		#end
	}

	inline function ensure(tk) {
		var t = token();
		if (t != tk)
			unexpected(t);
	}

	inline function ensureToken(tk) {
		var t = token();
		if (!Type.enumEq(t, tk))
			unexpected(t);
	}

	function maybe(tk) {
		var t = token();
		if (Type.enumEq(t, tk))
			return true;
		push(t);
		return false;
	}

	function getIdent() {
		var tk = token();
		return extractIdent(tk);
	}

	function extractIdent(tk: Token): String {
		switch (tk) {
			case TId(id):
				return id;
			default:
				unexpected(tk);
				return null;
		}
	}

	inline function expr(e: Expr) {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	inline function pmin(e: Expr) {
		#if hscriptPos
		return e == null ? 0 : e.pmin;
		#else
		return 0;
		#end
	}

	inline function pmax(e: Expr) {
		#if hscriptPos
		return e == null ? 0 : e.pmax;
		#else
		return 0;
		#end
	}

	inline function mk(e, ?pmin, ?pmax): Expr {
		#if hscriptPos
		if (e == null)
			return null;
		if (pmin == null)
			pmin = tokenMin;
		if (pmax == null)
			pmax = tokenMax;
		return {
			e: e,
			pmin: pmin,
			pmax: pmax,
			origin: origin,
			line: line
		};
		#else
		return e;
		#end
	}

	function isBlock(e) {
		if (e == null)
			return false;
		return switch (expr(e)) {
			case EBlock(_), EObject(_), ESwitch(_), EEnum(_, _), EClass(_, _, _, _): true;
			case EFunction(_, e, _, _, _): isBlock(e);
			case EVar(_, _, t, e, _): e != null ? isBlock(e) : t != null ? t.match(CTAnon(_)) : false;
			case EIf(_, e1, e2): if (e2 != null) isBlock(e2) else isBlock(e1);
			case EBinop(_, _, e): isBlock(e);
			case EUnop(_, prefix, e): !prefix && isBlock(e);
			case EWhile(_, e): isBlock(e);
			case EDoWhile(_, e): isBlock(e);
			case EFor(_, _, e): isBlock(e);
			case EReturn(e): e != null && isBlock(e);
			case ETry(_, _, _, e): isBlock(e);
			case EMeta(_, _, e): isBlock(e);
			case EIgnore(skipSemicolon): skipSemicolon;
			default: false;
		}
	}

	function parseFullExpr(exprs: Array<Expr>) {
		var e = parseExpr();
		if (!expr(e).match(EIgnore(_)))
			exprs.push(e);

		var tk = token();
		// this is a hack to support var a,b,c; with a single EVar
		while (tk == TComma && e != null && expr(e).match(EVar(_, _))) {
			e = parseStructure("var"); // next variable
			if (!expr(e).match(EIgnore(_)))
				exprs.push(e);
			tk = token();
		}

		if (tk != TSemicolon && tk != TEof) {
			if (isBlock(e))
				push(tk);
			else
				unexpected(tk);
		}
	}

	function parseObject(p1) {
		// parse object
		var fl: Array<ObjectDecl> = [];
		while (true) {
			var tk = token();
			var id = null;
			switch (tk) {
				case TId(i):
					id = i;
				case TConst(c):
					if (!allowJSON)
						unexpected(tk);
					switch (c) {
						case CString(s): id = s;
						default: unexpected(tk);
					}
				case TBrClose:
					break;
				default:
					unexpected(tk);
					break;
			}
			ensure(TDoubleDot);
			fl.push({name: id, e: parseExpr()});
			tk = token();
			switch (tk) {
				case TBrClose:
					break;
				case TComma:
				default:
					unexpected(tk);
			}
		}
		return parseExprNext(mk(EObject(fl), p1));
	}

	function automaticAbduct(condition: Bool, func: haxe.Constraints.Function, ?args: Array<Dynamic>) {
		var ttime = compatibles.length;
		if (condition) {
			compatibles.push(true);
			abductCount++;
		}
		var e = Reflect.callMethod(this, func, (args == null ? [] : args));
		if (condition) {
			while (compatibles.length > ttime)
				compatibles.pop();
			abductCount--;
		}
		return e;
	}

	function parseExpr() {
		var tk = token();
		#if hscriptPos
		var p1 = tokenMin;
		#end
		switch (tk) {
			case TId(id):
				var e = automaticAbduct(abducts.contains(id), parseStructure, [id, tk]);
				if (e == null)
					e = mk(EIdent(id));
				return parseExprNext(e);
			case TConst(c):
				return parseExprNext(mk(EConst(c)));
			case TRegex(i, opt):
				if (opt != null) {
					if (opt != "i" && opt != "g" && opt != "m" #if (!cs && !js) && opt != "s" #end#if (cpp || neko) && opt != "u" #end) {
						error(ECustom(opt + " is not a matching symbol for EReg"), tokenMin, tokenMax);
					}
				}
				return parseExprNext(mk(EConst(CEReg(i, opt))));
			case TPOpen:
				tk = token();
				if (tk == TPClose) {
					ensureToken(TOp("->"));
					var eret = automaticAbduct(true, parseExpr);
					return mk(EFunction([], mk(EReturn(eret), p1), abductCount), p1);
				}
				push(tk);
				var e = parseExpr();
				tk = token();
				switch (tk) {
					case TPClose:
						return parseExprNext(mk(EParent(e), p1, tokenMax));
					case TDoubleDot:
						var t = parseType();
						tk = token();
						switch (tk) {
							case TPClose:
								return parseExprNext(mk(ECheckType(e, t), p1, tokenMax));
							case TComma:
								switch (expr(e)) {
									case EIdent(v): return parseLambda([{name: v, t: t}], pmin(e));
									default:
								}
							default:
						}
					case TComma:
						switch (expr(e)) {
							case EIdent(v): return parseLambda([{name: v}], pmin(e));
							default:
						}
					default:
				}
				return unexpected(tk);
			case TBrOpen:
				tk = token();
				switch (tk) {
					case TBrClose:
						return parseExprNext(mk(EObject([]), p1));
					case TId(_):
						var tk2 = token();
						push(tk2);
						push(tk);
						switch (tk2) {
							case TDoubleDot:
								return parseExprNext(parseObject(p1));
							default:
						}
					case TConst(c):
						if (allowJSON) {
							switch (c) {
								case CString(_, _):
									var tk2 = token();
									push(tk2);
									push(tk);
									switch (tk2) {
										case TDoubleDot:
											return parseExprNext(parseObject(p1));
										default:
									}
								default:
									push(tk);
							}
						} else push(tk);
					default:
						push(tk);
				}
				var a = new Array();
				var doit: Bool = {
					if (compatibles.length > 0)
						compatibles.pop();
					else
						false;
				}
				if (!doit)
					abductCount++;
				while (true) {
					parseFullExpr(a);
					tk = token();
					if (tk == TBrClose || (resumeErrors && tk == TEof))
						break;
					push(tk);
				}
				if (!doit)
					abductCount--;
				return mk(EBlock(a), p1);
			case TOp(op):
				if (op == "-") {
					var start = tokenMin;
					var e = parseExpr();
					if (e == null)
						return makeUnop(op, e);
					switch (expr(e)) {
						case EConst(CInt(i)):
							return mk(EConst(CInt(-i)), start, pmax(e));
						case EConst(CFloat(f)):
							return mk(EConst(CFloat(-f)), start, pmax(e));
						default:
							return makeUnop(op, e);
					}
				}
				if (opPriority.get(op) < 0)
					return makeUnop(op, parseExpr());
				return unexpected(tk);
			case TBkOpen:
				var a = new Array();
				tk = token();
				while (tk != TBkClose && (!resumeErrors || tk != TEof)) {
					push(tk);
					a.push(parseExpr());
					tk = token();
					if (tk == TComma)
						tk = token();
				}
				if (a.length == 1 && a[0] != null)
					switch (expr(a[0])) {
						case EFor(_), EWhile(_), EDoWhile(_):
							var tmp = "__a_" + (uid++);
							var e = mk(EBlock([
								mk(EVar(tmp, abductCount, null, mk(EArrayDecl([]), p1)), p1),
								mapCompr(tmp, a[0]),
								mk(EIdent(tmp), p1),
							]), p1);
							return parseExprNext(e);
						default:
					}
				return parseExprNext(mk(EArrayDecl(a), p1));
			case TMeta(id) if (allowMetadata):
				var args = parseMetaArgs();
				return mk(EMeta(id, args, parseExpr()), p1);
			default:
				return unexpected(tk);
		}
	}

	function parseLambda(args: Array<Argument>, pmin) {
		while (true) {
			var id = getIdent();
			var t = maybe(TDoubleDot) ? parseType() : null;
			args.push({name: id, t: t});
			var tk = token();
			switch (tk) {
				case TComma:
				case TPClose:
					break;
				default:
					unexpected(tk);
					break;
			}
		}
		ensureToken(TOp("->"));
		var eret = automaticAbduct(true, parseExpr);
		return mk(EFunction(args, mk(EReturn(eret), pmin), abductCount), pmin);
	}

	function parseMetaArgs() {
		var tk = token();
		if (tk != TPOpen) {
			push(tk);
			return null;
		}
		var args = [];
		tk = token();
		if (tk != TPClose) {
			push(tk);
			while (true) {
				args.push(parseExpr());
				switch (token()) {
					case TComma:
					case TPClose:
						break;
					case tk:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function mapCompr(tmp: String, e: Expr) {
		if (e == null)
			return null;
		var edef = switch (expr(e)) {
			case EFor(v, it, e2):
				EFor(v, it, mapCompr(tmp, e2));
			case EWhile(cond, e2):
				EWhile(cond, mapCompr(tmp, e2));
			case EDoWhile(cond, e2):
				EDoWhile(cond, mapCompr(tmp, e2));
			case EIf(cond, e1, e2) if (e2 == null):
				EIf(cond, mapCompr(tmp, e1), null);
			case EBlock([e]):
				EBlock([mapCompr(tmp, e)]);
			case EParent(e2):
				EParent(mapCompr(tmp, e2));
			default:
				ECall(mk(EField(mk(EIdent(tmp), pmin(e), pmax(e)), "push", false), pmin(e), pmax(e)), [e]);
		}
		return mk(edef, pmin(e), pmax(e));
	}

	function makeUnop(op, e) {
		if (e == null && resumeErrors)
			return null;
		return switch (expr(e)) {
			case EBinop(bop, e1, e2): mk(EBinop(bop, makeUnop(op, e1), e2), pmin(e1), pmax(e2));
			case ETernary(e1, e2, e3): mk(ETernary(makeUnop(op, e1), e2, e3), pmin(e1), pmax(e3));
			default: mk(EUnop(op, true, e), pmin(e), pmax(e));
		}
	}

	function makeBinop(op, e1, e) {
		if (e == null && resumeErrors)
			return mk(EBinop(op, e1, e), pmin(e1), pmax(e1));
		return switch (expr(e)) {
			case EBinop(op2, e2, e3):
				if (opPriority.get(op) <= opPriority.get(op2)
					&& !opRightAssoc.exists(op)) mk(EBinop(op2, makeBinop(op, e1, e2), e3), pmin(e1), pmax(e3)); else mk(EBinop(op, e1, e), pmin(e1), pmax(e));
			case ETernary(e2, e3, e4):
				if (opRightAssoc.exists(op)) mk(EBinop(op, e1, e), pmin(e1), pmax(e)); else mk(ETernary(makeBinop(op, e1, e2), e3, e4), pmin(e1), pmax(e));
			default:
				mk(EBinop(op, e1, e), pmin(e1), pmax(e));
		}
	}

	function parseStructure(id, ?tt: Token) {
		#if hscriptPos
		var p1 = tokenMin;
		#end
		return switch (id) {
			case "if":
				ensure(TPOpen);
				var cond = parseExpr();
				ensure(TPClose);
				var e1 = parseExpr();
				var e2 = null;
				var semic = false;
				var tk = token();
				if (tk == TSemicolon) {
					semic = true;
					tk = token();
				}
				if (Type.enumEq(tk, TId("else"))) {
					compatibles.push(true);
					e2 = parseExpr();
				} else {
					push(tk);
					if (semic)
						push(TSemicolon);
				}
				mk(EIf(cond, e1, e2), p1, (e2 == null) ? tokenMax : pmax(e2));
			case id if (modifierContainer.contains(id)):
				if (abductCount != 0)
					unexpected(tt);
				if (tt != null)
					push(tt);
				else
					push(TId(id));
				injectorModifier();
			case "var", "final":
				if (tt != null)
					push(tt);
				else
					push(TId(id));
				injectorModifier();
			case "while":
				var econd = parseExpr();
				var e = parseExpr();
				mk(EWhile(econd, e), p1, pmax(e));
			case "do":
				var e = parseExpr();
				var tk = token();
				switch (tk) {
					case TId("while"): // Valid
					default: unexpected(tk);
				}
				var econd = parseExpr();
				mk(EDoWhile(econd, e), p1, pmax(econd));
			case "for":
				ensure(TPOpen);
				var vname = getIdent();
				ensureToken(TId("in"));
				var eiter = parseExpr();
				ensure(TPClose);
				var e = parseExpr();
				mk(EFor(vname, eiter, e), p1, pmax(e));
			case "break": mk(EBreak);
			case "continue": mk(EContinue);
			case "else": unexpected(TId(id));
			case "function":
				if (tt != null)
					push(tt);
				else
					push(TId(id));
				injectorModifier();
			case "return":
				var tk = token();
				push(tk);
				var e = if (tk == TSemicolon) null else parseExpr();
				mk(EReturn(e), p1, if (e == null) tokenMax else pmax(e));
			case "new":
				var a = new Array();
				a.push(getIdent());
				while (true) {
					var tk = token();
					switch (tk) {
						case TDot:
							a.push(getIdent());
						case TPOpen:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				var args = parseExprList(TPClose);
				mk(ENew(a.join("."), args), p1);
			case "throw":
				var e = parseExpr();
				mk(EThrow(e), p1, pmax(e));
			case "try":
				var e = parseExpr();
				ensureToken(TId("catch"));
				ensure(TPOpen);
				var vname = getIdent();
				ensure(TDoubleDot);
				var t = null;
				if (allowTypes)
					t = parseType();
				else
					ensureToken(TId("Dynamic"));
				ensure(TPClose);
				var ec = parseExpr();
				mk(ETry(e, vname, t, ec), p1, pmax(ec));
			case "switch":
				var parentExpr = parseExpr();
				var def = null, cases = [];
				ensure(TBrOpen);
				while (true) {
					var tk = token();
					switch (tk) {
						case TId("case"):
							var c: SwitchCase = {values: [], expr: null, ifExpr: null};
							cases.push(c);
							while (true) {
								var e = parseExpr();
								c.values.push(e);
								tk = token();
								switch (tk) {
									case TComma:
										// next expr
									case TId("if"):
										// if( Type.enumEq(e, EIdent("_")) )
										//	unexpected(TId("if"));

										var e = parseExpr();
										c.ifExpr = e;
										switch tk = token() {
											case TComma:
											case TDoubleDot: break;
											case _:
												unexpected(tk);
												break;
										}
									case TDoubleDot:
										break;
									default:
										unexpected(tk);
										break;
								}
							}
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose:
										break;
									case TEof if (resumeErrors):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							c.expr = if (exprs.length == 1) exprs[0]; else if (exprs.length == 0) mk(EBlock([]), tokenMin,
								tokenMin); else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));

							for (i in c.values) {
								switch Tools.expr(i) {
									case EIdent("_"):
										def = c.expr;
									case _:
								}
							}
						case TId("default"):
							if (def != null)
								unexpected(tk);
							ensure(TDoubleDot);
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose:
										break;
									case TEof if (resumeErrors):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							def = if (exprs.length == 1) exprs[0]; else if (exprs.length == 0) mk(EBlock([]), tokenMin,
								tokenMin); else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TBrClose:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				mk(ESwitch(parentExpr, cases, def), p1, tokenMax);
			case "import":
				// no need settup in local.
				if (abductCount > 0)
					unexpected(TId(id));
				var path = [getIdent()];
				var asStr: String = null;
				var star: Bool = false;

				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}
					t = token();
					switch (t) {
						case TOp("*"): star = true;
						case TId(id): path.push(id);
						default: unexpected(t);
					}
				}

				final asErr = " -> " + path.join(".") + " as " + asStr;

				if (maybe(TId("as"))) {
					asStr = getIdent();
					final uppercased: Bool = asStr.charAt(0) == asStr.charAt(0).toUpperCase();
					if (asStr == null || asStr == "null" || asStr == "")
						unexpected(TId("as"));
					if (!uppercased)
						error(ECustom("Import aliases must begin with an uppercase letter." + asErr), readPos, readPos);
				}
				// trace(asStr);
				/*
					if (token() != TSemicolon) {
						error(ECustom("Missing semicolon at the end of a \"import\" declaration. -> "+asErr), readPos, readPos);
						null;
					}
				 */
				mk(EImport(path.join('.'), asStr));
			case "class":
				if (abductCount > 0)
					unexpected(TId(id));

				var className: String = '';
				var extendedClassName: Null<String> = null;
				var interfacesNames: Array<String> = [];
				var t = token();

				switch (t) {
					case TId(id):
						if (~/^[A-Z][A-Za-z0-9_]*/.match(id)) className = id; else error(ECustom('Class Name "' + id +
							'" Initial capital letters are required'), tokenMin, tokenMax);
					case _:
						unexpected(t);
				}

				if (maybe(TId("extends"))) {
					t = token();
					switch (t) {
						case TId(id):
							if (~/^[A-Z][A-Za-z0-9_]*/.match(id)) extendedClassName = id; else error(ECustom('Extended Class Name "' + id
								+ '" Initial capital letters are required'), tokenMin, tokenMax);
						case _:
							unexpected(t);
					}
				}

				t = token();
				while (Type.enumEq(t, TId("implements"))) {
					var tk = token();
					switch (tk) {
						case TId(id):
							if (~/^[A-Z][A-Za-z0-9_]*/.match(id)) {
								if (!interfacesNames.contains(id))
									interfacesNames.push(id);
								else
									error(ECustom('Cannot reuse an interface "' + id + '"'), tokenMin, tokenMax);
							} else error(ECustom('Interface Name "' + id + '" Initial capital letters are required'), tokenMin, tokenMax);
						case _:
							unexpected(tk);
					}
					t = token();
				}

				push(t);
				var fields = [];
				ensure(TBrOpen);
				while (true) {
					t = token();
					if (t == TBrClose) {
						break;
					}
					push(t);
					fields.push(parseClassField());
				}
				mk(EClass(className, extendedClassName, interfacesNames, fields, packageName?.split(".")));
			case "enum":
				if (abductCount > 0)
					unexpected(TId(id));
				var name = getIdent();

				ensure(TBrOpen);

				var fields = [];

				var currentName = "";
				var currentArgs: Array<Argument> = null;

				while (true) {
					var tk = token();
					switch (tk) {
						case TBrClose:
							break;
						case TSemicolon | TComma:
							if (currentName == "")
								continue;

							if (currentArgs != null && currentArgs.length > 0) {
								fields.push(EnumType.EConstructor(currentName, currentArgs));
								currentArgs = null;
							} else {
								fields.push(EnumType.ESimple(currentName));
							}
							currentName = "";
						case TPOpen:
							if (currentArgs != null) {
								error(ECustom("Cannot have multiple argument lists in one enum constructor"), tokenMin, tokenMax);
								break;
							}
							currentArgs = parseFunctionArgs();
						default:
							if (currentName != "") {
								error(ECustom("Expected comma or semicolon"), tokenMin, tokenMax);
								break;
							}
							var name = extractIdent(tk);
							currentName = name;
					}
				}

				mk(EEnum(name, fields, packageName?.split(".")));
			case "super":
				parseExprNext(mk(EConst(CSuper)));
			case "typedef":
				if (abductCount > 0)
					unexpected(TId(id));
				// typedef Name = Type;

				/*
					Ignore parsing if its, typedef Name = {
						> Person
						var name:String;
						var age:Int;
					}

					If the value is a class then it will be parsed as a EVar(Name, value);
				 */

				var name = getIdent();

				ensureToken(TOp("="));

				var t = parseType();

				switch (t) {
					case CTAnon(_) | CTExtend(_) | CTIntersection(_) | CTFun(_):
						mk(EIgnore(true));
					case CTPath(tp):
						var path = tp.pack.concat([tp.name]);
						var params = tp.params;
						if (params != null && params.length > 1)
							error(ECustom("Typedefs can't have parameters"), tokenMin, tokenMax);

						if (path.length == 0)
							error(ECustom("Typedefs can't be empty"), tokenMin, tokenMax);

						{
							var className = path.join(".");
							var cl = Tools.getClass(className);
							if (cl != null) {
								return mk(EVar(name, abductCount, null, mk(EDirectValue(cl))));
							}
						}

						var expr = mk(EIdent(path.shift()));
						while (path.length > 0) {
							expr = mk(EField(expr, path.shift(), false));
						}

						// todo? add import to the beginning of the file?
						mk(EVar(name, abductCount, null, expr));
					default:
						error(ECustom("Typedef, unknown type " + t), tokenMin, tokenMax);
						null;
				}

			case "using":
				if (abductCount > 0)
					unexpected(TId(id));
				var path = parsePath();
				mk(EUsing(path.join(".")));
			case "package":
				if (abductCount > 0)
					unexpected(TId(id));
				// ignore package
				var tk = token();
				push(tk);
				packageName = "";
				if (tk == TSemicolon)
					return mk(EIgnore(false));

				var path = parsePath();
				// mk(EPackage(path.join(".")));
				packageName = path.join(".");
				mk(EIgnore(false));
			default:
				null;
		}
	}

	var modifierContainer: Array<String> = ["private", "public", "inline", "static", "dynamic"];

	private function injectorModifier(?injectors: Array<String>) {
		var t = token();
		return switch (t) {
			case TId(id) if (modifierContainer.contains(id)):
				if (injectors == null)
					injectors = [];
				injectors.push(id);
				while (true) {
					var tk = token();
					switch (tk) {
						case TId(id) if (modifierContainer.contains(id)):
							if (!injectors.contains(id)
								&& !(injectors.contains("public") && id == "private")
								&& !(injectors.contains("private") && id == "public")
								&& !(injectors.contains("dynamic") && id == "inline")
								&& !(injectors.contains("inline") && id == "dynamic")) injectors.push(id); else unexpected(tk);
						case _:
							push(tk);
							break;
					}
				}
				injectorModifier(injectors);
			case TId(id) if (id == "final" || id == "var"):
				var getter: String = "default";
				var setter: String = "default";
				var ident = getIdent();
				var tk = token();
				var t = null;
				if (injectors != null && injectors.contains("dynamic"))
					error(ECustom("Invalid accessor 'dynamic' for variable -> " + ident), tokenMin, tokenMax);
				if (tk == TPOpen) {
					if (!(injectors != null && injectors.contains("inline")) && abductCount == 0 && id == "var") {
						var getter1: Null<String> = null;
						var setter1: Null<String> = null;
						var displayComma: Bool = false;
						var closed: Bool = false;
						while (true) {
							var t = token();
							switch (t) {
								case TComma:
									if (getter != null && !displayComma) {
										displayComma = true;
									} else unexpected(t);
								case TId(byd):
									if (getter1 == null && !displayComma) {
										if (byd == "get" || byd == "never" || byd == "default" || byd == "null") {
											getter1 = byd;
										} else
											unexpected(t);
									} else if (setter1 == null && displayComma) {
										if (byd == "set" || byd == "never" || byd == "default" || byd == "null") {
											setter1 = byd;
										} else
											unexpected(t);
									} else unexpected(t);
								case TPClose:
									if (getter1 != null && setter1 != null) closed = true; else unexpected(t);
								default:
									unexpected(t);
							}

							if (closed)
								break;
						}

						if (getter1 != null)
							getter = getter1;
						if (setter1 != null)
							setter = setter1;

						tk = token();
					} else
						unexpected(tk);
				}
				if (tk == TDoubleDot && allowTypes) {
					t = parseType();
					tk = token();
				}

				var e = automaticAbduct(true, function(tk) {
					if (Type.enumEq(tk, TOp("=")))
						return parseExpr();
					else
						push(tk);
					return null;
				}, [tk]);
				mk(EVar(ident, abductCount, t, e, getter, setter, (id == "final"), if (abductCount == 0 && injectors != null) injectors else null), tokenMin,
					(e == null) ? tokenMax : pmax(e));
			case TId(id) if (id == "function"):
				var tk = token();
				var name = null;
				switch (tk) {
					case TId(id): name = id;
					default: push(tk);
				}
				var ttime = compatibles.length;
				if (abducts.contains(id)) {
					compatibles.push(true);
					abductCount++;
				}
				var inf = parseFunctionDecl();
				if (abducts.contains(id)) {
					while (compatibles.length > ttime)
						compatibles.pop();
					abductCount--;
				}

				mk(EFunction(inf.args, inf.body, abductCount, name, inf.ret, if (abductCount == 0 && injectors != null) injectors else null), tokenMin,
					pmax(inf.body));
			case _:
				unexpected(t);
		}
	}

	private var modifiers: Array<String> = ["public", "static", "override", "private", "inline"];

	function parseClassField(?injector: Array<String>, ?injectorMeta: Metadata): BydFieldDecl {
		var t = token();
		return switch (t) {
			case TMeta(name):
				if (injector != null && injector.length > 0)
					unexpected(t);
				if (injectorMeta == null)
					injectorMeta = [];
				injectorMeta.push({name: name, params: parseMetaArgs()});
				parseClassField(injector, injectorMeta);
			case TId(id) if (modifiers.contains(id)):
				if (injector != null) {
					if (injector.contains(id)
						|| (id == "public" && injector.contains("private"))
						|| (id == "private"
							&& injector.contains("public")
							|| (id == "override" && injector.contains("static"))
							|| (id == "static" && injector.contains("override")))) {
						unexpected(t);
					}
					injector.push(id);
					parseClassField(injector, injectorMeta);
				} else {
					var another = new Array<String>();
					another.push(id);
					parseClassField(another, injectorMeta);
				}
			case TId(id) if (id == "var" || id == "final"):
				var getter: String = "default";
				var setter: String = "default";
				var ident = getIdent();
				var tk = token();
				var t = null;
				if (tk == TPOpen) {
					if (id == "var") {
						var getter1: Null<String> = null;
						var setter1: Null<String> = null;
						var displayComma: Bool = false;
						var closed: Bool = false;
						while (true) {
							var t = token();
							switch (t) {
								case TComma:
									if (getter != null && !displayComma) {
										displayComma = true;
									} else unexpected(t);
								case TId(byd):
									if (getter1 == null && !displayComma) {
										if (byd == "get" || byd == "never" || byd == "default" || byd == "null") {
											getter1 = byd;
										} else
											unexpected(t);
									} else if (setter1 == null && displayComma) {
										if (byd == "set" || byd == "never" || byd == "default" || byd == "null") {
											setter1 = byd;
										} else
											unexpected(t);
									} else unexpected(t);
								case TPClose:
									if (getter1 != null && setter1 != null) closed = true; else unexpected(t);
								default:
									unexpected(t);
							}

							if (closed)
								break;
						}

						if (getter1 != null)
							getter = getter1;
						if (setter1 != null)
							setter = setter1;

						tk = token();
					} else
						unexpected(tk);
				}
				var ctype = null;
				if (tk == TDoubleDot && allowTypes) {
					t = parseType();
					ctype = t;
					tk = token();
				}
				var pos = mk(EIgnore(true));
				var e = null;
				if (Type.enumEq(tk, TOp("=")))
					e = parseExpr();
				else
					push(tk);
				ensure(TSemicolon);

				return {
					name: ident,
					meta: injectorMeta,
					kind: KVar({
						get: getter,
						set: setter,
						expr: e,
						type: ctype,
						isConst: (id == "final")
					}),
					access: {
						final real: Array<FieldAccess> = [];
						if (injector != null)
							for (ac in injector)
								switch (ac) {
									case "public": real.push(APublic);
									case "private": real.push(APrivate);
									case "inline": real.push(AInline);
									case "static": real.push(AStatic);
									case "override": real.push(AOverride);
									case _:
								}
						real;
					},
					pos: pos
				};
			case TId(id) if (id == "function"):
				var name = getIdent();
				// trace(injector + "; " + "function: " + name);
				ensure(TPOpen);
				var args = parseFunctionArgs();
				var ret = null;
				if (allowTypes) {
					var tk = token();
					if (tk != TDoubleDot)
						push(tk);
					else
						ret = parseType();
				}
				var pos = mk(EIgnore(true));
				var es = [];
				parseFullExpr(es);
				return {
					name: name,
					meta: injectorMeta,
					kind: KFunction({
						args: args,
						expr: es[0],
						ret: ret
					}),
					access: {
						final real: Array<FieldAccess> = [];
						if (injector != null)
							for (ac in injector)
								switch (ac) {
									case "public": real.push(APublic);
									case "private": real.push(APrivate);
									case "inline": real.push(AInline);
									case "static": real.push(AStatic);
									case "override": real.push(AOverride);
									case _:
								}
						real;
					},
					pos: pos
				};
			default:
				unexpected(t);
		}
	}

	function parseExprNext(e1: Expr) {
		var tk = token();
		switch (tk) {
			case TId("is"):
				return makeBinop("is", e1, parseExpr());
			case TOp(op):
				if (op == "->") {
					// single arg reinterpretation of `f -> e` , `(f) -> e` and `(f:T) -> e`
					switch (expr(e1)) {
						case EIdent(i), EParent(expr(_) => EIdent(i)):
							var eret = automaticAbduct(true, parseExpr);
							return mk(EFunction([{name: i}], mk(EReturn(eret), pmin(eret)), abductCount), pmin(e1));
						case ECheckType(expr(_) => EIdent(i), t):
							var eret = automaticAbduct(true, parseExpr);
							return mk(EFunction([{name: i, t: t}], mk(EReturn(eret), pmin(eret)), abductCount), pmin(e1));
						default:
					}
					unexpected(tk);
				}

				if (opPriority.get(op) == -1) {
					if (isBlock(e1) || switch (expr(e1)) {
							case EParent(_): true;
							default: false;
						}) {
						push(tk);
						return e1;
						}
					return parseExprNext(mk(EUnop(op, false, e1), pmin(e1)));
				}
				return makeBinop(op, e1, parseExpr());
			case TDot | TQuestionDot:
				var field = getIdent();
				return parseExprNext(mk(EField(e1, field, tk == TQuestionDot), pmin(e1)));
			case TPOpen:
				return parseExprNext(mk(ECall(e1, parseExprList(TPClose)), pmin(e1)));
			case TBkOpen:
				var e2 = parseExpr();
				ensure(TBkClose);
				return parseExprNext(mk(EArray(e1, e2), pmin(e1)));
			case TQuestion:
				var e2 = parseExpr();
				ensure(TDoubleDot);
				var e3 = parseExpr();
				return mk(ETernary(e1, e2, e3), pmin(e1), pmax(e3));
			default:
				push(tk);
				return e1;
		}
	}

	function parseFunctionArgs() {
		var args = new Array();
		var tk = token();
		if (tk != TPClose) {
			var done = false;
			while (!done) {
				var name = null, opt = false;
				switch (tk) {
					case TQuestion:
						opt = true;
						tk = token();
					default:
				}
				switch (tk) {
					case TId(id):
						name = id;
					default:
						unexpected(tk);
						break;
				}
				var arg: Argument = {name: name};
				args.push(arg);
				if (opt)
					arg.opt = true;
				if (allowTypes) {
					if (maybe(TDoubleDot))
						arg.t = parseType();
					if (maybe(TOp("=")))
						arg.value = parseExpr();
				}
				tk = token();
				switch (tk) {
					case TComma:
						tk = token();
					case TPClose:
						done = true;
					default:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function parseFunctionDecl() {
		ensure(TPOpen);
		var args = parseFunctionArgs();
		var ret = null;
		if (allowTypes) {
			var tk = token();
			if (tk != TDoubleDot)
				push(tk);
			else
				ret = parseType();
		}
		return {args: args, ret: ret, body: parseExpr()};
	}

	function parsePath() {
		var path = [getIdent()];
		while (true) {
			var t = token();
			if (t != TDot) {
				push(t);
				break;
			}
			path.push(getIdent());
		}
		return path;
	}

	function parseType(): CType {
		var t = token();
		switch (t) {
			case TId(v):
				push(t);
				var path = parsePath();
				var name = path.pop();
				var params = null;
				t = token();
				switch (t) {
					case TOp(op):
						if (op == "<") {
							params = [];
							while (true) {
								params.push(parseType());
								t = token();
								switch (t) {
									case TComma: continue;
									case TOp(op):
										if (op == ">")
											break;
										if (op.charCodeAt(0) == ">".code) {
											#if hscriptPos
											tokens.add(new TokenPos(TOp(op.substr(1)), tokenMax - op.length - 1, tokenMax));
											#else
											tokens.add(TOp(op.substr(1)));
											#end
											break;
										}
									default:
								}
								unexpected(t);
								break;
							}
						} else push(t);
					default:
						push(t);
				}
				return parseTypeNext(CTPath({
					pack: path,
					params: params,
					sub: null,
					name: name
				}));
			case TPOpen:
				var a = token(), b = token();

				push(b);
				push(a);

				function withReturn(args) {
					switch token() { // I think it wouldn't hurt if ensure used enumEq
						case TOp('->'):
						case t:
							unexpected(t);
					}

					return CTFun(args, parseType());
				}

				switch [a, b] {
					case [TPClose, _] | [TId(_), TDoubleDot]:
						var args = [
							for (arg in parseFunctionArgs()) {
								switch arg.value {
									case null:
									case v:
										error(ECustom('Default values not allowed in function types'), #if hscriptPos v.pmin, v.pmax #else 0, 0 #end);
								}

								CTNamed(arg.name, if (arg.opt) CTOpt(arg.t) else arg.t);
							}
						];

						return withReturn(args);
					default:
						var t = parseType();
						return switch token() {
							case TComma:
								var args = [t];

								while (true) {
									args.push(parseType());
									if (!maybe(TComma))
										break;
								}
								ensure(TPClose);
								withReturn(args);
							case TPClose:
								parseTypeNext(CTParent(t));
							case t: unexpected(t);
						}
				}
			case TBrOpen:
				var curType = null;
				var fields = [];
				var tps = [];
				var meta = null;
				while (true) {
					t = token();
					switch (t) {
						case TBrClose: break;
						case TId("var"):
							var name = getIdent();
							ensure(TDoubleDot);
							fields.push({name: name, t: parseType(), meta: meta});
							meta = null;
							ensure(TSemicolon);
						case TId(name):
							ensure(TDoubleDot);
							fields.push({name: name, t: parseType(), meta: meta});
							t = token();
							switch (t) {
								case TComma:
								case TBrClose: break;
								default: unexpected(t);
							}
						case TMeta(name):
							if (meta == null)
								meta = [];
							meta.push({name: name, params: parseMetaArgs()});
						case TOp(">"):
							var tp = parseType();
							switch (tp) {
								case CTPath(tp):
									tps.push(tp);
								default:
									unexpected(t);
							}
							t = token();
							switch (t) {
								case TComma:
								case TBrClose: break;
								default: unexpected(t);
							}
						default:
							#if IRIS_DEBUG
							trace(t, fields, tps);
							#end
							unexpected(t);
							break;
					}
				}
				return parseTypeNext(tps.length == 0 ? CTAnon(fields) : CTExtend(tps, fields));
			default:
				return unexpected(t);
		}
	}

	function parseTypeNext(t: CType) {
		var tk = token();
		var isIntersection = false;
		switch (tk) {
			case TOp(op):
				if (op != "->" && op != "&") {
					push(tk);
					return t;
				}
				isIntersection = op == "&";
			default:
				push(tk);
				return t;
		}
		var t2 = parseType();
		switch (t2) {
			case CTFun(args, _):
				args.unshift(t);
				return t2;
			default:
				if (isIntersection)
					return CTIntersection([t, t2]);
				return CTFun([t], t2);
		}
	}

	function parseExprList(etk) {
		var args = new Array();
		var tk = token();
		if (tk == etk)
			return args;
		push(tk);
		while (true) {
			args.push(parseExpr());
			tk = token();
			switch (tk) {
				case TComma:
				default:
					if (tk == etk)
						break;
					unexpected(tk);
					break;
			}
		}
		return args;
	}

	// ------------------------ module -------------------------------

	public function parseModule(content: String, ?origin: String = "hscript") {
		initParser(origin);
		input = content;
		readPos = 0;
		allowTypes = true;
		allowMetadata = true;
		var decls = [];
		while (true) {
			var tk = token();
			if (tk == TEof)
				break;
			push(tk);
			decls.push(parseModuleDecl());
		}
		return decls;
	}

	function parseMetadata(): Metadata {
		var meta = [];
		while (true) {
			var tk = token();
			switch (tk) {
				case TMeta(name):
					meta.push({name: name, params: parseMetaArgs()});
				default:
					push(tk);
					break;
			}
		}
		return meta;
	}

	function parseParams() {
		if (maybe(TOp("<")))
			error(EInvalidOp("Unsupported class type parameters"), readPos, readPos);
		return {};
	}

	function parseModuleDecl(): ModuleDecl {
		var meta = parseMetadata();
		var ident = getIdent();
		var isPrivate = false, isExtern = false;
		while (true) {
			switch (ident) {
				case "private":
					isPrivate = true;
				case "extern":
					isExtern = true;
				default:
					break;
			}
			ident = getIdent();
		}
		switch (ident) {
			case "package":
				var path = parsePath();
				ensure(TSemicolon);
				return DPackage(path);
			case "import":
				var path = [getIdent()];
				var star = false;
				var as = "";
				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}
					t = token();
					switch (t) {
						case TId(id):
							path.push(id);
						case TOp("*"):
							star = true;
						default:
							unexpected(t);
					}
				}
				ensure(TSemicolon);
				return DImport(path, star, as);
			case "class":
				var name = getIdent();
				var params = parseParams();
				var extend = null;
				var implement = [];

				while (true) {
					var t = token();
					switch (t) {
						case TId("extends"):
							extend = parseType();
						case TId("implements"):
							implement.push(parseType());
						default:
							push(t);
							break;
					}
				}

				var fields = [];
				ensure(TBrOpen);
				while (!maybe(TBrClose))
					fields.push(parseField());

				return DClass({
					name: name,
					meta: meta,
					params: params,
					extend: extend,
					implement: implement,
					fields: fields,
					isPrivate: isPrivate,
					isExtern: isExtern,
				});
			case "typedef":
				var name = getIdent();
				var params = parseParams();
				ensureToken(TOp("="));
				var t = parseType();
				return DTypedef({
					name: name,
					meta: meta,
					params: params,
					isPrivate: isPrivate,
					t: t,
				});
			default:
				unexpected(TId(ident));
		}
		return null;
	}

	function parseField(): FieldDecl {
		var meta = parseMetadata();
		var access = [];
		while (true) {
			var id = getIdent();
			switch (id) {
				case "override":
					access.push(AOverride);
				case "public":
					access.push(APublic);
				case "private":
					access.push(APrivate);
				case "inline":
					access.push(AInline);
				case "static":
					access.push(AStatic);
				case "macro":
					access.push(AMacro);
				case "function":
					var name = getIdent();
					var inf = parseFunctionDecl();
					return {
						name: name,
						meta: meta,
						access: access,
						kind: KFunction({
							args: inf.args,
							expr: inf.body,
							ret: inf.ret,
						}),
					};
				case "var", "final":
					var name = getIdent();
					var get = null, set = null;
					if (maybe(TPOpen)) {
						get = getIdent();
						ensure(TComma);
						set = getIdent();
						ensure(TPClose);
					}
					var type = maybe(TDoubleDot) ? parseType() : null;
					var expr = maybe(TOp("=")) ? parseExpr() : null;

					if (expr != null) {
						if (isBlock(expr))
							maybe(TSemicolon);
						else
							ensure(TSemicolon);
					} else if (type != null && type.match(CTAnon(_))) {
						maybe(TSemicolon);
					} else
						ensure(TSemicolon);

					return {
						name: name,
						meta: meta,
						access: access,
						kind: KVar({
							get: get,
							set: set,
							type: type,
							expr: expr,
						}),
					};
				default:
					unexpected(TId(id));
					break;
			}
		}
		return null;
	}

	// ------------------------ lexing -------------------------------

	inline function readChar() {
		return StringTools.fastCodeAt(input, readPos++);
	}

	function readString(until) {
		var pos: Int = 0;
		var c = 0;
		var b = new StringBuf();
		var esc = false;
		var im = false;
		var old = line;
		var s = input;
		var es = [];
		#if hscriptPos
		var p1 = readPos - 1;
		#end
		while (true) {
			var c = readChar();
			if (StringTools.isEof(c)) {
				line = old;
				error(EUnterminatedString, p1, p1);
				break;
			}
			#if haxe4
			if (im) {
				im = false;
				switch (c) {
					case 36:
						b.addChar(c);
						pos++;
					case char if (char == 123):
						var a = [];
						while (true) {
							var t = token();
							if (t == TBrClose)
								break;
							push(t);
							abductCount++;
							var e = parseExpr();
							if (!expr(e).match(EIgnore(_)))
								a.push(e);

							var tk = token();

							if (tk != TSemicolon && tk != TEof) {
								if (isBlock(e) || a.length < 2)
									push(tk);
								else
									unexpected(tk);
							}
							abductCount--;
						}
						es.push({e: mk(EBlock(a)), pos: pos});
					case char if (idents[char]):
						var cnst = "";
						while (idents[c] == true) {
							cnst += String.fromCharCode(c);
							c = readChar();
						}
						var oldPos = readPos;
						es.push({e: mk(EIdent(cnst)), pos: pos});
						// trace(es[es.length - 1]);
						readPos--;
					case _:
						b.addChar(36);
						pos++;
						b.addChar(c);
						pos++;
				}
				continue;
			}
			#end

			if (esc) {
				esc = false;
				switch (c) {
					case 'n'.code:
						b.addChar('\n'.code);
						pos++;
					case 'r'.code:
						b.addChar('\r'.code);
						pos++;
					case 't'.code:
						b.addChar('\t'.code);
						pos++;
					case "'".code, '"'.code, '\\'.code:
						b.addChar(c);
						pos++;
					case '/'.code:
						if (allowJSON) {
							b.addChar(c);
							pos++;
						} else
							invalidChar(c);
					case "u".code:
						if (!allowJSON)
							invalidChar(c);
						var k = 0;
						for (i in 0...4) {
							k <<= 4;
							var char = readChar();
							switch (char) {
								case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0-9
									k += char - 48;
								case 65, 66, 67, 68, 69, 70: // A-F
									k += char - 55;
								case 97, 98, 99, 100, 101, 102: // a-f
									k += char - 87;
								default:
									if (StringTools.isEof(char)) {
										line = old;
										error(EUnterminatedString, p1, p1);
									}
									invalidChar(char);
							}
						}
						b.addChar(k);
						pos++;
					default:
						invalidChar(c);
				}
			} else if (c == 92)
				esc = true;
			else if (c == until)
				break;
			else if (allowInterpolation && c == 36 && until == 39) {
				im = true;
			} else {
				if (c == 10)
					line++;
				b.addChar(c);
				pos++;
			}
		}
		return CString(b.toString(), es);
	}

	function token() {
	#if hscriptPos
	var t = tokens.pop();
	if (t != null) {
		tokenMin = t.min;
		tokenMax = t.max;
		return t.t;
	}
	oldTokenMin = tokenMin;
	oldTokenMax = tokenMax;
	tokenMin = (this.char < 0) ? readPos : readPos - 1;
	var t = _token();
	tokenMax = (this.char < 0) ? readPos - 1 : readPos - 2;
	return t;
	} function _token() {
	#else
	if (!tokens.isEmpty())
		return tokens.pop();
	#end
		var char;
		if (this.char < 0)
			char = readChar();
		else {
			char = this.char;
			this.char = -1;
		}
		while (true) {
			if (StringTools.isEof(char)) {
				this.char = char;
				return TEof;
			}
			switch (char) {
				case 0:
					return TEof;
				case 32, 9, 13: // space, tab, CR
					#if hscriptPos
					tokenMin++;
					#end
				case 10:
					line++; // LF
					#if hscriptPos
					tokenMin++;
					#end
				case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0...9
					var n = (char - 48) * 1.0;
					var exp = 0.;
					while (true) {
						char = readChar();
						exp *= 10;
						switch (char) {
							case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
								n = n * 10 + (char - 48);
							case '_'.code:
							case "e".code, "E".code:
								var tk = token();
								var pow: Null<Int> = null;
								switch (tk) {
									case TConst(CInt(e)): pow = e;
									case TOp("-"):
										tk = token();
										switch (tk) {
											case TConst(CInt(e)): pow = -e;
											default: push(tk);
										}
									default:
										push(tk);
								}
								if (pow == null)
									invalidChar(char);
								return TConst(CFloat((Math.pow(10, pow) / exp) * n * 10));
							case ".".code:
								if (exp > 0) {
									// in case of '0...'
									if (exp == 10 && readChar() == ".".code) {
										push(TOp("..."));
										var i = Std.int(n);
										return TConst((i == n) ? CInt(i) : CFloat(n));
									}
									invalidChar(char);
								}
								exp = 1.;
							case "x".code:
								if (n > 0 || exp > 0)
									invalidChar(char);
								// read hexa
								#if haxe3
								var n = 0;
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0-9
											n = (n << 4) + char - 48;
										case 65, 66, 67, 68, 69, 70: // A-F
											n = (n << 4) + (char - 55);
										case 97, 98, 99, 100, 101, 102: // a-f
											n = (n << 4) + (char - 87);
										case '_'.code:
										default:
											this.char = char;
											return TConst(CInt(n));
									}
								}
								#else
								var n = haxe.Int32.ofInt(0);
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0-9
											n = haxe.Int32.add(haxe.Int32.shl(n, 4), cast(char - 48));
										case 65, 66, 67, 68, 69, 70: // A-F
											n = haxe.Int32.add(haxe.Int32.shl(n, 4), cast(char - 55));
										case 97, 98, 99, 100, 101, 102: // a-f
											n = haxe.Int32.add(haxe.Int32.shl(n, 4), cast(char - 87));
										case '_'.code:
										default:
											this.char = char;
											// we allow to parse hexadecimal Int32 in Neko, but when the value will be
											// evaluated by Interpreter, a failure will occur if no Int32 operation is
											// performed
											var v = try CInt(haxe.Int32.toInt(n)) catch (e:Dynamic) CInt32(n);
											return TConst(v);
									}
								}
								#end
							case "b".code: // Custom thing, not supported in haxe
								if (n > 0 || exp > 0)
									invalidChar(char);
								// read binary
								#if haxe3
								var n = 0;
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49: // 0-1
											n = (n << 1) + char - 48;
										case '_'.code:
										default:
											this.char = char;
											return TConst(CInt(n));
									}
								}
								#else
								var n = haxe.Int32.ofInt(0);
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49: // 0-1
											n = haxe.Int32.add(haxe.Int32.shl(n, 1), cast(char - 48));
										case '_'.code:
										default:
											this.char = char;
											// we allow to parse binary Int32 in Neko, but when the value will be
											// evaluated by Interpreter, a failure will occur if no Int32 operation is
											// performed
											var v = try CInt(haxe.Int32.toInt(n)) catch (e:Dynamic) CInt32(n);
											return TConst(v);
									}
								}
								#end
							default:
								this.char = char;
								var i = Std.int(n);
								return TConst((exp > 0) ? CFloat(n * 10 / exp) : ((i == n) ? CInt(i) : CFloat(n)));
						}
					}
				case "~".code if ((char = readChar()) == "/".code):
					var iBuf: StringBuf = new StringBuf();
					var prevChar = char;
					var nextChar = readChar();
					while ((char = nextChar) != "/".code || prevChar == "\\".code) {
						nextChar = readChar();
						if (StringTools.isEof(char))
							unexpected(TEof);
						if (char == "\n".code)
							error(ECustom('Unexpected token: "~/"'), tokenMin, tokenMax);
						// trace(String.fromCharCode(prevChar) + ".." + String.fromCharCode(char) + ".." + String.fromCharCode(nextChar));
						if (!(char == '\\'.code && nextChar == "/".code))
							iBuf.add(String.fromCharCode(char));

						prevChar = char;
					}

					var opt: Null<String> = null;
					char = readChar();
					if (idents[char] == true) {
						opt = String.fromCharCode(char);
					} else {
						readPos--;
					}
					return TRegex(iBuf.toString(), opt);
				case ";".code:
					return TSemicolon;
				case "(".code:
					return TPOpen;
				case ")".code:
					return TPClose;
				case ",".code:
					return TComma;
				case ".".code:
					char = readChar();
					switch (char) {
						case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
							var n = char - 48;
							var exp = 1;
							while (true) {
								char = readChar();
								exp *= 10;
								switch (char) {
									case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
										n = n * 10 + (char - 48);
									default:
										this.char = char;
										return TConst(CFloat(n / exp));
								}
							}
						case ".".code:
							char = readChar();
							if (char != ".".code)
								invalidChar(char);
							return TOp("...");
						default:
							this.char = char;
							return TDot;
					}
				case "{".code:
					return TBrOpen;
				case "}".code:
					return TBrClose;
				case "[".code:
					return TBkOpen;
				case "]".code:
					return TBkClose;
				case "'".code, '"'.code:
					return TConst(readString(char));
				case "?".code:
					char = readChar();
					if (char == ".".code)
						return TQuestionDot;
					else if (char == "?".code) {
						char = readChar();
						if (char == "=".code)
							return TOp("??" + "=");
						return TOp("??");
					}
					this.char = char;
					return TQuestion;
				case ":".code:
					return TDoubleDot;
				case '='.code:
					char = readChar();
					if (char == '='.code)
						return TOp("==");
					else if (char == '>'.code)
						return TOp("=>");
					this.char = char;
					return TOp("=");
				case '@'.code:
					char = readChar();
					if (idents[char] || char == ':'.code) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (!idents[char]) {
								this.char = char;
								return TMeta(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				case '#'.code:
					char = readChar();
					if (idents[char]) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (!idents[char]) {
								this.char = char;
								return preprocess(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				default:
					if (ops[char]) {
						var op = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char))
								char = 0;
							if (!ops[char]) {
								this.char = char;
								return TOp(op);
							}
							var pop = op;
							op += String.fromCharCode(char);
							if (!opPriority.exists(op) && opPriority.exists(pop)) {
								if (op == "//" || op == "/*")
									return tokenComment(op, char);
								this.char = char;
								return TOp(pop);
							}
						}
					}
					if (idents[char]) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char))
								char = 0;
							if (!idents[char]) {
								this.char = char;
								return TId(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
			}
			char = readChar();
		}
		return null;
	}

	function preprocValue(id: String): Dynamic {
		return preprocesorValues.get(id);
	}

	var preprocStack: Array<PreprocessStackValue>;

	function parsePreproCond() {
		var tk = token();
		return switch (tk) {
			case TPOpen:
				push(TPOpen);
				parseExpr();
			case TId(id):
				mk(EIdent(id), tokenMin, tokenMax);
			case TOp("!"):
				mk(EUnop("!", true, parsePreproCond()), tokenMin, tokenMax);
			default:
				unexpected(tk);
		}
	}

	function evalPreproCond(e: Expr) {
		switch (expr(e)) {
			case EIdent(id):
				return preprocValue(id) != null;
			case EUnop("!", _, e):
				return !evalPreproCond(e);
			case EParent(e):
				return evalPreproCond(e);
			case EBinop("&&", e1, e2):
				return evalPreproCond(e1) && evalPreproCond(e2);
			case EBinop("||", e1, e2):
				return evalPreproCond(e1) || evalPreproCond(e2);
			default:
				error(EInvalidPreprocessor("Can't eval " + expr(e).getName()), readPos, readPos);
				return false;
		}
	}

	function preprocess(id: String): Token {
		switch (id) {
			case "if":
				var e = parsePreproCond();
				if (evalPreproCond(e)) {
					preprocStack.push({r: true});
					return token();
				}
				preprocStack.push({r: false});
				skipTokens();
				return token();
			case "else", "elseif" if (preprocStack.length > 0):
				if (preprocStack[preprocStack.length - 1].r) {
					preprocStack[preprocStack.length - 1].r = false;
					skipTokens();
					return token();
				} else if (id == "else") {
					preprocStack.pop();
					preprocStack.push({r: true});
					return token();
				} else {
					// elseif
					preprocStack.pop();
					return preprocess("if");
				}
			case "end" if (preprocStack.length > 0):
				preprocStack.pop();
				return token();
			default:
				return TPrepro(id);
		}
	}

	function skipTokens() {
		var spos = preprocStack.length - 1;
		var obj = preprocStack[spos];
		var pos = readPos;
		while (true) {
			var tk = token();
			if (tk == TEof) {
				// @see https://github.com/CodenameCrew/hscript-improved/pull/5/
				if (preprocStack.length != 0) {
					error(EInvalidPreprocessor("Unclosed"), pos, pos);
				} else {
					//  trace("line: " + pos);
					break;
				}
			}
			if (preprocStack[spos] != obj) {
				push(tk);
				break;
			}
		}
	}

	function tokenComment(op: String, char: Int) {
		var c = op.charCodeAt(1);
		var s = input;
		if (c == '/'.code) { // comment
			while (char != '\r'.code && char != '\n'.code) {
				char = readChar();
				if (StringTools.isEof(char))
					break;
			}
			this.char = char;
			return token();
		}
		if (c == '*'.code) {/* comment */
			var old = line;
			if (op == "/**/") {
				this.char = char;
				return token();
			}
			while (true) {
				while (char != '*'.code) {
					if (char == '\n'.code)
						line++;
					char = readChar();
					if (StringTools.isEof(char)) {
						line = old;
						error(EUnterminatedComment, tokenMin, tokenMin);
						break;
					}
				}
				char = readChar();
				if (StringTools.isEof(char)) {
					line = old;
					error(EUnterminatedComment, tokenMin, tokenMin);
					break;
				}
				if (char == '/'.code)
					break;
			}
			return token();
		}
		this.char = char;
		return TOp(op);
	}

	function constString(c) {
		return switch (c) {
			case CInt(v): Std.string(v);
			case CFloat(f): Std.string(f);
			case CString(s): s; // TODO : escape + quote
			case CSuper: "super";
			#if !haxe3
			case CInt32(v): Std.string(v);
			#end
			// CEReg并不会被肘出来（应该吧
			case _: "???";
		}
	}

	function tokenString(t) {
		return switch (t) {
			case TEof: "<eof>";
			case TConst(c): constString(c);
			case TId(s): s;
			case TOp(s): s;
			case TPOpen: "(";
			case TPClose: ")";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TComma: ",";
			case TSemicolon: ";";
			case TBkOpen: "[";
			case TBkClose: "]";
			case TRegex(i, opt): "~/" + i + "/" + (opt != null ? opt : "");
			case TQuestion: "?";
			case TDoubleDot: ":";
			case TMeta(id): "@" + id;
			case TPrepro(id): "#" + id;
			case TQuestionDot: "?.";
		}
	}
}

@:structInit
final class PreprocessStackValue {
	public var r: Bool;

	public function new(r: Bool) {
		this.r = r;
	}
}
