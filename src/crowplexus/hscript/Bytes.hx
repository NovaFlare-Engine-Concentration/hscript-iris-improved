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
import crowplexus.hscript.Types.ByteInt;
import haxe.Serializer;
import haxe.Unserializer;

enum abstract BytesExpr(ByteInt) from ByteInt to ByteInt {
	var EIgnore = 0;
	var EConst = 1;
	var EIdent = 2;
	var EImport = 3;
	var EVar = 4;
	var EParent = 5;
	var EBlock = 6;
	var EField = 7;
	var EBinop = 8;
	var EUnop = 9;
	var ECall = 10;
	var EIf = 11;
	var EWhile = 12;
	var EFor = 13;
	var EForGen = 14;
	var EBreak = 15;
	var EContinue = 16;
	var EFunction = 17;
	var EReturn = 18;
	var EArray = 19;
	var EArrayDecl = 20;
	var ENew = 21;
	var EThrow = 22;
	var ETry = 23;
	var EObject = 24;
	var ETernary = 25;
	var ESwitch = 26;
	var EDoWhile = 27;
	var EMeta = 28;
	var ECheckType = 29;
	var EClass = 30;
	var EEnum = 31;
	var ETypedef = 32;
	var EUsing = 33;
	var ECast = 34;
}

enum abstract BytesConst(ByteInt) from ByteInt to ByteInt {
	var CInt = 0;
	var CIntByte = 1;
	var CFloat = 2;
	var CString = 3;
	var CSuper = 4;
	var CEReg = 5;
	#if !haxe3
	var CInt32 = 6;
	#end
}

enum abstract BytesCType(ByteInt) from ByteInt to ByteInt {
	var CTPath = 0;
	var CTFun = 1;
	var CTAnon = 2;
	var CTExtend = 3;
	var CTParent = 4;
	var CTOpt = 5;
	var CTNamed = 6;
	var CTIntersection = 7;
}

enum abstract BytesIntSize(ByteInt) from ByteInt to ByteInt {
	var I8;
	var I16;
	var I32;
	var N8;
	var N16;
	var N32;
}

class Bytes {
	var bin: haxe.io.Bytes;
	var bout: haxe.io.BytesBuffer;
	var pin: Int;
	var hstrings: #if haxe3 Map<String, Int> #else Hash<Int> #end;
	var strings: Array<String>;
	var nstrings: Int;

	var opMap: Map<String, Int>;

	function new(?bin) {
		this.bin = bin;
		pin = 0;
		bout = new haxe.io.BytesBuffer();
		hstrings = #if haxe3 new Map() #else new Hash() #end;
		strings = [null];
		nstrings = 1;
	}

	function doEncodeString(v: String) {
		var vid = hstrings.get(v);
		if (vid == null) {
			if (nstrings == 256) {
				hstrings = #if haxe3 new Map() #else new Hash() #end;
				nstrings = 1;
			}
			hstrings.set(v, nstrings);
			bout.addByte(0);
			var vb = haxe.io.Bytes.ofString(v);
			bout.addByte(vb.length);
			bout.add(vb);
			nstrings++;
		} else
			bout.addByte(vid);
	}

	function doDecodeString() {
		var id = bin.get(pin++);
		if (id == 0) {
			var len = bin.get(pin);
			var str = #if (haxe_ver < 3.103) bin.readString(pin + 1, len); #else bin.getString(pin + 1, len); #end
			pin += len + 1;
			if (strings.length == 255)
				strings = [null];
			strings.push(str);
			return str;
		}
		return strings[id];
	}

	function doEncodeInt(v: Int) {
		var isNeg = v < 0;
		if (isNeg)
			v = -v;
		if (v >= 0 && v <= 255) {
			bout.addByte(isNeg ? N8 : I8);
			bout.addByte(v);
		} else if (v >= 0 && v <= 65535) {
			bout.addByte(isNeg ? N16 : I16);
			bout.addByte(v & 0xFF);
			bout.addByte((v >> 8) & 0xFF);
		} else {
			bout.addByte(isNeg ? N32 : I32);
			bout.addInt32(v);
		}
	}

