package haxiom;

import haxiom.AST;
import haxiom.VM.Opcode;
import haxiom.VM.BytecodeChunk;

typedef LoopContext = {
    var startLabel:Int;
    var endLabel:Int;
    var scopeDepth:Int;
}

class BytecodeCompiler {
    var instructions:Array<Int> = [];
    var constants:Array<Dynamic> = [];
    var positions:Array<Pos> = [];
    
    var loopStack:Array<LoopContext> = [];
    var currentScopeDepth:Int = 0;

    public function new() {}

    public static function compile(expr:Expr):BytecodeChunk {
        var compiler = new BytecodeCompiler();
        compiler.compileExpr(expr);
        return new BytecodeChunk(compiler.instructions, compiler.constants, compiler.positions);
    }

    inline function emit(op:Opcode, pos:Pos) {
        instructions.push(op);
        positions.push(pos);
    }

    inline function emitInt(val:Int, pos:Pos) {
        instructions.push(val);
        positions.push(pos);
    }

    function addConst(v:Dynamic):Int {
        if (v == null || Std.isOfType(v, String) || Std.isOfType(v, Int) || Std.isOfType(v, Float) || Std.isOfType(v, Bool)) {
            for (i in 0...constants.length) {
                if (constants[i] == v) return i;
            }
        }
        constants.push(v);
        return constants.length - 1;
    }

