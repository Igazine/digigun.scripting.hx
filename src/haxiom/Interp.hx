package haxiom;

import haxiom.AST;

enum ControlFlow {
    Return(val:Dynamic);
    Break;
    Continue;
}

class Scope {
    public var variables:Map<String, Dynamic> = new Map();
    public var types:Map<String, TypeDecl> = new Map();
    public var finals:Map<String, Bool> = new Map();
    public var parent:Scope;
    
    public function new(?parent:Scope) {
        this.parent = parent;
    }
    
    public function get(name:String):Dynamic {
        if (variables.exists(name)) return variables.get(name);
        if (parent != null) return parent.get(name);
        return null;
    }
    
    public function exists(name:String):Bool {
        if (variables.exists(name)) return true;
        if (parent != null) return parent.exists(name);
        return false;
    }
    
    public function set(name:String, val:Dynamic):Void {
        if (finals.get(name) == true) {
            throw 'Cannot reassign final variable $name';
        }
        if (variables.exists(name)) {
            variables.set(name, val);
        } else if (parent != null && parent.exists(name)) {
            parent.set(name, val);
        } else {
            variables.set(name, val);
        }
    }

    public function checkAndSet(name:String, val:Dynamic, interp:Interp):Void {
        if (finals.get(name) == true) {
            throw 'Cannot reassign final variable $name';
        }
        if (types.exists(name)) {
            interp.checkType(val, types.get(name), this);
            variables.set(name, val);
        } else if (variables.exists(name)) {
            variables.set(name, val);
        } else if (parent != null && parent.exists(name)) {
            parent.checkAndSet(name, val, interp);
        } else {
            variables.set(name, val);
        }
    }

    public function declare(name:String, val:Dynamic, ?type:TypeDecl, ?isFinal:Bool):Void {
        variables.set(name, val);
        if (type != null) types.set(name, type); else types.remove(name);
        if (isFinal == true) finals.set(name, true); else finals.remove(name);
    }
}

class HaxiomClass {
    public var name:String;
    public var parent:HaxiomClass;
    public var fields:Map<String, {name:String, expr:Expr, isStatic:Bool, isPublic:Bool, ?property:{get:String, set:String}}> = new Map();
    public var methods:Map<String, {name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, body:Expr, isStatic:Bool, isPublic:Bool}> = new Map();
    public var staticFields:Map<String, Dynamic> = new Map();
    public var interfaces:Array<String> = [];

    public function new(name:String, ?parent:HaxiomClass) {
        this.name = name;
        this.parent = parent;
    }
}

class HaxiomInterface {
    public var name:String;
    public var methods:Map<String, {name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, ?body:Null<Expr>}> = new Map();
    public var parents:Array<String>;

    public function new(name:String, ?parents:Array<String>) {
        this.name = name;
        this.parents = parents != null ? parents : [];
    }
}

class HaxiomInstance {
    public var cls:HaxiomClass;
    public var fields:Map<String, Dynamic> = new Map();
    
    public function new(cls:HaxiomClass) {
        this.cls = cls;
    }
}

class HaxiomEnum {
    public var name:String;
    public var constructors:Map<String, Array<{name:String, type:Null<TypeDecl>}>> = new Map();

    public function new(name:String) {
        this.name = name;
    }
}

class HaxiomEnumInstance {
    public var enumType:HaxiomEnum;
    public var constructorName:String;
    public var args:Array<Dynamic>;

    public function new(enumType:HaxiomEnum, constructorName:String, args:Array<Dynamic>) {
        this.enumType = enumType;
        this.constructorName = constructorName;
        this.args = args;
    }

    public function toString():String {
        if (args == null || args.length == 0) return constructorName;
        return constructorName + "(" + args.join(", ") + ")";
    }
}

@:keep
class HaxiomAnchor {
    public static function keep() {
        var s = new haxe.ds.StringMap<Dynamic>();
        var i = new haxe.ds.IntMap<Dynamic>();
        var o = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
        var l = new List<Dynamic>();
    }
}

class Interp {
    public var globals:Scope = new Scope();
    var currentThis:Dynamic = null;
    
    public var currentPackage:Array<String> = [];
    public var moduleResolver:String->String = null;
    public var importWhitelist:Array<String> = null;
    public var importedModules:Map<String, Scope> = new Map();
    var currentConstructorInstance:Dynamic = null;
    public var activeUsings:Array<Dynamic> = [];

    public var callStack:Array<{method:String, pos:Pos}> = [];
    public var errorHandler:Null<ScriptException->Void> = null;
    var lastEvalPos:Pos = null;

    public inline function pushFrame(methodName:String, pos:Pos) {
        callStack.push({ method: methodName, pos: pos });
    }

    public inline function popFrame() {
        callStack.pop();
    }

    public function new() {
        // Core standard print/trace redirection
        globals.declare("trace", (v:Dynamic) -> {
            haxe.Log.trace(Std.string(v), null);
        });
        
        // Dynamic Math binding
        globals.declare("Math", Math);
        
        // Expose global Std object
        var mapPlaceholder = { __isMapPlaceholder: true };
        var stdObj = {
            string: Std.string,
            parseInt: Std.parseInt,
            parseFloat: Std.parseFloat,
            isOfType: (v:Dynamic, t:Dynamic) -> {
                if (t == mapPlaceholder) {
                    return Std.isOfType(v, haxe.Constraints.IMap);
                }
                if (Std.isOfType(t, HaxiomClass)) {
                    if (v == null || !Std.isOfType(v, HaxiomInstance)) return false;
                    var inst:HaxiomInstance = cast v;
                    var curr = inst.cls;
                    while (curr != null) {
                        if (curr == t) return true;
                        curr = curr.parent;
                    }
                    return false;
                }
                if (Std.isOfType(t, HaxiomInterface)) {
                    if (v == null || !Std.isOfType(v, HaxiomInstance)) return false;
                    var inst:HaxiomInstance = cast v;
                    var itf:HaxiomInterface = cast t;
                    var curr = inst.cls;
                    while (curr != null) {
                        for (itfName in curr.interfaces) {
                            if (itfName == itf.name) return true;
                        }
                        curr = curr.parent;
                    }
                    return false;
                }
                return Std.isOfType(v, t);
            }
        };
        globals.declare("Std", stdObj);
        globals.declare("String", String);
        globals.declare("Array", Array);
        globals.declare("List", haxe.ds.List);
        globals.declare("Map", mapPlaceholder);
        globals.declare("StringTools", StringTools);
        
        var lambdaObj = {
            array: (it:Dynamic) -> Lambda.array(it),
            list: (it:Dynamic) -> Lambda.list(it),
            count: (it:Dynamic, ?pred:Dynamic) -> {
                if (pred == null) return Lambda.count(it);
                return Lambda.count(it, (x) -> Reflect.callMethod(null, pred, [x]));
            },
            empty: (it:Dynamic) -> Lambda.empty(it),
            indexOf: (it:Dynamic, val:Dynamic) -> Lambda.indexOf(it, val),
            find: (it:Dynamic, f:Dynamic) -> {
                return Lambda.find(it, (x) -> Reflect.callMethod(null, f, [x]));
            },
            exists: (it:Dynamic, f:Dynamic) -> {
                return Lambda.exists(it, (x) -> Reflect.callMethod(null, f, [x]));
            },
            foreach: (it:Dynamic, f:Dynamic) -> {
                return Lambda.foreach(it, (x) -> Reflect.callMethod(null, f, [x]));
            },
            iter: (it:Dynamic, f:Dynamic) -> {
                Lambda.iter(it, (x) -> Reflect.callMethod(null, f, [x]));
                return null;
            },
            map: (it:Dynamic, f:Dynamic) -> {
                return Lambda.map(it, (x) -> Reflect.callMethod(null, f, [x]));
            },
            filter: (it:Dynamic, f:Dynamic) -> {
                return Lambda.filter(it, (x) -> Reflect.callMethod(null, f, [x]));
            },
            fold: (it:Dynamic, f:Dynamic, first:Dynamic) -> {
                return Lambda.fold(it, (x, acc) -> Reflect.callMethod(null, f, [x, acc]), first);
            },
            has: (it:Dynamic, el:Dynamic) -> Lambda.has(it, el)
        };
        globals.declare("Lambda", lambdaObj);
        
        // Ensure DCE keep
        HaxiomAnchor.keep();
    }

    public function execute(expr:Expr):Dynamic {
        currentPackage = [];
        callStack = [];
        activeUsings = [];
        lastEvalPos = expr.pos;
        try {
            return eval(expr, globals);
        } catch (e:ControlFlow) {
            switch (e) {
                case Return(val): return val;
                default: throw "Unexpected control flow break/continue at top-level";
            }
        } catch (e:Dynamic) {
            var traceLines = [];
            var isScriptException = Std.isOfType(e, haxiom.ScriptException);
            
            var formatted = "";
            var finalException:Dynamic = null;
            if (isScriptException) {
                finalException = e;
            } else {
                var errPos = lastEvalPos != null ? lastEvalPos : expr.pos;
                var fileInfo = errPos.file != null ? errPos.file : "script";
                var lineVal = errPos != null ? errPos.line : 1;
                var colVal = errPos != null ? errPos.col : 1;

                traceLines.push('Runtime Error: ' + Std.string(e) + ' at ' + fileInfo + ':' + lineVal + ':' + colVal);
                var i = callStack.length - 1;
                while (i >= 0) {
                    var frame = callStack[i];
                    var fileInfoFrame = frame.pos.file != null ? frame.pos.file : "script";
                    var framePos = (i == callStack.length - 1 && lastEvalPos != null) ? lastEvalPos : frame.pos;
                    traceLines.push('    at ' + frame.method + ' (' + fileInfoFrame + ':' + framePos.line + ':' + framePos.col + ')');
                    i--;
                }
                if (callStack.length == 0) {
                    traceLines.push('    at toplevel (' + fileInfo + ':' + lineVal + ':' + colVal + ')');
                }
                formatted = traceLines.join("\n");
                finalException = new haxiom.ScriptException(e, callStack.copy(), formatted, lineVal, colVal, fileInfo);
            }
            
            if (errorHandler != null) {
                errorHandler(finalException);
                return null;
            }
            throw finalException;
        }
    }

    function getTypeName(v:Dynamic):String {
        if (v == null) return "null";
        if (Std.isOfType(v, Int)) return "Int";
        if (Std.isOfType(v, Float)) return "Float";
        if (Std.isOfType(v, String)) return "String";
        if (Std.isOfType(v, Bool)) return "Bool";
        if (Std.isOfType(v, Array)) return "Array";
        if (Reflect.isFunction(v)) return "function";
        var cls = Type.getClass(v);
        if (cls != null) {
            var name = Type.getClassName(cls);
            if (name != null) return name;
        }
        return "Unknown";
    }

    inline function checkArgCount(args:Array<Dynamic>, expectedMin:Int, expectedMax:Int, methodName:String):Void {
        if (args.length < expectedMin || args.length > expectedMax) {
            throw 'Method $methodName expected between $expectedMin and $expectedMax arguments but got ${args.length}';
        }
    }

    inline function checkNum(v:Dynamic, methodName:String, argName:String = "argument"):Void {
        if (!Std.isOfType(v, Float) && !Std.isOfType(v, Int)) {
            throw '$methodName expected a number for $argName but got ${getTypeName(v)}';
        }
    }

    inline function checkString(v:Dynamic, methodName:String, argName:String = "argument"):Void {
        if (!Std.isOfType(v, String)) {
            throw '$methodName expected a String for $argName but got ${getTypeName(v)}';
        }
    }

    inline function checkInt(v:Dynamic, methodName:String, argName:String = "argument"):Void {
        if (!Std.isOfType(v, Int)) {
            throw '$methodName expected an Int for $argName but got ${getTypeName(v)}';
        }
    }

    inline function checkFunction(v:Dynamic, methodName:String, argName:String = "callback"):Void {
        if (v == null || !Reflect.isFunction(v)) {
            throw '$methodName expected a function for $argName but got ${getTypeName(v)}';
        }
    }