	function doEncodeBool(v: Bool) {
		bout.addByte(v ? 1 : 0);
	}

	function doEncodeConst(c: Const) {
		switch (c) {
			case CInt(v):
				if (v >= 0 && v <= 255) {
					bout.addByte(CIntByte);
					bout.addByte(v & 0xFF);
				} else {
					bout.addByte(CInt);
					doEncodeInt(v);
				}
			case CFloat(f):
				bout.addByte(CFloat);
				doEncodeString(Std.string(f));
			case CString(s, csgo):
				bout.addByte(CString);
				doEncodeString(s);
				doEncodeBool(csgo != null);
				if(csgo != null) {
					doEncodeInt(csgo.length);
					for(sm in csgo) {
						doEncode(sm.e);
						doEncodeInt(sm.pos);
					}
				}
			case CEReg(r, opt):
				bout.addByte(CEReg);
				doEncodeString(r);
				doEncodeString(opt == null ? "" : opt);
			case CSuper:
				bout.addByte(CSuper);
			#if !haxe3
			case CInt32(v):
				bout.addByte(CInt32);
				var mid = haxe.Int32.toInt(haxe.Int32.and(v, haxe.Int32.ofInt(0xFFFFFF)));
				bout.addByte(mid & 0xFF);
				bout.addByte((mid >> 8) & 0xFF);
				bout.addByte(mid >> 16);
				bout.addByte(haxe.Int32.toInt(haxe.Int32.ushr(v, 24)));
			#end
		}
	}

	function doDecodeInt() {
		var ass = bin.get(pin++);
		var size:BytesIntSize = ass;
		var i = switch (size) {
			case I8 | N8: bin.get(pin++);
			case I16 | N16: bin.get(pin++) | bin.get(pin++) << 8;
			case I32 | N32: bin.getInt32(pin);
		}
		switch (size) {
			case I8 | N8:
			case I16 | N16:
			case I32 | N32:
				pin += 4;
		}
		switch (size) {
			case N8 | N16 | N32:
				i = -i;
			default:
		}
		return i;
	}

	function doDecodeConst(): Const {
		return switch (bin.get(pin++)) {
			case CIntByte:
				CInt(bin.get(pin++));
			case CInt:
				var i = doDecodeInt();
				CInt(i);
			case CFloat:
				CFloat(Std.parseFloat(doDecodeString()));
			case CString:
				var con = doDecodeString();
				var csgo:Array<{e:Expr, pos:Int}> = if(doDecodeBool()) {
					var csgo = [];
					for(i in 0...doDecodeInt()) {
						var e = doDecode();
						var pos = doDecodeInt();
						csgo.push({e: e, pos: pos});
					}
					csgo;
				} else null;
				CString(con, csgo);
			case CEReg:
				var r = doDecodeString();
				var opt = doDecodeString();
				CEReg(r, opt == "" ? null : opt);
			case CSuper:
				CSuper;
			#if !haxe3
			case CInt32:
				var i = bin.get(pin) | (bin.get(pin + 1) << 8) | (bin.get(pin + 2) << 16);
				var j = bin.get(pin + 3);
				pin += 4;
				CInt32(haxe.Int32.or(haxe.Int32.ofInt(i), haxe.Int32.shl(haxe.Int32.ofInt(j), 24)));
			#end
			default:
				throw "Invalid code " + bin.get(pin - 1);
		}
	}

	function doDecodeArg(): Argument {
		var name = doDecodeString();
		var opt = doDecodeBool();
		var t:Null<CType> = if(doDecodeBool()) doDecodeCType() else null;
		var value = doDecode();
		return {
			name: name,
			opt: opt,
			t: t,
			value: value,
		};
	}

