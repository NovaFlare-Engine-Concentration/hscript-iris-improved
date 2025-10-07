package crowplexus.iris;

abstract OneOfTwo<T1, T2>(Dynamic) from T1 from T2 to T1 to T2 {}

typedef RawIrisConfig = {
	var name: String;
	var ?allowEnum: Bool;
	var ?allowClass: Bool;
	var ?autoRun: Bool;
	var ?autoPreset: Bool;
	var ?requestedPackageName: String;
	var ?localBlocklist: Array<String>;
};

typedef AutoIrisConfig = OneOfTwo<IrisConfig, RawIrisConfig>;

class IrisConfig {
	public var name: String = null;
	public var allowEnum: Bool = false;
	public var allowClass: Bool = false;
	public var autoRun: Bool = true;
	public var autoPreset: Bool = true;
	public var requestedPackageName: String = null;
	@:unreflective public var localBlocklist: Array<String> = [];

	/**
	 * Initialises the Iris script config.
	 *
	 * @param name			The obvious!
	 * @param allowEnum			support script enum
	 * @param allowClass			support script class
	 * @param allowAbstract			support script abstract
	 * @param autoRun					Makes the script run automatically upon being created.
	 * @param autoPreset			Makes the script automatically set imports to itself upon creation.
	 * @param requestedPackageName		Idk
	 * @param localBlocklist	List of classes or enums that cannot be used within this particular script
	**/
	public function new(name: String, allowEnum: Bool = false, allowClass: Bool = false, autoRun: Bool = true, autoPreset: Bool = true,
			?requestedPackageName: String, ?localBlocklist: Array<String>) {
		this.name = name;
		this.allowEnum = allowEnum;
		this.allowClass = allowClass;
		this.autoRun = autoRun;
		this.autoPreset = autoPreset;
		if (requestedPackageName != null)
			this.requestedPackageName = requestedPackageName;
		if (localBlocklist != null)
			this.localBlocklist = localBlocklist;
	}

	public static function from(d: AutoIrisConfig): IrisConfig {
		if (d != null && Std.isOfType(d, IrisConfig))
			return d;
		var d: RawIrisConfig = cast d;
		return new IrisConfig(d.name, d.allowEnum, d.allowClass, d.autoRun, d.autoPreset, d.requestedPackageName, d.localBlocklist);
	}
}
