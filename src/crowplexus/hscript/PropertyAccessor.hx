package crowplexus.hscript;

// 我又干了
// 呵呵，我乱命名的，别在意
class PropertyAccessor {
	public var getter(default, null): String;
	public var setter(default, null): String;
	public var proxy(default, null): Interp;
	public var inState(default, null): Bool = true;
	public var link_getFunc(default, null): Void->Dynamic;
	public var link_setFunc(default, null): Dynamic->Dynamic;

	var isStatic: Bool;

	public function new(proxy: Interp, link_getFunc: Void->Dynamic, link_setFunc: Dynamic->Dynamic, getter1: String = "default", setter1: String = "default",
			isStatic: Bool = false) {
		this.proxy = proxy;
		this.link_getFunc = link_getFunc;
		this.link_setFunc = link_setFunc;
		this.getter = getter1;
		this.setter = setter1;
		this.isStatic = isStatic;
	}

	public function get(name: String): Dynamic {
		if (link_getFunc == null && proxy == null)
			return null;
		return switch (getter) {
			case "default":
				link_getFunc();
			case "never":
				throw proxy.error(ECustom('Cannot Access Read This Property -> "$name"'));
				null;
			case "null":
				link_getFunc();
			case "get":
				final variables = {
					if (this.isStatic)
						Interp.staticVariables;
					else
						proxy.variables;
				}
				if (Reflect.isFunction(variables.get('get_$name'))) {
					inState = false;
					var ret: Dynamic = Reflect.callMethod(null, variables.get('get_$name'), []);
					inState = true;
					return ret;
				} else
					proxy.error(ECustom('Cannot Access Read This Property "$name" Due To Invalid Function -> "get_$name"'));
				null;
			default:
				null;
		}
	}

	public function set(name: String, value: Dynamic) {
		if (link_setFunc == null && proxy == null)
			return null;
		return switch (setter) {
			case "default":
				link_setFunc(value);
			case "never":
				throw proxy.error(ECustom('Cannot Access Write This Property -> "$name"'));
				null;
			case "null":
				link_setFunc(value);
			case "set":
				final variables = {
					if (this.isStatic)
						Interp.staticVariables;
					else
						proxy.variables;
				}
				if (Reflect.isFunction(variables.get('set_$name'))) {
					inState = false;
					var ret: Dynamic = Reflect.callMethod(null, variables.get('set_$name'), [value]);
					inState = true;
					return ret;
				} else
					proxy.error(ECustom('Cannot Access Write This Property "$name" Due To Invalid Function -> "set_$name"'));
				null;
			default:
				null;
		}
	}
}
