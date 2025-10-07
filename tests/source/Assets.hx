package;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import haxe.io.Path;

class Assets {
	private static var rootPath: String;
	private static var scriptExtensions: Array<String>;

	public static function init(?rootPath: String, ?supportScriptExtensions: Array<String>) {
		if (supportScriptExtensions == null)
			supportScriptExtensions = [];
		Assets.scriptExtensions = supportScriptExtensions;
		#if sys
		Assets.rootPath = Path.addTrailingSlash(if (rootPath != null) rootPath else Sys.getCwd());
		#else
		error("Assets is not supported in the current version");
		#end
		#if IRIS_DEBUG
		trace("Assets:Get Root Path: " + Assets.rootPath);
		trace("Assets:Get Scripts Extension: " + scriptExtensions);
		#end
	}

	public static function getXml(path: String): Null<String> {
		return getContent(Path.withoutExtension(path) + ".xml");
	}

	public static function getScript(path: String): Null<String> {
		path = Path.withoutExtension(path);
		for (ext in scriptExtensions) {
			var realPath = "scripts/" + path + "." + ext;
			if (exists(realPath))
				return getContent(realPath);
		}
		return null;
	}

	public static function exists(path: String): Bool {
		#if sys
		return FileSystem.exists(rootPath + path);
		#else
		error("Assets is not supported in the current version");
		return false;
		#end
	}

	public static function getContent(path: String): Null<String> {
		#if IRIS_DEBUG
		trace("Assets:getContent():Loading Path: " + path);
		#end
		#if sys
		return try {
			File.getContent(rootPath + path);
		} catch (e) {
			error(Std.string(e));
			null;
		}
		#else
		error("Assets is not supported in the current version");
		return "";
		#end
	}

	private inline static function error(str: String) {
		throw str;
	}

	private inline static function warn(str: String) {
		#if sys
		Sys.println(str);
		#end
	}
}
