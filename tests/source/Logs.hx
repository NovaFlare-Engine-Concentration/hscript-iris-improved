package;

import haxe.Log;
import haxe.PosInfos;
import sys.io.FileOutput;
import sys.io.File;

class Logs {
	private static var nativeLog: (v: Dynamic, ?infos: PosInfos) -> Void = Log.trace;
	private static var output: FileOutput;

	public static function init() {
		output = File.write("logs.txt");

		Log.trace = trace;
	}

	static function trace(v:Dynamic, ?infos:PosInfos) {
		nativeLog(v, infos);

		output.writeString(Log.formatOutput(v, infos) + "\n");
	}
}