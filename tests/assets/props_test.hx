var mytest(get, never): String;

function get_mytest() {
	return "hello world";
}

var yourtest(get, set): Array;

function get_yourtest() {
	return yourtest = accessories;
}

function set_yourtest(val: Array): Array {
	yourtest = val;
	return accessories = val;
}

var accessories: Array = [];

function new() {
	yourtest.concat([for (i in 0...4) i]);
	trace(yourtest);
	trace(mytest);
}
