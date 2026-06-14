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
                if (currentFiber.stack.length > 0) {
                    currentFiber.stack[currentFiber.stack.length - 1].waiting = false;
                }
                fiberToSwitchTo = null;
                continue;
            }
            if (currentFiber.stack.length == 0) break;
            
            var frame = currentFiber.stack[currentFiber.stack.length - 1];
            if (frame.waiting) {
                if (fiberToSwitchTo == null) throw "Deadlock: Fiber waiting but no switch pending";
                continue;
            }

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
                                currentFiber.stack[currentFiber.stack.length - 1].waiting = false;
                            } else {
                                currentFiber.state = Done;
                                if (currentFiber.caller != null) {
                                    fiberToSwitchTo = currentFiber.caller;
                                    if (fiberToSwitchTo.stack.length > 0) {
                                        var result = val;
                                        fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].results.push(result);
                                        fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].waiting = false;
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
                    var fiber = currentFiber;
                    if (fiber.isTry && fiber.caller != null) {
                        fiber.state = Aborted;
                        fiber.error = e;
                        fiberToSwitchTo = fiber.caller;
                        if (fiberToSwitchTo.stack.length > 0) {
                            fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].results.push(Std.string(e));
                            fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].waiting = false;
                        }
                        isRunning = true;
                        continue;
                    }
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

            case ELogicalAnd(e1, e2):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var v1:Dynamic = frame.results[frame.results.length - 1];
                    if (v1 == false || v1 == null) {
                        popAndReturn(frame.results.pop());
                    } else {
                        frame.step = 2;
                        currentFiber.stack.push(Frame.get(e2, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    }
                } else {
                    var v2 = frame.results.pop();
                    frame.results.pop(); // discard v1
                    popAndReturn(v2);
                }

            case ELogicalOr(e1, e2):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var v1:Dynamic = frame.results[frame.results.length - 1];
                    if (v1 != false && v1 != null) {
                        popAndReturn(frame.results.pop());
                    } else {
                        frame.step = 2;
                        currentFiber.stack.push(Frame.get(e2, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    }
                } else {
                    var v2 = frame.results.pop();
                    frame.results.pop(); // discard v1
                    popAndReturn(v2);
                }

            case ETernary(cond, e1, e2):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(cond, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    var v:Dynamic = frame.results.pop();
                    frame.step = 2;
                    if (v != false && v != null) {
                        currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    } else {
                        currentFiber.stack.push(Frame.get(e2, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    }
                } else {
                    popAndReturn(frame.results.pop());
                }

            case EBreak:
                while (currentFiber.stack.length > 0) {
                    var top = currentFiber.stack[currentFiber.stack.length - 1];
                    switch (top.expr.def) {
                        case EWhile(_, _) | EFor(_, _, _):
                            popAndReturn(null);
                            return;
                        default:
                            var popped = currentFiber.stack.pop();
                            popped.release();
                    }
                }
                throwError("Break outside loop");

            case EContinue:
                while (currentFiber.stack.length > 0) {
                    var top = currentFiber.stack[currentFiber.stack.length - 1];
                    switch (top.expr.def) {
                        case EWhile(_, _):
                            top.step = 0;
                            return;
                        case EFor(_, _, _):
                            top.results.push(null);
                            top.step = 4;
                            return;
                        default:
                            var popped = currentFiber.stack.pop();
                            popped.release();
                    }
                }
                throwError("Continue outside loop");
            
            case EIdent(v):
                if (frame.step == 0) {
                    if (v.charAt(0) == "_" && frame.locals.exists("this")) {
                        var obj = frame.locals.get("this");
                        if (Std.isOfType(obj, WrenInstance)) {
                            var inst:WrenInstance = cast obj;
                            popAndReturn(inst.fields.get(v));
                            return;
                        }
                    }
                    if (frame.locals.exists(v)) {
                        popAndReturn(frame.locals.get(v));
                    } else if (frame.globals.exists(v)) {
                        popAndReturn(frame.globals.get(v));
                    } else if (frame.locals.exists("this")) {
                        var obj = frame.locals.get("this");
                        frame.step = 1;
                        callMethod(obj, v, null, frame);
                    } else {
                        throwError('Identifier not found: $v');
                    }
                } else {
                    if (frame.results.length == 0) return;
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
                if (field.charAt(0) == "_" && field.charAt(1) == "_") {
                    if (frame.methodClass != null) {
                        popAndReturn(frame.methodClass.classFields.get(field));
                    } else {
                        throwError('Cannot access class variable $field outside class');
                    }
                } else if (frame.step == 0) {
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
                            if (field.charAt(0) == "_" && field.charAt(1) == "_") {
                                if (frame.methodClass != null) {
                                    frame.methodClass.classFields.set(field, val);
                                    frame.results.pop(); // discard val from results
                                    popAndReturn(val);
                                } else {
                                    throwError('Cannot assign class variable $field outside class');
                                }
                            } else {
                                frame.step = 2;
                                currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                            }
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
                            var v1Cls = getClass(v1);
                            if (v1Cls != null) {
                                isSubclass(v1Cls, cast v2);
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
                    if (frame.step == 2) popAndReturn(res);
                } else {
                    if (frame.results.length == 0) return;
                    popAndReturn(frame.results.pop());
                }

            case ECall(objExpr, method, args):
                var argsList = args != null ? args : [];
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(objExpr, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step <= argsList.length) {
                    var argIdx = frame.step - 1;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(argsList[argIdx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == argsList.length + 1) {
                    var evalArgs = [];
                    for (i in 0...argsList.length) evalArgs.unshift(frame.results.pop());
                    var obj = frame.results.pop();
                    frame.step = 999;
                    callMethod(obj, method, args != null ? evalArgs : null, frame);
                } else {
                    if (frame.results.length == 0) return;
                    popAndReturn(frame.results.pop());
                }

            case EClass(name, fields, methods, parent, isForeign):
                var pCls = parent != null ? frame.globals.get(parent) : null;
                var mMap = new Map<String, WrenMethod>();
                var hasConstruct = false;
                for (m in methods) {
                    var mName = m.name;
                    if (m.args != null) {
                        mName += "(";
                        for (i in 0...m.args.length) {
                            mName += "_";
                            if (i < m.args.length - 1) mName += ",";
                        }
                        mName += ")";
                    }
                    mMap.set(mName, { args: m.args, body: m.body, isStatic: m.isStatic, isConstruct: m.isConstruct, isForeign: m.isForeign });
                    if (m.isConstruct) hasConstruct = true;
                }
                if (!hasConstruct && pCls == null) {
                    mMap.set("new()", { args: [], body: { def: EBlock([], true), pos: {line:0, col:0} }, isStatic: false, isConstruct: true, isForeign: false });
                }
                var cls = new WrenClass(name, [for (f in fields) f.name], mMap, pCls, isForeign, frame.globals);
                frame.globals.set(name, cls);
                popAndReturn(cls);

            case ESuper(method, args):
                var argsList = args != null ? args : [];
                if (frame.step < argsList.length) {
                    var argIdx = frame.step;
                    frame.step++;
                    currentFiber.stack.push(Frame.get(argsList[argIdx], frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == argsList.length) {
                    var evalArgs = [];
                    for (i in 0...argsList.length) evalArgs.unshift(frame.results.pop());
                    var obj = resolve("this", frame.locals, frame.globals);
                    if (frame.methodClass == null || frame.methodClass.parent == null) {
                        throwError("Cannot call super from this context");
                    }
                    var parentCls = frame.methodClass.parent;
                    
                    var mangledName = method;
                    if (args != null) {
                        mangledName += "(";
                        for (i in 0...args.length) {
                            mangledName += "_";
                            if (i < args.length - 1) mangledName += ",";
                        }
                        mangledName += ")";
                    }
                    
                    var m = findMethod(parentCls, mangledName);
                    if (m != null) {
                        frame.step = 999;
                        if (m.isForeign) {
                             var sig = '${method}(${argsList.length})';
                             var key = '${parentCls.name}.${(m.isStatic || m.isConstruct) ? "static " : ""}${sig}';
                             var impl = foreignMethods.get(key);
                             if (impl != null) {
                                 var fullArgs:Array<Dynamic> = [obj];
                                 for (a in evalArgs) fullArgs.push(a);
                                 var res = impl(fullArgs);
                                 if (m.isConstruct && Std.isOfType(obj, WrenInstance)) {
                                     cast(obj, WrenInstance).native = res;
                                 }
                                 if (fiberToSwitchTo == null && currentFiber != null && currentFiber.state == Running) popAndReturn(res);
                             } else {
                                 throwError('Foreign super method $key not found');
                             }
                        } else {
                            var newLocals = new Map<String, Dynamic>();
                            newLocals.set("this", obj);
                            var mArgsList = m.args != null ? m.args : [];
                            for (i in 0...mArgsList.length) newLocals.set(mArgsList[i], evalArgs[i]);
                            currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, m.isConstruct, '${parentCls.name}.${mangledName}', parentCls, parentCls.globals));
                        }
                    } else {
                        throwError('Super method $mangledName not found in ${parentCls.name}');
                    }
                } else {
                    if (frame.results.length == 0) return;
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
                    var v:Dynamic = frame.results.pop();
                    frame.step = 2;
                    if (v != false && v != null) currentFiber.stack.push(Frame.get(e1, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
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
                    var v:Dynamic = frame.results.pop();
                    if (v != false && v != null) {
                        frame.step = 2;
                        currentFiber.stack.push(Frame.get(body, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                    } else {
                        popAndReturn(null);
                    }
                } else {
                    if (frame.results.length > 0) frame.results.pop();
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
                var closure = new Map<String, Dynamic>();
                for (k in frame.locals.keys()) closure.set(k, frame.locals.get(k));
                popAndReturn(new WrenFn(args, body, closure, frame.globals));

            case EFor(v, it, e):
                if (frame.step == 0) {
                    frame.step = 1;
                    currentFiber.stack.push(Frame.get(it, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 1) {
                    if (frame.results.length < 1) return;
                    var iterable = frame.results[0];
                    frame.step = 2;
                    callMethod(iterable, "iterate", [null], frame);
                } else if (frame.step == 2) {
                    if (frame.results.length < 2) return;
                    var iterable = frame.results[0];
                    var iterator:Dynamic = frame.results[1];
                    if (iterator == null || iterator == false) {
                        popAndReturn(null);
                    } else {
                        frame.step = 3;
                        callMethod(iterable, "iteratorValue", [iterator], frame);
                    }
                } else if (frame.step == 3) {
                    if (frame.results.length < 3) return;
                    var val = frame.results.pop();
                    frame.locals.set(v, val);
                    frame.step = 4;
                    currentFiber.stack.push(Frame.get(e, frame.locals, false, false, false, frame.methodName, frame.methodClass, frame.globals));
                } else if (frame.step == 4) {
                    if (frame.results.length < 3) return;
                    frame.results.pop(); // discard body result
                    var iterable = frame.results[0];
                    var iterator = frame.results[1];
                    frame.step = 5;
                    callMethod(iterable, "iterate", [iterator], frame);
                } else if (frame.step == 5) {
                    if (frame.results.length < 3) return;
                    var nextIterator = frame.results.pop();
                    frame.results[1] = nextIterator;
                    frame.step = 2;
                }

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
            currentFiber.stack[currentFiber.stack.length - 1].waiting = false;
        } else {
            currentFiber.state = Done;
            if (currentFiber.caller != null) {
                fiberToSwitchTo = currentFiber.caller;
                if (fiberToSwitchTo.stack.length > 0) {
                    var result = val;
                    fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].results.push(result);
                    fiberToSwitchTo.stack[fiberToSwitchTo.stack.length - 1].waiting = false;
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
        var error = new WrenError('Runtime Error: $msg', pos.line, pos.col, pos.file, getStackTrace());
        throw error;
        return null;
    }

    function getStackTrace():Array<String> {
        var res = [];
        var i = currentFiber.stack.length - 1;
        while (i >= 0) {
            var f = currentFiber.stack[i];
            if (f.isFunction || f.isBlock || i == 0) {
                var name = f.methodName != null ? f.methodName : (f.isBlock ? "block" : (f.isFunction ? "anonymous" : "script"));
                var pos = f.expr.pos;
                var fileDetail = pos.file != null ? ' in ${pos.file}' : "";
                res.push('[line ${pos.line}, col ${pos.col}${fileDetail}] in $name');
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
        if (name.charAt(0) == "_" && locals.exists("this")) {
            var obj = locals.get("this");
            if (Std.isOfType(obj, WrenInstance)) {
                (cast obj : WrenInstance).fields.set(name, val);
                return;
            }
        }
        if (locals.exists(name)) {
            locals.set(name, val);
        } else if (globals.exists(name)) {
            globals.set(name, val);
        } else {
            locals.set(name, val); 
        }
    }

    function callMethod(obj:Dynamic, name:String, args:Array<Dynamic>, frame:Frame) {
        var argsList = args != null ? args : [];
        var methodName = name;
        if (args != null) {
            methodName += "(";
            for (i in 0...args.length) {
                methodName += "_";
                if (i < args.length - 1) methodName += ",";
            }
            methodName += ")";
        }
        var dispName = methodName.indexOf("(") != -1 ? methodName : methodName + "()";

        if (obj == null) {
            var cls = frame.globals.get("Null");
            var m = findMethod(cls, methodName);
            if (m == null) throwError('Method $dispName not found on null.');
            return;
        }

        if (Std.isOfType(obj, WrenClass)) {
            var cls:WrenClass = cast obj;
            var m:WrenMethod = cls.methods.get(methodName);
            var definingCls = cls;
            if (m == null) {
                var parent = cls.parent;
                while (parent != null) {
                    var pm = parent.methods.get(methodName);
                    if (pm != null && pm.isConstruct) {
                        m = pm;
                        definingCls = parent;
                        break;
                    }
                    parent = parent.parent;
                }
            }
            if (m != null && (m.isStatic || m.isConstruct)) {
                if (m.isForeign) {
                    var arity = m.args != null ? m.args.length : 0;
                    var sig = '${name}(${arity})';
                    var key = '${definingCls.name}.static ${sig}';
                    var impl = foreignMethods.get(key);
                    if (impl != null) {
                        if (m.isConstruct) {
                            var instance = new WrenInstance(cls);
                            var fullArgs:Array<Dynamic> = [instance];
                            for (a in argsList) fullArgs.push(a);
                            var res:Dynamic = impl(fullArgs);
                            if (Std.isOfType(res, WrenInstance)) instance = cast res;
                            else instance.native = res;
                            if (fiberToSwitchTo == null && currentFiber != null && currentFiber.state == Running) frame.results.push(instance);
                        } else {
                            var fullArgs:Array<Dynamic> = [cls];
                            for (a in argsList) fullArgs.push(a);
                            var res = impl(fullArgs);
                            if (fiberToSwitchTo == null && currentFiber != null && currentFiber.state == Running) frame.results.push(res);
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
                    var mArgs = m.args != null ? m.args : [];
                    for (i in 0...mArgs.length) newLocals.set(mArgs[i], argsList[i]);
                    frame.results.push(instance); 
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, true, '${definingCls.name}.new', definingCls, cls.globals));
                } else {
                    var newLocals = new Map<String, Dynamic>();
                    newLocals.set("this", cls);
                    var mArgs = m.args != null ? m.args : [];
                    for (i in 0...mArgs.length) newLocals.set(mArgs[i], argsList[i]);
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, false, '${cls.name}.${methodName}', cls, cls.globals));
                }
            } else {
                var classCls = frame.globals.get("Class");
                if (classCls != null && classCls != cls) {
                    var m2 = findMethod(classCls, methodName);
                    if (m2 != null && m2.isForeign) {
                        var arity = m2.args != null ? m2.args.length : 0;
                        var sig = '${name}(${arity})';
                        var key = 'Class.${m2.isStatic ? "static " : ""}${sig}';
                        var impl = foreignMethods.get(key);
                        if (impl != null) {
                            var fullArgs:Array<Dynamic> = [obj];
                            for (a in argsList) fullArgs.push(a);
                            var res = impl(fullArgs);
                            if (fiberToSwitchTo == null && currentFiber != null && currentFiber.state == Running) frame.results.push(res);
                            return;
                        }
                    }
                }
                throwError('Method $dispName not found on class ${cls.name}.');
            }
        } else {
            var cls = getClass(obj);
            if (cls != null) {
                if (Std.isOfType(obj, WrenFn)) {
                    var fn:WrenFn = cast obj;
                    if (name == "call") {
                        var newLocals = new Map<String, Dynamic>();
                        for (k in fn.closure.keys()) newLocals.set(k, fn.closure.get(k));
                        for (i in 0...fn.args.length) {
                            if (i < argsList.length) newLocals.set(fn.args[i], argsList[i]);
                        }
                        currentFiber.stack.push(Frame.get(fn.body, newLocals, false, true, false, "call", null, fn.globals));
                        return;
                    }
                }
                
                if (Std.isOfType(obj, String)) {
                    var str:String = cast obj;
                    switch (name) {
                        case "[]":
                            var idx = argsList[0];
                            if (Std.isOfType(idx, WrenInstance) && (cast idx : WrenInstance).cls.name == "Range") {
                                var r:WrenInstance = cast idx;
                                var from:Int = cast r.fields.get("_from");
                                var to:Int = cast r.fields.get("_to");
                                var isInclusive:Bool = cast r.fields.get("_isInclusive");
                                if (from < 0) from = str.length + from;
                                if (to < 0) to = str.length + to;
                                var len = to - from + (isInclusive ? 1 : 0);
                                if (len <= 0) {
                                    frame.results.push("");
                                } else {
                                    frame.results.push(str.substr(from, len));
                                }
                            } else {
                                var i:Int = cast idx;
                                if (i < 0) i = str.length + i;
                                if (i < 0 || i >= str.length) throwError("Index out of bounds");
                                frame.results.push(str.charAt(i));
                            }
                            return;
                    }
                }
                
                if (Std.isOfType(obj, Array)) {
                    var arr:Array<Dynamic> = cast obj;
                    switch (name) {
                        case "iterate":
                            var iter = argsList[0];
                            if (iter == null) {
                                if (arr.length == 0) frame.results.push(null);
                                else frame.results.push(0);
                            } else {
                                var i:Int = cast iter;
                                if (i < 0 || i >= arr.length - 1) frame.results.push(null);
                                else frame.results.push(i + 1);
                            }
                            return;
                        case "iteratorValue":
                            var i:Int = cast argsList[0];
                            frame.results.push(arr[i]);
                            return;
                        case "add":
                            arr.push(argsList[0]);
                            frame.results.push(argsList[0]);
                            return;
                        case "count":
                            frame.results.push(arr.length);
                            return;
                        case "[]":
                            var idx = argsList[0];
                            if (Std.isOfType(idx, WrenInstance) && (cast idx : WrenInstance).cls.name == "Range") {
                                var r:WrenInstance = cast idx;
                                var from:Int = cast r.fields.get("_from");
                                var to:Int = cast r.fields.get("_to");
                                var isInclusive:Bool = cast r.fields.get("_isInclusive");
                                if (from < 0) from = arr.length + from;
                                if (to < 0) to = arr.length + to;
                                var len = to - from + (isInclusive ? 1 : 0);
                                if (len <= 0) {
                                    frame.results.push([]);
                                } else {
                                    frame.results.push(arr.slice(from, from + len));
                                }
                            } else {
                                var i:Int = cast idx;
                                if (i < 0) i = arr.length + i;
                                if (i < 0 || i >= arr.length) throwError("Index out of bounds");
                                frame.results.push(arr[i]);
                            }
                            return;
                        case "[]=":
                            var idx = argsList[0];
                            var val = argsList[1];
                            var i:Int = cast idx;
                            if (i < 0) i = arr.length + i;
                            if (i < 0 || i >= arr.length) throwError("Index out of bounds");
                            arr[i] = val;
                            frame.results.push(val);
                            return;
                    }
                } else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
                    var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
                    switch (name) {
                        case "[]":
                            frame.results.push(map.get(argsList[0]));
                            return;
                        case "[]=":
                            map.set(argsList[0], argsList[1]);
                            frame.results.push(argsList[1]);
                            return;
                        case "iterate":
                            var ks = [for (k in map.keys()) k];
                            var iter = argsList[0];
                            if (iter == null) {
                                if (ks.length == 0) frame.results.push(null);
                                else frame.results.push(0);
                            } else {
                                var i:Int = cast iter;
                                if (i < 0 || i >= ks.length - 1) frame.results.push(null);
                                else frame.results.push(i + 1);
                            }
                            return;
                        case "iteratorValue":
                            var ks = [for (k in map.keys()) k];
                            var i:Int = cast argsList[0];
                            frame.results.push(ks[i]);
                            return;
                        case "count":
                            var c = 0;
                            for (k in map.keys()) c++;
                            frame.results.push(c);
                            return;
                        case "containsKey":
                            frame.results.push(map.exists(argsList[0]));
                            return;
                        case "remove":
                            frame.results.push(map.remove(argsList[0]));
                            return;
                    }
                }

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
                        var arity = m.args != null ? m.args.length : 0;
                        var sig = '${name}(${arity})';
                        var key = '${foundCls.name}.${m.isStatic ? "static " : ""}${sig}';
                        var impl = foreignMethods.get(key);
                        if (impl != null) {
                            var fullArgs:Array<Dynamic> = [obj];
                            for (a in argsList) fullArgs.push(a);
                            var res = impl(fullArgs);
                             if (fiberToSwitchTo == null && currentFiber != null && currentFiber.state == Running) frame.results.push(res);
                        } else {
                            throwError('Foreign method $key not found');
                        }
                        return;
                    }
                    
                    var newLocals = new Map<String, Dynamic>();
                    newLocals.set("this", obj);
                    var mArgs = m.args != null ? m.args : [];
                    for (i in 0...mArgs.length) newLocals.set(mArgs[i], argsList[i]);
                    currentFiber.stack.push(Frame.get(m.body, newLocals, false, true, false, '${foundCls.name}.${methodName}', foundCls, foundCls.globals));
                    return;
                }
            }

            if (StringTools.endsWith(name, "=") && name.length > 1) {
                var varName = name.substring(0, name.length - 1);
                if (frame.locals.exists(varName)) {
                    frame.locals.set(varName, argsList[0]);
                    frame.results.push(argsList[0]);
                    return;
                }
            }

            var field = Reflect.field(obj, methodName);
            if (field != null) {
                if (Reflect.isFunction(field)) {
                    frame.results.push(Reflect.callMethod(obj, field, argsList));
                } else {
                    frame.results.push(field);
                }
            } else {
                throwError('Method $dispName not found on ${cls != null ? cls.name : "unknown"}.');
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
        if (cls.interfaces != null) {
            for (i in cls.interfaces) {
                if (isSubclass(i, target)) return true;
            }
        }
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
