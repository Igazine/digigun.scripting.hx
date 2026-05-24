package haxiom;

class TestHaxiom {
    static function main() {
        trace("Haxiom Foundation Verification Suite");
        trace("------------------------------------");
        
        var haxiom = new haxiom.Haxiom();
        
        // 1. Basic variables, discarded types, ternary, arithmetic, and unops
        var script1 = '
            var a:Int = 10;
            var b:Float = 20.5;
            var c = a + b;
            var cond:Bool = c > 30;
            var result = cond ? "yes" : "no";
            var x = 5;
            var postfix = x++;
            var prefix = ++x;
            trace("Basic Math & Types: " + result);
            trace("Postfix x++: " + postfix);
            trace("Prefix ++x: " + prefix);
        ';
        haxiom.interpret(script1);

        // 2. Control flow: do-while, while, switch-case
        var script2 = '
            var i = 0;
            var whileRes = 0;
            while (i < 3) {
                i++;
                whileRes += i;
            }
            
            var j = 0;
            var doRes = 0;
            do {
                j++;
                doRes += j;
            } while (j < 3);

            var switchVal = "banana";
            var fruit = "unknown";
            switch (switchVal) {
                case "apple": fruit = "red";
                case "banana", "lemon": fruit = "yellow";
                default: fruit = "none";
            }
            
            trace("While Loop Res: " + whileRes);
            trace("Do-While Loop Res: " + doRes);
            trace("Switch Case Res: " + fruit);
        ';
        haxiom.interpret(script2);

        // 3. Dynamic Arrays, Anonymous structures, and subscript mapping
        var script3 = '
            var arr:Array<Int> = [1, 2, 3];
            arr[1] = 42;
            var obj:Dynamic = { x: 10, y: "tamas" };
            obj.x = 99;
            trace("Array Subscript: " + arr[1]);
            trace("Anonymous Struct: " + obj.x + ", " + obj.y);
        ';
        haxiom.interpret(script3);

        // 4. Haxe Iterator protocol compatibility on Haxiom loops
        var script4 = '
            var items = ["apple", "cherry"];
            var loopOutput = "";
            for (item in items) {
                loopOutput = loopOutput + item + " ";
            }
            trace("Iterable loop: " + loopOutput);
        ';
        haxiom.interpret(script4);

        // 5. Dynamic Object-Oriented Programming (extends, fields, methods, constructors, super)
        var script5 = '
            class Animal {
                public var name:String;
                public function new(name:String) {
                    this.name = name;
                }
                public function speak():String {
                    return name + " speaks";
                }
            }

            class Dog extends Animal {
                public function new(name:String) {
                    super(name);
                }
                public function speak():String {
                    return name + " barks: " + super.speak();
                }
            }

            var d:Animal = new Dog("Fido");
            trace("OOP Chaining: " + d.speak());
        ';
        haxiom.interpret(script5);

        // 6. Closures, arrow function lambdas
        var script6 = '
            var multiply = (x:Int, y:Int):Int -> x * y;
            var adder = function(x, y) { return x + y; };
            trace("Arrow Function: " + multiply(6, 7));
            trace("Formal Closure: " + adder(5, 5));
        ';
        haxiom.interpret(script6);

        // 7. Map Literals, additions and subscript mapping
        var script7 = '
            var m = ["apple" => 10, "banana" => 20];
            m["cherry"] = 30;
            trace("Map Literal string-key value: " + m["apple"]);
            trace("Map Literal cherry-key value: " + m["cherry"]);
            
            var intMap = [100 => "one-hundred", 200 => "two-hundred"];
            trace("Map Literal int-key value: " + intMap[200]);
        ';
        haxiom.interpret(script7);

        // 8. Properties with custom getters and setters
        var script8 = '
            class Player {
                public var x(get, set):Float;
                private var _x:Float = 0.0;
                
                public function new() {}
                
                public function get_x():Float {
                    return _x + 10.0;
                }
                
                public function set_x(v:Float):Float {
                    return _x = v * 2.0;
                }
            }
            
            var p = new Player();
            p.x = 5.0; // setter: _x = 5.0 * 2.0 = 10.0
            trace("Property getter/setter check: " + p.x); // getter: _x + 10.0 = 20.0
        ';
        haxiom.interpret(script8);

        // 9. Std Standard Library & isOfType Type Queries
        var script9 = '
            class Base {}
            class Derived extends Base {}
            
            var d = new Derived();
            var isDerived = Std.isOfType(d, Derived);
            var isBase = Std.isOfType(d, Base);
            
            var parsed = Std.parseInt("123");
            var strVal = Std.string(parsed + 1);
            
            trace("Std.isOfType Derived check: " + isDerived);
            trace("Std.isOfType Base check: " + isBase);
            trace("Std.parseInt & Std.string check: " + strVal);
        ';
        haxiom.interpret(script9);

        // 10. Strict Type Enforcement (Successful typed assignments)
        var script10 = '
            var name:String = "tamas";
            var age:Int = 35;
            var height:Float = 1.75;
            var active:Bool = true;
            
            // Valid re-assignments
            name = "sopronyi";
            age = 36;
            height = 1.8; 
            
            trace("Valid typed vars: " + name + ", age: " + age + ", height: " + height);
        ';
        haxiom.interpret(script10);

        // 11. Type Violation Exception Catching
        try {
            var script11 = '
                var count:Int = 10;
                count = "hello"; // Type mismatch! Should throw runtime error
            ';
            haxiom.interpret(script11);
            trace("FAILURE: count = 'hello' should have thrown an error");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected count type mismatch: " + e);
        }

        try {
            var script12 = '
                class User {
                    public var email:String;
                    public function new() {}
                }
                var u = new User();
                u.email = 123; // Type mismatch on class field! Should throw
            ';
            haxiom.interpret(script12);
            trace("FAILURE: u.email = 123 should have thrown an error");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected class field type mismatch: " + e);
        }

        try {
            var script13 = '
                var square = function(v:Int):Int {
                    return "not-an-int"; // Type mismatch on return value! Should throw
                };
                square(5);
            ';
            haxiom.interpret(script13);
            trace("FAILURE: return 'not-an-int' should have thrown an error");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected method return type mismatch: " + e);
        }

        // 12. Package Namespaces
        var script14 = '
            package game.core;
            class Player {
                public var name:String;
                public function new(name:String) {
                    this.name = name;
                }
            }
        ';
        haxiom.interpret(script14);
        var script14_eval = '
            var p = new game.core.Player("tamas");
            trace("Package FQ inst: " + p.name);
        ';
        haxiom.interpret(script14_eval);

        // 13. Native Imports & Aliases
        var script15 = '
            import haxe.ds.StringMap;
            import haxe.ds.StringMap as MyMap;
            var m = new StringMap();
            m.set("hello", "world");
            var m2 = new MyMap();
            m2.set("hi", "there");
            trace("StringMap: " + m.get("hello") + ", MyMap: " + m2.get("hi"));
        ';
        haxiom.interpret(script15);

        // 14. Module Resolver & Script Module Imports
        haxiom.moduleResolver = (fqName:String) -> {
            if (fqName == "entities.Enemy") {
                return '
                    package entities;
                    class Enemy {
                        public var hp:Int;
                        public function new(hp:Int) {
                            this.hp = hp;
                        }
                    }
                ';
            }
            return null;
        };
        var script16 = '
            import entities.Enemy;
            import entities.Enemy as ShortEnemy;
            var e = new Enemy(100);
            var e2 = new ShortEnemy(200);
            trace("Imported Enemy HP: " + e.hp + ", ShortEnemy HP: " + e2.hp);
        ';
        haxiom.interpret(script16);

        // 15. Native Exception Handling (try, catch, throw)
        var script17 = '
            var res = "";
            try {
                throw "thrown-error";
            } catch (e:String) {
                res = "Caught string: " + e;
            } catch (e:Dynamic) {
                res = "Caught dynamic: " + e;
            }
            trace("Try-Catch String: " + res);
            
            var res2 = "";
            try {
                throw 123;
            } catch (e:String) {
                res2 = "Caught string: " + e;
            } catch (e:Dynamic) {
                res2 = "Caught dynamic: " + e;
            }
            trace("Try-Catch Dynamic/Int: " + res2);
        ';
        haxiom.interpret(script17);

        // 16. Casting (unsafe and safe checked)
        var script18 = '
            var x:Dynamic = "hello";
            var s = cast(x, String);
            trace("Checked Cast String: " + s);
            var uns = cast x;
            trace("Unsafe Cast: " + uns);
        ';
        haxiom.interpret(script18);

        try {
            var script18_err = '
                var x:Dynamic = 123;
                var s = cast(x, String);
            ';
            haxiom.interpret(script18_err);
            trace("FAILURE: cast(123, String) should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected cast mismatch error: " + e);
        }

        // 17. Final Immutability (locals)
        try {
            var script19_var = '
                final x = 10;
                x = 20;
            ';
            haxiom.interpret(script19_var);
            trace("FAILURE: final x reassignment should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected final local variable reassignment error: " + e);
        }

        // 18. Final Immutability (class fields)
        var script19_cls = '
            class Vector2D {
                public final x:Float;
                public function new(x:Float) {
                    this.x = x;
                }
            }
            var v = new Vector2D(5.0);
            trace("Final field initialized: " + v.x);
        ';
        haxiom.interpret(script19_cls);

        try {
            var script19_cls_err = '
                class Vector2D {
                    public final x:Float;
                    public function new(x:Float) {
                        this.x = x;
                    }
                }
                var v = new Vector2D(5.0);
                v.x = 10.0;
            ';
            haxiom.interpret(script19_cls_err);
            trace("FAILURE: final field reassignment should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected final field reassignment error: " + e);
        }

        // 19. Final Immutability (static fields)
        try {
            var script19_static_err = '
                class Config {
                    public static final VERSION = "1.0.0";
                }
                Config.VERSION = "2.0.0";
            ';
            haxiom.interpret(script19_static_err);
            trace("FAILURE: static final field reassignment should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected static final field reassignment error: " + e);
        }

        // 20. Unified Base Interfaces
        var haxiomEngine:common.IScriptEngine = haxiom;
        var wrenEngine:common.IScriptEngine = new wren.Wren();
        trace("SUCCESS: Both Haxiom and Wren implement common.IScriptEngine perfectly!");

        // 21. Interfaces & Implements Contract Conformance
        var script21_ok = '
            interface IUpdatable {
                function update(dt:Float):Void;
            }
            class Game implements IUpdatable {
                public function new() {}
                public function update(dt:Float):Void {
                    trace("Game updated: " + dt);
                }
            }
            var g = new Game();
            g.update(0.16);
        ';
        haxiom.interpret(script21_ok);

        // Conformance Mismatch Validation Checks
        try {
            var script21_err = '
                interface IUpdatable {
                    function update(dt:Float):Void;
                }
                class Game implements IUpdatable {
                    public function new() {}
                    public function update():Void {} // Argument count mismatch!
                }
            ';
            haxiom.interpret(script21_err);
            trace("FAILURE: interface signature mismatch should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected interface signature mismatch: " + e);
        }

        // 22. Std.isOfType Interface Validation
        var script22 = '
            interface IRenderable {
                function render():Void;
            }
            class Player implements IRenderable {
                public function new() {}
                public function render():Void {
                    trace("Player rendered");
                }
            }
            var p = new Player();
            trace("isOfType Player: " + Std.isOfType(p, Player));
            trace("isOfType IRenderable: " + Std.isOfType(p, IRenderable));
        ';
        haxiom.interpret(script22);

        // 23. Standard Math Library Integration
        var script23 = '
            trace("Math.abs: " + Math.abs(-15));
            trace("Math.min: " + Math.min(10, 20));
            trace("Math.max: " + Math.max(10, 20));
        ';
        haxiom.interpret(script23);

        // 24. Call Stack & Stack Trace Diagnostics
        try {
            var script24 = '
                class TestTrace {
                    public function new() {}
                    public function error():Void {
                        throw "thrown-nested-error";
                    }
                    public function run():Void {
                        this.error();
                    }
                }
                var tt = new TestTrace();
                tt.run();
            ';
            haxiom.interpret(script24);
            trace("FAILURE: nested exception should have thrown detailed stack trace");
        } catch (e:Dynamic) {
            var strErr = Std.string(e);
            trace("SUCCESS: Caught expected virtual call stack trace:\n" + strErr);
        }

        // 25. Enums & Advanced Switch Pattern Matching
        var script25 = '
            enum Status {
                Idle;
                Active(speed:Float);
                Error(code:Int, msg:String);
            }
            
            var s1 = Idle;
            var s2 = Active(5.5);
            var s3 = Error(404, "Not Found");
            
            function checkStatus(s:Status):String {
                switch (s) {
                    case Idle: return "idle";
                    case Active(spd): return "active at " + spd;
                    case Error(code, _): return "error code " + code;
                }
            }
            
            trace("check s1: " + checkStatus(s1));
            trace("check s2: " + checkStatus(s2));
            trace("check s3: " + checkStatus(s3));
        ';
        haxiom.interpret(script25);

        // 26. Encapsulation Access Enforcements (Default Private)
        var script26_class = '
            class Account {
                var balance:Float = 100.0; // Defaults to private!
                public var name:String = "savings";
                
                public function new() {}
                
                function internalAccess():Void { // Defaults to private!
                    trace("internal call balance: " + balance);
                }
                
                public function perform():Void {
                    internalAccess(); // Allowed from within class
                }
            }
            var acc = new Account();
            acc.perform();
        ';
        haxiom.interpret(script26_class);
        
        // Assert that external access to private balance fails
        try {
            haxiom.interpret('
                var acc = new Account();
                trace(acc.balance);
            ');
            trace("FAILURE: external access to private balance should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected private field access error: " + e);
        }
        
        // Assert that external access to private internalAccess fails
        try {
            haxiom.interpret('
                var acc = new Account();
                acc.internalAccess();
            ');
            trace("FAILURE: external access to private method should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected private method access error: " + e);
        }
        
        // Assert private constructor access violation
        try {
            haxiom.interpret('
                class PrivateCtor {
                    private function new() {}
                }
                var p = new PrivateCtor();
            ');
            trace("FAILURE: instantiating class with private constructor should have thrown");
        } catch (e:Dynamic) {
            trace("SUCCESS: Caught expected private constructor access error: " + e);
        }

        // 27. Custom ScriptException and configurable errorHandler
        var script27_err = '
            function fail():Void {
                throw "script-exception-test";
            }
            fail();
        ';
        
        // Assert default ScriptException wrapping
        try {
            haxiom.interpret(script27_err);
            trace("FAILURE: script error should have thrown ScriptException");
        } catch (e:haxiom.ScriptException) {
            trace("SUCCESS: Caught expected haxiom.ScriptException: " + e.message);
            trace("Raw value: " + e.rawValue);
        }
        
        // Assert errorHandler callback intercepting exception silently
        var intercepted:haxiom.ScriptException = null;
        haxiom.errorHandler = (err) -> {
            intercepted = err;
        };
        var result = haxiom.interpret(script27_err);
        haxiom.errorHandler = null; // Clean up
        
        if (result == null && intercepted != null) {
            trace("SUCCESS: Captured script error via errorHandler silently: " + intercepted.rawValue);
        } else {
            trace("FAILURE: errorHandler did not capture exception silently");
        }

        // 28. Caching Compiler (compile once, execute multiple times)
        var source28 = '
            var count = 0;
            function tick():Int {
                count = count + 1;
                return count;
            }
        ';
        var ast = haxiom.compile(source28, "physics_tick.hx");
        haxiom.execute(ast); // Initial load
        var runTick:Int = haxiom.interpret('tick();');
        trace("tick 1: " + runTick);
        var runTick2:Int = haxiom.interpret('tick();');
        trace("tick 2: " + runTick2);

        // 29. Strongly Typed Generic Return Values & Callbacks
        var callbackVal:String = null;
        var name:String = haxiom.interpret("return 'Alice';", (val:String) -> {
            callbackVal = val;
        });
        trace("strongly typed name: " + name);
        trace("strongly typed callback: " + callbackVal);

        // 30. Standard Library String & Array Extensions
        var script30 = '
            // String method assertions
            var s = "Haxiom-Script";
            trace("str.length: " + s.length);
            trace("str.charAt(0): " + s.charAt(0));
            trace("str.charCodeAt(0): " + s.charCodeAt(0));
            trace("str.indexOf(\'x\'): " + s.indexOf("x"));
            trace("str.lastIndexOf(\'i\'): " + s.lastIndexOf("i"));
            trace("str.substring(0, 7): " + s.substring(0, 7));
            trace("str.toLowerCase(): " + s.toLowerCase());
            trace("str.toUpperCase(): " + s.toUpperCase());
            
            var parts = s.split("-");
            trace("str.split length: " + parts.length);
            trace("str.split[0]: " + parts[0]);
            trace("str.split[1]: " + parts[1]);
            
            // Array method assertions
            var a = [10, 20, 30];
            trace("arr.length before: " + a.length);
            
            var newLen = a.push(40);
            trace("arr.length after push: " + a.length + ", push returned: " + newLen);
            trace("arr[3]: " + a[3]);
            
            var popped = a.pop();
            trace("arr.pop: " + popped + ", arr.length: " + a.length);
            
            var shifted = a.shift();
            trace("arr.shift: " + shifted + ", arr.length: " + a.length);
            
            a.unshift(5);
            trace("arr.unshift: " + a[0] + ", arr.length: " + a.length);
            
            var removed = a.remove(20);
            trace("arr.remove(20): " + removed + ", arr.length: " + a.length);
            
            var idx = a.indexOf(30);
            trace("arr.indexOf(30): " + idx);
            
            var sliceRes = a.slice(0, 1);
            trace("arr.slice(0, 1) length: " + sliceRes.length + ", item: " + sliceRes[0]);
            
            var joined = a.join("|");
            trace("arr.join: " + joined);
            
            // Closure binding extraction
            var extractPush = a.push;
            extractPush(99);
            trace("extracted push item: " + a[a.length - 1]);
        ';
        haxiom.interpret(script30);
    }
}