    function evalField(obj:Dynamic, field:String, scope:Scope, pos:Pos):Dynamic {
        if (obj == null) throw 'Cannot read field "$field" of null';
        
        if (Std.isOfType(obj, String)) {
            var str:String = cast obj;
            if (field == "length") return str.length;
            switch (field) {
                case "split":
                    return (delim:Dynamic) -> {
                        checkString(delim, "String.split", "delimiter");
                        return str.split(delim);
                    };
                case "indexOf":
                    return (sub:Dynamic, ?start:Dynamic) -> {
                        checkString(sub, "String.indexOf", "substring");
                        if (start != null) checkInt(start, "String.indexOf", "start index");
                        return str.indexOf(sub, start);
                    };
                case "lastIndexOf":
                    return (sub:Dynamic, ?start:Dynamic) -> {
                        checkString(sub, "String.lastIndexOf", "substring");
                        if (start != null) checkInt(start, "String.lastIndexOf", "start index");
                        return str.lastIndexOf(sub, start);
                    };
                case "charAt":
                    return (idx:Dynamic) -> {
                        checkInt(idx, "String.charAt", "index");
                        return str.charAt(idx);
                    };
                case "charCodeAt":
                    return (idx:Dynamic) -> {
                        checkInt(idx, "String.charCodeAt", "index");
                        return str.charCodeAt(idx);
                    };
                case "substring":
                    return (start:Dynamic, ?end:Dynamic) -> {
                        checkInt(start, "String.substring", "start index");
                        if (end != null) checkInt(end, "String.substring", "end index");
                        return str.substring(start, end);
                    };
                case "substr":
                    return (start:Dynamic, ?len:Dynamic) -> {
                        checkInt(start, "String.substr", "start index");
                        if (len != null) checkInt(len, "String.substr", "length");
                        return str.substr(start, len);
                    };
                case "toLowerCase":
                    return () -> str.toLowerCase();
                case "toUpperCase":
                    return () -> str.toUpperCase();
                case "toString":
                    return () -> str;
                case "startsWith":
                    return (start:Dynamic) -> {
                        checkString(start, "StringTools.startsWith", "prefix");
                        return StringTools.startsWith(str, start);
                    };
                case "endsWith":
                    return (end:Dynamic) -> {
                        checkString(end, "StringTools.endsWith", "suffix");
                        return StringTools.endsWith(str, end);
                    };
                case "trim":
                    return () -> StringTools.trim(str);
                case "ltrim":
                    return () -> StringTools.ltrim(str);
                case "rtrim":
                    return () -> StringTools.rtrim(str);
                case "replace":
                    return (sub:Dynamic, by:Dynamic) -> {
                        checkString(sub, "StringTools.replace", "sub");
                        checkString(by, "StringTools.replace", "by");
                        return StringTools.replace(str, sub, by);
                    };
                case "lpad":
                    return (c:Dynamic, l:Dynamic) -> {
                        checkString(c, "StringTools.lpad", "char");
                        checkInt(l, "StringTools.lpad", "length");
                        return StringTools.lpad(str, c, l);
                    };
                case "rpad":
                    return (c:Dynamic, l:Dynamic) -> {
                        checkString(c, "StringTools.rpad", "char");
                        checkInt(l, "StringTools.rpad", "length");
                        return StringTools.rpad(str, c, l);
                    };
                case "urlEncode":
                    return () -> StringTools.urlEncode(str);
                case "urlDecode":
                    return () -> StringTools.urlDecode(str);
                case "htmlEscape":
                    return (?quotes:Dynamic) -> {
                        if (quotes != null && !Std.isOfType(quotes, Bool)) throw "String.htmlEscape expected a Bool for quotes";
                        return StringTools.htmlEscape(str, quotes);
                    };
                case "htmlUnescape":
                    return () -> StringTools.htmlUnescape(str);
                default:
            }
        }
        if (Std.isOfType(obj, Array)) {
            var arr:Array<Dynamic> = cast obj;
            if (field == "length") return arr.length;
            switch (field) {
                case "concat":
                    return (other:Dynamic) -> {
                        if (!Std.isOfType(other, Array)) throw "Array.concat expected an Array for argument but got " + getTypeName(other);
                        return arr.concat(other);
                    };
                case "push":
                    return (x:Dynamic) -> arr.push(x);
                case "pop":
                    return () -> arr.pop();
                case "shift":
                    return () -> arr.shift();
                case "unshift":
                    return (x:Dynamic) -> {
                        arr.unshift(x);
                        return null;
                    };
                case "remove":
                    return (x:Dynamic) -> arr.remove(x);
                case "indexOf":
                    return (x:Dynamic, ?start:Dynamic) -> {
                        if (start != null) checkInt(start, "Array.indexOf", "start index");
                        return arr.indexOf(x, start);
                    };
                case "lastIndexOf":
                    return (x:Dynamic, ?start:Dynamic) -> {
                        if (start != null) checkInt(start, "Array.lastIndexOf", "start index");
                        return arr.lastIndexOf(x, start);
                    };
                case "insert":
                    return (idx:Dynamic, x:Dynamic) -> {
                        checkInt(idx, "Array.insert", "index");
                        arr.insert(idx, x);
                        return null;
                    };
                case "reverse":
                    return () -> {
                        arr.reverse();
                        return null;
                    };
                case "sort":
                    return (f:Dynamic) -> {
                        checkFunction(f, "Array.sort", "comparator");
                        arr.sort((a, b) -> Reflect.callMethod(null, f, [a, b]));
                        return null;
                    };
                case "resize":
                    return (len:Dynamic) -> {
                        checkInt(len, "Array.resize", "length");
                        arr.resize(len);
                        return null;
                    };
                case "contains":
                    return (x:Dynamic) -> arr.contains(x);
                case "join":
                    return (sep:Dynamic) -> {
                        checkString(sep, "Array.join", "separator");
                        return arr.join(sep);
                    };
                case "slice":
                    return (start:Dynamic, ?end:Dynamic) -> {
                        checkInt(start, "Array.slice", "start index");
                        if (end != null) checkInt(end, "Array.slice", "end index");
                        return arr.slice(start, end);
                    };
                case "copy":
                    return () -> arr.copy();
                case "filter":
                    return (f:Dynamic) -> {
                        checkFunction(f, "Array.filter", "callback");
                        return arr.filter((x) -> Reflect.callMethod(null, f, [x]));
                    };
                case "map":
                    return (f:Dynamic) -> {
                        checkFunction(f, "Array.map", "callback");
                        return arr.map((x) -> Reflect.callMethod(null, f, [x]));
                    };
                case "toString":
                    return () -> arr.toString();
                case "iterator":
                    return () -> arr.iterator();
                case "keyValueIterator":
                    return () -> arr.keyValueIterator();
                default:
            }
        }
        if (Std.isOfType(obj, haxe.ds.List)) {
            var list:haxe.ds.List<Dynamic> = cast obj;
            switch (field) {
                case "add":
                    return (item:Dynamic) -> {
                        list.add(item);
                        return null;
                    };
                case "push":
                    return (item:Dynamic) -> {
                        list.push(item);
                        return null;
                    };
                case "first":
                    return () -> list.first();
                case "last":
                    return () -> list.last();
                case "pop":
                    return () -> list.pop();
                case "isEmpty":
                    return () -> list.isEmpty();
                case "clear":
                    return () -> {
                        list.clear();
                        return null;
                    };
                case "remove":
                    return (item:Dynamic) -> list.remove(item);
                case "iterator":
                    return () -> list.iterator();
                case "toString":
                    return () -> list.toString();
                case "join":
                    return (sep:Dynamic) -> {
                        checkString(sep, "List.join", "separator");
                        return list.join(sep);
                    };
                case "filter":
                    return (f:Dynamic) -> {
                        checkFunction(f, "List.filter", "callback");
                        return list.filter((x) -> Reflect.callMethod(null, f, [x]));
                    };
                case "map":
                    return (f:Dynamic) -> {
                        checkFunction(f, "List.map", "callback");
                        return list.map((x) -> Reflect.callMethod(null, f, [x]));
                    };
                default:
            }
        }
        if (obj == String) {
            switch (field) {
                case "fromCharCode":
                    return (code:Dynamic) -> {
                        checkInt(code, "String.fromCharCode", "code");
                        return String.fromCharCode(code);
                    };
                default:
            }
        }
        if (obj == StringTools) {
            switch (field) {
                case "urlEncode":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.urlEncode", "s");
                        return StringTools.urlEncode(s);
                    };
                case "urlDecode":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.urlDecode", "s");
                        return StringTools.urlDecode(s);
                    };
                case "htmlEscape":
                    return (s:Dynamic, ?quotes:Dynamic) -> {
                        checkString(s, "StringTools.htmlEscape", "s");
                        if (quotes != null && !Std.isOfType(quotes, Bool)) throw "StringTools.htmlEscape expected a Bool for quotes";
                        return StringTools.htmlEscape(s, quotes);
                    };
                case "htmlUnescape":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.htmlUnescape", "s");
                        return StringTools.htmlUnescape(s);
                    };
                case "hex":
                    return (n:Dynamic, ?digits:Dynamic) -> {
                        checkInt(n, "StringTools.hex", "n");
                        if (digits != null) checkInt(digits, "StringTools.hex", "digits");
                        return StringTools.hex(n, digits);
                    };
                case "fastCodeAt":
                    return (s:Dynamic, index:Dynamic) -> {
                        checkString(s, "StringTools.fastCodeAt", "s");
                        checkInt(index, "StringTools.fastCodeAt", "index");
                        return StringTools.fastCodeAt(s, index);
                    };
                case "isSpace":
                    return (s:Dynamic, index:Dynamic) -> {
                        checkString(s, "StringTools.isSpace", "s");
                        checkInt(index, "StringTools.isSpace", "index");
                        return StringTools.isSpace(s, index);
                    };
                case "trim":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.trim", "s");
                        return StringTools.trim(s);
                    };
                case "ltrim":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.ltrim", "s");
                        return StringTools.ltrim(s);
                    };
                case "rtrim":
                    return (s:Dynamic) -> {
                        checkString(s, "StringTools.rtrim", "s");
                        return StringTools.rtrim(s);
                    };
                case "replace":
                    return (s:Dynamic, sub:Dynamic, by:Dynamic) -> {
                        checkString(s, "StringTools.replace", "s");
                        checkString(sub, "StringTools.replace", "sub");
                        checkString(by, "StringTools.replace", "by");
                        return StringTools.replace(s, sub, by);
                    };
                case "startsWith":
                    return (s:Dynamic, prefix:Dynamic) -> {
                        checkString(s, "StringTools.startsWith", "s");
                        checkString(prefix, "StringTools.startsWith", "prefix");
                        return StringTools.startsWith(s, prefix);
                    };
                case "endsWith":
                    return (s:Dynamic, suffix:Dynamic) -> {
                        checkString(s, "StringTools.endsWith", "s");
                        checkString(suffix, "StringTools.endsWith", "suffix");
                        return StringTools.endsWith(s, suffix);
                    };
                case "lpad":
                    return (s:Dynamic, c:Dynamic, l:Dynamic) -> {
                        checkString(s, "StringTools.lpad", "s");
                        checkString(c, "StringTools.lpad", "char");
                        checkInt(l, "StringTools.lpad", "length");
                        return StringTools.lpad(s, c, l);
                    };
                case "rpad":
                    return (s:Dynamic, c:Dynamic, l:Dynamic) -> {
                        checkString(s, "StringTools.rpad", "s");
                        checkString(c, "StringTools.rpad", "char");
                        checkInt(l, "StringTools.rpad", "length");
                        return StringTools.rpad(s, c, l);
                    };
                default:
            }
        }
        if (obj == Math) {
            if (field == "PI") return Math.PI;
            if (field == "NaN") return Math.NaN;
            if (field == "NEGATIVE_INFINITY") return Math.NEGATIVE_INFINITY;
            if (field == "POSITIVE_INFINITY") return Math.POSITIVE_INFINITY;
            switch (field) {
                case "abs":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.abs");
                        return Math.abs(x);
                    };
                case "sin":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.sin");
                        return Math.sin(x);
                    };
                case "cos":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.cos");
                        return Math.cos(x);
                    };
                case "tan":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.tan");
                        return Math.tan(x);
                    };
                case "atan2":
                    return (y:Dynamic, x:Dynamic) -> {
                        checkNum(y, "Math.atan2", "y");
                        checkNum(x, "Math.atan2", "x");
                        return Math.atan2(y, x);
                    };
                case "sqrt":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.sqrt");
                        return Math.sqrt(x);
                    };
                case "pow":
                    return (v:Dynamic, exp:Dynamic) -> {
                        checkNum(v, "Math.pow", "base");
                        checkNum(exp, "Math.pow", "exponent");
                        return Math.pow(v, exp);
                    };
                case "floor":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.floor");
                        return Math.floor(x);
                    };
                case "ceil":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.ceil");
                        return Math.ceil(x);
                    };
                case "round":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.round");
                        return Math.round(x);
                    };
                case "random":
                    return () -> Math.random();
                case "min":
                    return (a:Dynamic, b:Dynamic) -> {
                        checkNum(a, "Math.min", "a");
                        checkNum(b, "Math.min", "b");
                        return Math.min(a, b);
                    };
                case "max":
                    return (a:Dynamic, b:Dynamic) -> {
                        checkNum(a, "Math.max", "a");
                        checkNum(b, "Math.max", "b");
                        return Math.max(a, b);
                    };
                case "acos":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.acos");
                        return Math.acos(x);
                    };
                case "asin":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.asin");
                        return Math.asin(x);
                    };
                case "atan":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.atan");
                        return Math.atan(x);
                    };
                case "exp":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.exp");
                        return Math.exp(x);
                    };
                case "log":
                    return (x:Dynamic) -> {
                        checkNum(x, "Math.log");
                        return Math.log(x);
                    };
                case "isNaN":
                    return (x:Dynamic) -> Math.isNaN(x);
                case "isFinite":
                    return (x:Dynamic) -> Math.isFinite(x);
                default:
            }
        }
        if (Std.isOfType(obj, haxe.Constraints.IMap)) {
            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
            switch (field) {
                case "exists":
                    return (key:Dynamic) -> map.exists(key);
                case "get":
                    return (key:Dynamic) -> map.get(key);
                case "set":
                    return (key:Dynamic, val:Dynamic) -> {
                        map.set(key, val);
                        return null;
                    };
                case "remove":
                    return (key:Dynamic) -> map.remove(key);
                case "clear":
                    return () -> {
                        map.clear();
                        return null;
                    };
                case "keys":
                    return () -> map.keys();
                case "iterator":
                    return () -> map.iterator();
                case "keyValueIterator":
                    return () -> map.keyValueIterator();
                case "toString":
                    return () -> map.toString();
                default:
            }
        }
        
        if (Std.isOfType(obj, HaxiomInstance)) {
            var inst:HaxiomInstance = cast obj;
            var fDef = findFieldDef(inst.cls, field);
            if (fDef != null) {
                checkMemberAccess(inst.cls, fDef.isPublic);
                if (fDef.property != null && fDef.property.get == "get") {
                    var m = findMethod(inst.cls, "get_" + field);
                    if (m != null) return Reflect.callMethod(null, bindMethod(obj, m), []);
                }
            }
            if (inst.fields.exists(field)) return inst.fields.get(field);
            
            var m = findMethod(inst.cls, field);
            if (m != null) {
                checkMemberAccess(inst.cls, m.isPublic);
                return bindMethod(obj, m);
            }
            var usingRes = resolveUsing(obj, field);
            if (usingRes != null) return usingRes;
            throw 'Method or field "$field" not found on class ${inst.cls.name}';
        }
        
        if (Std.isOfType(obj, HaxiomClass)) {
            var cls:HaxiomClass = cast obj;
            var fDef = findFieldDef(cls, field);
            if (fDef != null) {
                checkMemberAccess(cls, fDef.isPublic);
            }
            if (cls.staticFields.exists(field)) return cls.staticFields.get(field);
            
            var m = findStaticMethod(cls, field);
            if (m != null) {
                checkMemberAccess(cls, m.isPublic);
                return bindMethod(obj, m);
            }
            var usingRes = resolveUsing(obj, field);
            if (usingRes != null) return usingRes;
            throw 'Static method or field "$field" not found on class ${cls.name}';
        }

        // Native Haxe reflection
        var f = Reflect.getProperty(obj, field);
            // Check if this is an abstract method or property redirection closure/getter
            for (absName in haxiom.FFI.exposedAbstracts.keys()) {
                var absInfo = haxiom.FFI.exposedAbstracts.get(absName);
                var getterName = "get_" + field;
                var isGetter = absInfo.methods.indexOf(getterName) != -1;
                var methodName = isGetter ? getterName : field;
                
                if (absInfo.methods.indexOf(methodName) != -1) {
                    var matchesType = false;
                    switch (absInfo.underlying) {
                        case "Int": matchesType = Std.isOfType(obj, Int);
                        case "Float": matchesType = Std.isOfType(obj, Float);
                        case "String": matchesType = Std.isOfType(obj, String);
                        case "Bool": matchesType = Std.isOfType(obj, Bool);
                        default:
                            var cls = Type.resolveClass(absInfo.underlying);
                            if (cls != null) matchesType = Std.isOfType(obj, cls);
                    }
                    
                    if (matchesType) {
                        var implCls = resolveAbstractImpl(absName, absInfo.implClass);
                        if (implCls != null) {
                            var m = Reflect.field(implCls, methodName);
                            if (m != null) {
                                if (isGetter) {
                                    return Reflect.callMethod(null, m, [obj]);
                                } else {
                                    return Reflect.makeVarArgs(function(args:Array<Dynamic>) {
                                        return Reflect.callMethod(null, m, [obj].concat(args));
                                    });
                                }
                            }
                        }
                    }
                }
            }
        if (Reflect.isFunction(f)) return f;
        if (f != null) return f;
        
        var usingRes = resolveUsing(obj, field);
        if (usingRes != null) return usingRes;
        return null;
    }

    function assignField(obj:Dynamic, field:String, val:Dynamic, scope:Scope):Dynamic {
        if (Std.isOfType(obj, HaxiomInstance)) {
            var inst:HaxiomInstance = cast obj;
            var fDef = findFieldDef(inst.cls, field);
            if (fDef != null) {
                checkMemberAccess(inst.cls, fDef.isPublic);
                if (fDef.property != null && fDef.property.set == "set") {
                    var m = findMethod(inst.cls, "set_" + field);
                    if (m != null) return Reflect.callMethod(null, bindMethod(obj, m), [val]);
                }
                if (fDef.isFinal) {
                    if (currentConstructorInstance != inst) {
                        throw 'Cannot reassign final field $field outside of constructor';
                    }
                }
                if (fDef.type != null) {
                    checkType(val, fDef.type, scope);
                }
            }
            inst.fields.set(field, val);
        } else {
            if (Std.isOfType(obj, HaxiomClass)) {
                var cls:HaxiomClass = cast obj;
                var fDef = findFieldDef(cls, field);
                if (fDef != null) {
                    checkMemberAccess(cls, fDef.isPublic);
                    if (fDef.isFinal) {
                        throw 'Cannot reassign static final field $field';
                    }
                    if (fDef.type != null) {
                        checkType(val, fDef.type, scope);
                    }
                }
                cls.staticFields.set(field, val);
            } else {
                // Check if this is an abstract setter redirection
                var setterResolved = false;
                for (absName in haxiom.FFI.exposedAbstracts.keys()) {
                    var absInfo = haxiom.FFI.exposedAbstracts.get(absName);
                    var setterName = "set_" + field;
                    if (absInfo.methods.indexOf(setterName) != -1) {
                        var matchesType = false;
                        switch (absInfo.underlying) {
                            case "Int": matchesType = Std.isOfType(obj, Int);
                            case "Float": matchesType = Std.isOfType(obj, Float);
                            case "String": matchesType = Std.isOfType(obj, String);
                            case "Bool": matchesType = Std.isOfType(obj, Bool);
                            default:
                                var cls = Type.resolveClass(absInfo.underlying);
                                if (cls != null) matchesType = Std.isOfType(obj, cls);
                        }
                        
                        if (matchesType) {
                            var implCls = resolveAbstractImpl(absName, absInfo.implClass);
                            if (implCls != null) {
                                var m = Reflect.field(implCls, setterName);
                                if (m != null) {
                                    Reflect.callMethod(null, m, [obj, val]);
                                    setterResolved = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                if (!setterResolved) {
                    Reflect.setProperty(obj, field, val);
                }
            }
        }
        return val;
    }

    function eval(e:Expr, scope:Scope):Dynamic {
        if (e != null && e.pos != null) lastEvalPos = e.pos;
        var pos = e.pos;
        switch (e.def) {
            case EValue(v):
                return v;

            case EIdent(name):
                var pathRes = tryResolveExpressionPath(e, scope);
                if (pathRes.success) return pathRes.value;
                
                if (name == "this") return currentThis;
                if (scope.exists(name)) return scope.get(name);
                
                // Implicit this field/method resolution
                if (currentThis != null) {
                    if (Std.isOfType(currentThis, HaxiomInstance)) {
                        var inst:HaxiomInstance = cast currentThis;
                        var fDef = findFieldDef(inst.cls, name);
                        if (fDef != null && fDef.property != null && fDef.property.get == "get") {
                            var m = findMethod(inst.cls, "get_" + name);
                            if (m != null) return Reflect.callMethod(null, bindMethod(currentThis, m), []);
                        }
                        if (inst.fields.exists(name)) return inst.fields.get(name);
                        
                        var m = findMethod(inst.cls, name);
                        if (m != null) return bindMethod(currentThis, m);
                    } else {
                        // Native Haxe object field
                        var f = Reflect.field(currentThis, name);
                        if (f != null) {
                            return f;
                        }
                    }
                }
                
                throw 'Identifier "$name" not found at ${pos.line}:${pos.col}';

            case EVar(name, type, expr, isFinal):
                var val = expr != null ? eval(expr, scope) : null;
                checkType(val, type, scope);
                scope.declare(name, val, type, isFinal);
                return val;

            case EAssign(target, expr):
                var val = eval(expr, scope);
                switch (target.def) {
                    case EIdent(name):
                        if (name == "this") throw "Cannot assign to 'this'";
                        if (scope.exists(name)) {
                            scope.checkAndSet(name, val, this);
                        } else if (currentThis != null) {
                            // Assign to implicit this field
                            if (Std.isOfType(currentThis, HaxiomInstance)) {
                                var inst:HaxiomInstance = cast currentThis;
                                var fDef = findFieldDef(inst.cls, name);
                                if (fDef != null && fDef.property != null && fDef.property.set == "set") {
                                    var m = findMethod(inst.cls, "set_" + name);
                                    if (m != null) return Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
                                }
                                if (fDef != null && fDef.isFinal) {
                                    if (currentConstructorInstance != inst) {
                                        throw 'Cannot reassign final field $name outside of constructor';
                                    }
                                }
                                if (fDef != null && fDef.type != null) {
                                    checkType(val, fDef.type, scope);
                                }
                                inst.fields.set(name, val);
                            } else {
                                Reflect.setField(currentThis, name, val);
                            }
                        } else {
                            scope.declare(name, val);
                        }
                        return val;
                    case EField(objExpr, field):
                        switch (objExpr.def) {
                            case EIdent("super"):
                                if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
                                    var inst:HaxiomInstance = cast currentThis;
                                    inst.fields.set(field, val);
                                    return val;
                                }
                                throw "Cannot use 'super' outside of a class instance";
                            default:
                        }
                        var obj = eval(objExpr, scope);
                        if (obj == null) throw 'Cannot write field "$field" of null';
                        return assignField(obj, field, val, scope);
                    case ESafeField(objExpr, field):
                        var obj = eval(objExpr, scope);
                        if (obj == null) return null;
                        return assignField(obj, field, val, scope);
                    case EBinop("[]", objExpr, indexExpr):
                        var obj = eval(objExpr, scope);
                        var idx = eval(indexExpr, scope);
                        setSubscript(obj, idx, val);
                        return val;
                    default:
                        throw "Invalid assignment target";
                }

            case EBinop(op, e1, e2):
                if (op == "&&") {
                    var v1 = eval(e1, scope);
                    if (v1 == false || v1 == null) return v1;
                    return eval(e2, scope);
                }
                if (op == "||") {
                    var v1 = eval(e1, scope);
                    if (v1 != false && v1 != null) return v1;
                    return eval(e2, scope);
                }
                if (op == "?") {
                    // Ternary is represented as: Binop("?", cond, Binop(":", e1, e2))
                    var cond = eval(e1, scope);
                    switch (e2.def) {
                        case EBinop(":", left, right):
                            if (cond != false && cond != null) return eval(left, scope);
                            return eval(right, scope);
                        default: throw "Invalid ternary operator format";
                    }
                }
                if (op == "[]") {
                    var obj = eval(e1, scope);
                    var idx = eval(e2, scope);
                    return getSubscript(obj, idx);
                }

                if (op == "??") {
                    var v1 = eval(e1, scope);
                    if (v1 != null) return v1;
                    return eval(e2, scope);
                }
                if (op == "...") {
                    var v1 = eval(e1, scope);
                    var v2 = eval(e2, scope);
                    checkInt(v1, "IntIterator start");
                    checkInt(v2, "IntIterator end");
                    return new IntIterator(cast v1, cast v2);
                }

                var v1 = eval(e1, scope);
                var v2 = eval(e2, scope);
                var binopRes:Dynamic = null;
                switch (op) {
                    case "+": binopRes = (v1 + v2 : Dynamic);
                    case "-": binopRes = (v1 - v2 : Dynamic);
                    case "*": binopRes = (v1 * v2 : Dynamic);
                    case "/": binopRes = (v1 / v2 : Dynamic);
                    case "%": binopRes = (v1 % v2 : Dynamic);
                    case "==": binopRes = (v1 == v2 : Dynamic);
                    case "!=": binopRes = (v1 != v2 : Dynamic);
                    case "<": binopRes = (v1 < v2 : Dynamic);
                    case "<=": binopRes = (v1 <= v2 : Dynamic);
                    case ">": binopRes = (v1 > v2 : Dynamic);
                    case ">=": binopRes = (v1 >= v2 : Dynamic);
                    case "&": binopRes = ((cast v1 : Int) & (cast v2 : Int) : Dynamic);
                    case "|": binopRes = ((cast v1 : Int) | (cast v2 : Int) : Dynamic);
                    case "^": binopRes = ((cast v1 : Int) ^ (cast v2 : Int) : Dynamic);
                    case "<<": binopRes = ((cast v1 : Int) << (cast v2 : Int) : Dynamic);
                    case ">>": binopRes = ((cast v1 : Int) >> (cast v2 : Int) : Dynamic);
                    case ">>>": binopRes = ((cast v1 : Int) >>> (cast v2 : Int) : Dynamic);
                    default: throw 'Unknown operator "$op"';
                }
                return binopRes;

            case EUnop(op, expr):
                if (op == "post++" || op == "post--") {
                    var val = eval(expr, scope);
                    var nextVal = op == "post++" ? (cast val : Float) + 1 : (cast val : Float) - 1;
                    assign(expr, nextVal, scope);
                    return val;
                }
                var val = eval(expr, scope);
                var unopRes:Dynamic = null;
                switch (op) {
                    case "!": unopRes = !(cast val : Bool);
                    case "-": unopRes = -(cast val : Float);
                    case "~": unopRes = ~(cast val : Int);
                    case "++":
                        var resVal = (cast val : Float) + 1;
                        assign(expr, resVal, scope);
                        unopRes = resVal;
                    case "--":
                        var resVal = (cast val : Float) - 1;
                        assign(expr, resVal, scope);
                        unopRes = resVal;
                    default: throw 'Unknown unary operator "$op"';
                }
                return unopRes;

            case EField(objExpr, field):
                var pathRes = tryResolveExpressionPath(e, scope);
                if (pathRes.success) return pathRes.value;
                
                switch (objExpr.def) {
                    case EIdent("super"):
                        if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
                            var inst:HaxiomInstance = cast currentThis;
                            var parentCls = inst.cls.parent;
                            var m = findMethod(parentCls, field);
                            if (m != null) return bindMethod(currentThis, m);
                            throw 'Parent method or field "$field" not found on class ${inst.cls.name}';
                        }
                        throw "Cannot use 'super' outside of a class instance";
                    default:
                }
                var obj = eval(objExpr, scope);
                return evalField(obj, field, scope, pos);

            case ESafeField(objExpr, field):
                var pathRes = tryResolveExpressionPath(e, scope);
                if (pathRes.success) return pathRes.value;
                
                var obj = eval(objExpr, scope);
                if (obj == null) return null;
                return evalField(obj, field, scope, pos);

            case ECall(calleeExpr, argsExprs):
                switch (calleeExpr.def) {
                    case EIdent("super"):
                        if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
                            var inst:HaxiomInstance = cast currentThis;
                            var parentCls = inst.cls.parent;
                            if (parentCls != null) {
                                var constr = findMethod(parentCls, "new");
                                if (constr != null) {
                                    var args = [for (a in argsExprs) eval(a, scope)];
                                    var cScope = new Scope(scope);
                                    cScope.declare("this", currentThis);
                                    for (i in 0...constr.args.length) {
                                        var arg = constr.args[i];
                                        var val = i < args.length ? args[i] : null;
                                        checkType(val, arg.type, cScope);
                                        cScope.declare(arg.name, val, arg.type);
                                    }
                                    var oldThis = currentThis;
                                    var oldConstrInst = currentConstructorInstance;
                                    currentConstructorInstance = inst;
                                    try {
                                        eval(constr.body, cScope);
                                    } catch (flow:ControlFlow) {
                                        switch (flow) {
                                            case Return(_):
                                            default: throw flow;
                                        }
                                    }
                                    currentConstructorInstance = oldConstrInst;
                                    currentThis = oldThis;
                                }
                            }
                            return null;
                        }
                        throw "Cannot call 'super' constructor outside of subclass constructor";
                    default:
                }
                
                // Native Haxe object method call bound-this optimization
                var isSafe = false;
                var objExpr:Expr = null;
                var field:String = null;
                switch (calleeExpr.def) {
                    case EField(oe, f):
                        switch (oe.def) {
                            case EIdent("super"): // skip
                            default:
                                objExpr = oe;
                                field = f;
                        }
                    case ESafeField(oe, f):
                        objExpr = oe;
                        field = f;
                        isSafe = true;
                    default:
                }
                
                if (objExpr != null && field != null) {
                    var obj:Dynamic = eval(objExpr, scope);
                    if (obj == null) {
                        if (isSafe) return null;
                        throw 'Cannot call method "$field" of null';
                    }
                    
                    if (!Std.isOfType(obj, HaxiomInstance) && !Std.isOfType(obj, HaxiomClass)) {
                        // Native Haxe object method call optimization
                        if (Std.isOfType(obj, String)) {
                            var str:String = cast obj;
                            var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                            switch (field) {
                                case "split":
                                    checkArgCount(args, 1, 1, "String.split");
                                    checkString(args[0], "String.split", "delimiter");
                                    return str.split(args[0]);
                                case "indexOf":
                                    checkArgCount(args, 1, 2, "String.indexOf");
                                    checkString(args[0], "String.indexOf", "substring");
                                    if (args.length > 1) checkInt(args[1], "String.indexOf", "start index");
                                    return args.length > 1 ? str.indexOf(args[0], args[1]) : str.indexOf(args[0]);
                                case "lastIndexOf":
                                    checkArgCount(args, 1, 2, "String.lastIndexOf");
                                    checkString(args[0], "String.lastIndexOf", "substring");
                                    if (args.length > 1) checkInt(args[1], "String.lastIndexOf", "start index");
                                    return args.length > 1 ? str.lastIndexOf(args[0], args[1]) : str.lastIndexOf(args[0]);
                                case "charAt":
                                    checkArgCount(args, 1, 1, "String.charAt");
                                    checkInt(args[0], "String.charAt", "index");
                                    return str.charAt(args[0]);
                                case "charCodeAt":
                                    checkArgCount(args, 1, 1, "String.charCodeAt");
                                    checkInt(args[0], "String.charCodeAt", "index");
                                    return str.charCodeAt(args[0]);
                                case "substring":
                                    checkArgCount(args, 1, 2, "String.substring");
                                    checkInt(args[0], "String.substring", "start index");
                                    if (args.length > 1) checkInt(args[1], "String.substring", "end index");
                                    return args.length > 1 ? str.substring(args[0], args[1]) : str.substring(args[0]);
                                case "substr":
                                    checkArgCount(args, 1, 2, "String.substr");
                                    checkInt(args[0], "String.substr", "start index");
                                    if (args.length > 1) checkInt(args[1], "String.substr", "length");
                                    return args.length > 1 ? str.substr(args[0], args[1]) : str.substr(args[0]);
                                case "toLowerCase":
                                    checkArgCount(args, 0, 0, "String.toLowerCase");
                                    return str.toLowerCase();
                                case "toUpperCase":
                                    checkArgCount(args, 0, 0, "String.toUpperCase");
                                    return str.toUpperCase();
                                case "toString":
                                    checkArgCount(args, 0, 0, "String.toString");
                                    return str;
                                case "startsWith":
                                    checkArgCount(args, 1, 1, "StringTools.startsWith");
                                    checkString(args[0], "StringTools.startsWith", "prefix");
                                    return StringTools.startsWith(str, args[0]);
                                case "endsWith":
                                    checkArgCount(args, 1, 1, "StringTools.endsWith");
                                    checkString(args[0], "StringTools.endsWith", "suffix");
                                    return StringTools.endsWith(str, args[0]);
                                case "trim":
                                    checkArgCount(args, 0, 0, "StringTools.trim");
                                    return StringTools.trim(str);
                                case "ltrim":
                                    checkArgCount(args, 0, 0, "StringTools.ltrim");
                                    return StringTools.ltrim(str);
                                case "rtrim":
                                    checkArgCount(args, 0, 0, "StringTools.rtrim");
                                    return StringTools.rtrim(str);
                                case "replace":
                                    checkArgCount(args, 2, 2, "StringTools.replace");
                                    checkString(args[0], "StringTools.replace", "sub");
                                    checkString(args[1], "StringTools.replace", "by");
                                    return StringTools.replace(str, args[0], args[1]);
                                case "lpad":
                                    checkArgCount(args, 2, 2, "StringTools.lpad");
                                    checkString(args[0], "StringTools.lpad", "char");
                                    checkInt(args[1], "StringTools.lpad", "length");
                                    return StringTools.lpad(str, args[0], args[1]);
                                case "rpad":
                                    checkArgCount(args, 2, 2, "StringTools.rpad");
                                    checkString(args[0], "StringTools.rpad", "char");
                                    checkInt(args[1], "StringTools.rpad", "length");
                                    return StringTools.rpad(str, args[0], args[1]);
                                case "urlEncode":
                                    checkArgCount(args, 0, 0, "StringTools.urlEncode");
                                    return StringTools.urlEncode(str);
                                case "urlDecode":
                                    checkArgCount(args, 0, 0, "StringTools.urlDecode");
                                    return StringTools.urlDecode(str);
                                case "htmlEscape":
                                    checkArgCount(args, 0, 1, "StringTools.htmlEscape");
                                    if (args.length > 0 && !Std.isOfType(args[0], Bool)) throw "StringTools.htmlEscape expected a Bool for quotes";
                                    return args.length > 0 ? StringTools.htmlEscape(str, args[0]) : StringTools.htmlEscape(str);
                                case "htmlUnescape":
                                    checkArgCount(args, 0, 0, "StringTools.htmlUnescape");
                                    return StringTools.htmlUnescape(str);
                                default:
                            }
                        }
                        if (Std.isOfType(obj, Array)) {
                            var arr:Array<Dynamic> = cast obj;
                            var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                            switch (field) {
                                case "concat":
                                    checkArgCount(args, 1, 1, "Array.concat");
                                    if (!Std.isOfType(args[0], Array)) throw "Array.concat expected an Array but got " + getTypeName(args[0]);
                                    return arr.concat(args[0]);
                                case "push":
                                    checkArgCount(args, 1, 1, "Array.push");
                                    return arr.push(args[0]);
                                case "pop":
                                    checkArgCount(args, 0, 0, "Array.pop");
                                    return arr.pop();
                                case "shift":
                                    checkArgCount(args, 0, 0, "Array.shift");
                                    return arr.shift();
                                case "unshift":
                                    checkArgCount(args, 1, 1, "Array.unshift");
                                    arr.unshift(args[0]);
                                    return null;
                                case "remove":
                                    checkArgCount(args, 1, 1, "Array.remove");
                                    return arr.remove(args[0]);
                                case "indexOf":
                                    checkArgCount(args, 1, 2, "Array.indexOf");
                                    if (args.length > 1) checkInt(args[1], "Array.indexOf", "start index");
                                    return args.length > 1 ? arr.indexOf(args[0], args[1]) : arr.indexOf(args[0]);
                                case "lastIndexOf":
                                    checkArgCount(args, 1, 2, "Array.lastIndexOf");
                                    if (args.length > 1) checkInt(args[1], "Array.lastIndexOf", "start index");
                                    return args.length > 1 ? arr.lastIndexOf(args[0], args[1]) : arr.lastIndexOf(args[0]);
                                case "insert":
                                    checkArgCount(args, 2, 2, "Array.insert");
                                    checkInt(args[0], "Array.insert", "index");
                                    arr.insert(args[0], args[1]);
                                    return null;
                                case "reverse":
                                    checkArgCount(args, 0, 0, "Array.reverse");
                                    arr.reverse();
                                    return null;
                                case "sort":
                                    checkArgCount(args, 1, 1, "Array.sort");
                                    checkFunction(args[0], "Array.sort", "comparator");
                                    arr.sort((a, b) -> Reflect.callMethod(null, args[0], [a, b]));
                                    return null;
                                case "resize":
                                    checkArgCount(args, 1, 1, "Array.resize");
                                    checkInt(args[0], "Array.resize", "length");
                                    arr.resize(args[0]);
                                    return null;
                                case "contains":
                                    checkArgCount(args, 1, 1, "Array.contains");
                                    return arr.contains(args[0]);
                                case "join":
                                    checkArgCount(args, 1, 1, "Array.join");
                                    checkString(args[0], "Array.join", "separator");
                                    return arr.join(args[0]);
                                case "slice":
                                    checkArgCount(args, 1, 2, "Array.slice");
                                    checkInt(args[0], "Array.slice", "start index");
                                    if (args.length > 1) checkInt(args[1], "Array.slice", "end index");
                                    return args.length > 1 ? arr.slice(args[0], args[1]) : arr.slice(args[0]);
                                case "copy":
                                    checkArgCount(args, 0, 0, "Array.copy");
                                    return arr.copy();
                                case "filter":
                                    checkArgCount(args, 1, 1, "Array.filter");
                                    checkFunction(args[0], "Array.filter", "callback");
                                    return arr.filter((x) -> Reflect.callMethod(null, args[0], [x]));
                                case "map":
                                    checkArgCount(args, 1, 1, "Array.map");
                                    checkFunction(args[0], "Array.map", "callback");
                                    return arr.map((x) -> Reflect.callMethod(null, args[0], [x]));
                                case "toString":
                                    checkArgCount(args, 0, 0, "Array.toString");
                                    return arr.toString();
                                case "iterator":
                                    checkArgCount(args, 0, 0, "Array.iterator");
                                    return arr.iterator();
                                case "keyValueIterator":
                                    checkArgCount(args, 0, 0, "Array.keyValueIterator");
                                    return arr.keyValueIterator();
                                default:
                            }
                        }
                        if (Std.isOfType(obj, haxe.ds.List)) {
                             var list:haxe.ds.List<Dynamic> = cast obj;
                             var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                             switch (field) {
                                 case "add":
                                     checkArgCount(args, 1, 1, "List.add");
                                     list.add(args[0]);
                                     return null;
                                 case "push":
                                     checkArgCount(args, 1, 1, "List.push");
                                     list.push(args[0]);
                                     return null;
                                 case "first":
                                     checkArgCount(args, 0, 0, "List.first");
                                     return list.first();
                                 case "last":
                                     checkArgCount(args, 0, 0, "List.last");
                                     return list.last();
                                 case "pop":
                                     checkArgCount(args, 0, 0, "List.pop");
                                     return list.pop();
                                 case "isEmpty":
                                     checkArgCount(args, 0, 0, "List.isEmpty");
                                     return list.isEmpty();
                                 case "clear":
                                     checkArgCount(args, 0, 0, "List.clear");
                                     list.clear();
                                     return null;
                                 case "remove":
                                     checkArgCount(args, 1, 1, "List.remove");
                                     return list.remove(args[0]);
                                 case "iterator":
                                     checkArgCount(args, 0, 0, "List.iterator");
                                     return list.iterator();
                                 case "toString":
                                     checkArgCount(args, 0, 0, "List.toString");
                                     return list.toString();
                                 case "join":
                                     checkArgCount(args, 1, 1, "List.join");
                                     checkString(args[0], "List.join", "separator");
                                     return list.join(args[0]);
                                 case "filter":
                                     checkArgCount(args, 1, 1, "List.filter");
                                     checkFunction(args[0], "List.filter", "callback");
                                     return list.filter((x) -> Reflect.callMethod(null, args[0], [x]));
                                 case "map":
                                     checkArgCount(args, 1, 1, "List.map");
                                     checkFunction(args[0], "List.map", "callback");
                                     return list.map((x) -> Reflect.callMethod(null, args[0], [x]));
                                 default:
                             }
                         }
                        if (obj == String) {
                             var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                             switch (field) {
                                 case "fromCharCode":
                                     checkArgCount(args, 1, 1, "String.fromCharCode");
                                     checkInt(args[0], "String.fromCharCode", "code");
                                     return String.fromCharCode(args[0]);
                                 default:
                             }
                         }
                         if (obj == StringTools) {
                             var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                             switch (field) {
                                 case "urlEncode":
                                     checkArgCount(args, 1, 1, "StringTools.urlEncode");
                                     checkString(args[0], "StringTools.urlEncode", "s");
                                     return StringTools.urlEncode(args[0]);
                                 case "urlDecode":
                                     checkArgCount(args, 1, 1, "StringTools.urlDecode");
                                     checkString(args[0], "StringTools.urlDecode", "s");
                                     return StringTools.urlDecode(args[0]);
                                 case "htmlEscape":
                                     checkArgCount(args, 1, 2, "StringTools.htmlEscape");
                                     checkString(args[0], "StringTools.htmlEscape", "s");
                                     if (args.length > 1 && !Std.isOfType(args[1], Bool)) throw "StringTools.htmlEscape expected a Bool for quotes";
                                     return args.length > 1 ? StringTools.htmlEscape(args[0], args[1]) : StringTools.htmlEscape(args[0]);
                                 case "htmlUnescape":
                                     checkArgCount(args, 1, 1, "StringTools.htmlUnescape");
                                     checkString(args[0], "StringTools.htmlUnescape", "s");
                                     return StringTools.htmlUnescape(args[0]);
                                 case "hex":
                                     checkArgCount(args, 1, 2, "StringTools.hex");
                                     checkInt(args[0], "StringTools.hex", "n");
                                     if (args.length > 1) checkInt(args[1], "StringTools.hex", "digits");
                                     return args.length > 1 ? StringTools.hex(args[0], args[1]) : StringTools.hex(args[0]);
                                 case "fastCodeAt":
                                     checkArgCount(args, 2, 2, "StringTools.fastCodeAt");
                                     checkString(args[0], "StringTools.fastCodeAt", "s");
                                     checkInt(args[1], "StringTools.fastCodeAt", "index");
                                     return StringTools.fastCodeAt(args[0], args[1]);
                                 case "isSpace":
                                     checkArgCount(args, 2, 2, "StringTools.isSpace");
                                     checkString(args[0], "StringTools.isSpace", "s");
                                     checkInt(args[1], "StringTools.isSpace", "index");
                                     return StringTools.isSpace(args[0], args[1]);
                                 case "trim":
                                     checkArgCount(args, 1, 1, "StringTools.trim");
                                     checkString(args[0], "StringTools.trim", "s");
                                     return StringTools.trim(args[0]);
                                 case "ltrim":
                                     checkArgCount(args, 1, 1, "StringTools.ltrim");
                                     checkString(args[0], "StringTools.ltrim", "s");
                                     return StringTools.ltrim(args[0]);
                                 case "rtrim":
                                     checkArgCount(args, 1, 1, "StringTools.rtrim");
                                     checkString(args[0], "StringTools.rtrim", "s");
                                     return StringTools.rtrim(args[0]);
                                 case "replace":
                                     checkArgCount(args, 3, 3, "StringTools.replace");
                                     checkString(args[0], "StringTools.replace", "s");
                                     checkString(args[1], "StringTools.replace", "sub");
                                     checkString(args[2], "StringTools.replace", "by");
                                     return StringTools.replace(args[0], args[1], args[2]);
                                 case "startsWith":
                                     checkArgCount(args, 2, 2, "StringTools.startsWith");
                                     checkString(args[0], "StringTools.startsWith", "s");
                                     checkString(args[1], "StringTools.startsWith", "prefix");
                                     return StringTools.startsWith(args[0], args[1]);
                                 case "endsWith":
                                     checkArgCount(args, 2, 2, "StringTools.endsWith");
                                     checkString(args[0], "StringTools.endsWith", "s");
                                     checkString(args[1], "StringTools.endsWith", "suffix");
                                     return StringTools.endsWith(args[0], args[1]);
                                 case "lpad":
                                     checkArgCount(args, 3, 3, "StringTools.lpad");
                                     checkString(args[0], "StringTools.lpad", "s");
                                     checkString(args[1], "StringTools.lpad", "char");
                                     checkInt(args[2], "StringTools.lpad", "length");
                                     return StringTools.lpad(args[0], args[1], args[2]);
                                 case "rpad":
                                     checkArgCount(args, 3, 3, "StringTools.rpad");
                                     checkString(args[0], "StringTools.rpad", "s");
                                     checkString(args[1], "StringTools.rpad", "char");
                                     checkInt(args[2], "StringTools.rpad", "length");
                                     return StringTools.rpad(args[0], args[1], args[2]);
                                 default:
                             }
                         }
                        if (obj == Math) {
                            var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                            switch (field) {
                                case "abs":
                                    checkArgCount(args, 1, 1, "Math.abs");
                                    checkNum(args[0], "Math.abs");
                                    return Math.abs(args[0]);
                                case "sin":
                                    checkArgCount(args, 1, 1, "Math.sin");
                                    checkNum(args[0], "Math.sin");
                                    return Math.sin(args[0]);
                                case "cos":
                                    checkArgCount(args, 1, 1, "Math.cos");
                                    checkNum(args[0], "Math.cos");
                                    return Math.cos(args[0]);
                                case "tan":
                                    checkArgCount(args, 1, 1, "Math.tan");
                                    checkNum(args[0], "Math.tan");
                                    return Math.tan(args[0]);
                                case "atan2":
                                    checkArgCount(args, 2, 2, "Math.atan2");
                                    checkNum(args[0], "Math.atan2", "y");
                                    checkNum(args[1], "Math.atan2", "x");
                                    return Math.atan2(args[0], args[1]);
                                case "sqrt":
                                    checkArgCount(args, 1, 1, "Math.sqrt");
                                    checkNum(args[0], "Math.sqrt");
                                    return Math.sqrt(args[0]);
                                case "pow":
                                    checkArgCount(args, 2, 2, "Math.pow");
                                    checkNum(args[0], "Math.pow", "base");
                                    checkNum(args[1], "Math.pow", "exponent");
                                    return Math.pow(args[0], args[1]);
                                case "floor":
                                    checkArgCount(args, 1, 1, "Math.floor");
                                    checkNum(args[0], "Math.floor");
                                    return Math.floor(args[0]);
                                case "ceil":
                                    checkArgCount(args, 1, 1, "Math.ceil");
                                    checkNum(args[0], "Math.ceil");
                                    return Math.ceil(args[0]);
                                case "round":
                                    checkArgCount(args, 1, 1, "Math.round");
                                    checkNum(args[0], "Math.round");
                                    return Math.round(args[0]);
                                case "random":
                                    checkArgCount(args, 0, 0, "Math.random");
                                    return Math.random();
                                case "min":
                                    checkArgCount(args, 2, 2, "Math.min");
                                    checkNum(args[0], "Math.min", "a");
                                    checkNum(args[1], "Math.min", "b");
                                    return Math.min(args[0], args[1]);
                                case "max":
                                    checkArgCount(args, 2, 2, "Math.max");
                                    checkNum(args[0], "Math.max", "a");
                                    checkNum(args[1], "Math.max", "b");
                                    return Math.max(args[0], args[1]);
                                case "acos":
                                    checkArgCount(args, 1, 1, "Math.acos");
                                    checkNum(args[0], "Math.acos");
                                    return Math.acos(args[0]);
                                case "asin":
                                    checkArgCount(args, 1, 1, "Math.asin");
                                    checkNum(args[0], "Math.asin");
                                    return Math.asin(args[0]);
                                case "atan":
                                    checkArgCount(args, 1, 1, "Math.atan");
                                    checkNum(args[0], "Math.atan");
                                    return Math.atan(args[0]);
                                case "exp":
                                    checkArgCount(args, 1, 1, "Math.exp");
                                    checkNum(args[0], "Math.exp");
                                    return Math.exp(args[0]);
                                case "log":
                                    checkArgCount(args, 1, 1, "Math.log");
                                    checkNum(args[0], "Math.log");
                                    return Math.log(args[0]);
                                case "isNaN":
                                    checkArgCount(args, 1, 1, "Math.isNaN");
                                    return Math.isNaN(args[0]);
                                case "isFinite":
                                    checkArgCount(args, 1, 1, "Math.isFinite");
                                    return Math.isFinite(args[0]);
                                default:
                            }
                        }
                        if (Std.isOfType(obj, haxe.Constraints.IMap)) {
                            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
                            var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                            switch (field) {
                                case "exists":
                                    checkArgCount(args, 1, 1, "Map.exists");
                                    return map.exists(args[0]);
                                case "get":
                                    checkArgCount(args, 1, 1, "Map.get");
                                    return map.get(args[0]);
                                case "set":
                                    checkArgCount(args, 2, 2, "Map.set");
                                    map.set(args[0], args[1]);
                                    return null;
                                case "remove":
                                    checkArgCount(args, 1, 1, "Map.remove");
                                    return map.remove(args[0]);
                                case "clear":
                                    checkArgCount(args, 0, 0, "Map.clear");
                                    map.clear();
                                    return null;
                                case "keys":
                                    checkArgCount(args, 0, 0, "Map.keys");
                                    return map.keys();
                                case "iterator":
                                    checkArgCount(args, 0, 0, "Map.iterator");
                                    return map.iterator();
                                case "keyValueIterator":
                                    checkArgCount(args, 0, 0, "Map.keyValueIterator");
                                    return map.keyValueIterator();
                                case "toString":
                                    checkArgCount(args, 0, 0, "Map.toString");
                                    return map.toString();
                                default:
                            }
                        }
                        var method = Reflect.field(obj, field);
                        if (method != null && Reflect.isFunction(method)) {
                            var args = [for (a in argsExprs) eval(a, scope)];
                            return Reflect.callMethod(obj, method, args);
                        }
                        
                        // Check if this is an abstract method redirection call
                        for (absName in haxiom.FFI.exposedAbstracts.keys()) {
                            var absInfo = haxiom.FFI.exposedAbstracts.get(absName);
                            if (absInfo.methods.indexOf(field) != -1) {
                                var matchesType = false;
                                switch (absInfo.underlying) {
                                    case "Int": matchesType = Std.isOfType(obj, Int);
                                    case "Float": matchesType = Std.isOfType(obj, Float);
                                    case "String": matchesType = Std.isOfType(obj, String);
                                    case "Bool": matchesType = Std.isOfType(obj, Bool);
                                    default:
                                        var cls = Type.resolveClass(absInfo.underlying);
                                        if (cls != null) matchesType = Std.isOfType(obj, cls);
                                }
                                
                                if (matchesType) {
                                    var implCls = resolveAbstractImpl(absName, absInfo.implClass);
                                    if (implCls != null) {
                                        var m = Reflect.field(implCls, field);
                                        if (m != null) {
                                            var args = [for (a in argsExprs) eval(a, scope)];
                                            return Reflect.callMethod(null, m, [obj].concat(args));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                var callee = eval(calleeExpr, scope);
                var args = [for (a in argsExprs) eval(a, scope)];
                
                if (Reflect.isFunction(callee) && Type.getClassName(cast callee) == null) {
                    return Reflect.callMethod(null, callee, args);
                }
                
                if (Std.isOfType(callee, HaxiomClass)) {
                    // Instantiate Haxiom class
                    var cls:HaxiomClass = cast callee;
                    var inst = new HaxiomInstance(cls);
                    
                    // Initialize default instance fields
                    var curr = cls;
                    while (curr != null) {
                        for (f in curr.fields) {
                            if (!f.isStatic) {
                                inst.fields.set(f.name, f.expr != null ? eval(f.expr, scope) : null);
                            }
                        }
                        curr = curr.parent;
                    }
                    
                    // Run constructor 'new'
                    var constr = findMethod(cls, "new");
                    if (constr != null) {
                        checkMemberAccess(cls, constr.isPublic);
                        var cScope = new Scope(scope);
                        cScope.declare("this", inst);
                        for (i in 0...constr.args.length) {
                            var arg = constr.args[i];
                            var val = i < args.length ? args[i] : null;
                            checkType(val, arg.type, cScope);
                            cScope.declare(arg.name, val, arg.type);
                        }
                        var oldThis = currentThis;
                        currentThis = inst;
                        var oldConstrInst = currentConstructorInstance;
                        currentConstructorInstance = inst;
                        pushFrame(cls.name + ".new", constr.body.pos);
                        try {
                            eval(constr.body, cScope);
                            popFrame();
                        } catch (e:ControlFlow) {
                            popFrame();
                            switch (e) {
                                case Return(_): // constructors return instance implicitly
                                default: throw e;
                            }
                        } catch (err:Dynamic) {
                            popFrame();
                            throw err;
                        }
                        currentConstructorInstance = oldConstrInst;
                        currentThis = oldThis;
                    }
                    return inst;
                }
                
                if (callee == null) {
                    throw "Callee is null or undefined";
                }
                
                if (Type.getClassName(cast callee) != null) {
                    var className = Type.getClassName(cast callee);
                    switch (className) {
                        case "haxe.ds.StringMap":
                            return new haxe.ds.StringMap<Dynamic>();
                        case "haxe.ds.IntMap":
                            return new haxe.ds.IntMap<Dynamic>();
                        case "haxe.ds.ObjectMap":
                            return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
                        default:
                            return Type.createInstance(cast callee, args);
                    }
                }
                
                throw "Callee is not a callable function or constructor";

            case ENew(typeDecl, argsExprs):
                var args = [for (a in argsExprs) eval(a, scope)];
                switch (typeDecl) {
                    case TPath(path, params):
                        var fqName = path.join(".");
                        var callee:Dynamic = resolveTypePath(path, scope);
                        
                        // 1. Check Generic Mapping Lookup
                        if (params.length > 0) {
                            var paramNames = [];
                            for (p in params) {
                                switch (p) {
                                    case TPath(pPath, _):
                                        var resolvedParam = resolveTypePath(pPath, scope);
                                        if (resolvedParam != null) {
                                            if (Std.isOfType(resolvedParam, Class)) {
                                                var className = Type.getClassName(resolvedParam);
                                                if (className != null) {
                                                    paramNames.push(className);
                                                } else {
                                                    paramNames.push(pPath.join("."));
                                                }
                                            } else if (Std.isOfType(resolvedParam, HaxiomClass)) {
                                                paramNames.push((cast resolvedParam : HaxiomClass).name);
                                            } else {
                                                paramNames.push(pPath.join("."));
                                            }
                                        } else {
                                            paramNames.push(pPath.join("."));
                                        }
                                    default:
                                        paramNames.push("Dynamic");
                                }
                            }
                            var genericSig = fqName + "<" + paramNames.join(",") + ">";
                            var mappedGenClass = haxiom.FFI.exposedGenerics.get(genericSig);
                            if (mappedGenClass != null) {
                                var cls = Type.resolveClass(mappedGenClass);
                                if (cls != null) callee = cls;
                            }
                        }
                        
                        // 2. Check Multi-type Map Factory
                        if (fqName == "Map" || fqName == "haxe.ds.Map") {
                            if (params.length > 0) {
                                switch (params[0]) {
                                    case TPath(pPath, _):
                                        var keyName = pPath[pPath.length - 1];
                                        if (keyName == "String") {
                                            return new haxe.ds.StringMap<Dynamic>();
                                        } else if (keyName == "Int") {
                                            return new haxe.ds.IntMap<Dynamic>();
                                        } else {
                                            return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
                                        }
                                    default:
                                }
                            }
                            return new haxe.ds.StringMap<Dynamic>();
                        }
                        
                        // 3. Check Exposed Abstracts constructor redirection
                        var absInfo = haxiom.FFI.exposedAbstracts.get(fqName);
                        if (absInfo != null) {
                            var implCls = resolveAbstractImpl(fqName, absInfo.implClass);
                            if (implCls != null) {
                                var newMethod = Reflect.field(implCls, "_new");
                                if (newMethod != null) {
                                    return Reflect.callMethod(null, newMethod, args);
                                }
                            }
                        }
                        
                        // 4. Instantiate Class (Haxiom or Native)
                        if (callee == null) {
                            throw 'Class not found: $fqName';
                        }
                        
                        if (Std.isOfType(callee, HaxiomClass)) {
                            var cls:HaxiomClass = cast callee;
                            var inst = new HaxiomInstance(cls);
                            
                            var curr = cls;
                            while (curr != null) {
                                for (f in curr.fields) {
                                    if (!f.isStatic) {
                                        inst.fields.set(f.name, f.expr != null ? eval(f.expr, scope) : null);
                                    }
                                }
                                curr = curr.parent;
                            }
                            
                            var constr = findMethod(cls, "new");
                            if (constr != null) {
                                checkMemberAccess(cls, constr.isPublic);
                                var cScope = new Scope(scope);
                                cScope.declare("this", inst);
                                for (i in 0...constr.args.length) {
                                    var arg = constr.args[i];
                                    var val = i < args.length ? args[i] : null;
                                    checkType(val, arg.type, cScope);
                                    cScope.declare(arg.name, val, arg.type);
                                }
                                var oldThis = currentThis;
                                currentThis = inst;
                                var oldConstrInst = currentConstructorInstance;
                                currentConstructorInstance = inst;
                                pushFrame(cls.name + ".new", constr.body.pos);
                                try {
                                    eval(constr.body, cScope);
                                    popFrame();
                                } catch (e:ControlFlow) {
                                    popFrame();
                                    switch (e) {
                                        case Return(_):
                                        default: throw e;
                                    }
                                } catch (err:Dynamic) {
                                    popFrame();
                                    throw err;
                                }
                                currentConstructorInstance = oldConstrInst;
                                currentThis = oldThis;
                            }
                            return inst;
                        }
                        
                        if (Type.getClassName(cast callee) != null) {
                            var className = Type.getClassName(cast callee);
                            switch (className) {
                                case "haxe.ds.StringMap":
                                    return new haxe.ds.StringMap<Dynamic>();
                                case "haxe.ds.IntMap":
                                    return new haxe.ds.IntMap<Dynamic>();
                                case "haxe.ds.ObjectMap":
                                    return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
                                default:
                                    return Type.createInstance(cast callee, args);
                            }
                        }
                        
                        throw 'Cannot instantiate type: $fqName';
                    default:
                        throw "Constructor call expects a type path";
                }

            case EArrayDecl(values):
                return [for (v in values) eval(v, scope)];

            case EObjectDecl(fields):
                var obj = {};
                for (f in fields) {
                    Reflect.setField(obj, f.name, eval(f.expr, scope));
                }
                return obj;

            case EMapDecl(values):
                var evaluated = [];
                var allString = true;
                var allInt = true;
                for (kv in values) {
                    var k = eval(kv.key, scope);
                    var v = eval(kv.value, scope);
                    evaluated.push({ key: k, value: v });
                    if (!Std.isOfType(k, String)) allString = false;
                    if (!Std.isOfType(k, Int)) allInt = false;
                }
                var map:haxe.Constraints.IMap<Dynamic, Dynamic> = null;
                if (allString) {
                    map = new haxe.ds.StringMap<Dynamic>();
                } else if (allInt) {
                    map = new haxe.ds.IntMap<Dynamic>();
                } else {
                    map = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
                }
                for (kv in evaluated) {
                    map.set(kv.key, kv.value);
                }
                return map;

            case EClass(name, fields, methods, parentName, interfaceNames):
                var parentCls = parentName != null ? scope.get(parentName) : null;
                var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
                var cls = new HaxiomClass(name, parentCls);
                cls.name = fqName;
                for (f in fields) {
                    cls.fields.set(f.name, f);
                    if (f.isStatic && f.expr != null) {
                        cls.staticFields.set(f.name, eval(f.expr, scope));
                    }
                }
                for (m in methods) {
                    cls.methods.set(m.name, m);
                }
                
                var implementedInterfaces = interfaceNames != null ? interfaceNames : [];
                if (implementedInterfaces.length > 0) {
                    for (itfName in implementedInterfaces) {
                        var itfVal = scope.get(itfName);
                        if (itfVal == null || !Std.isOfType(itfVal, HaxiomInterface)) {
                            throw 'Interface $itfName not found at ${pos.line}:${pos.col}';
                        }
                        var itf:HaxiomInterface = cast itfVal;
                        cls.interfaces.push(itf.name);
                        for (itfMethod in itf.methods) {
                            var classMethod = findMethod(cls, itfMethod.name);
                            if (classMethod == null) {
                                if (itfMethod.body != null) {
                                    classMethod = {
                                        name: itfMethod.name,
                                        args: itfMethod.args,
                                        retType: itfMethod.retType,
                                        body: itfMethod.body,
                                        isStatic: false,
                                        isPublic: true
                                    };
                                    cls.methods.set(itfMethod.name, classMethod);
                                } else {
                                    throw 'Class ${cls.name} does not implement method ${itfMethod.name} required by interface ${itf.name} at ${pos.line}:${pos.col}';
                                }
                            }
                            if (classMethod.args.length != itfMethod.args.length) {
                                throw 'Method ${cls.name}.${itfMethod.name} has argument count mismatch: expected ${itfMethod.args.length} but got ${classMethod.args.length} at ${pos.line}:${pos.col}';
                            }
                            for (i in 0...itfMethod.args.length) {
                                var itfArg = itfMethod.args[i];
                                var clsArg = classMethod.args[i];
                                if (itfArg.type != null && clsArg.type != null) {
                                    if (Std.string(itfArg.type) != Std.string(clsArg.type)) {
                                        throw 'Method ${cls.name}.${itfMethod.name} argument ${clsArg.name} type mismatch: expected ${itfArg.type} but got ${clsArg.type} at ${pos.line}:${pos.col}';
                                    }
                                }
                            }
                            if (itfMethod.retType != null && classMethod.retType != null) {
                                if (Std.string(itfMethod.retType) != Std.string(classMethod.retType)) {
                                    throw 'Method ${cls.name}.${itfMethod.name} return type mismatch: expected ${itfMethod.retType} but got ${classMethod.retType} at ${pos.line}:${pos.col}';
                                }
                            }
                        }
                    }
                }
                
                scope.declare(name, cls);
                if (globals != scope) {
                    globals.declare(name, cls);
                }
                if (currentPackage.length > 0) {
                    registerFullyQualified(fqName, cls, globals);
                }
                return cls;

            case EInterface(name, itfMethods, parents):
                var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
                var itf = new HaxiomInterface(name, parents);
                itf.name = fqName;
                for (m in itfMethods) {
                    itf.methods.set(m.name, m);
                }
                scope.declare(name, itf);
                if (globals != scope) {
                    globals.declare(name, itf);
                }
                if (currentPackage.length > 0) {
                    registerFullyQualified(fqName, itf, globals);
                }
                return itf;

            case EEnum(name, constructors):
                var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
                var haxiomEnum = new HaxiomEnum(name);
                haxiomEnum.name = fqName;
                for (c in constructors) {
                    haxiomEnum.constructors.set(c.name, c.args != null ? c.args : []);
                }
                scope.declare(name, haxiomEnum);
                if (globals != scope) {
                    globals.declare(name, haxiomEnum);
                }
                if (currentPackage.length > 0) {
                    registerFullyQualified(fqName, haxiomEnum, globals);
                }
                
                // Register constructors as builders or constants
                for (c in constructors) {
                    if (c.args == null) {
                        var instance = new HaxiomEnumInstance(haxiomEnum, c.name, []);
                        scope.declare(c.name, instance);
                        if (globals != scope) {
                            globals.declare(c.name, instance);
                        }
                    } else {
                        var numArgs = c.args.length;
                        var builderFunc:Dynamic = switch (numArgs) {
                            case 0: () -> new HaxiomEnumInstance(haxiomEnum, c.name, []);
                            case 1: (a) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a]);
                            case 2: (a, b) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b]);
                            case 3: (a, b, c) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b, c]);
                            case 4: (a, b, c, d) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b, c, d]);
                            default: (callArgs:Array<Dynamic>) -> new HaxiomEnumInstance(haxiomEnum, c.name, callArgs);
                        };
                        scope.declare(c.name, builderFunc);
                        if (globals != scope) {
                            globals.declare(c.name, builderFunc);
                        }
                    }
                }
                return haxiomEnum;

            case EPackage(path):
                currentPackage = path;
                return null;

            case EImport(path, alias):
                var fqName = path.join(".");
                var shortName = alias != null ? alias : path[path.length - 1];
                var targetName = path[path.length - 1];
                
                if (shortName == "*") {
                    var parentPath = path.slice(0, path.length - 1).join(".");
                    if (moduleResolver != null) {
                        var moduleScope = getOrLoadModule(parentPath);
                        if (moduleScope != null) {
                            for (key in moduleScope.variables.keys()) {
                                scope.declare(key, moduleScope.variables.get(key));
                            }
                        }
                    }
                    return null;
                }
                
                if (isImportWhitelisted(fqName)) {
                    var nativeClass = Type.resolveClass(fqName);
                    if (nativeClass != null) {
                        scope.declare(shortName, nativeClass);
                        return null;
                    }
                    var nativeEnum = Type.resolveEnum(fqName);
                    if (nativeEnum != null) {
                        scope.declare(shortName, nativeEnum);
                        return null;
                    }
                    
                    // Module check
                    if (FFI.exposedModules.exists(fqName)) {
                        var types = FFI.exposedModules.get(fqName);
                        for (typeFq in types) {
                            var subParts = typeFq.split(".");
                            var subShortName = subParts[subParts.length - 1];
                            var nc = Type.resolveClass(typeFq);
                            if (nc != null) {
                                scope.declare(subShortName, nc);
                            } else {
                                var ne = Type.resolveEnum(typeFq);
                                if (ne != null) {
                                    scope.declare(subShortName, ne);
                                }
                            }
                        }
                        return null;
                    }
                    
                    // Module subtype check
                    for (modKey in FFI.exposedModules.keys()) {
                        if (StringTools.startsWith(fqName, modKey + ".")) {
                            var subName = fqName.substr(modKey.length + 1);
                            var lastDot = modKey.lastIndexOf(".");
                            var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
                            var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;
                            
                            var nc = Type.resolveClass(runtimeFq);
                            if (nc != null) {
                                scope.declare(shortName, nc);
                                return null;
                            }
                            var ne = Type.resolveEnum(runtimeFq);
                            if (ne != null) {
                                scope.declare(shortName, ne);
                                return null;
                            }
                        }
                    }
                }
                
                if (moduleResolver != null) {
                    var moduleScope = getOrLoadModule(fqName);
                    if (moduleScope != null) {
                        if (moduleScope.variables.exists(targetName)) {
                            scope.declare(shortName, moduleScope.variables.get(targetName));
                            return null;
                        } else {
                            for (key in moduleScope.variables.keys()) {
                                if (key == targetName || StringTools.endsWith(key, "." + targetName)) {
                                    scope.declare(shortName, moduleScope.variables.get(key));
                                    return null;
                                }
                            }
                        }
                    }
                }
                
                throw 'Could not resolve import $fqName';

            case EUsing(path):
                var fqName = path.join(".");
                if (!isImportWhitelisted(fqName)) {
                    throw 'Using $fqName is not whitelisted';
                }
                var resolved = resolveTypePath(path, scope);
                if (resolved == null) {
                    throw 'Could not resolve using target: $fqName';
                }
                if (activeUsings.indexOf(resolved) == -1) {
                    activeUsings.push(resolved);
                }
                return null;

            case EThrow(expr):
                var val = eval(expr, scope);
                throw val;

            case ETry(tryExpr, catches):
                var stackDepth = callStack.length;
                try {
                    return eval(tryExpr, scope);
                } catch (flow:ControlFlow) {
                    throw flow;
                } catch (errVal:Dynamic) {
                    while (callStack.length > stackDepth) {
                        callStack.pop();
                    }
                    for (c in catches) {
                        if (c.type == null) {
                            var cScope = new Scope(scope);
                            cScope.declare(c.name, errVal);
                            return eval(c.body, cScope);
                        }
                        try {
                            checkType(errVal, c.type, scope);
                            var cScope = new Scope(scope);
                            cScope.declare(c.name, errVal, c.type);
                            return eval(c.body, cScope);
                        } catch (_:Dynamic) {
                            // Mismatch, try next catch block
                        }
                    }
                    throw errVal;
                }

            case ECast(expr, type):
                var val = eval(expr, scope);
                if (type != null) {
                    try {
                        checkType(val, type, scope);
                    } catch (err:Dynamic) {
                        throw 'Class cast error: expected ${typeToString(type)} but got ${val}';
                    }
                }
                return val;

            case EBlock(exprs):
                var bScope = (scope == globals) ? globals : new Scope(scope);
                var lastVal:Dynamic = null;
                for (expr in exprs) {
                    lastVal = eval(expr, bScope);
                }
                return lastVal;

            case EFunction(name, args, retType, body):
                var closure = new Scope(scope);
                var func = (callArgs:Array<Dynamic>) -> {
                    var fScope = new Scope(closure);
                    for (i in 0...args.length) {
                        var arg = args[i];
                        var val = i < callArgs.length ? callArgs[i] : null;
                        checkType(val, arg.type, fScope);
                        fScope.declare(arg.name, val, arg.type);
                    }
                    var funcName = name != null ? name : "anonymous";
                    pushFrame(funcName, body.pos);
                    try {
                        var res = eval(body, fScope);
                        checkType(res, retType, fScope);
                        popFrame();
                        return res;
                    } catch (flow:ControlFlow) {
                        popFrame();
                        switch (flow) {
                            case Return(val):
                                checkType(val, retType, fScope);
                                return val;
                            default: throw flow;
                        }
                    }
                };
                var haxeFunc:Dynamic = switch (args.length) {
                    case 0: () -> func([]);
                    case 1: (a) -> func([a]);
                    case 2: (a, b) -> func([a, b]);
                    case 3: (a, b, c) -> func([a, b, c]);
                    case 4: (a, b, c, d) -> func([a, b, c, d]);
                    default: (callArgs:Array<Dynamic>) -> func(callArgs);
                };
                if (name != null) {
                    scope.declare(name, haxeFunc);
                }
                return haxeFunc;

            case EIf(cond, e1, e2):
                var v = eval(cond, scope);
                if (v != false && v != null) {
                    return eval(e1, scope);
                } else if (e2 != null) {
                    return eval(e2, scope);
                }
                return null;

            case EWhile(cond, body):
                var lastVal:Dynamic = null;
                while (true) {
                    var c = eval(cond, scope);
                    if (c == false || c == null) break;
                    try {
                        lastVal = eval(body, scope);
                    } catch (flow:ControlFlow) {
                        switch (flow) {
                            case Break: return lastVal;
                            case Continue: continue;
                            case Return(val): throw Return(val);
                        }
                    }
                }
                return lastVal;

            case EDoWhile(cond, body):
                var lastVal:Dynamic = null;
                while (true) {
                    try {
                        lastVal = eval(body, scope);
                    } catch (flow:ControlFlow) {
                        switch (flow) {
                            case Break: return lastVal;
                            case Continue: // Fall through to condition check
                            case Return(val): throw Return(val);
                        }
                    }
                    var c = eval(cond, scope);
                    if (c == false || c == null) break;
                }
                return lastVal;

            case EFor(vName, iterableExpr, body):
                var iterable = eval(iterableExpr, scope);
                var lastVal:Dynamic = null;
                
                // Dynamic Haxe Iterator protocol
                if (iterable != null) {
                    var iterator:Dynamic = null;
                    if (Reflect.field(iterable, "iterator") != null) {
                        iterator = Reflect.callMethod(iterable, Reflect.field(iterable, "iterator"), []);
                    } else if (Std.isOfType(iterable, Array)) {
                        iterator = (cast iterable : Array<Dynamic>).iterator();
                    } else if (Std.isOfType(iterable, haxe.Constraints.IMap)) {
                        iterator = (cast iterable : haxe.Constraints.IMap<Dynamic, Dynamic>).iterator();
                    } else if (Std.isOfType(iterable, IntIterator)) {
                        iterator = iterable;
                    } else if (Reflect.field(iterable, "hasNext") != null && Reflect.field(iterable, "next") != null) {
                        iterator = iterable;
                    }
                    
                    if (iterator != null) {
                        if (Std.isOfType(iterator, IntIterator)) {
                            var it:IntIterator = cast iterator;
                            while (it.hasNext()) {
                                var item = it.next();
                                var fScope = new Scope(scope);
                                fScope.declare(vName, item);
                                try {
                                    lastVal = eval(body, fScope);
                                } catch (flow:ControlFlow) {
                                    switch (flow) {
                                        case Break: break;
                                        case Continue: continue;
                                        case Return(val): throw Return(val);
                                    }
                                }
                            }
                        } else if (Reflect.field(iterator, "hasNext") != null && Reflect.field(iterator, "next") != null) {
                            while (Reflect.callMethod(iterator, Reflect.field(iterator, "hasNext"), [])) {
                                var item = Reflect.callMethod(iterator, Reflect.field(iterator, "next"), []);
                                var fScope = new Scope(scope);
                                fScope.declare(vName, item);
                                try {
                                    lastVal = eval(body, fScope);
                                } catch (flow:ControlFlow) {
                                    switch (flow) {
                                        case Break: break;
                                        case Continue: continue;
                                        case Return(val): throw Return(val);
                                    }
                                }
                            }
                        }
                    }
                }
                return lastVal;

            case ESwitch(expr, cases, defExpr):
                var val = eval(expr, scope);
                var matched = false;
                var result:Dynamic = null;
                for (c in cases) {
                    for (vExpr in c.values) {
                        var caseScope = new Scope(scope);
                        if (matchPattern(val, vExpr, scope, caseScope)) {
                            var guardOk = true;
                            if (c.guard != null) {
                                var guardVal = eval(c.guard, caseScope);
                                if (guardVal != true) {
                                    guardOk = false;
                                }
                            }
                            if (guardOk) {
                                matched = true;
                                result = eval(c.expr, caseScope);
                                break;
                            }
                        }
                    }
                    if (matched) break;
                }
                if (!matched && defExpr != null) {
                    result = eval(defExpr, scope);
                }
                return result;

            case EReturn(retExpr):
                var val = retExpr != null ? eval(retExpr, scope) : null;
                throw Return(val);

            case EBreak:
                throw Break;

            case EContinue:
                throw Continue;
        }
        return null;
    }

    function assign(target:Expr, val:Dynamic, scope:Scope) {
        switch (target.def) {
            case EIdent(name):
                if (scope.exists(name)) {
                    scope.checkAndSet(name, val, this);
                } else if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
                    var inst:HaxiomInstance = cast currentThis;
                    var fDef = findFieldDef(inst.cls, name);
                    if (fDef != null && fDef.property != null && fDef.property.set == "set") {
                        var m = findMethod(inst.cls, "set_" + name);
                        if (m != null) {
                            Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
                            return;
                        }
                    }
                    if (fDef != null && fDef.isFinal) {
                        if (currentConstructorInstance != inst) {
                            throw 'Cannot reassign final field $name outside of constructor';
                        }
                    }
                    if (fDef != null && fDef.type != null) {
                        checkType(val, fDef.type, scope);
                    }
                    inst.fields.set(name, val);
                } else {
                    scope.checkAndSet(name, val, this);
                }
            case EField(objExpr, field):
                switch (objExpr.def) {
                    case EIdent("super"):
                        if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
                            var inst:HaxiomInstance = cast currentThis;
                            inst.fields.set(field, val);
                            return;
                        }
                        throw "Cannot use 'super' outside of a class instance";
                    default:
                }
                var obj = eval(objExpr, scope);
                if (Std.isOfType(obj, HaxiomInstance)) {
                    var inst:HaxiomInstance = cast obj;
                    var fDef = findFieldDef(inst.cls, field);
                    if (fDef != null && fDef.property != null && fDef.property.set == "set") {
                        var m = findMethod(inst.cls, "set_" + field);
                        if (m != null) {
                            Reflect.callMethod(null, bindMethod(obj, m), [val]);
                            return;
                        }
                    }
                    if (fDef != null && fDef.isFinal) {
                        if (currentConstructorInstance != inst) {
                            throw 'Cannot reassign final field $field outside of constructor';
                        }
                    }
                    if (fDef != null && fDef.type != null) {
                        checkType(val, fDef.type, scope);
                    }
                    inst.fields.set(field, val);
                } else {
                    if (Std.isOfType(obj, HaxiomClass)) {
                        var cls:HaxiomClass = cast obj;
                        var fDef = findFieldDef(cls, field);
                        if (fDef != null && fDef.isFinal) {
                            throw 'Cannot reassign static final field $field';
                        }
                        if (fDef != null && fDef.type != null) {
                            checkType(val, fDef.type, scope);
                        }
                        cls.staticFields.set(field, val);
                    } else {
                        Reflect.setField(obj, field, val);
                    }
                }
            default:
                throw "Invalid assignment target";
        }
    }

    function isSubclassOf(c1:HaxiomClass, c2:HaxiomClass):Bool {
        var curr = c1;
        while (curr != null) {
            if (curr == c2) return true;
            curr = curr.parent;
        }
        return false;
    }

    function checkMemberAccess(targetCls:HaxiomClass, isPublic:Bool):Void {
        if (isPublic) return;
        if (currentThis != null) {
            if (Std.isOfType(currentThis, HaxiomInstance)) {
                var inst:HaxiomInstance = cast currentThis;
                if (isSubclassOf(inst.cls, targetCls) || isSubclassOf(targetCls, inst.cls)) {
                    return;
                }
            } else if (Std.isOfType(currentThis, HaxiomClass)) {
                var cls:HaxiomClass = cast currentThis;
                if (isSubclassOf(cls, targetCls) || isSubclassOf(targetCls, cls)) {
                    return;
                }
            }
        }
        throw 'Cannot access private member of class ${targetCls.name}';
    }

    function matchPattern(val:Dynamic, pattern:Expr, scope:Scope, outBindings:Scope):Bool {
        switch (pattern.def) {
            case EIdent("_"):
                return true;
                
            case EIdent(name):
                if (scope.exists(name)) {
                    var inScopeVal = scope.get(name);
                    if (Std.isOfType(inScopeVal, HaxiomEnumInstance)) {
                        var enumInst:HaxiomEnumInstance = cast inScopeVal;
                        if (Std.isOfType(val, HaxiomEnumInstance)) {
                            var valInst:HaxiomEnumInstance = cast val;
                            return valInst.enumType == enumInst.enumType && valInst.constructorName == enumInst.constructorName;
                        }
                        return false;
                    } else if (Reflect.isEnumValue(inScopeVal)) {
                        if (Reflect.isEnumValue(val)) {
                            return Type.enumEq(val, inScopeVal);
                        }
                        return false;
                    }
                }
                outBindings.declare(name, val);
                return true;
                
            case ECall(calleeExpr, args):
                var constructorName = "";
                var expectedEnum:Dynamic = null;
                switch (calleeExpr.def) {
                    case EIdent(name): constructorName = name;
                    case EField(objExpr, field): 
                        constructorName = field;
                        try {
                            expectedEnum = eval(objExpr, scope);
                        } catch (e:Dynamic) {}
                    default:
                }
                
                if (constructorName != "") {
                    if (Std.isOfType(val, HaxiomEnumInstance)) {
                        var valInst:HaxiomEnumInstance = cast val;
                        if (valInst.constructorName == constructorName) {
                            if (expectedEnum != null && valInst.enumType != expectedEnum) {
                                return false;
                            }
                            if (args.length == valInst.args.length) {
                                for (i in 0...args.length) {
                                    if (!matchPattern(valInst.args[i], args[i], scope, outBindings)) {
                                        return false;
                                    }
                                }
                                return true;
                            }
                        }
                    } else if (Reflect.isEnumValue(val)) {
                        var nativeCtor = Type.enumConstructor(val);
                        var nativeParams = Type.enumParameters(val);
                        if (nativeCtor == constructorName) {
                            if (expectedEnum != null) {
                                var valEnum = Type.getEnum(val);
                                if (valEnum != expectedEnum) return false;
                            }
                            if (args.length == nativeParams.length) {
                                for (i in 0...args.length) {
                                    if (!matchPattern(nativeParams[i], args[i], scope, outBindings)) {
                                        return false;
                                    }
                                }
                                return true;
                            }
                        }
                    }
                }
                return false;
                
            default:
                var patVal = eval(pattern, scope);
                if (Std.isOfType(val, HaxiomEnumInstance) && Std.isOfType(patVal, HaxiomEnumInstance)) {
                    var valInst:HaxiomEnumInstance = cast val;
                    var patInst:HaxiomEnumInstance = cast patVal;
                    if (valInst.enumType != patInst.enumType || valInst.constructorName != patInst.constructorName) {
                        return false;
                    }
                    if (valInst.args.length != patInst.args.length) return false;
                    for (i in 0...valInst.args.length) {
                        if (valInst.args[i] != patInst.args[i]) return false;
                    }
                    return true;
                } else if (Reflect.isEnumValue(val) && Reflect.isEnumValue(patVal)) {
                    return Type.enumEq(val, patVal);
                }
                return val == patVal;
        }
    }

    function findMethod(cls:HaxiomClass, name:String):Dynamic {
        if (cls == null) return null;
        if (cls.methods.exists(name)) return cls.methods.get(name);
        return findMethod(cls.parent, name);
    }

    function findFieldDef(cls:HaxiomClass, name:String):Dynamic {
        if (cls == null) return null;
        if (cls.fields.exists(name)) return cls.fields.get(name);
        return findFieldDef(cls.parent, name);
    }

    function findStaticMethod(cls:HaxiomClass, name:String):Dynamic {
        if (cls == null) return null;
        if (cls.methods.exists(name)) {
            var m = cls.methods.get(name);
            if (m.isStatic) return m;
        }
        return findStaticMethod(cls.parent, name);
    }

    function bindMethod(obj:Dynamic, method:{name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, body:Expr, isStatic:Bool, isPublic:Bool}):Dynamic {
        var func = (callArgs:Array<Dynamic>) -> {
            var fScope = new Scope(globals);
            fScope.declare("this", obj);
            for (i in 0...method.args.length) {
                var arg = method.args[i];
                var val = i < callArgs.length ? callArgs[i] : null;
                checkType(val, arg.type, fScope);
                fScope.declare(arg.name, val, arg.type);
            }
            var oldThis = currentThis;
            currentThis = obj;
            var className = (obj != null && Std.isOfType(obj, HaxiomInstance)) ? (cast(obj, HaxiomInstance).cls.name) : "toplevel";
            pushFrame(className + "." + method.name, method.body.pos);
            try {
                var res = eval(method.body, fScope);
                checkType(res, method.retType, fScope);
                currentThis = oldThis;
                popFrame();
                return res;
            } catch (flow:ControlFlow) {
                currentThis = oldThis;
                popFrame();
                switch (flow) {
                    case Return(val):
                        checkType(val, method.retType, fScope);
                        return val;
                    default: throw flow;
                }
            }
        };
        var boundFunc:Dynamic = switch (method.args.length) {
            case 0: () -> func([]);
            case 1: (a) -> func([a]);
            case 2: (a, b) -> func([a, b]);
            case 3: (a, b, c) -> func([a, b, c]);
            case 4: (a, b, c, d) -> func([a, b, c, d]);
            default: (callArgs:Array<Dynamic>) -> func(callArgs);
        };
        return boundFunc;
    }

    function bindStaticExtensionMethod(obj:Dynamic, method:{name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, body:Expr, isStatic:Bool, isPublic:Bool}):Dynamic {
        var func = (callArgs:Array<Dynamic>) -> {
            var fScope = new Scope(globals);
            var fullArgs = [obj].concat(callArgs);
            for (i in 0...method.args.length) {
                var arg = method.args[i];
                var val = i < fullArgs.length ? fullArgs[i] : null;
                checkType(val, arg.type, fScope);
                fScope.declare(arg.name, val, arg.type);
            }
            var oldThis = currentThis;
            currentThis = null;
            var className = (obj != null && Std.isOfType(obj, HaxiomInstance)) ? (cast(obj, HaxiomInstance).cls.name) : "static";
            pushFrame(className + "." + method.name, method.body.pos);
            try {
                var res = eval(method.body, fScope);
                checkType(res, method.retType, fScope);
                currentThis = oldThis;
                popFrame();
                return res;
            } catch (flow:ControlFlow) {
                currentThis = oldThis;
                popFrame();
                switch (flow) {
                    case Return(val):
                        checkType(val, method.retType, fScope);
                        return val;
                    default: throw flow;
                }
            }
        };
        var arity = method.args.length - 1;
        if (arity < 0) arity = 0;
        var boundFunc:Dynamic = switch (arity) {
            case 0: () -> func([]);
            case 1: (a) -> func([a]);
            case 2: (a, b) -> func([a, b]);
            case 3: (a, b, c) -> func([a, b, c]);
            case 4: (a, b, c, d) -> func([a, b, c, d]);
            default: (callArgs:Array<Dynamic>) -> func(callArgs);
        };
        return boundFunc;
    }

    function resolveUsing(obj:Dynamic, field:String):Dynamic {
        if (activeUsings == null || activeUsings.length == 0) return null;
        var i = activeUsings.length - 1;
        while (i >= 0) {
            var usingTarget = activeUsings[i];
            if (usingTarget != null) {
                if (Std.isOfType(usingTarget, HaxiomClass)) {
                    var cls:HaxiomClass = cast usingTarget;
                    var m = findStaticMethod(cls, field);
                    if (m != null) {
                        return bindStaticExtensionMethod(obj, m);
                    }
                } else {
                    var m = Reflect.field(usingTarget, field);
                    if (m != null && Reflect.isFunction(m)) {
                        return Reflect.makeVarArgs(function(args:Array<Dynamic>) {
                            return Reflect.callMethod(null, m, [obj].concat(args));
                        });
                    }
                }
            }
            i--;
        }
        return null;
    }

    public function checkType(val:Dynamic, type:TypeDecl, scope:Scope):Void {
        if (type == null) return;
        switch (type) {
            case TPath(path, params):
                var typeName = path.join(".");
                switch (typeName) {
                    case "Dynamic": return;
                    case "Void":
                        if (val != null) throw "Type mismatch: expected Void";
                    case "Int":
                        if (!Std.isOfType(val, Int)) throw 'Type mismatch: expected Int but got ${val == null ? "null" : Type.getClassName(Type.getClass(val)) != null ? Type.getClassName(Type.getClass(val)) : Std.string(val)}';
                    case "Float":
                        if (!Std.isOfType(val, Float) && !Std.isOfType(val, Int)) throw 'Type mismatch: expected Float but got ${val == null ? "null" : Std.string(val)}';
                    case "String":
                        if (!Std.isOfType(val, String)) throw 'Type mismatch: expected String but got ${val == null ? "null" : Std.string(val)}';
                    case "Bool":
                        if (!Std.isOfType(val, Bool)) throw 'Type mismatch: expected Bool but got ${val == null ? "null" : Std.string(val)}';
                    case "Array":
                        if (val == null) return;
                        if (!Std.isOfType(val, Array)) throw 'Type mismatch: expected Array but got ${val == null ? "null" : Std.string(val)}';
                    case "List" | "haxe.ds.List":
                        if (val == null) return;
                        if (!Std.isOfType(val, haxe.ds.List)) throw 'Type mismatch: expected List but got ${val == null ? "null" : Std.string(val)}';
                    case "Map" | "haxe.ds.Map":
                        if (val == null) return;
                        if (!Std.isOfType(val, haxe.Constraints.IMap)) throw 'Type mismatch: expected Map but got ${val == null ? "null" : Std.string(val)}';
                    default:
                        // Subclass type checking for Haxiom classes
                        if (scope.exists(typeName)) {
                            var cls = scope.get(typeName);
                            if (Std.isOfType(cls, HaxiomClass)) {
                                if (val == null) return;
                                if (!Std.isOfType(val, HaxiomInstance)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                                var inst:HaxiomInstance = cast val;
                                var curr = inst.cls;
                                while (curr != null) {
                                    if (curr == cls) return;
                                    curr = curr.parent;
                                }
                                throw 'Type mismatch: expected $typeName but got ${inst.cls.name}';
                            }
                            if (Std.isOfType(cls, HaxiomInterface)) {
                                if (val == null) return;
                                if (!Std.isOfType(val, HaxiomInstance)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                                var inst:HaxiomInstance = cast val;
                                var itf:HaxiomInterface = cast cls;
                                var curr = inst.cls;
                                while (curr != null) {
                                    for (itfName in curr.interfaces) {
                                        if (itfName == itf.name) return;
                                    }
                                    curr = curr.parent;
                                }
                                throw 'Type mismatch: expected interface $typeName but got ${inst.cls.name}';
                            }
                            if (Std.isOfType(cls, HaxiomEnum)) {
                                if (val == null) return;
                                if (!Std.isOfType(val, HaxiomEnumInstance)) throw 'Type mismatch: expected $typeName';
                                var inst:HaxiomEnumInstance = cast val;
                                var enumCls:HaxiomEnum = cast cls;
                                if (inst.enumType == enumCls) return;
                                throw 'Type mismatch: expected enum $typeName but got ${inst.enumType.name}';
                            }
                        }
                        // Native check
                        var nativeClass = Type.resolveClass(typeName);
                        if (nativeClass != null) {
                            if (val == null) return;
                            if (!Std.isOfType(val, nativeClass)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                            return;
                        }
                        throw 'Type mismatch: expected $typeName';
                }
            case TFun(args, ret):
                if (!Reflect.isFunction(val)) throw "Type mismatch: expected Function";
            case TAnonymous(fields):
                if (val == null) return;
                if (Reflect.isFunction(val) || Std.isOfType(val, Int) || Std.isOfType(val, Float) || Std.isOfType(val, Bool) || Std.isOfType(val, String)) {
                    throw 'Type mismatch: expected anonymous structure but got ' + getTypeName(val);
                }
                for (field in fields) {
                    var res = hasAndGetField(val, field.name);
                    if (!res.exists) {
                        throw 'Type mismatch: object is missing field "${field.name}"';
                    }
                    try {
                        checkType(res.val, field.type, scope);
                    } catch (e:Dynamic) {
                        throw 'Type mismatch in field "${field.name}": ' + Std.string(e);
                    }
                }
            default:
        }
    }

    function hasAndGetField(obj:Dynamic, fieldName:String):{exists:Bool, val:Dynamic} {
        if (obj == null) return {exists: false, val: null};
        if (Std.isOfType(obj, HaxiomInstance)) {
            var inst:HaxiomInstance = cast obj;
            if (inst.fields.exists(fieldName)) {
                return {exists: true, val: inst.fields.get(fieldName)};
            }
            var m = findMethod(inst.cls, fieldName);
            if (m != null) {
                return {exists: true, val: bindMethod(inst, m)};
            }
            var fDef = findFieldDef(inst.cls, fieldName);
            if (fDef != null) {
                var fieldVal:Dynamic = null;
                if (fDef.property != null && fDef.property.get == "get") {
                    var gm = findMethod(inst.cls, "get_" + fieldName);
                    if (gm != null) {
                        fieldVal = Reflect.callMethod(null, bindMethod(inst, gm), []);
                    }
                }
                return {exists: true, val: fieldVal};
            }
            return {exists: false, val: null};
        }
        
        if (Reflect.hasField(obj, fieldName)) {
            return {exists: true, val: Reflect.field(obj, fieldName)};
        }
        var prop = Reflect.getProperty(obj, fieldName);
        if (prop != null) {
            return {exists: true, val: prop};
        }
        var f = Reflect.field(obj, fieldName);
        if (f != null) {
            return {exists: true, val: f};
        }
        return {exists: false, val: null};
    }

    // Dynamic map/array subscript helpers
    function getSubscript(obj:Dynamic, key:Dynamic):Dynamic {
        if (Std.isOfType(obj, Array)) {
            return (cast obj : Array<Dynamic>)[cast key];
        } else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
            return (cast obj : haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
        } else if (Std.isOfType(obj, HaxiomInstance)) {
            return (cast obj : HaxiomInstance).fields.get(key);
        }
        throw "Target object does not support subscript access";
    }

    function setSubscript(obj:Dynamic, key:Dynamic, val:Dynamic):Void {
        if (Std.isOfType(obj, Array)) {
            (cast obj : Array<Dynamic>)[cast key] = val;
        } else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
            (cast obj : haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, val);
        } else if (Std.isOfType(obj, HaxiomInstance)) {
            (cast obj : HaxiomInstance).fields.set(key, val);
        } else {
            throw "Target object does not support subscript assignment";
        }
    }

    function typeToString(type:TypeDecl):String {
        if (type == null) return "Dynamic";
        switch (type) {
            case TPath(path, params):
                var base = path.join(".");
                if (params.length > 0) {
                    return base + "<" + params.map(typeToString).join(", ") + ">";
                }
                return base;
            case TFun(args, ret):
                return "(" + args.map(typeToString).join(", ") + ") -> " + typeToString(ret);
            case TAnonymous(fields):
                return "{" + fields.map(f -> f.name + ":" + typeToString(f.type)).join(", ") + "}";
        }
    }

    function getExprPath(e:Expr):Array<String> {
        if (e == null) return null;
        switch (e.def) {
            case EIdent(name):
                return [name];
            case EField(objExpr, field):
                var sub = getExprPath(objExpr);
                if (sub != null) {
                    return sub.concat([field]);
                }
            default:
        }
        return null;
    }

    function isPackageObject(val:Dynamic):Bool {
        if (val == null) return false;
        return Reflect.field(val, "__isHaxiomPackage") == true;
    }

    function tryResolveExpressionPath(e:Expr, scope:Scope):{success:Bool, value:Dynamic} {
        var path = getExprPath(e);
        if (path == null || path.length == 0) return {success: false, value: null};
        
        var first = path[0];
        if (scope.exists(first)) {
            var val = scope.get(first);
            if (!isPackageObject(val)) {
                return {success: false, value: null};
            }
        }
        
        var len = path.length;
        while (len > 0) {
            var prefix = path.slice(0, len);
            var fqName = prefix.join(".");
            
            var resolvedType:Dynamic = null;
            var cls = Type.resolveClass(fqName);
            if (cls != null) {
                resolvedType = cls;
            } else {
                var enm = Type.resolveEnum(fqName);
                if (enm != null) {
                    resolvedType = enm;
                }
            }
            
            if (resolvedType == null) {
                for (modKey in FFI.exposedModules.keys()) {
                    if (StringTools.startsWith(fqName, modKey + ".")) {
                        var subName = fqName.substr(modKey.length + 1);
                        var lastDot = modKey.lastIndexOf(".");
                        var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
                        var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;
                        
                        var c = Type.resolveClass(runtimeFq);
                        if (c != null) {
                            resolvedType = c;
                            break;
                        }
                        var enm = Type.resolveEnum(runtimeFq);
                        if (enm != null) {
                            resolvedType = enm;
                            break;
                        }
                    }
                }
            }
            
            if (resolvedType != null) {
                var remaining = path.slice(len);
                var current:Dynamic = resolvedType;
                for (field in remaining) {
                    if (current == null) {
                        return {success: true, value: null};
                    }
                    current = Reflect.field(current, field);
                }
                return {success: true, value: current};
            }
            
            len--;
        }
        
        return {success: false, value: null};
    }

    function resolveTypePath(path:Array<String>, scope:Scope):Dynamic {
        var name = path[0];
        var val:Dynamic = null;
        if (scope.exists(name)) {
            val = scope.get(name);
            for (i in 1...path.length) {
                if (val == null) break;
                val = Reflect.field(val, path[i]);
            }
        }
        
        if (val != null) return val;
        
        var fqName = path.join(".");
        var cls = Type.resolveClass(fqName);
        if (cls != null) return cls;
        var enm = Type.resolveEnum(fqName);
        if (enm != null) return enm;
        
        // Check if fqName is a module subtype compile-time path
        for (modKey in FFI.exposedModules.keys()) {
            if (StringTools.startsWith(fqName, modKey + ".")) {
                var subName = fqName.substr(modKey.length + 1);
                var lastDot = modKey.lastIndexOf(".");
                var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
                var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;
                
                var c = Type.resolveClass(runtimeFq);
                if (c != null) return c;
                var e = Type.resolveEnum(runtimeFq);
                if (e != null) return e;
            }
        }
        return null;
    }

    public function registerFullyQualified(fullName:String, value:Dynamic, scope:Scope) {
        var parts = fullName.split(".");
        if (parts.length == 1) {
            scope.declare(parts[0], value);
            return;
        }
        
        var current:Dynamic = null;
        var firstPart = parts[0];
        if (scope.exists(firstPart)) {
            current = scope.get(firstPart);
        } else {
            current = {};
            Reflect.setField(current, "__isHaxiomPackage", true);
            scope.declare(firstPart, current);
        }
        
        for (i in 1...parts.length - 1) {
            var part = parts[i];
            if (Reflect.hasField(current, part)) {
                current = Reflect.field(current, part);
            } else {
                var nextObj = {};
                Reflect.setField(nextObj, "__isHaxiomPackage", true);
                Reflect.setField(current, part, nextObj);
                current = nextObj;
            }
        }
        
        Reflect.setField(current, parts[parts.length - 1], value);
    }

    function isImportWhitelisted(fqName:String):Bool {
        if (importWhitelist == null) return true;
        for (pattern in importWhitelist) {
            if (pattern == fqName) return true;
            if (StringTools.endsWith(pattern, "*")) {
                var prefix = pattern.substring(0, pattern.length - 1);
                if (StringTools.startsWith(fqName, prefix)) return true;
            }
        }
        return false;
    }

    function resolveAbstractImpl(absName:String, implClassName:String):Dynamic {
        var implCls = haxiom.FFI.abstractImpls.get(absName);
        if (implCls == null) {
            implCls = Type.resolveClass(implClassName);
        }
        return implCls;
    }

    function getOrLoadModule(fqName:String):Scope {
        if (importedModules.exists(fqName)) {
            return importedModules.get(fqName);
        }
        if (moduleResolver != null) {
            var src = moduleResolver(fqName);
            if (src != null) {
                var moduleScope = new Scope(globals);
                var lexer = new Lexer(src);
                var tokens = lexer.tokenize();
                var parser = new Parser(tokens);
                var ast = parser.parse();
                
                var oldPkg = currentPackage;
                currentPackage = [];
                
                switch (ast.def) {
                    case EBlock(exprs):
                        for (expr in exprs) {
                            eval(expr, moduleScope);
                        }
                    default:
                        eval(ast, moduleScope);
                }
                
                currentPackage = oldPkg;
                
                importedModules.set(fqName, moduleScope);
                return moduleScope;
            }
        }
        return null;
    }
}
