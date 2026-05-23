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

            class Sequence {
                all(f) {
                    var result = true
                    for (element in this) {
                        result = f.call(element)
                        if (!result) return result
                    }
                    return result
                }

                any(f) {
                    var result = false
                    for (element in this) {
                        result = f.call(element)
                        if (result) return result
                    }
                    return result
                }

                contains(element) {
                    for (item in this) {
                        if (element == item) return true
                    }
                    return false
                }

                count {
                    var result = 0
                    for (element in this) {
                        result = result + 1
                    }
                    return result
                }

                count(f) {
                    var result = 0
                    for (element in this) {
                        if (f.call(element)) result = result + 1
                    }
                    return result
                }

                each(f) {
                    for (element in this) {
                        f.call(element)
                    }
                }

                isEmpty { !iterate(null) }

                map(transformation) { MapSequence.new(this, transformation) }

                skip(count) {
                    if (!(count is Num)) {
                        Fiber.abort(\"Count must be a non-negative integer.\")
                    }
                    if (count < 0) {
                        Fiber.abort(\"Count must be a non-negative integer.\")
                    }
                    return SkipSequence.new(this, count)
                }

                take(count) {
                    if (!(count is Num)) {
                        Fiber.abort(\"Count must be a non-negative integer.\")
                    }
                    if (count < 0) {
                        Fiber.abort(\"Count must be a non-negative integer.\")
                    }
                    return TakeSequence.new(this, count)
                }

                where(predicate) { WhereSequence.new(this, predicate) }

                reduce(acc, f) {
                    for (element in this) {
                        acc = f.call(acc, element)
                    }
                    return acc
                }

                reduce(f) {
                    var iter = iterate(null)
                    if (!iter) Fiber.abort(\"Can't reduce an empty sequence.\")
                    var result = iteratorValue(iter)
                    while (iter = iterate(iter)) {
                        result = f.call(result, iteratorValue(iter))
                    }
                    return result
                }

                join() { join(\"\") }

                join(sep) {
                    var first = true
                    var result = \"\"
                    for (element in this) {
                        if (!first) result = result + sep
                        first = false
                        result = result + element.toString
                    }
                    return result
                }

                toList {
                    var result = List.new()
                    for (element in this) {
                        result.add(element)
                    }
                    return result
                }
            }

            class MapSequence is Sequence {
                construct new(seq, fn) {
                    _seq = seq
                    _fn = fn
                }
                iterate(iter) { _seq.iterate(iter) }
                iteratorValue(iter) { _fn.call(_seq.iteratorValue(iter)) }
            }

            class WhereSequence is Sequence {
                construct new(seq, fn) {
                    _seq = seq
                    _fn = fn
                }
                iterate(iter) {
                    while (iter = _seq.iterate(iter)) {
                        if (_fn.call(_seq.iteratorValue(iter))) return iter
                    }
                    return null
                }
                iteratorValue(iter) { _seq.iteratorValue(iter) }
            }

            class SkipSequence is Sequence {
                construct new(seq, count) {
                    _seq = seq
                    _count = count
                }
                iterate(iter) {
                    if (iter == null) {
                        iter = _seq.iterate(null)
                        var i = 0
                        var keepGoing = true
                        while (keepGoing) {
                            if (iter) {
                                if (i < _count) {
                                    iter = _seq.iterate(iter)
                                    i = i + 1
                                } else {
                                    keepGoing = false
                                }
                            } else {
                                keepGoing = false
                            }
                        }
                        return iter
                    }
                    return _seq.iterate(iter)
                }
                iteratorValue(iter) { _seq.iteratorValue(iter) }
            }

            class TakeSequence is Sequence {
                construct new(seq, count) {
                    _seq = seq
                    _count = count
                }
                iterate(iter) {
                    if (_count == 0) return null
                    if (iter == null) {
                        var originalIter = _seq.iterate(null)
                        if (!originalIter) return null
                        return [originalIter, 1]
                    }
                    var originalIter = iter[0]
                    var count = iter[1]
                    if (count >= _count) return null
                    var nextIter = _seq.iterate(originalIter)
                    if (!nextIter) return null
                    return [nextIter, count + 1]
                }
                iteratorValue(iter) { _seq.iteratorValue(iter[0]) }
            }

            class String is Sequence {
                foreign count
                foreign contains(other)
                foreign startsWith(prefix)
                foreign endsWith(suffix)
                foreign toString
                foreign iterate(iter)
                foreign iteratorValue(iter)
                foreign codePointAt_(index)
                foreign split(separator)
                foreign trim()
                foreign replace(from, to)

                codePoints {
                    var res = []
                    var i = 0
                    while (i < count) {
                        res.add(codePointAt_(i))
                        i = i + 1
                    }
                    return res
                }
                bytes { codePoints }
            }
            
            class Fn is Object {
                foreign static new(fn)
                foreign call()
                foreign call(a)
                foreign call(a, b)
                foreign call(a, b, c)
            }

            class Fiber is Object {
                construct new(fn) foreign
                foreign static suspend()
                foreign static current
                foreign isDone
                foreign static yield()
                foreign static yield(v)
                foreign call()
                foreign call(v)
                foreign transfer()
                foreign transfer(v)
                foreign try()
                foreign error
                foreign state
                foreign static abort(msg)
            }

            class List is Sequence {
                construct new() foreign
                foreign count
                foreign add(val)
                foreign insert(index, val)
                foreign removeAt(index)
                foreign clear()
                foreign swap(index1, index2)
                foreign toString
                foreign iterate(iter)
                foreign iteratorValue(iter)
            }

            class MapKeySequence is Sequence {
                construct new(map) {
                    _map = map
                }
                iterate(iter) { _map.iterate(iter) }
                iteratorValue(iter) { _map.iteratorValue(iter) }
            }

            class MapValueSequence is Sequence {
                construct new(map) {
                    _map = map
                }
                iterate(iter) { _map.iterate(iter) }
                iteratorValue(iter) { _map[_map.iteratorValue(iter)] }
            }

            class Map is Sequence {
                construct new() foreign
                foreign count
                keys { MapKeySequence.new(this) }
                values { MapValueSequence.new(this) }
                foreign clear()
                foreign containsKey(key)
                foreign remove(key)
                foreign toString
                foreign iterate(iter)
                foreign iteratorValue(iter)
            }

            class Num is Object {
                foreign toString
                foreign abs
                foreign ceil
                foreign floor
                foreign sqrt
            }

            class Bool is Object {
                foreign toString
            }

            class Null is Object {
                toString { \"null\" }
            }

            class System {
                foreign static print(value)
            }

            class Math {
                foreign static pi
                foreign static sin(x)
                foreign static cos(x)
                foreign static tan(x)
                foreign static sqrt(x)
                foreign static abs(x)
                foreign static ceil(x)
                foreign static floor(x)
                foreign static atan2(y, x)
                foreign static min(a, b)
                foreign static max(a, b)
                foreign static pow(base, exp)
                foreign static exp(x)
                foreign static log(x)
                foreign static acos(x)
                foreign static asin(x)
                foreign static round(x)
                foreign static sign(x)
            }

            class Range is Sequence {
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
        ";

        bindForeignMethod("System", "print", true, 1, (args) -> {
            var val = args[1];
            trace("PRINT: " + val);
            onPrint(val == null ? "null" : Std.string(val));
            return null;
        });
        
        bindForeignMethod("Fn", "new", true, 1, (args) -> {
            return args[1];
        });

        bindForeignClass("List", "new", 0, (args) -> {
            return [];
        });

        bindForeignClass("Map", "new", 0, (args) -> {
            return new Map<Dynamic, Dynamic>();
        });

        // Reflection
        bindForeignMethod("Object", "type", false, 0, (args) -> interp.getClass(args[0]));
        bindForeignMethod("Class", "name", false, 0, (args) -> (cast args[0] : WrenClass).name);
        bindForeignMethod("Class", "supertype", false, 0, (args) -> (cast args[0] : WrenClass).parent);

        // Fiber
        bindForeignMethod("Fiber", "new", true, 1, (args) -> {
            if (!Std.isOfType(args[1], WrenFn)) throw "Argument must be a function";
            var fn:WrenFn = cast args[1];
            var instance:WrenInstance = cast args[0];
            var fiber = new WrenFiber(instance.cls);
            fiber.stack = [Frame.get(fn.body, fn.closure, false, true, false, "fiber", null, fn.globals)];
            return fiber;
        });

        bindForeignMethod("Fiber", "yield", true, 0, (args) -> {
            var caller = interp.currentFiber.caller;
            if (caller == null) throw "Cannot yield from the root fiber";
            interp.fiberToSwitchTo = caller;
            interp.currentFiber.state = Suspended;
            if (caller.stack.length > 0) caller.stack[caller.stack.length - 1].results.push(null);
            return null;
        });

        bindForeignMethod("Fiber", "yield", true, 1, (args) -> {
            var caller = interp.currentFiber.caller;
            if (caller == null) throw "Cannot yield from the root fiber";
            interp.fiberToSwitchTo = caller;
            interp.currentFiber.state = Suspended;
            if (caller.stack.length > 0) caller.stack[caller.stack.length - 1].results.push(args[1]);
            return null;
        });

        bindForeignMethod("Fiber", "call", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            if (fiber.state == Done || fiber.state == Aborted) throw "Cannot call a finished fiber";
            fiber.caller = interp.currentFiber;
            interp.fiberToSwitchTo = fiber;
            fiber.state = Running;
            if (fiber.stack.length > 0) fiber.stack[fiber.stack.length - 1].results.push(null);
            return null;
        });

        bindForeignMethod("Fiber", "call", false, 1, (args) -> {
            var fiber:WrenFiber = cast args[0];
            if (fiber.state == Done || fiber.state == Aborted) throw "Cannot call a finished fiber";
            fiber.caller = interp.currentFiber;
            interp.fiberToSwitchTo = fiber;
            fiber.state = Running;
            if (fiber.stack.length > 0) fiber.stack[fiber.stack.length - 1].results.push(args[1]);
            return null;
        });

        bindForeignMethod("Fiber", "suspend", true, 0, (args) -> {
            var current = interp.currentFiber;
            var caller = current.caller;
            if (caller != null) {
                interp.fiberToSwitchTo = caller;
                current.caller = null;
                current.state = Suspended;
                if (caller.stack.length > 0) caller.stack[caller.stack.length - 1].results.push(null);
            } else {
                current.state = Suspended;
                interp.currentFiber = null;
                interp.fiberToSwitchTo = null;
            }
            return null;
        });

        bindForeignMethod("Fiber", "current", true, 0, (args) -> {
            return interp.currentFiber;
        });

        bindForeignMethod("Fiber", "isDone", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            return fiber.state == Done || fiber.state == Aborted;
        });

        bindForeignMethod("Fiber", "transfer", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            if (fiber.state == Done || fiber.state == Aborted) throw "Cannot transfer to a finished fiber";
            interp.currentFiber.state = Suspended;
            interp.fiberToSwitchTo = fiber;
            fiber.state = Running;
            if (fiber.stack.length > 0) fiber.stack[fiber.stack.length - 1].results.push(null);
            return null;
        });

        bindForeignMethod("Fiber", "transfer", false, 1, (args) -> {
            var fiber:WrenFiber = cast args[0];
            if (fiber.state == Done || fiber.state == Aborted) throw "Cannot transfer to a finished fiber";
            interp.currentFiber.state = Suspended;
            interp.fiberToSwitchTo = fiber;
            fiber.state = Running;
            if (fiber.stack.length > 0) fiber.stack[fiber.stack.length - 1].results.push(args[1]);
            return null;
        });

        bindForeignMethod("Fiber", "abort", true, 1, (args) -> {
            throw args[1];
            return null;
        });

        bindForeignMethod("Fiber", "try", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            if (fiber.state == Done || fiber.state == Aborted) throw "Cannot try a finished fiber";
            fiber.caller = interp.currentFiber;
            fiber.isTry = true;
            interp.fiberToSwitchTo = fiber;
            fiber.state = Running;
            return null;
        });

        bindForeignMethod("Fiber", "error", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            return fiber.error != null ? Std.string(fiber.error) : null;
        });

        bindForeignMethod("Fiber", "state", false, 0, (args) -> {
            var fiber:WrenFiber = cast args[0];
            return switch (fiber.state) {
                case Starting: "suspended";
                case Running: "running";
                case Suspended: "suspended";
                case Done: "done";
                case Aborted: "error";
            }
        });

        // Math
        bindForeignMethod("Math", "pi", true, 0, (args) -> Math.PI);
        bindForeignMethod("Math", "sin", true, 1, (args) -> Math.sin(args[1]));
        bindForeignMethod("Math", "cos", true, 1, (args) -> Math.cos(args[1]));
        bindForeignMethod("Math", "tan", true, 1, (args) -> Math.tan(args[1]));
        bindForeignMethod("Math", "sqrt", true, 1, (args) -> Math.sqrt(args[1]));
        bindForeignMethod("Math", "abs", true, 1, (args) -> Math.abs(args[1]));
        bindForeignMethod("Math", "ceil", true, 1, (args) -> Math.ceil(args[1]));
        bindForeignMethod("Math", "floor", true, 1, (args) -> Math.floor(args[1]));
        bindForeignMethod("Math", "atan2", true, 2, (args) -> Math.atan2(args[1], args[2]));
        bindForeignMethod("Math", "min", true, 2, (args) -> Math.min(args[1], args[2]));
        bindForeignMethod("Math", "max", true, 2, (args) -> Math.max(args[1], args[2]));
        bindForeignMethod("Math", "pow", true, 2, (args) -> Math.pow(args[1], args[2]));
        bindForeignMethod("Math", "exp", true, 1, (args) -> Math.exp(args[1]));
        bindForeignMethod("Math", "log", true, 1, (args) -> Math.log(args[1]));
        bindForeignMethod("Math", "acos", true, 1, (args) -> Math.acos(args[1]));
        bindForeignMethod("Math", "asin", true, 1, (args) -> Math.asin(args[1]));
        bindForeignMethod("Math", "round", true, 1, (args) -> Math.round(args[1]));
        bindForeignMethod("Math", "sign", true, 1, (args) -> {
            var v:Float = args[1];
            return v > 0 ? 1 : (v < 0 ? -1 : 0);
        });

        // String
        bindForeignMethod("String", "count", false, 0, (args) -> (cast args[0] : String).length);
        bindForeignMethod("String", "contains", false, 1, (args) -> (cast args[0] : String).indexOf(args[1]) != -1);
        bindForeignMethod("String", "startsWith", false, 1, (args) -> StringTools.startsWith(args[0], args[1]));
        bindForeignMethod("String", "endsWith", false, 1, (args) -> StringTools.endsWith(args[0], args[1]));
        bindForeignMethod("String", "toString", false, 0, (args) -> args[0]);
        bindForeignMethod("String", "codePointAt_", false, 1, (args) -> (cast args[0] : String).charCodeAt(cast args[1]));
        bindForeignMethod("String", "split", false, 1, (args) -> (cast args[0] : String).split(cast args[1]));
        bindForeignMethod("String", "trim", false, 0, (args) -> StringTools.trim(args[0]));
        bindForeignMethod("String", "replace", false, 2, (args) -> StringTools.replace(args[0], args[1], args[2]));
        bindForeignMethod("String", "iterate", false, 1, (args) -> {
            var str:String = args[0];
            var iter = args[1];
            if (iter == null) return str.length == 0 ? null : 0;
            var i:Int = cast iter;
            if (i < 0 || i >= str.length - 1) return null;
            return i + 1;
        });
        bindForeignMethod("String", "iteratorValue", false, 1, (args) -> {
            var str:String = args[0];
            var i:Int = cast args[1];
            return str.charAt(i);
        });

        // List
        bindForeignMethod("List", "count", false, 0, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            return arr.length;
        });
        bindForeignMethod("List", "add", false, 1, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            arr.push(args[1]);
            return args[1];
        });
        bindForeignMethod("List", "insert", false, 2, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            arr.insert(cast args[1], args[2]);
            return args[2];
        });
        bindForeignMethod("List", "removeAt", false, 1, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            return arr.splice(cast args[1], 1)[0];
        });
        bindForeignMethod("List", "clear", false, 0, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            arr.splice(0, arr.length);
            return null;
        });
        bindForeignMethod("List", "swap", false, 2, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            var i1:Int = cast args[1];
            var i2:Int = cast args[2];
            if (i1 < 0) i1 = arr.length + i1;
            if (i2 < 0) i2 = arr.length + i2;
            if (i1 < 0 || i1 >= arr.length || i2 < 0 || i2 >= arr.length) throw "Index out of bounds";
            var tmp = arr[i1];
            arr[i1] = arr[i2];
            arr[i2] = tmp;
            return null;
        });
        bindForeignMethod("List", "iterate", false, 1, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            var iter = args[1];
            if (iter == null) return arr.length == 0 ? null : 0;
            var i:Int = cast iter;
            if (i < 0 || i >= arr.length - 1) return null;
            return i + 1;
        });
        bindForeignMethod("List", "iteratorValue", false, 1, (args) -> {
            var arr:Array<Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            return arr[cast args[1]];
        });

        // Map
        bindForeignMethod("Map", "count", false, 0, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            var c = 0;
            for (k in map.keys()) c++;
            return c;
        });
        bindForeignMethod("Map", "iterate", false, 1, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            var ks = [for (k in map.keys()) k];
            var iter = args[1];
            if (iter == null) return ks.length == 0 ? null : 0;
            var i:Int = cast iter;
            if (i < 0 || i >= ks.length - 1) return null;
            return i + 1;
        });
        bindForeignMethod("Map", "iteratorValue", false, 1, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            var ks = [for (k in map.keys()) k];
            return ks[cast args[1]];
        });
        bindForeignMethod("Map", "containsKey", false, 1, (args) -> {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = ((Std.isOfType(args[0], WrenInstance)) ? (cast args[0] : WrenInstance).native : args[0]);
            return map.exists(args[1]);
        });

        // Num
        bindForeignMethod("Num", "toString", false, 0, (args) -> Std.string(args[0]));

        // Bool
        bindForeignMethod("Bool", "toString", false, 0, (args) -> Std.string(args[0]));

        interpret(core, (res) -> {});
    }



    public function interpret(source:String, ?onDone:Dynamic->Void) {
        var lexer = new Lexer(source);
        var tokens = lexer.tokenize();
        var parser = new Parser(tokens);
        var ast = parser.parse();
        interp.execute(ast, onDone != null ? onDone : (r) -> {});
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



