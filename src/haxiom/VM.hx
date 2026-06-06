package haxiom;

import haxiom.AST;
import haxiom.Interp;
import haxe.DynamicAccess;

enum abstract Opcode(Int) from Int to Int {
    var OP_NOP = 0;
    var OP_LOAD_CONST = 1;
    var OP_GET_LOCAL = 2;
    var OP_SET_LOCAL = 3;
    var OP_GET_VAR = 4;
    var OP_SET_VAR = 5;
    var OP_DECLARE_VAR = 6;
    var OP_ADD = 7;
    var OP_SUB = 8;
    var OP_MUL = 9;
    var OP_DIV = 10;
    var OP_MOD = 11;
    var OP_EQ = 12;
    var OP_NEQ = 13;
    var OP_LT = 14;
    var OP_LTE = 15;
    var OP_GT = 16;
    var OP_GTE = 17;
    var OP_AND = 18;
    var OP_OR = 19;
    var OP_NOT = 20;
    var OP_BIT_AND = 21;
    var OP_BIT_OR = 22;
    var OP_BIT_XOR = 23;
    var OP_BIT_NOT = 24;
    var OP_SHL = 25;
    var OP_SHR = 26;
    var OP_USHR = 27;
    var OP_JUMP = 28;
    var OP_JUMP_IF_FALSE = 29;
    var OP_JUMP_IF_FALSE_PEEK = 30;
    var OP_JUMP_IF_TRUE_PEEK = 31;
    var OP_JUMP_IF_NOT_NULL_PEEK = 32;
    var OP_CALL = 33;
    var OP_RETURN = 34;
    var OP_GET_FIELD = 35;
    var OP_SET_FIELD = 36;
    var OP_NEW_ARRAY = 37;
    var OP_NEW_OBJECT = 38;
    var OP_THROW = 39;
    var OP_GET_THIS = 40;
    var OP_MAKE_FUNCTION = 41;
    var OP_POP = 42;
    var OP_PUSH_SCOPE = 43;
    var OP_POP_SCOPE = 44;
    var OP_GET_ITERATOR = 45;
    var OP_ITERATOR_HAS_NEXT = 46;
    var OP_ITERATOR_NEXT = 47;
    var OP_PUSH_TRY = 48;
    var OP_POP_TRY = 49;
    var OP_MATCH_CASE = 50;
    var OP_MATCH_CATCH = 51;
    var OP_UNOP = 52;
    var OP_UNOP_MUTATE = 53;
    var OP_ARRAY_ACCESS_GET = 54;
    var OP_ARRAY_ACCESS_SET = 55;
    var OP_NEW = 56;
    var OP_SAFE_GET_FIELD = 57;
    var OP_SAFE_SET_FIELD = 58;
    var OP_CAST = 59;
    var OP_DECLARE_CLASS = 60;
    var OP_DECLARE_INTERFACE = 61;
    var OP_DECLARE_ENUM = 62;
    var OP_DECLARE_ABSTRACT = 63;
    var OP_DECLARE_TYPEDEF = 64;
    var OP_IMPORT = 65;
    var OP_USING = 66;
    var OP_PACKAGE = 67;
    var OP_DUP = 68;
    var OP_CALL_METHOD = 69;
    var OP_NEW_MAP = 70;
    var OP_RANGE = 71;
    var OP_PUSH_CASE_SCOPE = 72;
}

@:keep
class BytecodeChunk {
    public var instructions:Array<Int>;
    public var constants:Array<Dynamic>;
    public var positions:Array<Pos>;

    public function new(instructions:Array<Int>, constants:Array<Dynamic>, positions:Array<Pos>) {
        this.instructions = instructions;
        this.constants = constants;
        this.positions = positions;
    }
}

class VMCallFrame {
    public var chunk:BytecodeChunk;
    public var ip:Int;
    public var scope:Scope;
    public var methodName:String;
    public var tryStack:Array<{catchIp:Int, stackSize:Int, scope:Scope}> = [];

    public function new(chunk:BytecodeChunk, ip:Int, scope:Scope, ?methodName:String = "") {
        this.chunk = chunk;
        this.ip = ip;
        this.scope = scope;
        this.methodName = methodName;
    }
}