	function doEncodeExprType(t: BytesExpr) {
		/*switch (t) {
			case EIdent:
				bout.addString("EIdent");
			case EVar:
				bout.addString("EVar");
			case EConst:
				bout.addString("EConst");
			case EParent:
				bout.addString("EParent");
			case EBlock:
				bout.addString("EBlock");
			case EField:
				bout.addString("EField");
			case EBinop:
				bout.addString("EBinop");
			case EUnop:
				bout.addString("EUnop");
			case ECall:
				bout.addString("ECall");
			case EIf:
				bout.addString("EIf");
			case EWhile:
				bout.addString("EWhile");
			case EFor:
				bout.addString("EFor");
			case EBreak:
				bout.addString("EBreak");
			case EContinue:
				bout.addString("EContinue");
			case EFunction:
				bout.addString("EFunction");
			case EReturn:
				bout.addString("EReturn");
			case EArray:
				bout.addString("EArray");
			case EArrayDecl:
				bout.addString("EArrayDecl");
			case ENew:
				bout.addString("ENew");
			case EThrow:
				bout.addString("EThrow");
			case ETry:
				bout.addString("ETry");
			case EObject:
				bout.addString("EObject");
			case ETernary:
				bout.addString("ETernary");
			case ESwitch:
				bout.addString("ESwitch");
			case EDoWhile:
				bout.addString("EDoWhile");
			case EMeta:
				bout.addString("EMeta");
			case ECheckType:
				bout.addString("ECheckType");
			case EImport:
				bout.addString("EImport");
			case EEnum:
				bout.addString("EEnum");
			case EDirectValue:
				bout.addString("EDirectValue");
		}*/
		bout.addByte(t);
	}

	function doEncodeArg(a: Argument) {
		doEncodeString(a.name);
		doEncodeBool(a.opt == true);
		doEncodeBool(a.t != null);
		if(a.t != null)
			doEncodeCType(a.t);
		if (a.value == null)
			bout.addByte(255);
		else
			doEncode(a.value);
	}

	function doEncodeCType(ct:CType) {
		switch(ct) {
			case CTPath(path):
				bout.addByte(CTPath);
				doEncodeTypePath(path);
			case CTFun(args, ret):
				bout.addByte(CTFun);
				doEncodeInt(args.length);
				for(a in args) {
					doEncodeCType(a);
				}
				doEncodeCType(ret);
			case CTAnon(fields):
				bout.addByte(CTAnon);
				doEncodeTypeFields(fields);
			case CTExtend(t, fields):
				bout.addByte(CTExtend);
				doEncodeInt(t.length);
				for(a in t) {
					doEncodeTypePath(a);
				}
				doEncodeTypeFields(fields);
			case CTParent(t):
				bout.addByte(CTParent);
				doEncodeCType(t);
			case CTOpt(t):
				bout.addByte(CTOpt);
				doEncodeCType(t);
			case CTNamed(n, t):
				bout.addByte(CTNamed);
				doEncodeString(n);
				doEncodeCType(t);
			case CTIntersection(types):
				bout.addByte(CTIntersection);
				doEncodeInt(types.length);
				for(a in types) {
					doEncodeCType(a);
				}
		}
	}

	function doEncodeTypeFields(fields:Array<{name: String, t: CType, ?meta:Metadata}>) {
		doEncodeInt(fields.length);
		for(f in fields) {
			doEncodeString(f.name);
			doEncodeCType(f.t);
			doEncodeBool(f.meta != null);
			if(f.meta != null) {
				doEncodeMetadata(f.meta);
			}
		}
	}

	function doEncodeMetadata(meta:Metadata) {
		doEncodeInt(meta.length);
		for(m in meta) {
			doEncodeString(m.name);
			doEncodeBool(m.params != null);
			if(m.params != null) {
				doEncodeInt(m.params.length);
				for(p in m.params) doEncode(p);
			}
		}
	}

	function doEncodeTypePath(tp:TypePath) {
		// pack
		doEncodeInt(tp.pack.length);
		for(p in tp.pack) doEncodeString(p);
		// name
		doEncodeString(tp.name);
		// params
		doEncodeBool(tp.params != null);
		if(tp.params != null) {
			doEncodeInt(tp.params.length);
			for(p in tp.params) {
				doEncodeCType(p);
			}
		}
		// sub
		doEncodeBool(tp.sub != null);
		if(tp.sub != null) doEncodeString(tp.sub);
	}

