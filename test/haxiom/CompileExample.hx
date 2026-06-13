package haxiom;

import haxe.io.Bytes;
import sys.io.File;

class CompileExample {
	public static function main() {
		var script = "
            function calculateSum(n) {
                var sum = 0;
                var i = 1;
                while (i <= n) {
                    sum += i;
                    i++;
                }
                return sum;
            }

            var result = calculateSum(10);
            trace('Sum of 1 to 10 is: ' + result);
        ";

		var engine = new Haxiom();
		engine.useVM = true;

		// Compile without key (unencrypted)
		var bytes1 = engine.compileToBytecodeBytes(script, "example1.hx", null, false);
		// File.saveBytes("example1.hxbc", bytes1);
		trace("Saved example1.hxbc (" + bytes1.length + " bytes)");

		// Compile with 'this_is_my_secret' key (encrypted)
		var key = new HXBCKey("this_is_my_secret");
		var bytes2 = engine.compileToBytecodeBytes(script, "example2.hx", key, false);
		// File.saveBytes("example2.hxbc", bytes2);
		trace("Saved example2.hxbc (" + bytes2.length + " bytes)");

		var content = File.getBytes('./test/haxiom/openfl/scripts/Bytecode.hx');
		var bytes3 = engine.compileToBytecodeBytes(content.toString(), null, null, false);
		File.saveBytes("./test/haxiom/openfl/scripts/Bytecode.hxbc", bytes3);
		trace("Saved Bytecode.hxbc (" + bytes3.length + " bytes)");
	}
}
