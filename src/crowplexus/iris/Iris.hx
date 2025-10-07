package crowplexus.iris;

import crowplexus.iris.utils.Ansi;
import haxe.ds.StringMap;
import crowplexus.hscript.*;
import crowplexus.hscript.Expr;
import crowplexus.iris.ErrorSeverity;
import crowplexus.iris.IrisConfig;
import crowplexus.iris.utils.UsingEntry;
import crowplexus.hscript.ISharedScript;
import scripts.stages.modules.ScriptedModuleNotify;
import scripts.stages.modules.ModuleAgency;

using crowplexus.iris.utils.Ansi;
using StringTools;

@:structInit
class IrisCall {
	/**
	 * an HScript Function Name.
	**/
	public var funName: String;

	/**
	 * an HScript Function's signature.
	**/
	public var signature: Dynamic;

	/**
	 * an HScript Method's return value.
	**/
	public var returnValue: Dynamic;
}

/**
 * This basic object helps with the creation of scripts,
 * along with having neat helper functions to initialize and stop scripts
 *
 * It is highly recommended that you override this class to add custom defualt variables and such.
**/
class Iris implements ISharedScript {
	/**
	 * Map with stored instances of scripts.
	**/
	public static var instances: StringMap<Iris> = new StringMap<Iris>();

	public static var registeredUsingEntries: Array<UsingEntry> = [
		new UsingEntry("StringTools", function(o: Dynamic, f: String, args: Array<Dynamic>): IrisCall {
			if (f == "isEof") // has @:noUsing
				return null;
			switch (Type.typeof(o)) {
				case TInt if (f == "hex"):
					return {funName: f, signature: o, returnValue: StringTools.hex(o, args[0])};
				case TClass(String):
					var field: Dynamic = Reflect.getProperty(StringTools, f);
					if (Reflect.isFunction(field)) {
						return {funName: f, signature: o, returnValue: Reflect.callMethod(StringTools, field, [o].concat(args))};
					}
				default:
			}
			return null;
		}),
		new UsingEntry("Lambda", function(o: Dynamic, f: String, args: Array<Dynamic>): Dynamic {
			if (Tools.isIterable(o)) {
				var field = Reflect.getProperty(Lambda, f);
				if (Reflect.isFunction(field)) {
					return {funName: f, signature: o, returnValue: Reflect.callMethod(Lambda, field, [o].concat(args))};
				}
			}
			return null;
		}),
	];

	/**
	 * Contains Classes/Enums that cannot be accessed via HScript.
	 *
	 * you may find this useful if you want your project to be more secure.
	**/
	@:unreflective public static var blocklistImports: Array<String> = [];

	/**
	 * Contains proxies for classes. So they can be sandboxed or add extra functionality.
	**/
	@:unreflective public static var proxyImports: Map<String, Dynamic> = crowplexus.iris.macro.ProxyMacro.getProxyClasses();

	@:unreflective public static var starPackageClasses:Map<String, Array<{var name:String; var value:Dynamic;}>> = #if STAR_CLASSES {
		var r:Array<String> = cast Lambda.find(haxe.rtti.Rtti.getRtti(Iris).meta, f -> f.name == ":classes")?.params ?? [];
		var map = new Map<String, Array<{var name:String; var value:Dynamic;}>>();

		for (i in r) {
			final lastIndex = i.lastIndexOf(".");
			final pack = lastIndex > -1 ? i.substr(0, lastIndex) : "";
			final lastName = i.substr(lastIndex > -1 ? lastIndex + 1 : 0);

			if (lastIndex > -1 && i.indexOf('_Impl_') == -1 && pack.trim() != "")
			{
				var c = Iris.proxyImports.get(i) ?? crowplexus.hscript.proxy.ProxyType.resolveClass(i);
				if (c != null) {
					if(!map.exists(pack)) map.set(pack, []);
					map[pack].push({name: lastName, value: c});
				}
			}
		}

