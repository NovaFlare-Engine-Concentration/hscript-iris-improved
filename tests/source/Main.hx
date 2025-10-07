package;

import samples.*;
import scripted.*;
import crowplexus.hscript.Interp;
import crowplexus.hscript.Parser;
import crowplexus.hscript.Expr;
import crowplexus.hscript.Tools;
import crowplexus.hscript.scriptclass.IScriptedClass;
import crowplexus.iris.Iris;
import haxe.Constraints;

@:build(macros.TestingMacro.build())
class Main {
	public static function test_hello_world() {
		var script: HScript = new HScript("hello_world");
		script.execute();
		script.call("onCreate");
		for (i in 0...9)
			script.call("mathTen");
	}

	public static function test_static_variables() {
		var script1: HScript = new HScript("static_variables_1");
		script1.execute();
		var script1: HScript = new HScript("static_variables_2");
		script1.execute();
		script1.call("onCreate");
	}

	@:testName("typedef & name")
	public static function test_typedef_enum() {
		var script: HScript = new HScript("typedef_enum", true, false, false);
		script.execute();
	}

	@:testName("regex & interpolation")
	public static function test_regex_interpolation() {
		var script: HScript = new HScript("test_regex_interpolation", false, false, true);
		script.set("interpolation_player", "Beihu235");
		script.execute();
	}

	@:testName("import shared variables")
	public static function test_import_shared() {
		var script1: HScript = new HScript("shared/transmitter", false, false, false, "shared");
		script1.execute();
		var script2: HScript = new HScript("shared/recipient", false, false, false, "shared");
		@:privateAccess script2.interp.allowAbstractHappened = true;
		script2.execute();
	}

	@:testName("is type")
	public static function test_isType() {
		var script: HScript = new HScript("isType");
		script.execute();
	}

	@:testName
	public static function test_class_samples() {
		var script: HScript = new HScript("class_samples", false, true, false);
		script.execute();

		for (path in ScriptedBaseSample.__sc_scriptClassLists()) {
			trace(ScriptedBaseSample.createScriptClassInstance(path));
		}
	}

	public static function test_switch_case() {
		var script: HScript = new HScript("switch_case", true);
		script.set("EnumSample", samples.enums.EnumSample);
		script.set("EnumSampleBinop", samples.enums.EnumSampleBinop);
		script.set("SampleRef", samples.enums.EnumSampleBinop.SampleRef);
		script.execute();

		script.call("onCreate");
	}

	@:testName("proxy: xml \"Access\"")
	public static function test_proxy_access() {
		var script: HScript = new HScript("proxy/xmlAccess", false, false, true);
		script.execute();
		if (script.exists("onCreate"))
			script.call("onCreate");
	}

	public static function test_import_star() {
		var script: HScript = new HScript("import_star");
		script.execute();
	}

	public static function test_extra() {
		var script: HScript = new HScript("extra");
		script.execute();
	}

	public static function main() {
		Main.init();
		Usage.init();
	}

	@:noCompletion static function loadNeeded() {
		trace(ScriptedBaseSample);
		trace(ScriptedGroupSample);
		trace(ObjectSample);
		trace(IntSample);
		trace(cast([], IMap<Dynamic, Dynamic>));
	}

	static function init() {
		Assets.init(haxe.io.Path.addTrailingSlash(Sys.getCwd()) + "assets", ["hxc", "hxs"]);
	}
}
