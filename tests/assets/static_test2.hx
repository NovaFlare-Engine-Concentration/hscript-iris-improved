static final fan: Int = 666;
static var sad: String = "alive";

function new() {
	// reading
	trace("static_test1 static var allbad: " + allBad);
	var old = allRight;
	allRight += " forever";
	trace("static_test1 static var allright: " + allRight);
	trace("writing sad compare: [" + old + "<=>" + allRight + "]");
}