class VM {
    public static function runChunk(interp:Interp, chunk:BytecodeChunk, scope:Scope, ?currentThis:Dynamic, ?methodName:String = "toplevel"):Dynamic {
        var stack:Array<Dynamic> = [];
        var callFrames:Array<VMCallFrame> = [];
        
        var frame = new VMCallFrame(chunk, 0, scope, methodName);
        callFrames.push(frame);
        
        var ip = 0;
        var inst = chunk.instructions;
        var consts = chunk.constants;
        var posTable = chunk.positions;

        inline function currentPos():Pos {
            return frame.chunk.positions[frame.ip] != null ? frame.chunk.positions[frame.ip] : { line: 1, col: 1 };
        }

        while (true) {
            try {
                if (frame.ip >= inst.length) {
                    if (callFrames.length > 1) {
                        callFrames.pop();
                        frame = callFrames[callFrames.length - 1];
                        inst = frame.chunk.instructions;
                        consts = frame.chunk.constants;
                        posTable = frame.chunk.positions;
                        continue;
                    }
                    break;
                }
                
                // Track source position in interpreter for stack traces
                var currentFramePos = frame.chunk.positions[frame.ip];
                if (currentFramePos != null) {
                    interp.lastEvalPos = currentFramePos;
                }

                var op:Opcode = inst[frame.ip++];
                switch (op) {
                    case OP_NOP:
                        // Do nothing

                    case OP_LOAD_CONST:
                        var idx = inst[frame.ip++];
                        stack.push(consts[idx]);

                    case OP_GET_LOCAL:
                        // Slot-based local access can be mapped to scope variables in this VM
                        var idx = inst[frame.ip++];
                        var name = consts[idx];
                        stack.push(frame.scope.get(name));

                    case OP_SET_LOCAL:
                        var idx = inst[frame.ip++];
                        var name = consts[idx];
                        var val = stack[stack.length - 1];
                        frame.scope.set(name, val);

                    case OP_GET_VAR:
                        var idx = inst[frame.ip++];
                        var name:String = consts[idx];
                        if (name == "this") {
                            stack.push(interp.currentThis);
                        } else {
                            if (!frame.scope.exists(name) && interp.currentThis != null && Std.isOfType(interp.currentThis, HaxiomInstance)) {
                                stack.push(interp.evalField(interp.currentThis, name, frame.scope, currentPos()));
                            } else {
                                stack.push(frame.scope.get(name));
                            }
                        }

                    case OP_SET_VAR:
                        var idx = inst[frame.ip++];
                        var name:String = consts[idx];
                        var val = stack[stack.length - 1];
                        if (name == "this") {
                            interp.currentThis = val;
                        } else {
                            if (!frame.scope.exists(name) && interp.currentThis != null && Std.isOfType(interp.currentThis, HaxiomInstance)) {
                                var inst:HaxiomInstance = cast interp.currentThis;
                                var fDef = interp.findFieldDef(inst.cls, name);
                                if (fDef != null && fDef.property != null && fDef.property.set == "set" && !interp.isInsideAccessor(name)) {
                                    var m = interp.findMethod(inst.cls, "set_" + name);
                                    if (m != null) {
                                        Reflect.callMethod(null, interp.bindMethod(interp.currentThis, m), [val]);
                                    }
                                } else {
                                    if (fDef != null && fDef.isFinal && interp.currentConstructorInstance != inst) {
                                        throw 'Cannot reassign final field $name outside of constructor';
                                    }
                                    if (fDef != null && fDef.type != null) {
                                        interp.checkType(val, fDef.type, frame.scope, inst.genericBindings);
                                    }
                                    inst.fields.set(name, val);
                                }
                            } else {
                                frame.scope.checkAndSet(name, val, interp);
                            }
                        }

                    case OP_DECLARE_VAR:
                        var nameIdx = inst[frame.ip++];
                        var typeIdx = inst[frame.ip++];
                        var isFinal = inst[frame.ip++];
                        var name:String = consts[nameIdx];
                        var type:TypeDecl = typeIdx >= 0 ? consts[typeIdx] : null;
                        var val = stack.pop();
                        if (type != null) {
                            interp.checkType(val, type, frame.scope);
                        }
                        frame.scope.declare(name, val, type, isFinal == 1);

                    case OP_ADD:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("+", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 + v2 : Dynamic));

                    case OP_SUB:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("-", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 - v2 : Dynamic));

                    case OP_MUL:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("*", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 * v2 : Dynamic));

                    case OP_DIV:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("/", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 / v2 : Dynamic));

