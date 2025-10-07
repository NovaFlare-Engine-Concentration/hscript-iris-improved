package samples;

class ObjectSample extends BaseSample<Int> {
	public override function working(): Void {
		if (this.active) {
			this.output = Reflect.copy(this.input);
			Reflect.setField(this.output, "shagua", 114514);
		}
	}
}