    function compileExpr(e:Expr) {
        if (e == null) {
            emit(OP_LOAD_CONST, { line: 1, col: 1 });
            emitInt(addConst(null), { line: 1, col: 1 });
            return;
        }

        switch (e.def) {
            case EValue(v):
                emit(OP_LOAD_CONST, e.pos);
                emitInt(addConst(v), e.pos);

            case EIdent(name):
                emit(OP_GET_VAR, e.pos);
                emitInt(addConst(name), e.pos);

            case EVar(name, type, expr, isFinal, meta):
                if (expr != null) {
                    compileExpr(expr);
                } else {
                    emit(OP_LOAD_CONST, e.pos);
                    emitInt(addConst(null), e.pos);
                }
                var nameIdx = addConst(name);
                var typeIdx = type != null ? addConst(type) : -1;
                emit(OP_DECLARE_VAR, e.pos);
                emitInt(nameIdx, e.pos);
                emitInt(typeIdx, e.pos);
                emitInt(isFinal ? 1 : 0, e.pos);

            case EAssign(target, expr):
                switch (target.def) {
                    case EIdent(name):
                        compileExpr(expr);
                        emit(OP_SET_VAR, e.pos);
                        emitInt(addConst(name), e.pos);
                    case EField(obj, field):
                        compileExpr(obj);
                        compileExpr(expr);
                        emit(OP_SET_FIELD, e.pos);
                        emitInt(addConst(field), e.pos);
                    case ESafeField(obj, field):
                        compileExpr(obj);
                        compileExpr(expr);
                        emit(OP_SAFE_SET_FIELD, e.pos);
                        emitInt(addConst(field), e.pos);
                    case EBinop("[]", obj, indexExpr):
                        compileExpr(obj);
                        compileExpr(indexExpr);
                        compileExpr(expr);
                        emit(OP_ARRAY_ACCESS_SET, e.pos);
                    default:
                        throw "Invalid assignment target";
                }

            case EBinop(op, e1, e2):
                if (op == "&&") {
                    compileExpr(e1);
                    emit(OP_JUMP_IF_FALSE_PEEK, e.pos);
                    var jumpIdx = instructions.length;
                    emitInt(0, e.pos); // placeholder
                    emit(OP_POP, e.pos);
                    compileExpr(e2);
                    instructions[jumpIdx] = instructions.length;
                } else if (op == "||") {
                    compileExpr(e1);
                    emit(OP_JUMP_IF_TRUE_PEEK, e.pos);
                    var jumpIdx = instructions.length;
                    emitInt(0, e.pos); // placeholder
                    emit(OP_POP, e.pos);
                    compileExpr(e2);
                    instructions[jumpIdx] = instructions.length;
                } else if (op == "??") {
                    compileExpr(e1);
                    emit(OP_JUMP_IF_NOT_NULL_PEEK, e.pos);
                    var jumpIdx = instructions.length;
                    emitInt(0, e.pos); // placeholder
                    emit(OP_POP, e.pos);
                    compileExpr(e2);
                    instructions[jumpIdx] = instructions.length;
                } else if (op == "?") {
                    compileExpr(e1);
                    emit(OP_JUMP_IF_FALSE, e.pos);
                    var elseJumpIdx = instructions.length;
                    emitInt(0, e.pos);
                    
                    switch (e2.def) {
                        case EBinop(":", left, right):
                            compileExpr(left);
                            emit(OP_JUMP, e.pos);
                            var endJumpIdx = instructions.length;
                            emitInt(0, e.pos);
                            
                            instructions[elseJumpIdx] = instructions.length;
                            compileExpr(right);
                            instructions[endJumpIdx] = instructions.length;
                        default:
                            throw "Invalid ternary operator format";
                    }
                } else if (op == "[]") {
                    compileExpr(e1);
                    compileExpr(e2);
                    emit(OP_ARRAY_ACCESS_GET, e.pos);
                } else if (op == "...") {
                    compileExpr(e1);
                    compileExpr(e2);
                    emit(OP_RANGE, e.pos);
                } else {
                    compileExpr(e1);
                    compileExpr(e2);
                    var opc:Opcode = switch (op) {
                        case "+": OP_ADD;
                        case "-": OP_SUB;
                        case "*": OP_MUL;
                        case "/": OP_DIV;
                        case "%": OP_MOD;
                        case "==": OP_EQ;
                        case "!=": OP_NEQ;
                        case "<": OP_LT;
                        case "<=": OP_LTE;
                        case ">": OP_GT;
                        case ">=": OP_GTE;
                        case "&": OP_BIT_AND;
                        case "|": OP_BIT_OR;
                        case "^": OP_BIT_XOR;
                        case "<<": OP_SHL;
                        case ">>": OP_SHR;
                        case ">>>": OP_USHR;
                        default: throw 'Unknown operator "$op"';
                    };
                    emit(opc, e.pos);
                }

            case EUnop(op, expr):
                if (op == "++" || op == "--" || op == "post++" || op == "post--") {
                    emit(OP_UNOP_MUTATE, e.pos);
                    emitInt(addConst(op), e.pos);
                    emitInt(addConst(expr), e.pos);
                } else {
                    compileExpr(expr);
                    emit(OP_UNOP, e.pos);
                    emitInt(addConst(op), e.pos);
                }

            case EField(objExpr, field):
                compileExpr(objExpr);
                emit(OP_GET_FIELD, e.pos);
                emitInt(addConst(field), e.pos);

            case ESafeField(objExpr, field):
                compileExpr(objExpr);
                emit(OP_SAFE_GET_FIELD, e.pos);
                emitInt(addConst(field), e.pos);

            case ECall(callExpr, args):
                switch (callExpr.def) {
                    case EField(obj, field):
                        for (arg in args) {
                            compileExpr(arg);
                        }
                        compileExpr(obj);
                        emit(OP_CALL_METHOD, e.pos);
                        emitInt(addConst(field), e.pos);
                        emitInt(args.length, e.pos);
                    default:
                        for (arg in args) {
                            compileExpr(arg);
                        }
                        compileExpr(callExpr);
                        emit(OP_CALL, e.pos);
                        emitInt(args.length, e.pos);
                }

            case EArrayDecl(values):
                for (val in values) {
                    compileExpr(val);
                }
                emit(OP_NEW_ARRAY, e.pos);
                emitInt(values.length, e.pos);

            case EObjectDecl(fields):
                for (f in fields) {
                    compileExpr(f.expr);
                }
                emit(OP_NEW_OBJECT, e.pos);
                emitInt(fields.length, e.pos);
                for (i in 0...fields.length) {
                    var f = fields[fields.length - 1 - i];
                    emitInt(addConst(f.name), e.pos);
                }

            case EMapDecl(values):
                for (kv in values) {
                    compileExpr(kv.key);
                    compileExpr(kv.value);
                }
                emit(OP_NEW_MAP, e.pos);
                emitInt(values.length, e.pos);

            case EBlock(exprs):
                if (exprs.length == 0) {
                    emit(OP_LOAD_CONST, e.pos);
                    emitInt(addConst(null), e.pos);
                } else {
                    for (i in 0...exprs.length) {
                        compileExpr(exprs[i]);
                        if (i < exprs.length - 1) {
                            emit(OP_POP, e.pos);
                        }
                    }
                }

            case EFunction(name, args, retType, body):
                var bodyChunk = BytecodeCompiler.compile(body);
                // Clean the body Chunk's positions so it knows its location
                var proto = {
                    name: name,
                    args: args,
                    retType: retType,
                    bodyChunk: bodyChunk
                };
                emit(OP_MAKE_FUNCTION, e.pos);
                emitInt(addConst(proto), e.pos);

            case EIf(cond, e1, e2):
                compileExpr(cond);
                emit(OP_JUMP_IF_FALSE, e.pos);
                var elseJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                compileExpr(e1);
                emit(OP_JUMP, e.pos);
                var endJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                instructions[elseJumpIdx] = instructions.length;
                if (e2 != null) {
                    compileExpr(e2);
                } else {
                    emit(OP_LOAD_CONST, e.pos);
                    emitInt(addConst(null), e.pos);
                }
                instructions[endJumpIdx] = instructions.length;

            case EWhile(cond, body):
                var startLabel = instructions.length;
                compileExpr(cond);
                emit(OP_JUMP_IF_FALSE, e.pos);
                var endJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                loopStack.push({ startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth });
                var loopIdx = loopStack.length - 1;
                
                compileExpr(body);
                emit(OP_POP, e.pos); // clean body result
                emit(OP_JUMP, e.pos);
                emitInt(startLabel, e.pos);
                
                instructions[endJumpIdx] = instructions.length;
                loopStack[loopIdx].endLabel = instructions.length;
                
                // break jumps must go here
                // Patch break jumps that were compiled with loopEnd placeholder
                for (i in startLabel...instructions.length) {
                    if (instructions[i] == -999) { // -999 is placeholder for loop end
                        instructions[i] = instructions.length;
                    }
                    if (instructions[i] == -888) { // -888 is placeholder for loop start
                        instructions[i] = startLabel;
                    }
                }
                
                loopStack.pop();
                emit(OP_LOAD_CONST, e.pos);
                emitInt(addConst(null), e.pos);

            case EDoWhile(cond, body):
                var startLabel = instructions.length;
                
                loopStack.push({ startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth });
                var loopIdx = loopStack.length - 1;
                
                compileExpr(body);
                emit(OP_POP, e.pos);
                
                var condLabel = instructions.length;
                compileExpr(cond);
                emit(OP_JUMP_IF_TRUE_PEEK, e.pos); // wait, jumps if true (meaning it loops back to startLabel)
                emitInt(startLabel, e.pos);
                emit(OP_POP, e.pos); // pop cond result
                
                loopStack[loopIdx].endLabel = instructions.length;
                
                // Patch breaks and continues
                for (i in startLabel...instructions.length) {
                    if (instructions[i] == -999) {
                        instructions[i] = instructions.length;
                    }
                    if (instructions[i] == -888) {
                        instructions[i] = condLabel;
                    }
                }
                
                loopStack.pop();
                emit(OP_LOAD_CONST, e.pos);
                emitInt(addConst(null), e.pos);

            case EFor(v, itExpr, body):
                compileExpr(itExpr);
                emit(OP_GET_ITERATOR, e.pos);
                
                var startLabel = instructions.length;
                emit(OP_ITERATOR_HAS_NEXT, e.pos);
                emit(OP_JUMP_IF_FALSE, e.pos);
                var endJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                emit(OP_PUSH_SCOPE, e.pos);
                currentScopeDepth++;
                
                emit(OP_ITERATOR_NEXT, e.pos);
                emit(OP_DECLARE_VAR, e.pos);
                emitInt(addConst(v), e.pos);
                emitInt(-1, e.pos); // no type
                emitInt(0, e.pos); // not final
                
                loopStack.push({ startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth });
                var loopIdx = loopStack.length - 1;
                
                compileExpr(body);
                emit(OP_POP, e.pos);
                
                emit(OP_POP_SCOPE, e.pos);
                currentScopeDepth--;
                
                emit(OP_JUMP, e.pos);
                emitInt(startLabel, e.pos);
                
                instructions[endJumpIdx] = instructions.length;
                loopStack[loopIdx].endLabel = instructions.length;
                
                // Patch break/continues
                for (i in startLabel...instructions.length) {
                    if (instructions[i] == -999) {
                        instructions[i] = instructions.length;
                    }
                    if (instructions[i] == -888) {
                        instructions[i] = startLabel;
                    }
                }
                
                loopStack.pop();
                emit(OP_POP, e.pos); // pop the iterator from stack
                emit(OP_LOAD_CONST, e.pos);
                emitInt(addConst(null), e.pos);

            case EBreak:
                if (loopStack.length == 0) throw "Break outside loop";
                var ctx = loopStack[loopStack.length - 1];
                var scopeDiff = currentScopeDepth - ctx.scopeDepth;
                for (i in 0...scopeDiff) {
                    emit(OP_POP_SCOPE, e.pos);
                }
                emit(OP_JUMP, e.pos);
                emitInt(-999, e.pos); // placeholder for loop end

            case EContinue:
                if (loopStack.length == 0) throw "Continue outside loop";
                var ctx = loopStack[loopStack.length - 1];
                var scopeDiff = currentScopeDepth - ctx.scopeDepth;
                for (i in 0...scopeDiff) {
                    emit(OP_POP_SCOPE, e.pos);
                }
                emit(OP_JUMP, e.pos);
                emitInt(-888, e.pos); // placeholder for loop start / check

            case EReturn(exprVal):
                if (exprVal != null) {
                    compileExpr(exprVal);
                } else {
                    emit(OP_LOAD_CONST, e.pos);
                    emitInt(addConst(null), e.pos);
                }
                emit(OP_RETURN, e.pos);

            case EThrow(exprVal):
                compileExpr(exprVal);
                emit(OP_THROW, e.pos);

            case ETry(tryExpr, catches):
                emit(OP_PUSH_TRY, e.pos);
                var catchJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                compileExpr(tryExpr);
                emit(OP_POP_TRY, e.pos);
                emit(OP_JUMP, e.pos);
                var endTryJumpIdx = instructions.length;
                emitInt(0, e.pos);
                
                instructions[catchJumpIdx] = instructions.length;
                
                // Catches block: top of stack has the exception
                for (i in 0...catches.length) {
                    var c = catches[i];
                    var clauseIdx = addConst(c);
                    emit(OP_MATCH_CATCH, e.pos);
                    emitInt(clauseIdx, e.pos);
                    
                    emit(OP_JUMP_IF_FALSE, e.pos);
                    var nextCatchJumpIdx = instructions.length;
                    emitInt(0, e.pos);
                    
                    // Matches: caseScope is on stack
                    emit(OP_PUSH_CASE_SCOPE, e.pos);
                    currentScopeDepth++;
                    
                    compileExpr(c.body);
                    
                    emit(OP_POP_SCOPE, e.pos);
                    currentScopeDepth--;
                    
                    emit(OP_JUMP, e.pos);
                    var exitTryJumpIdx = instructions.length;
                    emitInt(0, e.pos);
                    
                    instructions[nextCatchJumpIdx] = instructions.length;
                    // If we exit this catch, continue to next or throw
                    if (i == catches.length - 1) {
                        // Rethrow exception
                        emit(OP_THROW, e.pos);
                    }
                    
                    // Patch exit Try jumps
                    instructions[exitTryJumpIdx] = endTryJumpIdx; // we patch it later to end of try
                }
                
                // Patch end Try jumps
                var finalEndOffset = instructions.length;
                instructions[endTryJumpIdx] = finalEndOffset;
                for (i in catchJumpIdx...instructions.length) {
                    if (instructions[i] == endTryJumpIdx) {
                        instructions[i] = finalEndOffset;
                    }
                }

            case ESwitch(exprVal, cases, defExpr):
                compileExpr(exprVal); // leaves match val on stack
                
                var endSwitchJumpIndices = [];
                
                for (c in cases) {
                    var caseBodyLabel = -1;
                    var valueJumpPlaceholderIndices = [];
                    
                    for (v in c.values) {
                        var patternIdx = addConst(v);
                        var guardIdx = c.guard != null ? addConst(c.guard) : -1;
                        emit(OP_MATCH_CASE, e.pos);
                        emitInt(patternIdx, e.pos);
                        emitInt(guardIdx, e.pos);
                        
                        emit(OP_JUMP_IF_TRUE_PEEK, e.pos);
                        valueJumpPlaceholderIndices.push(instructions.length);
                        emitInt(0, e.pos); // placeholder to jump to body
                        
                        emit(OP_POP, e.pos); // pop false if match failed
                    }
                    
                    emit(OP_JUMP, e.pos);
                    var skipBodyJumpIdx = instructions.length;
                    emitInt(0, e.pos);
                    
                    // Case body
                    var bodyLabel = instructions.length;
                    for (idx in valueJumpPlaceholderIndices) {
                        instructions[idx] = bodyLabel;
                    }
                    
                    emit(OP_POP, e.pos); // pop true from OP_JUMP_IF_TRUE_PEEK
                    emit(OP_PUSH_CASE_SCOPE, e.pos);
                    currentScopeDepth++;
                    
                    compileExpr(c.expr);
                    
                    emit(OP_POP_SCOPE, e.pos);
                    currentScopeDepth--;
                    
                    emit(OP_JUMP, e.pos);
                    endSwitchJumpIndices.push(instructions.length);
                    emitInt(0, e.pos);
                    
                    instructions[skipBodyJumpIdx] = instructions.length;
                }
                
                // If we get here, no case matched
                emit(OP_POP, e.pos); // pop match val
                
                if (defExpr != null) {
                    compileExpr(defExpr);
                } else {
                    emit(OP_LOAD_CONST, e.pos);
                    emitInt(addConst(null), e.pos);
                }
                
                var endLabel = instructions.length;
                for (idx in endSwitchJumpIndices) {
                    instructions[idx] = endLabel;
                }

            case ENew(type, args):
                for (arg in args) {
                    compileExpr(arg);
                }
                emit(OP_NEW, e.pos);
                emitInt(addConst(type), e.pos);
                emitInt(args.length, e.pos);

            case ECast(exprVal, type):
                compileExpr(exprVal);
                emit(OP_CAST, e.pos);
                emitInt(type != null ? addConst(type) : -1, e.pos);

            case EClass(name, fields, methods, parent, interfaces, params, meta):
                emit(OP_DECLARE_CLASS, e.pos);
                emitInt(addConst(e), e.pos);

            case EInterface(name, fields, methods, parents, params, meta):
                emit(OP_DECLARE_INTERFACE, e.pos);
                emitInt(addConst(e), e.pos);

            case EEnum(name, constructors):
                emit(OP_DECLARE_ENUM, e.pos);
                emitInt(addConst(e), e.pos);

            case EAbstract(name, underlyingType, fields, methods, params, meta):
                emit(OP_DECLARE_ABSTRACT, e.pos);
                emitInt(addConst(e), e.pos);

            case ETypedef(name, type, params):
                emit(OP_DECLARE_TYPEDEF, e.pos);
                emitInt(addConst(e), e.pos);

            case EImport(path, alias):
                emit(OP_IMPORT, e.pos);
                emitInt(addConst(e), e.pos);

            case EUsing(path):
                emit(OP_USING, e.pos);
                emitInt(addConst(e), e.pos);

            case EPackage(path):
                emit(OP_PACKAGE, e.pos);
                emitInt(addConst(e), e.pos);

            case EMeta(meta, exprVal):
                compileExpr(exprVal);

            default:
                throw 'Unsupported compile AST node: ${Type.enumConstructor(e.def)}';
        }
    }
}