                    case OP_MOD:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("%", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 % v2 : Dynamic));

                    case OP_EQ:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("==", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 == v2 : Dynamic));

                    case OP_NEQ:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("!=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 != v2 : Dynamic));

                    case OP_LT:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("<", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 < v2 : Dynamic));

                    case OP_LTE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("<=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 <= v2 : Dynamic));

                    case OP_GT:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload(">", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 > v2 : Dynamic));

                    case OP_GTE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload(">=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 >= v2 : Dynamic));

                    case OP_AND:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((v1 : Bool) && (v2 : Bool));

                    case OP_OR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((v1 : Bool) || (v2 : Bool));

                    case OP_NOT:
                        var v = stack.pop();
                        stack.push(!cast(v, Bool));

                    case OP_BIT_AND:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) & (cast v2 : Int));

                    case OP_BIT_OR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) | (cast v2 : Int));

                    case OP_BIT_XOR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) ^ (cast v2 : Int));

                    case OP_BIT_NOT:
                        var v = stack.pop();
                        stack.push(~(cast v : Int));

                    case OP_SHL:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) << (cast v2 : Int));

                    case OP_SHR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) >> (cast v2 : Int));

                    case OP_USHR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) >>> (cast v2 : Int));

                    case OP_JUMP:
                        var targetIp = inst[frame.ip++];
                        frame.ip = targetIp;

                    case OP_JUMP_IF_FALSE:
                        var targetIp = inst[frame.ip++];
                        var v = stack.pop();
                        if (v == false || v == null) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_FALSE_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (v == false || v == null) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_TRUE_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (v != false && v != null) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_NOT_NULL_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (v != null) {
                            frame.ip = targetIp;
                        }

                    case OP_CALL:
                        var argCount = inst[frame.ip++];
                        var func = stack.pop();
                        var args = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }
                        
                        var res = Reflect.callMethod(null, func, args);
                        stack.push(res);

                    case OP_RETURN:
                        var res = stack.pop();
                        if (callFrames.length > 1) {
                            callFrames.pop();
                            frame = callFrames[callFrames.length - 1];
                            inst = frame.chunk.instructions;
                            consts = frame.chunk.constants;
                            posTable = frame.chunk.positions;
                            stack.push(res);
                        } else {
                            return res;
                        }

                    case OP_GET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var obj = stack.pop();
                        if (obj == null) throw 'Cannot read field "$fieldName" of null';
                        stack.push(interp.evalField(obj, fieldName, frame.scope, currentPos()));

                    case OP_SET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var val = stack.pop();
                        var obj = stack.pop();
                        if (obj == null) throw 'Cannot write field "$fieldName" of null';
                        stack.push(interp.assignField(obj, fieldName, val, frame.scope));

                    case OP_SAFE_GET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var obj = stack.pop();
                        if (obj == null) {
                            stack.push(null);
                        } else {
                            stack.push(interp.evalField(obj, fieldName, frame.scope, currentPos()));
                        }

                    case OP_SAFE_SET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var val = stack.pop();
                        var obj = stack.pop();
                        if (obj == null) {
                            stack.push(null);
                        } else {
                            stack.push(interp.assignField(obj, fieldName, val, frame.scope));
                        }

                    case OP_NEW_ARRAY:
                        var size = inst[frame.ip++];
                        var arr = [];
                        for (i in 0...size) {
                            arr.unshift(stack.pop());
                        }
                        stack.push(arr);

                    case OP_NEW_OBJECT:
                        var fieldCount = inst[frame.ip++];
                        var obj:DynamicAccess<Dynamic> = {};
                        var fields = [];
                        for (i in 0...fieldCount) {
                            var val = stack.pop();
                            var nameIdx = inst[frame.ip++];
                            var name:String = consts[nameIdx];
                            fields.push({ name: name, val: val });
                        }
                        for (f in fields) {
                            obj.set(f.name, f.val);
                        }
                        stack.push(obj);

                    case OP_THROW:
                        var val = stack.pop();
                        throw val;

                    case OP_GET_THIS:
                        stack.push(interp.currentThis);

                    case OP_MAKE_FUNCTION:
                        var protoIdx = inst[frame.ip++];
                        var proto = consts[protoIdx];
                        var closureScope = frame.scope;
                        closureScope.markCaptured();
                        
                        var func = (callArgs:Array<Dynamic>) -> {
                            var fScope = Scope.create(closureScope);
                            for (i in 0...proto.args.length) {
                                var arg = proto.args[i];
                                var val = i < callArgs.length ? callArgs[i] : null;
                                interp.checkType(val, arg.type, fScope);
                                fScope.declare(arg.name, val, arg.type);
                            }
                            
                            interp.pushFrame(proto.name != null ? proto.name : "anonymous", currentPos());
                            try {
                                var res = VM.runChunk(interp, proto.bodyChunk, fScope, interp.currentThis, proto.name != null ? proto.name : "anonymous");
                                if (proto.retType != null && interp.typeToString(proto.retType) == "Void") {
                                    res = null;
                                } else {
                                    interp.checkType(res, proto.retType, fScope);
                                }
                                interp.popFrame();
                                Scope.recycle(fScope);
                                return res;
                            } catch (flow:ControlFlow) {
                                interp.popFrame();
                                switch (flow) {
                                    case Return(val):
                                        if (proto.retType != null && interp.typeToString(proto.retType) == "Void") {
                                            Scope.recycle(fScope);
                                            return null;
                                        }
                                        interp.checkType(val, proto.retType, fScope);
                                        Scope.recycle(fScope);
                                        return val;
                                    default:
                                        Scope.recycle(fScope);
                                        throw flow;
                                }
                            } catch (err:Dynamic) {
                                interp.popFrame();
                                Scope.recycle(fScope);
                                throw err;
                            }
                        };
                        
                        var boundFunc:Dynamic = switch (proto.args.length) {
                            case 0: () -> func([]);
                            case 1: (a) -> func([a]);
                            case 2: (a, b) -> func([a, b]);
                            case 3: (a, b, c) -> func([a, b, c]);
                            case 4: (a, b, c, d) -> func([a, b, c, d]);
                            default: (callArgs:Array<Dynamic>) -> func(callArgs);
                        };
                        
                        var signatureArgs = [];
                        for (arg in proto.args) {
                            var t = arg.type != null ? arg.type : TPath(["Dynamic"], []);
                            signatureArgs.push(t);
                        }
                        var signatureRet = proto.retType != null ? proto.retType : TPath(["Dynamic"], []);
                        interp.functionSignatures.set(boundFunc, TFun(signatureArgs, signatureRet));
                        
                        if (proto.name != null) {
                            frame.scope.declare(proto.name, boundFunc);
                        }
                        stack.push(boundFunc);

                    case OP_POP:
                        stack.pop();

                    case OP_PUSH_SCOPE:
                        frame.scope = Scope.create(frame.scope);

                    case OP_PUSH_CASE_SCOPE:
                        var caseScope:Scope = stack.pop();
                        frame.scope = caseScope;

                    case OP_POP_SCOPE:
                        var s = frame.scope;
                        frame.scope = s.parent;
                        Scope.recycle(s);

                    case OP_GET_ITERATOR:
                        var iterable = stack.pop();
                        var iterator:Dynamic = null;
                        if (iterable != null) {
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
                        }
                        stack.push(iterator);

                    case OP_ITERATOR_HAS_NEXT:
                        var iterator = stack[stack.length - 1];
                        if (iterator != null) {
                            if (Std.isOfType(iterator, IntIterator)) {
                                stack.push((cast iterator : IntIterator).hasNext());
                            } else {
                                stack.push(Reflect.callMethod(iterator, Reflect.field(iterator, "hasNext"), []));
                            }
                        } else {
                            stack.push(false);
                        }

                    case OP_ITERATOR_NEXT:
                        var iterator = stack[stack.length - 1];
                        if (iterator != null) {
                            if (Std.isOfType(iterator, IntIterator)) {
                                stack.push((cast iterator : IntIterator).next());
                            } else {
                                stack.push(Reflect.callMethod(iterator, Reflect.field(iterator, "next"), []));
                            }
                        } else {
                            stack.push(null);
                        }

                    case OP_PUSH_TRY:
                        var catchIp = inst[frame.ip++];
                        frame.tryStack.push({ catchIp: catchIp, stackSize: stack.length, scope: frame.scope });

                    case OP_POP_TRY:
                        frame.tryStack.pop();

                    case OP_MATCH_CASE:
                        var patternIdx = inst[frame.ip++];
                        var guardIdx = inst[frame.ip++];
                        var val = stack[stack.length - 1];
                        var pattern = consts[patternIdx];
                        var guard = guardIdx >= 0 ? consts[guardIdx] : null;
                        var caseScope = Scope.create(frame.scope);
                        var matched = false;
                        try {
                            if (interp.matchPattern(val, pattern, frame.scope, caseScope)) {
                                var guardMatched = true;
                                if (guard != null) {
                                    guardMatched = interp.eval(guard, caseScope) == true;
                                }
                                if (guardMatched) {
                                    matched = true;
                                }
                            }
                        } catch (_:Dynamic) {
                            matched = false;
                        }
                        
                        if (matched) {
                            stack.pop(); // pop matched value
                            stack.push(caseScope);
                            stack.push(true);
                        } else {
                            Scope.recycle(caseScope);
                            stack.push(false);
                        }

                    case OP_MATCH_CATCH:
                        var clauseIdx = inst[frame.ip++];
                        var c = consts[clauseIdx];
                        var errVal = stack[stack.length - 1];
                        var caseScope = Scope.create(frame.scope);
                        var matched = false;
                        try {
                            if (interp.matchPattern(errVal, c.pattern, frame.scope, caseScope)) {
                                var typeMatched = true;
                                if (c.type != null) {
                                    try {
                                        interp.checkType(errVal, c.type, frame.scope);
                                    } catch (_:Dynamic) {
                                        typeMatched = false;
                                    }
                                }
                                if (typeMatched) {
                                    var guardMatched = true;
                                    if (c.guard != null) {
                                        guardMatched = interp.eval(c.guard, caseScope) == true;
                                    }
                                    if (guardMatched) {
                                        matched = true;
                                    }
                                }
                            }
                        } catch (_:Dynamic) {
                            matched = false;
                        }

                        if (matched) {
                            stack.pop(); // pop exception
                            stack.push(caseScope);
                            stack.push(true);
                        } else {
                            Scope.recycle(caseScope);
                            stack.push(false);
                        }

                    case OP_UNOP:
                        var opStr:String = consts[inst[frame.ip++]];
                        var val = stack.pop();
                        var overloadRes = interp.findAbstractUnopOverload(opStr, val);
                        if (overloadRes.success) {
                            stack.push(overloadRes.value);
                        } else {
                            var unopRes:Dynamic = null;
                            switch (opStr) {
                                case "!": unopRes = !(cast val : Bool);
                                case "-": unopRes = -(cast val : Float);
                                case "~": unopRes = ~(cast val : Int);
                                default: throw 'Unknown unary operator "$opStr"';
                            }
                            stack.push(unopRes);
                        }

                    case OP_UNOP_MUTATE:
                        var opStr:String = consts[inst[frame.ip++]];
                        var targetExprIdx = inst[frame.ip++];
                        var targetExpr = consts[targetExprIdx];
                        
                        var val = interp.eval(targetExpr, frame.scope);
                        var overloadRes = interp.findAbstractUnopOverload(opStr, val);
                        var finalVal:Dynamic = null;
                        var retVal:Dynamic = null;

                        if (overloadRes.success) {
                            finalVal = overloadRes.value;
                            retVal = finalVal;
                            if (opStr == "post++" || opStr == "post--") {
                                retVal = val;
                            }
                            interp.assign(targetExpr, finalVal, frame.scope);
                        } else {
                            switch (opStr) {
                                case "post++":
                                    finalVal = (cast val : Float) + 1;
                                    retVal = val;
                                case "post--":
                                    finalVal = (cast val : Float) - 1;
                                    retVal = val;
                                case "++":
                                    finalVal = (cast val : Float) + 1;
                                    retVal = finalVal;
                                case "--":
                                    finalVal = (cast val : Float) - 1;
                                    retVal = finalVal;
                                default:
                                    throw 'Unknown mutating unary operator "$opStr"';
                            }
                            interp.assign(targetExpr, finalVal, frame.scope);
                        }
                        stack.push(retVal);

                    case OP_ARRAY_ACCESS_GET:
                        var idx = stack.pop();
                        var obj = stack.pop();
                        stack.push(interp.getSubscript(obj, idx));

                    case OP_ARRAY_ACCESS_SET:
                        var val = stack.pop();
                        var idx = stack.pop();
                        var obj = stack.pop();
                        interp.setSubscript(obj, idx, val);
                        stack.push(val);

                    case OP_NEW:
                        var typeIdx = inst[frame.ip++];
                        var argCount = inst[frame.ip++];
                        var type:TypeDecl = consts[typeIdx];
                        var args = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }

                        // Evaluate new instance using parser/interpreter helpers
                        var fakeNewExpr = { def: ENew(type, [for (a in args) { def: EValue(a), pos: currentPos() }]), pos: currentPos() };
                        var res = interp.eval(fakeNewExpr, frame.scope);
                        stack.push(res);

                    case OP_CAST:
                        var typeIdx = inst[frame.ip++];
                        var type:TypeDecl = typeIdx >= 0 ? consts[typeIdx] : null;
                        var val = stack.pop();
                        if (type != null) {
                            try {
                                interp.checkType(val, type, frame.scope);
                            } catch (err:Dynamic) {
                                throw 'Class cast error: expected ${interp.typeToString(type)} but got ${val}';
                            }
                        }
                        stack.push(val);

                    case OP_DECLARE_CLASS:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        // In VM mode, any method body of the class will be compiled to bytecode upon invocation
                        stack.push(res);

                    case OP_DECLARE_INTERFACE:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_ENUM:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_ABSTRACT:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_TYPEDEF:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_IMPORT:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_USING:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_PACKAGE:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DUP:
                        stack.push(stack[stack.length - 1]);

                    case OP_CALL_METHOD:
                        var fieldIdx = inst[frame.ip++];
                        var argCount = inst[frame.ip++];
                        var fieldName:String = consts[fieldIdx];
                        var obj = stack.pop();
                        
                        var args = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }

                        if (obj != null && Std.isOfType(obj, HaxiomInstance)) {
                            var instObj:HaxiomInstance = cast obj;
                            var m = interp.findMethod(instObj.cls, fieldName);
                            if (m != null) {
                                // Dynamic execution wrapper for script-defined methods
                                var boundMethod = interp.bindMethod(obj, m);
                                var res = Reflect.callMethod(null, boundMethod, args);
                                stack.push(res);
                                continue;
                            }
                        }
                        
                        // Fallback: resolve method as a field and invoke
                        var resolvedField = interp.evalField(obj, fieldName, frame.scope, currentPos());
                        var res = Reflect.callMethod(null, resolvedField, args);
                        stack.push(res);

                    case OP_NEW_MAP:
                        var size = inst[frame.ip++];
                        var evaluated = [];
                        for (i in 0...size) {
                            var val = stack.pop();
                            var key = stack.pop();
                            evaluated.unshift({ key: key, value: val });
                        }
                        var allString = true;
                        var allInt = true;
                        for (kv in evaluated) {
                            if (!Std.isOfType(kv.key, String)) allString = false;
                            if (!Std.isOfType(kv.key, Int)) allInt = false;
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
                        stack.push(map);

                    case OP_RANGE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        interp.checkInt(v1, "IntIterator start");
                        interp.checkInt(v2, "IntIterator end");
                        stack.push(new IntIterator(cast v1, cast v2));

                    default:
                        throw 'Unsupported opcode $op';
                }
            } catch (e:ControlFlow) {
                // Rethrow control flows like Return, Break, Continue
                throw e;
            } catch (e:Dynamic) {
                var foundHandler = false;
                while (callFrames.length > 0) {
                    var f = callFrames[callFrames.length - 1];
                    if (f.tryStack.length > 0) {
                        var handler = f.tryStack.pop();
                        frame = f;
                        inst = frame.chunk.instructions;
                        consts = frame.chunk.constants;
                        posTable = frame.chunk.positions;
                        
                        // Reset stack size to pre-try size, push exception, restore scope, and jump to catch
                        while (stack.length > handler.stackSize) {
                            stack.pop();
                        }
                        stack.push(e);
                        frame.scope = handler.scope;
                        frame.ip = handler.catchIp;
                        foundHandler = true;
                        break;
                    }
                    callFrames.pop();
                }
                if (foundHandler) {
                    continue;
                }
                throw e;
            }
        }

        return stack.length > 0 ? stack[stack.length - 1] : null;
    }
}