	function doEncodeClassField(field:BydFieldDecl) {
		doEncodeString(field.name);

		doEncodeBool(field.meta != null);
		if(field.meta != null) doEncodeMetadata(field.meta);

		switch(field.kind) {
			case KVar(decl):
				bout.addByte(0);
				doEncodeVarDecl(decl);
			case KFunction(decl):
				bout.addByte(1);
				doEncodeFunctionDecl(decl);
		}

		doEncodeBool(field.access != null);
		if(field.access != null) {
			doEncodeInt(field.access.length);
			for(a in field.access) {
				bout.addByte(cast a);
			}
		}

		doEncode(field.pos);
	}

	function doEncodeVarDecl(decl:VarDecl) {
		doEncodeBool(decl.get != null);
		if(decl.get != null) doEncodeString(decl.get);

		doEncodeBool(decl.set != null);
		if(decl.set != null) doEncodeString(decl.set);

		if (decl.expr == null)
			bout.addByte(255);
		else
			doEncode(decl.expr);

		doEncodeBool(decl.type != null);
		if(decl.type != null) doEncodeCType(decl.type);

		doEncodeBool(decl.isConst == true);
	}

	function doEncodeFunctionDecl(decl:FunctionDecl) {
		doEncodeInt(decl.args.length);
		for(a in decl.args) doEncodeArg(a);
		doEncode(decl.expr);
		doEncodeBool(decl.ret != null);
		if(decl.ret != null) doEncodeCType(decl.ret);
	}

