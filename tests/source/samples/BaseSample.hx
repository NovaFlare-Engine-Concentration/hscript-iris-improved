package samples;

class BaseSample<T> {
	public var active: Bool;
	public var exists: Bool;

	public var output(default, null): T;

	private var input: Null<T>;

	public function new() {
		active = exists = true;
	}

	public function inputContent(input: T): Void {
		if (this.active)
			this.input = input;
	}

	public function working(): Void {}

	public function destroy(): Void {
		active = false;
	}

	public function toString(): String {
		return '(active: ${this.active} | exists: ${this.exists})';
	}
}
