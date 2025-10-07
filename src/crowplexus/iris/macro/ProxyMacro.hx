package crowplexus.iris.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.ExprTools;
import haxe.macro.Expr;
import haxe.macro.Compiler;
import haxe.macro.TypeTools;
#end

class ProxyMacro {
	public static inline var PREFIX:String = "crowplexus.hscript.proxy";

	public static macro function getProxyClasses() {
		#if (macro && !display)
		var map:Map<String, Expr> = [];
		var standard = includeAndGetModules(PREFIX);
		for(module in standard) {
			for(type in module) {
				switch(type) {
					case TInst(_.get() => cls, params) if(!cls.isPrivate && StringTools.startsWith(cls.name, "Proxy")):
						var pack = cls.pack.join(".").substr(PREFIX.length + 1);
						var moduleName = cls.module.substr(cls.module.lastIndexOf(".") + 1);
						map.set((StringTools.trim(pack) != "" ? pack + "." : pack) + cls.name.substr("Proxy".length), Context.parse(cls.pack.join(".") + "." + (moduleName != cls.name ? moduleName + "." + cls.name : cls.name), Context.currentPos()));
					case _:
				}
			}
		}

		return {
			expr: EArrayDecl([for(key=>value in map) {expr: EBinop(OpArrow, {expr: EConst(CString(key)), pos: Context.currentPos()}, value), pos: Context.currentPos()}]),
			pos: Context.currentPos()
		};
		#else
		return macro [];
		#end
	}

	#if macro
	public static function includeAndGetModules(pack:String, ?rec = true, ?ignore:Array<String>, ?classPaths:Array<String>, strict = false):Array<Array<Type>> {
		var modules:Array<Array<Type>> = [];

		var ignoreWildcard:Array<String> = [];
		var ignoreString:Array<String> = [];
		if (ignore != null) {
			for (ignoreRule in ignore) {
				if (StringTools.endsWith(ignoreRule, "*")) {
					ignoreWildcard.push(ignoreRule.substr(0, ignoreRule.length - 1));
				} else {
					ignoreString.push(ignoreRule);
				}
			}
		}
		var skip = if (ignore == null) {
			function(c) return false;
		} else {
			function(c:String) {
				if (Lambda.has(ignoreString, c))
					return true;
				for (ignoreRule in ignoreWildcard)
					if (StringTools.startsWith(c, ignoreRule))
						return true;
				return false;
			}
		}
		var displayValue = Context.definedValue("display");
		if (classPaths == null) {
			classPaths = Context.getClassPath();
			// do not force inclusion when using completion
			switch (displayValue) {
				case null:
				case "usage":
				case _:
					return modules;
			}
			// normalize class path
			for (i in 0...classPaths.length) {
				var cp = StringTools.replace(classPaths[i], "\\", "/");
				if (StringTools.endsWith(cp, "/"))
					cp = cp.substr(0, -1);
				if (cp == "")
					cp = ".";
				classPaths[i] = cp;
			}
		}
		var prefix = pack == '' ? '' : pack + '.';
		var found = false;
		for (cp in classPaths) {
			var path = pack == '' ? cp : cp + "/" + pack.split(".").join("/");
			if (!sys.FileSystem.exists(path) || !sys.FileSystem.isDirectory(path))
				continue;
			found = true;
			for (file in sys.FileSystem.readDirectory(path)) {
				if (StringTools.endsWith(file, ".hx") && file.substr(0, file.length - 3).indexOf(".") < 0) {
					if( file == "import.hx" ) continue;
					var cl = prefix + file.substr(0, file.length - 3);
					if (skip(cl))
						continue;
					final byd = Context.getModule(cl);
					modules.push(byd);
				} else if (rec && sys.FileSystem.isDirectory(path + "/" + file) && !skip(prefix + file)) {
					for(module in includeAndGetModules(prefix + file, true, ignore, classPaths)) modules.push(module);
				}
			}
		}
		if (strict && !found)
			Context.error('Package "$pack" was not found in any of class paths', Context.currentPos());

		return modules;
	}
	#end
}