	function doEncode(e: Expr) {
		#if hscriptPos
		doEncodeString(e.origin);
		doEncodeInt(e.line);
		var e = e.e;
		#end
		switch (e) {
			case EIgnore(b):
				doEncodeExprType(EIgnore);
				doEncodeBool(b);
			case EConst(c):
				doEncodeExprType(EConst);
				doEncodeConst(c);
			case EIdent(v):
				doEncodeExprType(EIdent);
				doEncodeString(v);
			case EVar(n, depth, t, e, getter, setter, c, access):
				doEncodeExprType(EVar);
				doEncodeString(n);
				doEncodeInt(depth);

				doEncodeBool(t != null);
				if(t != null) {
					doEncodeCType(t);
				}

				if (e == null)
					bout.addByte(255);
				else
					doEncode(e);
				doEncodeBool(getter != null);
				if(getter != null) {
					doEncodeString(getter);
				}
				doEncodeBool(setter != null);
				if(setter != null) {
					doEncodeString(setter);
				}
				doEncodeBool(c);
				doEncodeBool(access != null);
				if(access != null) {
					doEncodeInt(access.length);
					for(a in access) doEncodeString(a);
				}
			case EParent(e):
				doEncodeExprType(EParent);
				doEncode(e);
			case EBlock(el):
				doEncodeExprType(EBlock);
				doEncodeInt(el.length);
				for (e in el)
					doEncode(e);
			case EField(e, f, s):
				doEncodeExprType(EField);
				doEncode(e);
				doEncodeString(f);
				doEncodeBool(s);
			case EBinop(op, e1, e2):
				doEncodeExprType(EBinop);
				doEncodeString(op);
				doEncode(e1);
				doEncode(e2);
			case EUnop(op, prefix, e):
				doEncodeExprType(EUnop);
				doEncodeString(op);
				doEncodeBool(prefix);
				doEncode(e);
			case ECall(e, el):
				doEncodeExprType(ECall);
				doEncode(e);
				bout.addByte(el.length);
				for (e in el)
					doEncode(e);
			case EIf(cond, e1, e2):
				doEncodeExprType(EIf);
				doEncode(cond);
				doEncode(e1);
				if (e2 == null)
					bout.addByte(255);
				else
					doEncode(e2);
			case EWhile(cond, e):
				doEncodeExprType(EWhile);
				doEncode(cond);
				doEncode(e);
			case EDoWhile(cond, e):
				doEncodeExprType(EDoWhile);
				doEncode(cond);
				doEncode(e);
			case EFor(v, it, e):
				doEncodeExprType(EFor);
				doEncodeString(v);
				doEncode(it);
				doEncode(e);
			case EForGen(it, e):
				doEncodeExprType(EForGen);
				doEncode(it);
				doEncode(e);
			case EBreak:
				doEncodeExprType(EBreak);
			case EContinue:
				doEncodeExprType(EContinue);
			case EFunction(params, e, depth, name, ret, access):
				doEncodeExprType(EFunction);
				doEncodeInt(params.length);
				for (p in params)
					doEncodeArg(p);
				doEncode(e);
				doEncodeInt(depth);
				doEncodeString(name == null ? "" : name);

				doEncodeBool(ret != null);
				if(ret != null) {
					doEncodeCType(ret);
				}
				doEncodeBool(access != null);
				if(access != null) {
					doEncodeInt(access.length);
					for(a in access) doEncodeString(a);
				}
			case EReturn(e):
				doEncodeExprType(EReturn);
				if (e == null)
					bout.addByte(255);
				else
					doEncode(e);
			case EArray(e, index):
				doEncodeExprType(EArray);
				doEncode(e);
				doEncode(index);
			case EArrayDecl(el):
				doEncodeExprType(EArrayDecl);
				doEncodeInt(el.length);
				for (e in el)
					doEncode(e);
			case ENew(cl, params):
				doEncodeExprType(ENew);
				doEncodeTypePath(cl);
				bout.addByte(params.length);
				for (e in params)
					doEncode(e);
			case EThrow(e):
				doEncodeExprType(EThrow);
				doEncode(e);
			case ETry(e, v, _, ecatch):
				doEncodeExprType(ETry);
				doEncode(e);
				doEncodeString(v);
				doEncode(ecatch);
			case EObject(fl):
				doEncodeExprType(EObject);
				doEncodeInt(fl.length);
				for (f in fl) {
					doEncodeString(f.name);
					doEncode(f.e);
				}
			case ETernary(cond, e1, e2):
				doEncodeExprType(ETernary);
				doEncode(cond);
				doEncode(e1);
				doEncode(e2);
			case ESwitch(e, cases, def):
				doEncodeExprType(ESwitch);
				doEncode(e);
				for (c in cases) {
					if (c.values.length == 0)
						throw "assert";
					for (v in c.values)
						doEncode(v);
					bout.addByte(255);
					doEncode(c.expr);
					doEncode(c.ifExpr);
				}
				bout.addByte(255);
				if (def == null)
					bout.addByte(255)
				else
					doEncode(def);
			case EMeta(name, args, e):
				doEncodeExprType(EMeta);
				doEncodeString(name);
				doEncodeInt(args == null ? 0 : args.length + 1);
				if (args != null)
					for (e in args)
						doEncode(e);
				doEncode(e);
			case ECheckType(e, t):
				doEncodeExprType(ECheckType);
				doEncode(e);
				doEncodeCType(t);
			case EEnum(name, fields, pkg):
				doEncodeExprType(EEnum);
				doEncodeString(name);
				bout.addByte(fields.length);
				for (f in fields)
					switch (f) {
						case ESimple(name):
							bout.addByte(0);
							doEncodeString(name);
						case EConstructor(name, args):
							bout.addByte(1);
							doEncodeString(name);
							bout.addByte(args.length);
							for (a in args)
								doEncodeArg(a);
					}

				doEncodeBool(pkg != null);
				if(pkg != null) {
					doEncodeInt(pkg.length);
					for(p in pkg) doEncodeString(p);
				}
			case EClass(className, exn, imn, fields, params, pkg):
				doEncodeExprType(EClass);
				doEncodeString(className);
				doEncodeBool(exn != null);
				if(exn != null) doEncodeTypePath(exn);
				doEncodeInt(imn.length);
				for(im in imn) doEncodeTypePath(im);
				doEncodeInt(fields.length);
				for(f in fields) doEncodeClassField(f);

				doEncodeBool(pkg != null);
				if(pkg != null) {
					doEncodeInt(pkg.length);
					for(p in pkg) doEncodeString(p);
				}
			case ETypedef(n, t, pkg):
				doEncodeExprType(ETypedef);
				doEncodeString(n);
				doEncodeCType(t);
				doEncodeBool(pkg != null);
				if(pkg != null) {
					doEncodeInt(pkg.length);
					for(p in pkg) doEncodeString(p);
				}
			case EImport(v, as, star):
				doEncodeExprType(EImport);
				doEncodeString(v);
				doEncodeBool(as != null);
				if(as != null) doEncodeString(as);
				doEncodeBool(star);
			case EUsing(name):
				doEncodeExprType(EUsing);
				doEncodeString(name);
			case ECast(e, shut, t):
				doEncodeExprType(ECast);
				doEncode(e);
				doEncodeBool(shut);
				doEncodeBool(t != null);
				if(t != null) doEncodeCType(t);
		}
		// bout.addString("__||__");
	}

