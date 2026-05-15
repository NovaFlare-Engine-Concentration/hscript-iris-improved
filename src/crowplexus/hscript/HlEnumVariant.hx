package crowplexus.hscript;

#if hl
@:allow(crowplexus.hscript.Interp)
class HlEnumVariant {
	static var _cache_profity:Map<String, Array<HlEnumVariant>> = new Map();
	@:access(String)
	public static function get(e: Enum<Dynamic>, n: String): Dynamic {
		var shabby: hl.BaseType.Enum = cast e;
		final b = n.bytes;

		var index:Int = if(shabby.__emap__.exists(b)) {
			var i = cast(shabby.__emap__.get(b), Int);
			if(shabby.__evalues__[i] != null) return shabby.__evalues__[i];
			i;
		} else return null;

		/*
		if(o is Enum) @:privateAccess {
			var shabby: hl.BaseType.Enum = cast o;
			final b = f.bytes;
			if(shabby.__emap__.exists(b)) {
				return new crowplexus.hscript.HlEnumVariant(cast(shabby.__emap__.get(b), Int), cast o);
			}
		}
		*/
		final en = Type.getEnumName(e);
		var arr = if(!_cache_profity.exists(en)) {
			var tmp = [];
			_cache_profity.set(en, tmp);
			tmp;
		} else _cache_profity.get(en);

		if(index > -1) {
			if(arr.length - 1 < index || arr[index] == null) {
				final tmp = new crowplexus.hscript.HlEnumVariant(index, e);
				arr[index] = tmp;
				return tmp;
			} else {
				return arr[index];
			}
		}

		return null;
	}

	var i: Int;
	var e: Enum<Dynamic>;

	function new(i: Int, e: Enum<Dynamic>) {
		this.i = i;
		this.e = e;
	}

	public function create(?args: Array<Dynamic>): Dynamic {
		return Type.createEnumIndex(e, i, args);
	}
}
#end