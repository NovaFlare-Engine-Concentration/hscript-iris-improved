package crowplexus.hscript.scriptenum;

import crowplexus.hscript.Expr;

class ScriptEnum implements crowplexus.hscript.ISharedScript {
	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this;
	}

	public var name: String;
	public var fullPath(get, never): String;

	@:dox(hide) inline function get_fullPath(): String {
		if (packages != null && packages.length > 0) {
			return packages.join(".") + "." + name;
		}
		return name;
	}

	public var packages: Array<String>;

	@:allow(crowplexus.hscript.Interp)
	var sm: Map<String, Dynamic> = [];

	public function new(name: String, ?packages: Array<String>) {
		this.name = name;
		this.packages = packages;
	}

	public function hget(id: String, ?e: Expr): Dynamic {
		if (!sm.exists(id))
			throw "ScriptEnum -> '" + name + "' Has Not EnumValue -> '" + id + "'";
		return sm.get(id);
	}

	public function hset(name: String, value: Dynamic, ?e: Expr): Void {
		throw "Cannot Set-up EnumValue";
	}
}