	function doDecodeBool(): Bool {
		return bin.get(pin++) != 0;
	}

	function doDecodeCType(): CType {
		var bytesType:BytesCType = bin.get(pin++);
		return switch(bytesType) {
			case CTPath:
				CTPath(doDecodeTypePath());
			case CTFun:
				var args = [for(i in 0...doDecodeInt()) doDecodeCType()];
				var ret = doDecodeCType();
				CTFun(args, ret);
			case CTAnon:
				CTAnon(doDecodeTypeFields());
			case CTExtend:
				var t = [for(i in 0...doDecodeInt()) doDecodeTypePath()];
				var fields = doDecodeTypeFields();
				CTExtend(t, fields);
			case CTParent:
				CTParent(doDecodeCType());
			case CTOpt:
				CTOpt(doDecodeCType());
			case CTNamed:
				var n = doDecodeString();
				var t = doDecodeCType();
				CTNamed(n, t);
			case CTIntersection:
				CTIntersection([for(i in 0...doDecodeInt()) doDecodeCType()]);
		}
	}

	function doDecodeTypeFields():Array<{name: String, t: CType, ?meta:Metadata}> {
		var fields:Array<{name: String, t: CType, ?meta:Metadata}> = [];
		for(i in 0...doDecodeInt()) {
			var name = doDecodeString();
			var t = doDecodeCType();
			var meta:Metadata = if(doDecodeBool()) doDecodeMetadata() else null;
			fields.push({
				name: name,
				t: t,
				meta: meta,
			});
		}
		return fields;
	}

	function doDecodeMetadata(): Metadata {
		var meta:Metadata = [];
		for(i in 0...doDecodeInt()) {
			var name = doDecodeString();
			var params:Null<Array<Expr>> = if(doDecodeBool()) [for(p in 0...doDecodeInt()) doDecode()] else null;
			meta.push({
				name: name,
				params: params
			});
		}
		return meta;
	}

