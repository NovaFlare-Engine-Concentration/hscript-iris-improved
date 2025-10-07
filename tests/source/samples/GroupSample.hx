package samples;

class GroupSample<T:BaseSample<Dynamic>> extends BaseSample<Dynamic> {
	public var members: Array<T>;

	public var outputs(default, null): Array<Dynamic>;

	public var length(get, never): Int;

	@:dox(hide) inline function get_length(): Int {
		return members.length;
	}

	public function new() {
		members = new Array<T>();
		super();
	}

	public override function inputContent(content: Dynamic) {
		if (active) {
			for (member in members) {
				member.inputContent(content);
			}
		}
	}

	public override function working(): Void {
		if (active) {
			this.outputs = [];
			for (member in members) {
				member.working();
				outputs.push(member.output);
			}
		}
	}

	public function interator(func: T->Void) {
		for (m in members) {
			func(m);
		}
	}

	public function push(sample: T) {
		if (this.active && sample.exists && sample.active) {
			members.push(sample);
		}
	}

	public function insert(pos: Int, sample: T) {
		if (this.active && sample.exists && sample.active) {
			members.insert(pos, sample);
		}
	}

	public function remove(sample: T) {
		if (this.active && sample.exists && sample.active && members.contains(sample)) {
			members.remove(sample);
		}
	}

	override function destroy() {
		members = null;
	}

	override function toString(): String {
		return '(length: $this.length | active: ${this.active} | exists: ${this.exists})';
	}
}
