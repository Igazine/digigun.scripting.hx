package;

import wren.Wren;
import wren.WrenTypes;

import wren.ModuleLoader;

class TestLoader implements ModuleLoader {

    public function new() {}
    public function loadModule(name:String):String {
        if (name == "math") return "var Pi = 3.14159";
        return null;
    }
}


class TestWren {

    static function main() {
        trace("Wren Test Suite Started");
        
        var wrenInstance = new Wren();

        wrenInstance.setModuleLoader(new TestLoader());

        // Bind foreign class Resource
        wrenInstance.bindForeignClass("Resource", "new", 1, (args) -> {
            var path = args[1];
            return { path: path, data: "Content of " + path };
        });
        wrenInstance.bindForeignMethod("Resource", "data", false, 0, (args) -> {
            var inst:WrenInstance = cast args[0];
            return inst.native.data;
        });

        var script = '
            foreign class Resource {
                construct new(path)
                foreign data
                toString { "Resource(%(data))" }
            }

            class Player is Resource {
                construct new(name, path) {
                    super(path)
                    _name = name
                }
                name { _name }
                toString { "Player(%(name)) inherits from %(super.toString)" }
            }

            var s = "Hello Wren"
            System.print("Starts with Hello? " + s.startsWith("Hello").toString)
            System.print("Ends with Wren? " + s.endsWith("Wren").toString)
            System.print("Contains Wren? " + s.contains("Wren").toString)
            System.print("Contains Haxe? " + s.contains("Haxe").toString)

            var p = Player.new("Tamas", "/path/to/file")
            System.print(p.toString)

            // Verification of new compliance features on JS
            System.print("&& Check: " + (true && false).toString)
            System.print("|| Check: " + (true || false).toString)
            System.print("Ternary Check: " + (true ? "yes" : "no"))
            var i = 0
            while (i < 5) {
                i = i + 1
                if (i == 2) continue
                if (i == 4) break
                System.print("Loop Step: " + i.toString)
            }
            class Counter {
                construct new() {}
                static init() { __count = 42 }
                static count { __count }
            }
            Counter.init()
            System.print("Class Var Count: " + Counter.count.toString)
        ';



        wrenInstance.interpret(script, (res) -> {
            trace("Execution finished with result: " + res);
        });




    }

}
