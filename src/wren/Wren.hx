package wren;

import wren.AST;
import wren.WrenTypes;

import wren.Lexer;
import wren.Parser;
import wren.Interp;

class Wren {

    public var interp:Interp;
    public var onPrint:String->Void = (s) -> trace(s);
    var moduleLoader:ModuleLoader;

    public function new() {
        interp = new Interp();
        initialize();
    }

    public function setModuleLoader(loader:ModuleLoader) {
        this.moduleLoader = loader;
        interp.moduleLoader = (name) -> loader.loadModule(name);
    }


    function initialize() {
        // Load Core.wren
        var core = "
            class Object {
                toString { \"[object]\" }
                foreign type
            }
            class Class is Object {
                foreign name
                foreign supertype
            }

            class String is Object {
                foreign count
                foreign contains(other)
                foreign startsWith(prefix)
                foreign endsWith(suffix)
                foreign toString
            }
            class Fn is Object {}


            class List is Object {
                foreign count
                foreign add(item)
                foreign insert(index, item)
                foreign removeAt(index)
                foreign clear()
                foreign toString
                foreign iterate(iter)
                foreign iteratorValue(iter)
                map(fn) {
                    var res = []
                    for (item in this) res.add(fn.call(item))
                    return res
                }
                where(fn) {
                    var res = []
                    for (item in this) {
                        if (fn.call(item)) res.add(item)
                    }
                    return res
                }
            }

            class Map is Object {
                foreign count
                foreign keys
                foreign values
                foreign clear()
                foreign containsKey(key)
                foreign remove(key)
                foreign toString
                foreign iterate(iter)
                foreign iteratorValue(iter)
            }
            class Math is Object {
                foreign static pi
                foreign static sin(x)
                foreign static cos(x)
                foreign static tan(x)
                foreign static sqrt(x)
                foreign static abs(x)
                foreign static ceil(x)
                foreign static floor(x)
            }
            class Bool is Object {
                foreign toString
            }
            class Num is Object {
                foreign static pi
                foreign abs
                foreign ceil
                foreign floor
                foreign sqrt
                foreign toString
            }
            class Null is Object {
                toString { \"null\" }

            }

            class Range {
                construct new(from, to, isInclusive) {
                    _from = from
                    _to = to
                    _isInclusive = isInclusive
                }
                from { _from }
                to { _to }
                isInclusive { _isInclusive }

                iterate(iter) {
                    if (iter == null) return _from
                    if (_isInclusive) {
                        if (iter >= _to) return null
                    } else {
                        if (iter >= _to - 1) return null
                    }
                    return iter + 1
                }
                iteratorValue(iter) { iter }
            }
            class System {

                foreign static print(value)
            }
        ";
        bindForeignMethod("System", "print", true, 1, (args) -> {
            var val = args[1];
            onPrint(val == null ? "null" : Std.string(val));
            return null;
        });

        // Reflection
        bindForeignMethod("Object", "type", false, 0, (args) -> interp.getClass(args[0]));
        bindForeignMethod("Class", "name", false, 0, (args) -> (cast args[0] : WrenClass).name);
        bindForeignMethod("Class", "supertype", false, 0, (args) -> (cast args[0] : WrenClass).parent);

        // Math

        bindForeignMethod("Math", "pi", true, 0, (args) -> Math.PI);
        bindForeignMethod("Math", "sin", true, 1, (args) -> Math.sin(args[1]));
        bindForeignMethod("Math", "cos", true, 1, (args) -> Math.cos(args[1]));
        bindForeignMethod("Math", "tan", true, 1, (args) -> Math.tan(args[1]));
        bindForeignMethod("Math", "sqrt", true, 1, (args) -> Math.sqrt(args[1]));
        bindForeignMethod("Math", "abs", true, 1, (args) -> Math.abs(args[1]));
        bindForeignMethod("Math", "ceil", true, 1, (args) -> Math.ceil(args[1]));
        bindForeignMethod("Math", "floor", true, 1, (args) -> Math.floor(args[1]));

        // String
        bindForeignMethod("String", "count", false, 0, (args) -> (cast args[0] : String).length);
        bindForeignMethod("String", "contains", false, 1, (args) -> (cast args[0] : String).indexOf(args[1]) != -1);
        bindForeignMethod("String", "startsWith", false, 1, (args) -> StringTools.startsWith(args[0], args[1]));
        bindForeignMethod("String", "endsWith", false, 1, (args) -> StringTools.endsWith(args[0], args[1]));
        bindForeignMethod("String", "toString", false, 0, (args) -> args[0]);

        // List
        bindForeignMethod("List", "count", false, 0, (args) -> (cast args[0] : Array<Dynamic>).length);
        bindForeignMethod("List", "add", false, 1, (args) -> { (cast args[0] : Array<Dynamic>).push(args[1]); return args[1]; });
        bindForeignMethod("List", "insert", false, 2, (args) -> { (cast args[0] : Array<Dynamic>).insert(cast args[1], args[2]); return args[2]; });
        bindForeignMethod("List", "removeAt", false, 1, (args) -> (cast args[0] : Array<Dynamic>).splice(cast args[1], 1)[0]);
        bindForeignMethod("List", "clear", false, 0, (args) -> { (cast args[0] : Array<Dynamic>).splice(0, (cast args[0] : Array<Dynamic>).length); return null; });
        bindForeignMethod("List", "toString", false, 0, (args) -> Std.string(args[0]));
        bindForeignMethod("List", "iterate", false, 1, (args) -> {
            var arr:Array<Dynamic> = cast args[0];
            var iter = args[1];
            if (iter == null) return arr.length == 0 ? null : 0;
            var i:Int = cast iter;
            if (i < 0 || i >= arr.length - 1) return null;
            return i + 1;
        });
        bindForeignMethod("List", "iteratorValue", false, 1, (args) -> (cast args[0] : Array<Dynamic>)[cast args[1]]);

        // Map
        bindForeignMethod("Map", "count", false, 0, (args) -> {
            var c = 0;
            for (k in (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>).keys()) c++;
            return c;
        });
        bindForeignMethod("Map", "keys", false, 0, (args) -> [for (k in (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>).keys()) k]);
        bindForeignMethod("Map", "values", false, 0, (args) -> [for (v in (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>).iterator()) v]);
        bindForeignMethod("Map", "clear", false, 0, (args) -> {
            var map = (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>);
            var ks = [for (k in map.keys()) k];
            for (k in ks) map.remove(k);
            return null;
        });
        bindForeignMethod("Map", "containsKey", false, 1, (args) -> (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>).exists(args[1]));
        bindForeignMethod("Map", "remove", false, 1, (args) -> (cast args[0] : haxe.Constraints.IMap<Dynamic, Dynamic>).remove(args[1]));
        bindForeignMethod("Map", "toString", false, 0, (args) -> Std.string(args[0]));
        bindForeignMethod("Map", "iterate", false, 1, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast args[0];
            var ks = [for (k in map.keys()) k];
            var iter = args[1];
            if (iter == null) return ks.length == 0 ? null : 0;
            var i:Int = cast iter;
            if (i < 0 || i >= ks.length - 1) return null;
            return i + 1;
        });
        bindForeignMethod("Map", "iteratorValue", false, 1, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast args[0];
            var ks = [for (k in map.keys()) k];
            return ks[cast args[1]];
        });


        // Num
        bindForeignMethod("Num", "toString", false, 0, (args) -> Std.string(args[0]));

        // Bool
        bindForeignMethod("Bool", "toString", false, 0, (args) -> Std.string(args[0]));

        interpret(core, (res) -> {});
    }



    public function interpret(source:String, ?onDone:Dynamic->Void) {
        try {
            var lexer = new Lexer(source);
            var tokens = lexer.tokenize();
            var parser = new Parser(tokens);
            var ast = parser.parse();
            interp.execute(ast, onDone != null ? onDone : (r) -> {});
        } catch (e:Dynamic) {
            if (Std.isOfType(e, wren.Error.WrenError)) {
                trace(wren.Error.ErrorPrinter.format(cast e));
            } else {
                trace("Uncaught exception: " + e);
            }
        }
    }

    public function setGlobal(name:String, value:Dynamic) {
        interp.globals.set(name, value);
    }

    public function bindForeignMethod(className:String, methodName:String, isStatic:Bool, argCount:Int, impl:Array<Dynamic>->Dynamic) {
        var sig = '${methodName}(${argCount})';
        var key = '${className}.${isStatic ? "static " : ""}${sig}';
        interp.foreignMethods.set(key, impl);
    }

    public function bindForeignClass(className:String, methodName:String, argCount:Int, constructor:Array<Dynamic>->Dynamic) {
        bindForeignMethod(className, methodName, true, argCount, constructor);
    }
}



