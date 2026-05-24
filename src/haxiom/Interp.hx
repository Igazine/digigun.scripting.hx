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
        if (type != null) types.set(name, type);
        if (isFinal == true) finals.set(name, true);
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
    public var methods:Map<String, {name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>}> = new Map();
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
    public var constructor:String;
    public var args:Array<Dynamic>;

    public function new(enumType:HaxiomEnum, constructor:String, args:Array<Dynamic>) {
        this.enumType = enumType;
        this.constructor = constructor;
        this.args = args;
    }

    public function toString():String {
        if (args == null || args.length == 0) return constructor;
        return constructor + "(" + args.join(", ") + ")";
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

    public var callStack:Array<{method:String, pos:Pos}> = [];
    public var errorHandler:Null<ScriptException->Void> = null;

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
        var stdObj = {
            string: Std.string,
            parseInt: Std.parseInt,
            parseFloat: Std.parseFloat,
            isOfType: (v:Dynamic, t:Dynamic) -> {
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
        
        // Ensure DCE keep
        HaxiomAnchor.keep();
    }

    public function execute(expr:Expr):Dynamic {
        currentPackage = [];
        callStack = [];
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
                traceLines.push('Runtime Error: ' + Std.string(e));
                var i = callStack.length - 1;
                while (i >= 0) {
                    var frame = callStack[i];
                    var fileInfo = frame.pos.file != null ? frame.pos.file : "script";
                    traceLines.push('    at ' + frame.method + ' (' + fileInfo + ':' + frame.pos.line + ')');
                    i--;
                }
                if (callStack.length == 0) {
                    var fileInfo = expr.pos.file != null ? expr.pos.file : "script";
                    traceLines.push('    at toplevel (' + fileInfo + ':' + expr.pos.line + ')');
                }
                formatted = traceLines.join("\n");
                finalException = new haxiom.ScriptException(e, callStack.copy(), formatted);
            }
            
            if (errorHandler != null) {
                errorHandler(finalException);
                return null;
            }
            throw finalException;
        }
    }

    function eval(e:Expr, scope:Scope):Dynamic {
        var pos = e.pos;
        switch (e.def) {
            case EValue(v):
                return v;

            case EIdent(name):
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
                                Reflect.setField(obj, field, val);
                            }
                        }
                        return val;
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
                if (obj == null) throw 'Cannot read field "$field" of null';
                
                if (Std.isOfType(obj, String)) {
                    var str:String = cast obj;
                    if (field == "length") return str.length;
                    switch (field) {
                        case "split": return (delim:String) -> str.split(delim);
                        case "indexOf": return (sub:String, ?start:Int) -> str.indexOf(sub, start);
                        case "lastIndexOf": return (sub:String, ?start:Int) -> str.lastIndexOf(sub, start);
                        case "charAt": return (idx:Int) -> str.charAt(idx);
                        case "charCodeAt": return (idx:Int) -> str.charCodeAt(idx);
                        case "substring": return (start:Int, ?end:Int) -> str.substring(start, end);
                        case "toLowerCase": return () -> str.toLowerCase();
                        case "toUpperCase": return () -> str.toUpperCase();
                        default:
                    }
                }
                if (Std.isOfType(obj, Array)) {
                    var arr:Array<Dynamic> = cast obj;
                    if (field == "length") return arr.length;
                    switch (field) {
                        case "push": return (x:Dynamic) -> arr.push(x);
                        case "pop": return () -> arr.pop();
                        case "shift": return () -> arr.shift();
                        case "unshift": return (x:Dynamic) -> arr.unshift(x);
                        case "remove": return (x:Dynamic) -> arr.remove(x);
                        case "indexOf": return (x:Dynamic, ?start:Int) -> arr.indexOf(x, start);
                        case "join": return (sep:String) -> arr.join(sep);
                        case "slice": return (start:Int, ?end:Int) -> arr.slice(start, end);
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
                    throw 'Static method or field "$field" not found on class ${cls.name}';
                }

                // Native Haxe reflection
                var f = Reflect.field(obj, field);
                if (Reflect.isFunction(f)) return f;
                return f;

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
                switch (calleeExpr.def) {
                    case EField(objExpr, field):
                        switch (objExpr.def) {
                            case EIdent("super"):
                                // Skip super calls for bound-this optimization to prevent scope evaluation error
                            default:
                                var obj = eval(objExpr, scope);
                                if (obj != null && !Std.isOfType(obj, HaxiomInstance) && !Std.isOfType(obj, HaxiomClass)) {
                                    if (Std.isOfType(obj, String)) {
                                        var str:String = cast obj;
                                        var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                                        switch (field) {
                                            case "split": return str.split(args[0]);
                                            case "indexOf": return args.length > 1 ? str.indexOf(args[0], args[1]) : str.indexOf(args[0]);
                                            case "lastIndexOf": return args.length > 1 ? str.lastIndexOf(args[0], args[1]) : str.lastIndexOf(args[0]);
                                            case "charAt": return str.charAt(args[0]);
                                            case "charCodeAt": return str.charCodeAt(args[0]);
                                            case "substring": return args.length > 1 ? str.substring(args[0], args[1]) : str.substring(args[0]);
                                            case "toLowerCase": return str.toLowerCase();
                                            case "toUpperCase": return str.toUpperCase();
                                            default:
                                        }
                                    }
                                    if (Std.isOfType(obj, Array)) {
                                        var arr:Array<Dynamic> = cast obj;
                                        var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
                                        switch (field) {
                                            case "push": return arr.push(args[0]);
                                            case "pop": return arr.pop();
                                            case "shift": return arr.shift();
                                            case "unshift": arr.unshift(args[0]); return null;
                                            case "remove": return arr.remove(args[0]);
                                            case "indexOf": return args.length > 1 ? arr.indexOf(args[0], args[1]) : arr.indexOf(args[0]);
                                            case "join": return arr.join(args[0]);
                                            case "slice": return args.length > 1 ? arr.slice(args[0], args[1]) : arr.slice(args[0]);
                                            default:
                                        }
                                    }
                                    var method = Reflect.field(obj, field);
                                    if (method != null && Reflect.isFunction(method)) {
                                        var args = [for (a in argsExprs) eval(a, scope)];
                                        return Reflect.callMethod(obj, method, args);
                                    }
                                }
                        }
                    default:
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
                                throw 'Class ${cls.name} does not implement method ${itfMethod.name} required by interface ${itf.name} at ${pos.line}:${pos.col}';
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
                    }
                    
                    if (iterator != null && Reflect.field(iterator, "hasNext") != null && Reflect.field(iterator, "next") != null) {
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
                return lastVal;

            case ESwitch(expr, cases, defExpr):
                var val = eval(expr, scope);
                var matched = false;
                var result:Dynamic = null;
                for (c in cases) {
                    for (vExpr in c.values) {
                        var caseScope = new Scope(scope);
                        if (matchPattern(val, vExpr, scope, caseScope)) {
                            matched = true;
                            result = eval(c.expr, caseScope);
                            break;
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
                            return valInst.enumType == enumInst.enumType && valInst.constructor == enumInst.constructor;
                        }
                        return false;
                    }
                }
                outBindings.declare(name, val);
                return true;
                
            case ECall(calleeExpr, args):
                switch (calleeExpr.def) {
                    case EIdent(constructorName):
                        if (Std.isOfType(val, HaxiomEnumInstance)) {
                            var valInst:HaxiomEnumInstance = cast val;
                            if (valInst.constructor == constructorName) {
                                if (args.length == valInst.args.length) {
                                    for (i in 0...args.length) {
                                        if (!matchPattern(valInst.args[i], args[i], scope, outBindings)) {
                                            return false;
                                        }
                                    }
                                    return true;
                                }
                            }
                        }
                        return false;
                    default:
                        return false;
                }
                
            default:
                var patVal = eval(pattern, scope);
                if (Std.isOfType(val, HaxiomEnumInstance) && Std.isOfType(patVal, HaxiomEnumInstance)) {
                    var valInst:HaxiomEnumInstance = cast val;
                    var patInst:HaxiomEnumInstance = cast patVal;
                    if (valInst.enumType != patInst.enumType || valInst.constructor != patInst.constructor) {
                        return false;
                    }
                    if (valInst.args.length != patInst.args.length) return false;
                    for (i in 0...valInst.args.length) {
                        if (valInst.args[i] != patInst.args[i]) return false;
                    }
                    return true;
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
            default:
        }
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

    function registerFullyQualified(fullName:String, value:Dynamic, scope:Scope) {
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
            scope.declare(firstPart, current);
        }
        
        for (i in 1...parts.length - 1) {
            var part = parts[i];
            if (Reflect.hasField(current, part)) {
                current = Reflect.field(current, part);
            } else {
                var nextObj = {};
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
