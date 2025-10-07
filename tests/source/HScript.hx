package;

import crowplexus.iris.Iris;
import crowplexus.iris.IrisConfig;
import crowplexus.hscript.Expr;
import crowplexus.hscript.Printer;

class HScript extends Iris {
	public var path: String;

	public function new(path: String, allowEnum: Bool = false, allowClass: Bool = false, experimental_features: Bool = false, ?requestedPackageName: String) {
		this.path = path;
		var sc: Null<String> = Assets.getScript(this.path);
		if (sc == null) {
			sc = "";
			Iris.error("Loading this script failed as invalid path -> " + this.path);
		}
		super(sc, new IrisConfig(path, allowEnum, allowClass, false, false, requestedPackageName));
		if (experimental_features) {
			this.parser.allowInterpolation = true;
		}
	}

	override function preset() {
		set("Assets", Assets);
		super.preset();
	}

	public function print(useTab: Bool = false, ?spaceBit: Int = 2): Null<String> {
		if (expr != null) {
			return new Printer(spaceBit, useTab).exprToString(expr);
		}
		return null;
	}
}
