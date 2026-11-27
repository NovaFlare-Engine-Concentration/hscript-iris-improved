package scripted;

class OwnMembersSample extends samples.BaseSample<Dynamic> implements IScriptedClass {
	public var own: Int = 7;
	public var doubled(get, set): Int;

	public function new(initial: Int) {
		super();
		own += initial;
	}

	function get_doubled(): Int return own * 2;

	function set_doubled(value: Int): Int {
		own = Std.int(value / 2);
		return value;
	}

	public function describeOwn(): String return 'host $own';

	override public function toString(): String return describeOwn();
}
