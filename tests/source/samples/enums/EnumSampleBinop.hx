package samples.enums;

enum EnumSampleBinop {
	ZERO;
	SINGLE;
	DOUBLE(one: SampleRef<EnumSampleBinop>);
	TRIPLE(one: SampleRef<EnumSampleBinop>, two: EnumSampleBinop);
}

class SampleRef<T> {
	var origin: T;

	public function new(origin: T) {
		this.origin = origin;
	}

	public inline function get(): T {
		return this.origin;
	}

	public inline function toString(): String {
		return "SampleRef(" + Std.string(this.origin) + ")";
	}
}