	function doDecodeTypePath(): TypePath {
		// pack
		var pack = [for(i in 0...doDecodeInt()) doDecodeString()];
		var name = doDecodeString();
		var params = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeCType()] else null;
		var sub = if(doDecodeBool()) doDecodeString() else null;
		return cast {
			pack: pack,
			name: name,
			params: params,
			sub: sub,
		};
	}

	function doDecodeClassField():BydFieldDecl {
		var name = doDecodeString();
		var meta:Null<Metadata> = if(doDecodeBool()) doDecodeMetadata() else null;
		var kind:FieldKind = switch(bin.get(pin++)) {
			case 0:
				KVar(doDecodeVarDecl());
			case 1:
				KFunction(doDecodeFunctionDecl());
			case _:
				throw "Invalid Field Kind";
		};
		var access:Null<Array<FieldAccess>> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) cast bin.get(pin++)] else null;
		var pos = doDecode();
		return cast {
			name: name,
			meta: meta,
			kind: kind,
			access: access,
			pos: pos,
		};
	}

	function doDecodeVarDecl():VarDecl {
		var getter:Null<String> = if(doDecodeBool()) doDecodeString() else null;
		var setter:Null<String> = if(doDecodeBool()) doDecodeString() else null;
		var expr = doDecode();
		var type:Null<CType> = if(doDecodeBool()) doDecodeCType() else null;
		var isConst = doDecodeBool();
		return cast {
			get: getter,
			set: setter,
			expr: expr,
			type: type,
			isConst: isConst,
		};
	}

	function doDecodeFunctionDecl():FunctionDecl {
		var args = [for(i in 0...doDecodeInt()) doDecodeArg()];
		var expr = doDecode();
		var ret:Null<CType> = if(doDecodeBool()) doDecodeCType() else null;
		return cast {
			args: args,
			expr: expr,
			ret: ret,
		};
	}

	function doDecode(): Expr {
	#if hscriptPos
	if (bin.get(pin) == 255) {
		pin++;
		return null;
	}
	var origin = doDecodeString();
	var line = doDecodeInt();
	return {
		e: _doDecode(),
		pmin: 0,
		pmax: 0,
		origin: origin,
		line: line
	};
	} function _doDecode(): ExprDef {
	#end
		var type: BytesExpr = bin.get(pin++);
		return switch (type) {
			case EIgnore:
				EIgnore(doDecodeBool());
			case EConst:
				EConst(doDecodeConst());
			case EIdent:
				EIdent(doDecodeString());
			case EVar:
				var v = doDecodeString();
				var d = doDecodeInt();
				var t:Null<CType> = if(doDecodeBool()) doDecodeCType() else null;
				var e = doDecode();

				var getter:Null<String> = if(doDecodeBool()) doDecodeString() else null;
				var setter:Null<String> = if(doDecodeBool()) doDecodeString() else null;

				var c = doDecodeBool();
				var access:Null<Array<String>> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeString()] else null;
				EVar(v, d, t, e, getter, setter, c, access);
			case EParent:
				EParent(doDecode());
			case EBlock:
				var a = new Array();
				var len = doDecodeInt();
				for (i in 0...len)
					a.push(doDecode());
				EBlock(a);
			case EField:
				var e = doDecode();
				var name = doDecodeString();
				var s = doDecodeBool();
				EField(e, name, s);
			case EBinop:
				var op = doDecodeString();
				var e1 = doDecode();
				var e2 = doDecode();
				EBinop(op, e1, e2);
			case EUnop:
				var op = doDecodeString();
				var prefix = doDecodeBool();
				EUnop(op, prefix, doDecode());
			case ECall:
				var e = doDecode();
				var params = new Array();
				for (i in 0...bin.get(pin++))
					params.push(doDecode());
				ECall(e, params);
			case EIf:
				var cond = doDecode();
				var e1 = doDecode();
				var eelse = doDecode();
				EIf(cond, e1, eelse);
			case EWhile:
				var cond = doDecode();
				EWhile(cond, doDecode());
			case EDoWhile:
				var cond = doDecode();
				EDoWhile(cond, doDecode());
			case EFor:
				var v = doDecodeString();
				var it = doDecode();
				EFor(v, it, doDecode());
			case EForGen:
				var it = doDecode();
				var e = doDecode();
				EForGen(it, e);
			case EBreak:
				EBreak;
			case EContinue:
				EContinue;
			case EFunction:
				var params = new Array<Argument>();
				for (i in 0...doDecodeInt())
					params.push(doDecodeArg());
				var e = doDecode();
				var depth = doDecodeInt();
				var name = doDecodeString();

				var t:Null<CType> = if(doDecodeBool()) doDecodeCType() else null;
				var access:Null<Array<String>> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeString()] else null;
				EFunction(params, e, depth, (name == "") ? null : name, t, access);
			case EReturn:
				EReturn(doDecode());
			case EArray:
				var e = doDecode();
				EArray(e, doDecode());
			case EArrayDecl:
				var el = new Array();
				var len = doDecodeInt();
				for (i in 0...len)
					el.push(doDecode());
				EArrayDecl(el);
			case ENew:
				var cl = doDecodeTypePath();
				var el = new Array();
				for (i in 0...bin.get(pin++))
					el.push(doDecode());
				ENew(cl, el);
			case EThrow:
				EThrow(doDecode());
			case ETry:
				var e = doDecode();
				var v = doDecodeString();
				ETry(e, v, null, doDecode());
			case EObject:
				var fl: Array<ObjectDecl> = [];
				var len = doDecodeInt();
				for (i in 0...len) {
					var name = doDecodeString();
					var e = doDecode();
					fl.push({name: name, e: e});
				}
				EObject(fl);
			case ETernary:
				var cond = doDecode();
				var e1 = doDecode();
				var e2 = doDecode();
				ETernary(cond, e1, e2);
			case ESwitch:
				var e = doDecode();
				var cases: Array<SwitchCase> = [];
				while (true) {
					var v = doDecode();
					if (v == null)
						break;
					var values = [v];
					while (true) {
						v = doDecode();
						if (v == null)
							break;
						values.push(v);
					}
					var expr = doDecode();
					var ifExpr = doDecode();
					cases.push({values: values, expr: expr, ifExpr: ifExpr});
				}
				var def = doDecode();
				ESwitch(e, cases, def);
			case EMeta:
				var name = doDecodeString();
				var count = doDecodeInt();
				var args = count == 0 ? null : [for (i in 0...count - 1) doDecode()];
				EMeta(name, args, doDecode());
			case ECheckType:
				ECheckType(doDecode(), doDecodeCType());
			case EEnum:
				var name = doDecodeString();
				var fields: Array<EnumType> = [];
				for (i in 0...bin.get(pin++)) {
					switch (bin.get(pin++)) {
						case 0:
							var name = doDecodeString();
							fields.push(ESimple(name));
						case 1:
							var name = doDecodeString();
							var args: Array<Argument> = [];
							for (i in 0...bin.get(pin++))
								args.push(doDecodeArg());
							fields.push(EConstructor(name, args));
						default:
							throw "Invalid code " + bin.get(pin - 1);
					}
				}
				var pkg:Array<String> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeString()] else null;
				EEnum(name, fields, pkg);
			case EClass:
				var cls = doDecodeString();
				var exn:Null<TypePath> = if(doDecodeBool()) doDecodeTypePath() else null;
				var imn = [for(i in 0...doDecodeInt()) doDecodeTypePath()];
				var fields = [for(i in 0...doDecodeInt()) doDecodeClassField()];
				var pkg:Array<String> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeString()] else null;
				EClass(cls, exn, imn, fields, null, pkg);
			case ETypedef:
				var n = doDecodeString();
				var t = doDecodeCType();
				var pkg:Array<String> = if(doDecodeBool()) [for(i in 0...doDecodeInt()) doDecodeString()] else null;
				ETypedef(n, t, pkg);
			case EImport:
				var v = doDecodeString();
				var as:Null<String> = if(doDecodeBool()) doDecodeString() else null;
				var star = doDecodeBool();
				EImport(v, as, star);
			case EUsing:
				var name = doDecodeString();
				EUsing(name);
			case ECast:
				var e = doDecode();
				var shut = doDecodeBool();
				var t:Null<CType> = (doDecodeBool() ? doDecodeCType() : null);
				ECast(e, shut, t);
			case 255:
				null;
				// default:
				//	throw "Invalid code " + bin.get(pin - 1);
		}
	}

	public static function encode(e: Expr): haxe.io.Bytes {
		var b = new Bytes();
		b.doEncode(e);
		return b.bout.getBytes();
	}

	public static function decode(bytes: haxe.io.Bytes): Expr {
		var b = new Bytes(bytes);
		return b.doDecode();
	}
}