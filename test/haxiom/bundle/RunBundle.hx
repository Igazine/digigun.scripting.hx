package haxiom.bundle;

import haxiom.Haxiom;
import sys.io.File;

class RunBundle {
	public static function main() {
		var engine = new Haxiom();
		engine.useVM = true;
		engine.importWhitelist = null; // Disable sandboxing for standard outputs

		trace("Loading library test bundle bytecode...");
		var bytes = File.getBytes("test/haxiom/bundle/MyLib.hxbc");
		
		trace("Executing library test bundle...");
		engine.executeBytes(bytes);
		
		trace("Resolving MyLib.doSomething closure from host...");
		var doSomething:Dynamic = engine.interpret("MyLib.doSomething;");
		if (doSomething == null) {
			throw "Failed to resolve MyLib.doSomething static method!";
		}
		
		var result:String = doSomething();
		trace("MyLib.doSomething() result: " + result);
		
		if (result == "Hello from MyLib!") {
			trace("SUCCESS: Library bytecode bundle loaded and executed successfully from host!");
		} else {
			throw "Verification failed: MyLib.doSomething() returned: " + result;
		}
	}
}
