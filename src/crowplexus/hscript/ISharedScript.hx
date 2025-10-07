package crowplexus.hscript;

import crowplexus.hscript.Expr;

/**
 * 一种更抽象的玩意儿
 * @see https://github.com/CodenameCrew/hscript-improved/blob/master/hscript/IHScriptCustomBehaviour.hx
 */
interface ISharedScript {
	public var standard(get, never): Dynamic;
	public function get_standard(): Dynamic;

	public function hget(name: String, ?expr: Expr): Dynamic;
	public function hset(name: String, value: Dynamic, ?expr: Expr): Void;
}
