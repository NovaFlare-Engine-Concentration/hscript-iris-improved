package macros;

import haxe.macro.Expr;
import haxe.macro.Context;

using StringTools;

class TestingMacro {
	public static function build(): Array<Field> {
		var fields = Context.getBuildFields();
		var testFields: Array<String> = [];
		for (field in fields) {
			if (Lambda.find(field.meta ?? [], m -> m.name == ":noTest") == null
				&& field.name.startsWith("test_")
				&& field.kind.match(FFun(_))) {
				testFields.push(field.name);
				resolveTestFunction(field);
			}
		}
		var mainField: Field = Lambda.find(fields, (f) -> f.name == "main");
		if (mainField != null && mainField.access.contains(AStatic) && mainField.kind.match(FFun(_))) {
			switch (mainField.kind) {
				case FFun(func):
					var insteaded: Expr = macro {
						$e{func.expr} ${

							{
								expr: EBlock([
									for (fn in testFields) {expr: ECall({expr: EConst(CIdent(fn)), pos: Context.currentPos()}, []), pos: Context.currentPos()}
								]),
								pos: Context.currentPos()
							}
						}
					}
					func.expr = insteaded;
				default:
			}
		}
		return fields;
	}

	static function resolveTestFunction(field: Field) {
		var display = field.name.substr("test_".length);
		if (field.meta != null && field.meta.length > 0)
			for (meta in field.meta) {
				if (meta.name == ":testName") {
					if (meta.params[0] != null) {
						switch (meta.params[0].expr) {
							case EConst(c):
								switch (c) {
									case CString(str):
										display = str;
									case _:
								}
							case _:
						}
					}
				}
			}
		switch (field.kind) {
			case FFun(func):
				var added = macro {
					function __shagua(idk: String, opt: String = "="): String {
						var e = "";
						for (i in 0...idk.length)
							e += opt;
						return e;
					}
					var __start = "======["
						+ "Starting To Test Script -> \""
						+ ${{expr: EConst(CString(display)), pos: Context.currentPos()}} + "\"" + "]======";
					var __end = "======[" + "Over Test Script -> \"" + ${{expr: EConst(CString(display)), pos: Context.currentPos()}} + "\"" + "]======";
					Sys.println("\n" + __shagua(__start) + "\n" + __start);
					var start = haxe.Timer.stamp();
					$e{func.expr} Sys.println("Execute Time: " + (haxe.Timer.stamp() - start) + "s");
					Sys.println(__end + "\n" + __shagua(__end) + "\n");
				};
				func.expr = added;
			case _:
		}
	}
}
