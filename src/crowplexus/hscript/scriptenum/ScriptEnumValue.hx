package crowplexus.hscript.scriptenum;

import crowplexus.hscript.Tools;

class ScriptEnumValue {
	public var enumName: String;
	public var name: String;
	public var index: Int;
	public var args: Array<Dynamic>;

	var parent: ScriptEnum;

	public function new(parent: ScriptEnum, enumName: String, name: String, index: Int, ?args: Array<Dynamic>) {
		this.parent = parent;
		this.enumName = enumName;
		this.name = name;
		this.index = index;
		this.args = args;
	}

	public function getEnum(): Dynamic {
		return parent;
	}

	public function toString(): String {
		if (args == null)
			return enumName + "." + name;
		return enumName + "." + name + "(" + [for (arg in args) arg].join(", ") + ")";
	}

	public inline function getEnumName(): String
		return this.enumName;

	public inline function getConstructorArgs(): Array<Dynamic>
		return this.args != null ? this.args : [];

	public function compare(other: ScriptEnumValue): Bool {
		if (this.parent != other.parent)
			return false;
		if (enumName != other.enumName || name != other.name)
			return false;
		if (args == null && other.args == null)
			return true;
		if (args == null || other.args == null)
			return false;
		if (Tools.valueSwitchMatch(args, other.args))
			return true;

		return false;
	}
}
