package haxiom.bundle;

import haxiom.Haxiom;
import sys.io.File;

class RunBundle {
	public static function main() {
		var engine = new Haxiom();
		engine.useVM = true;
		engine.importWhitelist = null; // Disable sandboxing for standard outputs

		trace("Loading test bundle bytecode...");
		var bytes = File.getBytes("test/haxiom/bundle/Main.hxbc");
		
		trace("Executing test bundle...");
		engine.executeBytes(bytes);
		
		var mainClass:Dynamic = engine.interp.globals.get("Main");
		if (mainClass == null) {
			throw "Main class was not registered in globals!";
		}
		
		var resMessage:Dynamic = mainClass.staticFields.get("outputMessage");
		var resValue:Dynamic = mainClass.staticFields.get("outputValue");
		
		trace("Bundle Execution Verification:");
		trace("outputMessage: " + resMessage);
		trace("outputValue: " + resValue);
		
		if (resMessage == "Hello from bundled MyClass!" && resValue == 40) {
			trace("SUCCESS: Single-module bytecode bundle executed and verified successfully!");
		} else {
			throw "Verification failed: outputMessage or outputValue did not match expected values.";
		}
	}
}
