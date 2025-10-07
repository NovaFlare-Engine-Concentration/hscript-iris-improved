package samples;

class IntSample extends BaseSample<Int> {
	public override function working(): Void {
		if (this.active) {
			if (this.input != null) {
				this.output = this.input + 10;
			}
		}
	}
}
