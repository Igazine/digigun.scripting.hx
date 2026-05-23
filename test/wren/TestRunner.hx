package wren;

import sys.FileSystem;
import sys.io.File;
import wren.Wren;
import wren.ModuleLoader;

using StringTools;

class FileModuleLoader implements ModuleLoader {
    var root:String;
    public function new(root:String) { this.root = root; }
    public function loadModule(name:String):String {
        var path = root + "/" + name + ".wren";
        if (sys.FileSystem.exists(path)) return sys.io.File.getContent(path);
        return null;
    }
}

class TestRunner {
    static function main() {
        var suiteDir = "test/wren/suite";
        if (!FileSystem.exists(suiteDir)) {
            FileSystem.createDirectory(suiteDir);
            Sys.println("Created empty test suite directory: " + suiteDir);
            Sys.println("Please add .wren files with '// expect: ...' comments.");
            return;
        }

        var args = Sys.args();
        var files:Array<String> = [];
        if (args.length > 0) {
            files = [args[0]];
        } else {
            files = FileSystem.readDirectory(suiteDir);
            files.sort(Reflect.compare);
        }

        var passed = 0;
        var total = 0;

        Sys.println("Wren Test Runner Starting...");
        Sys.println("---------------------------");

        for (file in files) {
            var fullPath = file.startsWith(suiteDir) ? file : suiteDir + "/" + file;
            if (fullPath.endsWith(".wren") && !file.startsWith("mod_")) {
                total++;
                if (runTest(fullPath)) {
                    passed++;
                }
            }
        }

        Sys.println("---------------------------");
        Sys.println('Results: $passed / $total passed');
        if (passed < total) Sys.exit(1);
    }

    static function runTest(path:String):Bool {
        var content = File.getContent(path);
        var expectedOutput:Array<String> = [];
        var lines = content.split("\n");
        for (line in lines) {
            var idx = line.indexOf("// expect: ");
            if (idx != -1) {
                expectedOutput.push(line.substring(idx + 11).trim());
            }
        }

        var actualOutput:Array<String> = [];
        var wren = new Wren();
        wren.onPrint = (s) -> actualOutput.push(s);
        
        var dir = path.substring(0, path.lastIndexOf("/"));
        wren.setModuleLoader(new FileModuleLoader(dir));

        Sys.print('Running $path... ');
        
        try {
            wren.interpret(content);
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            for (line in errStr.split("\n")) {
                actualOutput.push(line.trim());
            }
        }

        if (actualOutput.length != expectedOutput.length) {
            Sys.println("FAILED (Output count mismatch: expected " + expectedOutput.length + ", got " + actualOutput.length + ")");
            Sys.println("  Expected lines: " + expectedOutput.join(" | "));
            Sys.println("  Actual lines:   " + actualOutput.join(" | "));
            return false;
        }

        for (i in 0...expectedOutput.length) {
            if (actualOutput[i] != expectedOutput[i]) {
                Sys.println("FAILED (Output mismatch at line " + (i + 1) + ")");
                Sys.println("  Expected: " + expectedOutput[i]);
                Sys.println("  Actual:   " + actualOutput[i]);
                return false;
            }
        }

        Sys.println("PASSED");
        return true;
    }
}
