package crowplexus.hscript.proxy.haxe.xml;

import crowplexus.hscript.ISharedScript;
import crowplexus.hscript.Expr;

private class ProxyHasNodeAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		return this.x.elementsNamed(name).hasNext();
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		throw "Invalid Field -> " + name;
	}
}

private class ProxyHasAttribAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		if (this.x.nodeType == Xml.Document)
			throw "Cannot access document attribute " + name;
		return this.x.exists(name);
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		throw "Invalid Field -> " + name;
	}
}

private class ProxyAttribAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		if (this.x.nodeType == Xml.Document)
			throw "Cannot access document attribute " + name;
		var v = this.x.get(name);
		if (v == null)
			throw this.x.nodeName + " is missing attribute " + name;
		return v;
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		throw "Invalid Field -> " + name;
	}
}

private class ProxyNodeAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		var x: Xml = this.x.elementsNamed(name).next();
		if (x == null) {
			var xname = if (this.x.nodeType == Xml.Document) "Document" else this.x.nodeName;
			throw xname + " is missing element " + name;
		}
		return new ProxyAccess(x);
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		throw "Invalid Field -> " + name;
	}
}

private class ProxyNodeListAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		var l = [];
		for (x in this.x.elementsNamed(name))
			l.push(new ProxyAccess(x));
		return l;
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		throw "Invalid Field -> " + name;
	}
}

class ProxyAccess implements ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this.x;
	}

	public var name(get, never): String;

	inline function get_name(): String {
		return if (this.x.nodeType == Xml.Document) "Document" else this.x.nodeName;
	}

	public var innerData(get, never): String;
	public var innerHTML(get, never): String;
	public var node(default, null): ProxyNodeAccess;
	public var nodes(default, null): ProxyNodeListAccess;
	public var att(default, null): ProxyAttribAccess;
	public var has(default, null): ProxyHasAttribAccess;
	public var hasNode(default, null): ProxyHasNodeAccess;

	var x: Xml;

	public function new(x: Xml) {
		this.x = x;
		node = new ProxyNodeAccess(x);
		nodes = new ProxyNodeListAccess(x);
		att = new ProxyAttribAccess(x);
		has = new ProxyHasAttribAccess(x);
		hasNode = new ProxyHasNodeAccess(x);
	}

	public function hget(name: String, ?expr: Expr): Dynamic {
		return switch (name) {
			case "name" | "x" | "innerData" | "innerHTML" | "node" | "nodes" | "att" | "has" | "hasNode":
				Reflect.getProperty(this, name);
			default:
				throw "Invalid Field -> " + name;
				null;
		}
	}

	public function hset(name: String, value: Dynamic, ?expr: Expr): Void {
		switch (name) {
			default:
				throw "Invalid Field -> " + name;
		}
	}

	function get_innerData(): String {
		var it = this.x.iterator();
		if (!it.hasNext())
			throw name + " does not have data";
		var v = it.next();
		if (it.hasNext()) {
			var n = it.next();
			// handle <spaces>CDATA<spaces>
			if (v.nodeType == Xml.PCData && n.nodeType == Xml.CData && StringTools.trim(v.nodeValue) == "") {
				if (!it.hasNext())
					return n.nodeValue;
				var n2 = it.next();
				if (n2.nodeType == Xml.PCData && StringTools.trim(n2.nodeValue) == "" && !it.hasNext())
					return n.nodeValue;
			}
			throw name + " does not only have data";
		}
		if (v.nodeType != Xml.PCData && v.nodeType != Xml.CData)
			throw name + " does not have data";
		return v.nodeValue;
	}

	function get_innerHTML(): String {
		var s = new StringBuf();
		for (x in this.x)
			s.add(x.toString());
		return s.toString();
	}
}