		map;
	}
	#else
	[]
	#end;

	public static function addBlocklistImport(name: String): Void {
		blocklistImports.push(name);
	}

	public static function addProxyImport(name: String, value: Dynamic): Void {
		proxyImports.set(name, value);
	}

	public static function getProxiedImport(name: String): Dynamic {
		return proxyImports.get(name);
	}

	private static function getDefaultPos(name: String = "Iris"): haxe.PosInfos {
		return {
			fileName: name,
			lineNumber: -1,
			className: "UnknownClass",
			methodName: "unknownFunction",
			customParams: null
		}
	}

	/**
	 * Custom warning function for script wrappers.
	 *
	 * Overriding is recommended if you're doing custom error handling.
	**/
	public dynamic static function logLevel(level: ErrorSeverity, x, ?pos: haxe.PosInfos): Void {
		if (pos == null) {
			pos = getDefaultPos();
		}

		var out = Std.string(x);
		if (pos != null && pos.customParams != null)
			for (i in pos.customParams)
				out += "," + i;

		var prefix = ErrorSeverityTools.getPrefix(level);
		if (prefix != "" && prefix != null) {
			prefix = '$prefix:';
		}
		var posPrefix = '[$prefix${pos.fileName}]';
		if (pos.lineNumber != -1)
			posPrefix = '[$prefix${pos.fileName}:${pos.lineNumber}]';

		if (prefix != "" && prefix != null) {
			posPrefix = posPrefix.fg(ErrorSeverityTools.getColor(level)).reset();
			if (level == FATAL) {
				posPrefix = posPrefix.attr(INTENSITY_BOLD);
			}
		}
		#if sys
		Sys.println((posPrefix + ": " + out).stripColor());
		#else
		// Since non-sys targets lack printLn, a simple trace should work
		trace((posPrefix + ": " + out).stripColor());
		#end
	}

	/**
	 * Custom print function for script wrappers.
	**/
	public dynamic static function print(x, ?pos: haxe.PosInfos): Void {
		logLevel(NONE, x, pos);
	}

	/**
	 * Custom error function for script wrappers.
	**/
	public dynamic static function error(x, ?pos: haxe.PosInfos): Void {
		logLevel(ERROR, x, pos);
	}

	/**
	 * Custom warning function for script wrappers.
	 *
	 * Overriding is recommended if you're doing custom error handling.
	**/
	public dynamic static function warn(x, ?pos: haxe.PosInfos): Void {
		logLevel(WARN, x, pos);
	}

	/**
	 * Custom fatal error function for script wrappers.
	**/
	public dynamic static function fatal(x, ?pos: haxe.PosInfos): Void {
		logLevel(FATAL, x, pos);
	}

	/**
	 * Config file, set when creating a new `Iris` instance.
	**/
	public var config: IrisConfig = null;

	public var standard(get, never): Dynamic;

	public function get_standard(): Dynamic {
		return this;
	}

	/**
	 * Current script name, from `config.name`.
	**/
	public var name(get, never): String;

	inline function get_name(): String
		return config.name;

	/**
	 * The code passed in the `new` function for this script.
	 *
	 * contains a full haxe script instance
	**/
	var scriptCode: String = "";

	/**
	 * Current initialized script interpreter.
	**/
	var interp: Interp;

	/**
	 * Current initialized script parser.
	**/
	var parser: Parser;

	/**
	 * Current initialized script expression.
	**/
	var expr: Expr;

	/**
	 * Helper variable for the error string caused by a nulled interpreter.
	**/
	final interpErrStr: String = "Careful, the interpreter hasn't been initialized";

	/**
	 * Instantiates a new Script with the string value.
	 *
	 * ```haxe
	 * trace("Hello World!");
	 * ```
	 *
	 * will trace "Hello World!" to the standard output.
	 * @param scriptCode      the script to be parsed, e.g:
	 */
	public function new(scriptCode: String, ?config: AutoIrisConfig): Void {
		if (config == null)
			config = new IrisConfig("Iris", true, true, []);
		this.scriptCode = scriptCode;
		this.config = IrisConfig.from(config);
		this.config.name = fixScriptName(this.name);

		parser = new Parser();
		interp = new Interp();
		interp.showPosOnLog = false;
		interp.allowScriptEnum = this.config.allowEnum;
		interp.allowScriptClass = this.config.allowClass;
		interp.importHandler = _importHandler;

		parser.allowTypes = true;
		parser.allowMetadata = true;
		parser.allowJSON = true;
		parser.preprocesorValues = crowplexus.iris.macro.DefineMacro.defines;

		// set variables to the interpreter.
		if (this.config.autoPreset)
			preset();
		// run the script.
		if (this.config.autoRun)
			execute();
	}

	private static function fixScriptName(toFix: String): String {
		// makes sure that we never have instances with identical names.
		var _name = toFix;
		var copyID: Int = 1;
		while (Iris.instances.exists(_name)) {
			_name = toFix + "_" + copyID;
			copyID += 1;
		}
		return _name;
	}

	/**
	 * Executes this script and returns the interp's run result.
	**/
	public function execute(): Dynamic {
		// I'm sorry but if you just decide to destroy the script at will, that's your fault
		if (interp == null)
			throw "Attempt to run script failed, script is probably destroyed.";

		if (expr == null)
			expr = parse();

		Iris.instances.set(this.name, this);

		return try {
			if (expr != null)
				interp.execute(expr);
			else
				null;
		#if hscriptPos
		} catch (e:Error) {
			Iris.error(Printer.errorToString(e, false), cast {fileName: e.origin, lineNumber: e.line});
			null;
		#end
		} catch (e) {
			Iris.error(Std.string(e), cast interp.posInfos());
			null;
		}
	}

	/**
		 * If you want to override the script, you should do parse(true);
		 *
		 * just parse(); otherwise, forcing may fix some behaviour depending on your implementation.
		**/
	public function parse(force: Bool = false) {
		if (force || expr == null) {
			expr = try {
				parser.parseString(scriptCode, this.name, this.config.requestedPackageName);
			#if hscriptPos
			} catch (e:Error) {
				Iris.error(Printer.errorToString(e, false), cast {fileName: e.origin, lineNumber: parser.line});
				null;
			#end
			} catch (e) {
				@:privateAccess Iris.error(Std.string(e), cast {fileName: this.name, lineNumber: 0});
				null;
			}
		}
		return expr;
	}

	/**
			 * Appends Default Classes/Enums for the Script to use.
			**/
	public function preset(): Void {
		/*set("Std", Std);
					set("StringTools", StringTools);
					set("Math", Math); */
	}

	public function hget(name: String, ?e: Expr): Dynamic {
		if (interp != null && exists(name)) {
			var field = interp.directorFields.get(name);
			@:privateAccess
			if (interp.propertyLinks.get(name) != null && field.isPublic) {
				var l = interp.propertyLinks.get(name);
				if (l.inState)
					return l.get(name);
				else
					return l.link_getFunc();
			}

			if (field.isPublic)
				return field.value;
			else
				Iris.warn("This Script -> '" + this.name + "', its field -> '" + name + "' is not public",
					cast #if hscriptPos (e != null ? {fileName: e.origin, lineNumber: e.line} : {
						fileName: "hscript",
						lineNumber: 0
					}) #else {fileName: "hscript", lineNumber: 0} #end);
		} else if (interp != null && !exists(name)) {
			Iris.warn("This Script -> '" + this.name + "' has not field -> '" + name + "'",
				cast #if hscriptPos (e != null ? {fileName: e.origin, lineNumber: e.line} : {fileName: "hscript", lineNumber: 0}) #else {
					fileName: "hscript",
					lineNumber: 0
				} #end);
		}

		return null;
	}

	public function hset(name: String, value: Dynamic, ?e: Expr): Void {
		if (interp != null && exists(name)) {
			var field = interp.directorFields.get(name);
			@:privateAccess
			if (interp.propertyLinks.get(name) != null && field.isPublic) {
				var l = interp.propertyLinks.get(name);
				if (l.inState)
					l.set(name, value);
				else
					l.link_setFunc(value);
				return;
			}

			if (field.isPublic)
				field.value = value;
			else
				Iris.warn("This Script -> '" + this.name + "', its field -> '" + name + "' is not public",
					cast #if hscriptPos (e != null ? {fileName: e.origin, lineNumber: e.line} : {
						fileName: "hscript",
						lineNumber: 0
					}) #else {fileName: "hscript", lineNumber: 0} #end);
		} else if (interp != null && !exists(name)) {
			Iris.warn("This Script -> '" + this.name + "' has not field -> '" + name + "'",
				cast #if hscriptPos (e != null ? {fileName: e.origin, lineNumber: e.line} : {fileName: "hscript", lineNumber: 0}) #else {
					fileName: "hscript",
					lineNumber: 0
				} #end);
		}
	}

	/**
			 * Returns a field from the script.
			 * @param field 	The field that needs to be looked for.
			 */
	public function get(field: String): Dynamic {
		#if IRIS_DEBUG
		if (interp == null)
			Iris.fatal("[Iris:get()]: " + interpErrStr + ", when trying to get variable \"" + field + "\", returning false...");
		#end
		if (interp != null) {
			if (interp.directorFields.get(field) != null)
				return interp.directorFields.get(field).value;
			return interp.variables.get(field);
		}
		return null;
	}

	/**
			 * Sets a new field to the script
			 * @param name          The name of your new field, scripts will be able to use the field with the name given.
			 * @param value         The value for your new field.
			 */
	public function set(name: String, value: Dynamic): Void {
		if (interp == null || interp.variables == null) {
			#if IRIS_DEBUG
			Iris.fatal("[Iris:set()]: " + interpErrStr + ", when trying to set variable \"" + name + "\" so variables cannot be set.");
			#end
			return;
		}

		if (interp.imports != null)
			interp.imports.set(name, value);
	}

	/**
			 * Calls a method on the script
			 * @param fun       The name of the method you wanna call.
			 * @param args      The arguments that the method needs.
			 */
	public function call(fun: String, ?args: Array<Dynamic>): IrisCall {
		if (interp == null) {
			#if IRIS_DEBUG
			trace("[Iris:call()]: " + interpErrStr + ", so functions cannot be called.");
			#end
			return null;
		}

		if (args == null)
			args = [];

		// fun-ny
		var ny: Dynamic = interp.directorFields.get(fun); // function signature
		var isFunction: Bool = false;
		try {
			isFunction = ny != null && ny.type == "func" && Reflect.isFunction(ny.value);
			if (!isFunction)
				throw 'Tried to call a non-function, for "$fun"';
			// throw "Variable not found or not callable, for \"" + fun + "\"";

			final ret = Reflect.callMethod(null, ny.value, args);
			return {funName: fun, signature: ny, returnValue: ret};
		}
		// @formatter:off
		#if hscriptPos
		catch (e:Expr.Error) {
			Iris.error(Printer.errorToString(e, false), this.interp.posInfos());
		}
		#end
		catch(e) {
			var pos = isFunction ? this.interp.posInfos() : Iris.getDefaultPos(this.name);
			Iris.error(Std.string(e), pos);
		}
		// @formatter:on
		return null;
	}

	/**
			 * Checks the existance of a field or method within your script.
			 * @param field 		The field to check if exists.
			 */
	public function exists(field: String): Bool {
		#if IRIS_DEBUG
		if (interp == null)
			trace("[Iris:exists()]: " + interpErrStr + ", returning false...");
		#end
		return (interp != null) ? interp.directorFields.get(field) != null : false;
	}

	/**
			 * Destroys the current instance of this script
			 * along with its parser, and also removes it from the `Iris.instances` map.
			 *
			 * **WARNING**: this action CANNOT be undone.
			**/
	public function destroy(): Void {
		if (Iris.instances.exists(this.name))
			Iris.instances.remove(this.name);
		interp = null;
		parser = null;
	}

	@:noCompletion function _importHandler(s: String, alias: String, ?star:Bool): Bool {
		var replacer: String = StringTools.replace(s, ".", "/");
		if (Iris.instances.exists(replacer)) {
			var iris = Iris.instances.get(replacer);
			#if IRIS_DEBUG
			trace("try to importing script '" + replacer + "'");
			#end
			if (iris != null) {
				this.interp.imports.set((alias == null || StringTools.trim(alias) == "" ? Tools.last(replacer.split("/")) : alias), iris);
				return true;
			}
		} else {
			final last = s.lastIndexOf(".");
			final p = (star == true ? s : s.substr(0, last > -1 ? last : 0));
			#if STAR_CLASSES
			if(star == true) {
				@:privateAccess if(ScriptedModuleNotify.classSystems.exists(p)) {
					for(m in ScriptedModuleNotify.classSystems.get(p)) {
						for(id=>cl in m.unusedClasses) {
							if(m._preClassesName.contains(id)) m.unusedClasses.remove(id);
							m.__interp.execute(cl);
						}
					}
				}
			} else
			#end
			{
				final cn = (star == true ? "" : s.substr(last > -1 ? last + 1 : 0));
				@:privateAccess if(ScriptedModuleNotify.classSystems.exists(p)) {
					for(m in ScriptedModuleNotify.classSystems.get(p)) {
						if(m.unusedClasses.exists(cn)) {
							ModuleAgency.runThrow(() -> m.__interp.execute(m.unusedClasses.get(cn)), m.origin);
							break;
						}
					}
				}
			}
		}

		return false;
	}

	/**
			 * Destroys every single script found within the `Iris.instances` map.
			 *
			 * **WARNING**: this action CANNOT be undone.
			**/
	public static function destroyAll(): Void {
		for (key in Iris.instances.keys()) {
			var iris = Iris.instances.get(key);
			if (iris.interp == null)
				continue;
			iris.destroy();
		}

		Iris.instances.clear();
		Iris.instances = new StringMap<Iris>();
	}

	public static function registerUsingGlobal(name: String, call: UsingCall): UsingEntry {
		var entry = new UsingEntry(name, call);
		Iris.registeredUsingEntries.push(entry);
		return entry;
	}
}
