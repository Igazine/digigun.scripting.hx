package wren;

import wren.AST;
import wren.WrenTypes;
import wren.Error;

class Interp {
    public var currentFiber:WrenFiber;
    public var fiberToSwitchTo:WrenFiber;
    public var globals:Map<String, Dynamic> = new Map();
    public var foreignMethods:Map<String, Array<Dynamic>->Dynamic> = new Map();
    public var moduleLoader:String->String;
    public var modules:Map<String, Map<String, Dynamic>> = new Map();

    var onDone:Dynamic->Void;
    var isRunning:Bool = false;

    public function new() {
    }

    public function execute(expr:Expr, onDone:Dynamic->Void):Void {
        this.onDone = onDone;
        var fiber = new WrenFiber(globals.get("Fiber"));
        fiber.state = Running;
        fiber.stack = [Frame.get(expr, new Map(), false, false, false, null, null, globals)];
        this.currentFiber = fiber;
        run();
    }

    public function run() {
        if (isRunning) return;
        isRunning = true;
        
        while (currentFiber != null) {
            if (fiberToSwitchTo != null) {
                currentFiber = fiberToSwitchTo;
                fiberToSwitchTo = null;
                continue;
            }
            if (currentFiber.stack.length == 0) break;
            
            try {
                tick();
            } catch (e:Dynamic) {
                if (e != null && Reflect.hasField(e, "__isWrenReturn")) {
                    var val = Reflect.field(e, "value");
                    while (currentFiber.stack.length > 0) {
                        var f = currentFiber.stack.pop();
                        var isFunc = f.isFunction;
                        var isConstruct = f.isConstruct;
                        f.release();
                        if (isFunc) {
                            if (isConstruct) val = f.locals.get("this");
                            if (currentFiber.stack.length > 0) {
                                currentFiber.stack[currentFiber.stack.length - 1].results.push(val);
                            } else {
                                currentFiber.state = Done;
                                if (currentFiber.caller != null) {
                                    fiberToSwitchTo = currentFiber.caller;
                                    if (fiberToSwitchTo.stack.length > 0) {
                                        fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].results.push(val);
                                    }
                                } else if (onDone != null) {
                                    onDone(val);
                                }
                            }
                            break;
                        }
                    }
                    continue;
                } else {
                    isRunning = false;
                    if (Std.isOfType(e, String)) {
                        throwError(cast e);
                    } else {
                        throw e;
                    }
                }
            }
        }
        isRunning = false;
    }

    function tick() {
        var frame = currentFiber.stack[currentFiber.stack.length - 1];
        var e = frame.expr;
        switch (e.def) {
            case EValue(v):
                popAndReturn(v);
            
            case EIdent(v):
                if (frame.step == 0) {
                    if (frame.locals.exists(v)) {
                        popAndReturn(frame.locals.get(v));
                    } else if (frame.globals.exists(v)) {
                        popAndReturn(frame.globals.get(v));
                    } else if (frame.locals.exists("this")) {
                        var obj = frame.locals.get("this");
                        frame.step = 1;
                        callMethod(obj, v, [], frame);
                    } else {
                        throwError('Identifier not found: $v');
                    }
                } else {
                    popAndReturn(frame.results.pop());
                }

            case EReturn(expr):
                if (expr != null && frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(expr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var val = expr != null ? frame.results.pop() : null;
                    throw { __isWrenReturn: true, value: val };
                }

            case EBlock(exprs, isScope):
                if (frame.step < exprs.length) {
                    var idx = frame.step;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(exprs[idx], frame.locals, isScope ? true : frame.isBlock, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    popAndReturn(frame.results.length > 0 ? frame.results.pop() : null);
                }

            case EThis:
                var t = frame.locals.get("this");
                popAndReturn(t);

            case EGet(objExpr, field):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var obj = frame.results.pop();
                    if (Std.isOfType(obj, WrenInstance)) {
                        var instance:WrenInstance = cast obj;
                        popAndReturn(instance.fields.get(field));
                    } else {
                        popAndReturn(Reflect.field(obj, field));
                    }
                }

            case ESet(objExpr, field, valExpr):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    frame.step = 2;
                    currentFiber.stack.push(Frame.get(valExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var val = frame.results.pop();
                    var obj = frame.results.pop();
                    if (Std.isOfType(obj, WrenInstance)) {
                        var instance:WrenInstance = cast obj;
                        instance.fields.set(field, val);
                        popAndReturn(val);
                    } else {
                        Reflect.setField(obj, field, val);
                        popAndReturn(val);
                    }
                }

            case EAssign(target, expr):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(expr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var val = frame.results[0];
                    switch (target.def) {
                        case EIdent(name):
                            assign(name, val, frame.locals, frame.globals);
                            popAndReturn(val);
                        case EGet(objExpr, field):
                            frame.step = 2;
                            currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                        default: throw "Invalid assignment target";
                    }
                } else if (frame.step == 2) {
                    var obj = frame.results.pop();
                    var val = frame.results.pop();
                    switch (target.def) {
                        case EGet(_, field):
                            if (Std.isOfType(obj, WrenInstance)) {
                                cast(obj, WrenInstance).fields.set(field, val);
                            } else {
                                Reflect.setField(obj, field, val);
                            }
                            popAndReturn(val);
                        default: throw "Internal error";
                    }
                }

            case EVar(name, expr, isStatic):
                if (expr != null && frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(expr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var val = expr != null ? frame.results.pop() : null;
                    if (!frame.isBlock && !frame.isFunction) {
                        frame.globals.set(name, val);
                    } else {
                        frame.locals.set(name, val);
                    }
                    popAndReturn(val);
                }

            case EBinop(op, e1, e2):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    frame.step = 2;
                    currentFiber.stack.push(Frame.get(e2, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 2) {
                    var v2 = frame.results.pop();
                    var v1 = frame.results.pop();
                    var res:Dynamic = switch (op) {
                        case "+": 
                            if (Std.isOfType(v1, String) || Std.isOfType(v2, String)) Std.string(v1) + Std.string(v2);
                            else (cast v1 : Float) + (cast v2 : Float);
                        case "-": (cast v1 : Float) - (cast v2 : Float);
                        case "*": (cast v1 : Float) * (cast v2 : Float);
                        case "/": (cast v1 : Float) / (cast v2 : Float);
                        case "==": v1 == v2;
                        case "!=": v1 != v2;
                        case "<": (cast v1 : Float) < (cast v2 : Float);
                        case ">": (cast v1 : Float) > (cast v2 : Float);
                        case "<=": (cast v1 : Float) <= (cast v2 : Float);
                        case ">=": (cast v1 : Float) >= (cast v2 : Float);
                        case "%": (cast v1 : Float) % (cast v2 : Float);
                        case "is": 
                            if (Std.isOfType(v1, WrenInstance)) {
                                var inst:WrenInstance = cast v1;
                                isSubclass(inst.cls, cast v2);
                            } else {
                                false;
                            }
                        case "..":
                            var rangeCls = frame.globals.get("Range");
                            frame.step = 3;
                            callMethod(rangeCls, "new", [v1, v2, true], frame);
                            null;
                        case "...":
                            var rangeCls = frame.globals.get("Range");
                            frame.step = 3;
                            callMethod(rangeCls, "new", [v1, v2, false], frame);
                            null;
                        case "&": (cast v1 : Int) & (cast v2 : Int);
                        case "|": (cast v1 : Int) | (cast v2 : Int);
                        case "^": (cast v1 : Int) ^ (cast v2 : Int);
                        case "<<": (cast v1 : Int) << (cast v2 : Int);
                        case ">>": (cast v1 : Int) >> (cast v2 : Int);
                        default: throwError('Unknown operator $op');
                    }
                    popAndReturn(res);
                } else {
                    popAndReturn(frame.results.pop());
                }

            case ECall(objExpr, method, args):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step <= args.length) {
                    var argIdx = frame.step - 1;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(args[argIdx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == args.length + 1) {
                    var evalArgs = [];
                    for (i in 0...args.length) evalArgs.unshift(frame.results.pop());
                    var obj = frame.results.pop();
                    frame.step = 999;
                    callMethod(obj, method, evalArgs, frame);
                } else {
                    popAndReturn(frame.results.pop());
                }

            case EClass(name, fields, methods, parent, isForeign):
                var pCls = parent != null ? frame.globals.get(parent) : null;
                var mMap = new Map<String, WrenMethod>();
                var hasConstruct = false;
                for (m in methods) {
                    mMap.set(m.name, { args: m.args, body: m.body, isStatic: m.isStatic, isConstruct: m.isConstruct, isForeign: m.isForeign });
                    if (m.isConstruct) hasConstruct = true;
                }
                if (!hasConstruct) {
                    mMap.set("new", { args: [], body: { def: EBlock([], true), pos: {line:0, col:0} }, isStatic: false, isConstruct: true, isForeign: false });
                }
                var cls = new WrenClass(name, [for (f in fields) f.name], mMap, pCls, isForeign, frame.globals);
                frame.globals.set(name, cls);
                popAndReturn(cls);

            case ESuper(method, args):
                if (frame.step < args.length) {
                    var argIdx = frame.step;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(args[argIdx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == args.length) {
                    var evalArgs = [];
                    for (i in 0...args.length) evalArgs.unshift(frame.results.pop());
                    var obj = resolve("this", frame.locals, frame.globals);
                    if (frame.methodClass == null || frame.methodClass.parent == null) {
                        throwError("Cannot call super from this context");
                    }
                    var parentCls = frame.methodClass.parent;
                    var m = findMethod(parentCls, method);
                    if (m != null) {
                        frame.step = 999;
                        if (m.isForeign) {
                             var sig = '${method}(${args.length})';
                             var key = '${parentCls.name}.${(m.isStatic || m.isConstruct) ? "static " : ""}${sig}';
                             var impl = foreignMethods.get(key);
                             if (impl != null) {
                                 var fullArgs:Array<Dynamic> = [obj];
                                 for (a in evalArgs) fullArgs.push(a);
                                 var res = impl(fullArgs);
                                 if (m.isConstruct && Std.isOfType(obj, WrenInstance)) {
                                     cast(obj, WrenInstance).native = res;
                                 }
                                 if (fiberToSwitchTo == null) popAndReturn(res);
                             } else {
                                 throwError('Foreign super method $key not found');
                             }
                        } else {
                            var newLocals = new Map<String, Dynamic>();
                            newLocals.set("this", obj);
                            for (i in 0...m.args.length) newLocals.set(m.args[i], evalArgs[i]);
                            currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, m.isConstruct, '${parentCls.name}.${method}', parentCls, parentCls.globals));
                        }
                    } else {
                        throwError('Super method $method not found in ${parentCls.name}');
                    }
                } else {
                    popAndReturn(frame.results.pop());
                }

            case EArrayDecl(values):
                if (frame.step < values.length) {
                    var idx = frame.step;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(values[idx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var res = [];
                    for (i in 0...values.length) res.unshift(frame.results.pop());
                    popAndReturn(res);
                }

            case EMapDecl(keys, values):
                if (frame.step < keys.length * 2) {
                    var idx = Std.int(frame.step / 2);
                    var isVal = frame.step % 2 == 1;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(isVal ? values[idx] : keys[idx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var res = new Map<Dynamic, Dynamic>();
                    for (i in 0...keys.length) {
                        var v = frame.results.pop();
                        var k = frame.results.pop();
                        res.set(k, v);
                    }
                    popAndReturn(res);
                }

            case EIf(cond, e1, e2):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(cond, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var v = frame.results.pop();
                    frame.step = 2;
                    if (v == true) currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    else if (e2 != null) currentFiber.stack.push(Frame.get(e2, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    else popAndReturn(null);
                } else {
                    popAndReturn(frame.results.pop());
                }

            case EWhile(cond, body):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(cond, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var v = frame.results.pop();
                    if (v != false && v != null) {
                        frame.step = 2;
                        currentFiber.stack.push(Frame.get(body, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    } else {
                        popAndReturn(null);
                    }
                } else {
                    frame.step = 0;
                }

            case EUnop(op, e):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(e, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var v = frame.results.pop();
                    var res:Dynamic = switch (op) {
                        case "!": !v;
                        case "-": -v;
                        case "~": ~(cast v : Int);
                        default: throwError('Unknown unary operator $op');
                    }
                    popAndReturn(res);
                }

            case EInterpolation(exprs):
                if (frame.step < exprs.length) {
                    var idx = frame.step;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(exprs[idx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else {
                    var parts = [];
                    for (i in 0...exprs.length) parts.unshift(frame.results.pop());
                    var res = "";
                    for (p in parts) res += Std.string(p);
                    popAndReturn(res);
                }

            case EClosure(args, body):
                var captured = new Map<String, Dynamic>();
                for (k in frame.locals.keys()) captured.set(k, frame.locals.get(k));
                popAndReturn(new WrenFn(args, body, captured, frame.globals));

            case EFor(v, it, e): throw "Not implemented";

            case EImport(mod, imports):
                if (frame.step == 0) {
                    if (modules.exists(mod)) {
                        frame.step = 2;
                    } else if (moduleLoader != null) {
                        var src = moduleLoader(mod);
                        if (src != null) {
                            var lexer = new Lexer(src);
                            var parser = new Parser(lexer.tokenize());
                            var ast = parser.parse();
                            frame.step = 1;
                            var newGlobals = new Map<String, Dynamic>();
                            for (k in globals.keys()) newGlobals.set(k, globals.get(k));
                            modules.set(mod, newGlobals);
                            currentFiber.stack.push(Frame.get(ast, new Map(), false, false, false, null, null, newGlobals));
                        } else {
                            throwError('Module $mod not found');
                        }
                    } else {
                        throwError('No module loader configured');
                    }
                } else {
                    var modGlobals = modules.get(mod);
                    for (imp in imports) {
                        if (modGlobals.exists(imp.name)) {
                            frame.globals.set(imp.alias, modGlobals.get(imp.name));
                        } else {
                            throwError('Variable ${imp.name} not found in module $mod');
                        }
                    }
                    popAndReturn(null);
                }
        }
    }

    function popAndReturn(val:Dynamic) {
        if (currentFiber.stack.length == 0) return;
        var f = currentFiber.stack.pop();
        if (f.isConstruct) val = f.locals.get("this");
        
        if (currentFiber.stack.length > 0) {
            currentFiber.stack[currentFiber.stack.length - 1].results.push(val);
        } else {
            currentFiber.state = Done;
            if (currentFiber.caller != null) {
                fiberToSwitchTo = currentFiber.caller;
                if (fiberToSwitchTo.stack.length > 0) {
                    fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].results.push(val);
                }
            } else {
                if (onDone != null) onDone(val);
            }
        }
        f.release();
    }

    function throwError(msg:String, ?pos:Pos):Dynamic {
        if (pos == null && currentFiber.stack.length > 0) pos = currentFiber.stack[currentFiber.stack.length - 1].expr.pos;
        if (pos == null) pos = { line: 0, col: 0 };
        var error = new WrenError(msg, pos.line, pos.col, pos.file, getStackTrace());
        throw error;
        return null;
    }

    function getStackTrace():Array<String> {
        var res = [];
        var i = currentFiber.stack.length - 1;
        while (i >= 0) {
            var f = currentFiber.stack[i];
            if (f.isFunction || f.isBlock) {
                var name = f.methodName != null ? f.methodName : (f.isBlock ? "block" : "anonymous");
                res.push('at $name (line ${f.expr.pos.line})');
            }
            i--;
        }
        return res;
    }

    function resolve(name:String, locals:Map<String, Dynamic>, globals:Map<String, Dynamic>):Dynamic {
        if (locals.exists(name)) return locals.get(name);
        if (globals.exists(name)) return globals.get(name);
        throwError('Identifier not found: $name');
        return null;
    }

    function assign(name:String, val:Dynamic, locals:Map<String, Dynamic>, globals:Map<String, Dynamic>) {
        if (locals.exists(name)) {
            locals.set(name, val);
        } else if (globals.exists(name)) {
            globals.set(name, val);
        } else {
            locals.set(name, val); 
        }
    }

    function callMethod(obj:Dynamic, methodName:String, args:Array<Dynamic>, frame:Frame) {
        if (obj == null) {
            var cls = frame.globals.get("Null");
            var m = findMethod(cls, methodName);
            if (m == null) throwError('Method $methodName not found on null');
            return;
        }

        if (Std.isOfType(obj, WrenClass)) {
            var cls:WrenClass = cast obj;
            var m:WrenMethod = cls.methods.get(methodName);
            if (m != null && (m.isStatic || m.isConstruct)) {
                if (m.isForeign) {
                    var sig = '${methodName}(${m.args.length})';
                    var key = '${cls.name}.static ${sig}';
                    var impl = foreignMethods.get(key);
                    if (impl != null) {
                        if (m.isConstruct) {
                            var instance = new WrenInstance(cls);
                            var fullArgs:Array<Dynamic> = [instance];
                            for (a in args) fullArgs.push(a);
                            var res:Dynamic = impl(fullArgs);
                            if (Std.isOfType(res, WrenInstance)) instance = cast res;
                            else instance.native = res;
                            if (fiberToSwitchTo == null) popAndReturn(instance);
                        } else {
                            var fullArgs:Array<Dynamic> = [cls];
                            for (a in args) fullArgs.push(a);
                            var res = impl(fullArgs);
                            if (fiberToSwitchTo == null) popAndReturn(res);
                        }
                    } else {
                        throwError('Foreign method $key not found');
                    }
                    return;
                }
                
                if (m.isConstruct) {
                    var instance = new WrenInstance(cls);
                    var newLocals = new Map<String, Dynamic>();
                    newLocals.set("this", instance);
                    for (i in 0...m.args.length) newLocals.set(m.args[i], args[i]);
                    frame.results.push(instance); 
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, true, '${cls.name}.new', cls, cls.globals));
                } else {
                    var newLocals = new Map<String, Dynamic>();
                    newLocals.set("this", cls);
                    for (i in 0...m.args.length) newLocals.set(m.args[i], args[i]);
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, false, '${cls.name}.${methodName}', cls, cls.globals));
                }
            } else {
                var classCls = frame.globals.get("Class");
                if (classCls != null && classCls != cls) {
                    var m2 = findMethod(classCls, methodName);
                    if (m2 != null && m2.isForeign) {
                        var sig = '${methodName}(${args.length})';
                        var key = 'Class.${m2.isStatic ? "static " : ""}${sig}';
                        var impl = foreignMethods.get(key);
                        if (impl != null) {
                            var fullArgs:Array<Dynamic> = [obj];
                            for (a in args) fullArgs.push(a);
                            var res = impl(fullArgs);
                            if (fiberToSwitchTo == null) popAndReturn(res);
                            return;
                        }
                    }
                }
                throwError('Method $methodName not found on class ${cls.name}');
            }
        } else {
            var cls = getClass(obj);
            if (cls != null) {
                var foundCls = cls;
                var m = findMethod(cls, methodName);
                if (m == null && cls.name != "Object") {
                    var objCls = frame.globals.get("Object");
                    if (objCls != null) {
                        m = findMethod(objCls, methodName);
                        if (m != null) foundCls = objCls;
                    }
                }
                
                if (m != null) {
                    var search = cls;
                    while (search != null) {
                        if (search.methods.exists(methodName)) {
                            foundCls = search;
                            break;
                        }
                        search = search.parent;
                    }

                    if (m.isForeign) {
                        var sig = '${methodName}(${args.length})';
                        var key = '${foundCls.name}.${m.isStatic ? "static " : ""}${sig}';
                        var impl = foreignMethods.get(key);
                        if (impl != null) {
                            var fullArgs:Array<Dynamic> = [obj];
                            for (a in args) fullArgs.push(a);
                            var res = impl(fullArgs);
                            if (fiberToSwitchTo == null) popAndReturn(res);
                        } else {
                            throwError('Foreign method $key not found');
                        }
                        return;
                    }
                    
                    var newLocals = new Map<String, Dynamic>();
                    newLocals.set("this", obj);
                    for (i in 0...m.args.length) newLocals.set(m.args[i], args[i]);
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, false, '${foundCls.name}.${methodName}', foundCls, foundCls.globals));
                    return;
                }
            }

            if (Std.isOfType(obj, WrenFn)) {
                var fn:WrenFn = cast obj;
                if (methodName == "call") {
                    var newLocals = new Map<String, Dynamic>();
                    for (k in fn.closure.keys()) newLocals.set(k, fn.closure.get(k));
                    for (i in 0...fn.args.length) {
                        if (i < args.length) newLocals.set(fn.args[i], args[i]);
                    }
                    currentFiber.stack.push(Frame.get(fn.body, newLocals, false, true, false, "call", null, fn.globals));
                    return;
                }
            }
            
            if (Std.isOfType(obj, Array)) {
                var arr:Array<Dynamic> = cast obj;
                switch (methodName) {
                    case "iterate":
                        var iter = args[0];
                        if (iter == null) {
                            if (arr.length == 0) popAndReturn(null);
                            else popAndReturn(0);
                        } else {
                            var i:Int = cast iter;
                            if (i < 0 || i >= arr.length - 1) popAndReturn(null);
                            else popAndReturn(i + 1);
                        }
                        return;
                    case "iteratorValue":
                        var i:Int = cast args[0];
                        popAndReturn(arr[i]);
                        return;
                    case "add":
                        arr.push(args[0]);
                        popAndReturn(args[0]);
                        return;
                    case "count":
                        popAndReturn(arr.length);
                        return;
                    case "[]":
                        var i:Int = cast args[0];
                        popAndReturn(arr[i]);
                        return;
                    case "[]=":
                        var i:Int = cast args[0];
                        arr[i] = args[1];
                        popAndReturn(args[1]);
                        return;
                }
            } else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
                var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
                switch (methodName) {
                    case "[]":
                        popAndReturn(map.get(args[0]));
                        return;
                    case "[]=":
                        map.set(args[0], args[1]);
                        popAndReturn(args[1]);
                        return;
                    case "iterate":
                        var ks = [for (k in map.keys()) k];
                        var iter = args[0];
                        if (iter == null) {
                            if (ks.length == 0) popAndReturn(null);
                            else popAndReturn(0);
                        } else {
                            var i:Int = cast iter;
                            if (i < 0 || i >= ks.length - 1) popAndReturn(null);
                            else popAndReturn(i + 1);
                        }
                        return;
                    case "iteratorValue":
                        var ks = [for (k in map.keys()) k];
                        var i:Int = cast args[0];
                        popAndReturn(ks[i]);
                        return;
                    case "count":
                        var c = 0;
                        for (k in map.keys()) c++;
                        popAndReturn(c);
                        return;
                    case "containsKey":
                        popAndReturn(map.exists(args[0]));
                        return;
                    case "remove":
                        popAndReturn(map.remove(args[0]));
                        return;
                }
            }

            var field = Reflect.field(obj, methodName);
            if (Reflect.isFunction(field)) {
                popAndReturn(Reflect.callMethod(obj, field, args));
            } else {
                popAndReturn(field);
            }
        }
    }

    public function getClass(obj:Dynamic, ?globals:Map<String, Dynamic>):WrenClass {
        if (globals == null) globals = this.globals;
        if (obj == null) return globals.get("Null");
        if (Std.isOfType(obj, WrenInstance)) return (cast obj).cls;
        if (Std.isOfType(obj, WrenClass)) return globals.get("Class");
        if (Std.isOfType(obj, Float) || Std.isOfType(obj, Int)) return globals.get("Num");
        if (Std.isOfType(obj, String)) return globals.get("String");
        if (Std.isOfType(obj, Bool)) return globals.get("Bool");
        if (Std.isOfType(obj, WrenFn)) return globals.get("Fn");
        if (Std.isOfType(obj, Array)) return globals.get("List");
        if (Std.isOfType(obj, haxe.Constraints.IMap)) return globals.get("Map");
        return null;
    }

    function isSubclass(cls:WrenClass, target:WrenClass):Bool {
        if (cls == target) return true;
        if (cls.parent != null) return isSubclass(cls.parent, target);
        return false;
    }

    function findMethod(cls:WrenClass, name:String):WrenMethod {
        if (cls == null || cls.methods == null) return null;
        if (cls.methods.exists(name)) return cls.methods.get(name);
        if (cls.parent != null) return findMethod(cls.parent, name);
        return null;
    }
}
