package haxiom;

import haxiom.AST;

class Optimizer {
    public static function foldConstants(expr:Expr):Expr {
        if (expr == null) return null;
        
        var foldedDef = switch (expr.def) {
            case EValue(v):
                EValue(v);
                
            case EIdent(v):
                EIdent(v);
                
            case EVar(name, type, e, isFinal, meta):
                EVar(name, type, e == null ? null : foldConstants(e), isFinal, meta);
                
            case EAssign(target, e):
                EAssign(foldConstants(target), foldConstants(e));
                
            case EBinop(op, e1, e2):
                var e1_f = foldConstants(e1);
                var e2_f = foldConstants(e2);
                
                if (op == "&&") {
                    switch (e1_f.def) {
                        case EValue(v1):
                            if (v1 == false || v1 == null) {
                                EValue(v1);
                            } else {
                                e2_f.def;
                            }
                        default:
                            EBinop(op, e1_f, e2_f);
                    }
                } else if (op == "||") {
                    switch (e1_f.def) {
                        case EValue(v1):
                            if (v1 != false && v1 != null) {
                                EValue(v1);
                            } else {
                                e2_f.def;
                            }
                        default:
                            EBinop(op, e1_f, e2_f);
                    }
                } else if (op == "??") {
                    switch (e1_f.def) {
                        case EValue(v1):
                            if (v1 != null) {
                                EValue(v1);
                            } else {
                                e2_f.def;
                            }
                        default:
                            EBinop(op, e1_f, e2_f);
                    }
                } else if (op == "?") {
                    switch (e1_f.def) {
                        case EValue(condVal):
                            switch (e2_f.def) {
                                case EBinop(":", left, right):
                                    if (condVal != false && condVal != null) {
                                        left.def;
                                    } else {
                                        right.def;
                                    }
                                default:
                                    EBinop(op, e1_f, e2_f);
                            }
                        default:
                            EBinop(op, e1_f, e2_f);
                    }
                } else {
                    switch [e1_f.def, e2_f.def] {
                        case [EValue(v1), EValue(v2)]:
                            try {
                                var binopRes:Dynamic = switch (op) {
                                    case "+":
                                        if (Std.isOfType(v1, String) || Std.isOfType(v2, String)) {
                                            Std.string(v1) + Std.string(v2);
                                        } else {
                                            (v1 : Float) + (v2 : Float);
                                        }
                                    case "-": (v1 : Float) - (v2 : Float);
                                    case "*": (v1 : Float) * (v2 : Float);
                                    case "/":
                                        if ((v2 : Float) == 0) throw "DivByZero";
                                        (v1 : Float) / (v2 : Float);
                                    case "%":
                                        if ((v2 : Float) == 0) throw "ModByZero";
                                        (v1 : Float) % (v2 : Float);
                                    case "==": v1 == v2;
                                    case "!=": v1 != v2;
                                    case "<": (v1 : Float) < (v2 : Float);
                                    case "<=": (v1 : Float) <= (v2 : Float);
                                    case ">": (v1 : Float) > (v2 : Float);
                                    case ">=": (v1 : Float) >= (v2 : Float);
                                    case "&": (v1 : Int) & (v2 : Int);
                                    case "^": (v1 : Int) ^ (v2 : Int);
                                    case "<<": (v1 : Int) << (v2 : Int);
                                    case ">>": (v1 : Int) >> (v2 : Int);
                                    case ">>>": (v1 : Int) >>> (v2 : Int);
                                    default:
                                        throw "UnsupportedOp";
                                };
                                EValue(binopRes);
                            } catch (e:Dynamic) {
                                EBinop(op, e1_f, e2_f);
                            }
                        default:
                            EBinop(op, e1_f, e2_f);
                    }
                }
                
            case EUnop(op, e):
                var e_f = foldConstants(e);
                if (op != "++" && op != "--" && op != "post++" && op != "post--") {
                    switch (e_f.def) {
                        case EValue(val):
                            try {
                                var unopRes:Dynamic = switch (op) {
                                    case "!":
                                        var boolVal = (val != false && val != null);
                                        !boolVal;
                                    case "-":
                                        -(val : Float);
                                    case "~":
                                        ~(val : Int);
                                    default:
                                        throw "UnsupportedOp";
                                };
                                EValue(unopRes);
                            } catch (err:Dynamic) {
                                EUnop(op, e_f);
                            }
                        default:
                            EUnop(op, e_f);
                    }
                } else {
                    EUnop(op, e_f);
                }
                
            case EField(e, field):
                EField(foldConstants(e), field);
                
            case ECall(e, args):
                ECall(foldConstants(e), args.map(foldConstants));
                
            case EArrayDecl(values):
                EArrayDecl(values.map(foldConstants));
                
            case EObjectDecl(fields):
                EObjectDecl(fields.map(f -> {name: f.name, expr: foldConstants(f.expr)}));
                
            case EMapDecl(values):
                EMapDecl(values.map(v -> {key: foldConstants(v.key), value: foldConstants(v.value)}));
                
            case EClass(name, fields, methods, parent, interfaces, params, meta):
                var foldedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    expr: f.expr == null ? null : foldConstants(f.expr),
                    isStatic: f.isStatic,
                    isPublic: f.isPublic,
                    isFinal: f.isFinal,
                    property: f.property,
                    meta: f.meta
                });
                var foldedMethods = methods.map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: foldConstants(m.body),
                    isStatic: m.isStatic,
                    isPublic: m.isPublic,
                    meta: m.meta
                });
                EClass(name, foldedFields, foldedMethods, parent, interfaces, params, meta);
                
            case EBlock(exprs):
                EBlock(exprs.map(foldConstants));
                
            case EFunction(name, args, retType, body):
                EFunction(name, args, retType, foldConstants(body));
                
            case EIf(cond, e1, e2):
                var cond_f = foldConstants(cond);
                switch (cond_f.def) {
                    case EValue(condVal):
                        if (condVal != false && condVal != null) {
                            foldConstants(e1).def;
                        } else if (e2 != null) {
                            foldConstants(e2).def;
                        } else {
                            EValue(null);
                        }
                    default:
                        EIf(cond_f, foldConstants(e1), e2 == null ? null : foldConstants(e2));
                }
                
            case EWhile(cond, e):
                EWhile(foldConstants(cond), foldConstants(e));
                
            case EDoWhile(cond, e):
                EDoWhile(foldConstants(cond), foldConstants(e));
                
            case EFor(v, it, e):
                EFor(v, foldConstants(it), foldConstants(e));
                
            case ESwitch(e, cases, defExpr):
                var foldedCases = cases.map(c -> {
                    values: c.values.map(foldConstants),
                    guard: c.guard == null ? null : foldConstants(c.guard),
                    expr: foldConstants(c.expr)
                });
                ESwitch(foldConstants(e), foldedCases, defExpr == null ? null : foldConstants(defExpr));
                
            case EReturn(e):
                EReturn(e == null ? null : foldConstants(e));
                
            case EBreak:
                EBreak;
                
            case EContinue:
                EContinue;
                
            case EPackage(path):
                EPackage(path);
                
            case EImport(path, alias):
                EImport(path, alias);
                
            case EUsing(path):
                EUsing(path);
                
            case EThrow(e):
                EThrow(foldConstants(e));
                
            case ETry(tryExpr, catches):
                var foldedCatches = catches.map(c -> {
                    pattern: foldConstants(c.pattern),
                    type: c.type,
                    guard: c.guard == null ? null : foldConstants(c.guard),
                    body: foldConstants(c.body)
                });
                ETry(foldConstants(tryExpr), foldedCatches);
                
            case ECast(e, type):
                ECast(foldConstants(e), type);
                
            case EMeta(meta, e):
                EMeta(meta, foldConstants(e));
                
            case EInterface(name, fields, methods, parents, params, meta):
                var foldedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    property: f.property,
                    meta: f.meta
                });
                var foldedMethods = methods.map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: m.body == null ? null : foldConstants(m.body),
                    meta: m.meta
                });
                EInterface(name, foldedFields, foldedMethods, parents, params, meta);
                
            case EEnum(name, constructors, params):
                EEnum(name, constructors, params);
                
            case ESafeField(e, field):
                ESafeField(foldConstants(e), field);
                
            case ENew(type, args):
                ENew(type, args.map(foldConstants));
                
            case EAbstract(name, underlyingType, fields, methods, params, meta):
                var foldedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    expr: f.expr == null ? null : foldConstants(f.expr),
                    isStatic: f.isStatic,
                    isPublic: f.isPublic,
                    isFinal: f.isFinal,
                    property: f.property,
                    meta: f.meta
                });
                var foldedMethods = methods.map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: foldConstants(m.body),
                    isStatic: m.isStatic,
                    isPublic: m.isPublic,
                    meta: m.meta
                });
                EAbstract(name, underlyingType, foldedFields, foldedMethods, params, meta);
                
            case ETypedef(name, type, params):
                ETypedef(name, type, params);
        };
        
        return { def: foldedDef, pos: expr.pos };
    }

    // =========================================================================
    // Dead Code Elimination (DCE)
    // =========================================================================

    /**
     * Entry point for the DCE pass. Returns a pruned copy of the AST with:
     *   - Unreachable statements after return/throw/break/continue removed
     *   - Unused pure local variables removed
     *   - Pure expression-statements (no side effects) removed
     *   - Unused private/static class methods removed
     *
     * Runs after foldConstants so constant-folded branches are already resolved.
     */
    public static function eliminateDeadCode(expr:Expr):Expr {
        if (expr == null) return null;
        return dceExpr(expr);
    }

    static function dceExpr(expr:Expr):Expr {
        if (expr == null) return null;
        var def = switch (expr.def) {

            case EBlock(exprs):
                // Collect usages across the entire block first, then prune
                var usages = new Map<String, Int>();
                for (e in exprs) collectUsages(e, usages);
                var pruned = pruneBlock(exprs, usages);
                EBlock(pruned.map(dceExpr));

            case EClass(name, fields, methods, parent, interfaces, params, meta):
                // Collect all method names referenced anywhere in the class body
                var usages = new Map<String, Int>();
                for (m in methods) {
                    if (m.body != null) collectUsages(m.body, usages);
                }
                for (f in fields) {
                    if (f.expr != null) collectUsages(f.expr, usages);
                }
                // Keep a method if: public, or named "new", or its name appears in usages
                var prunedMethods = methods.filter(m -> {
                    if (m.isPublic) return true;
                    if (m.name == "new") return true;
                    return usages.exists(m.name);
                }).map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: dceExpr(m.body),
                    isStatic: m.isStatic,
                    isPublic: m.isPublic,
                    meta: m.meta
                });
                var prunedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    expr: f.expr == null ? null : dceExpr(f.expr),
                    isStatic: f.isStatic,
                    isPublic: f.isPublic,
                    isFinal: f.isFinal,
                    property: f.property,
                    meta: f.meta
                });
                EClass(name, prunedFields, prunedMethods, parent, interfaces, params, meta);

            case EFunction(name, args, retType, body):
                EFunction(name, args, retType, dceExpr(body));

            case EIf(cond, e1, e2):
                EIf(dceExpr(cond), dceExpr(e1), e2 == null ? null : dceExpr(e2));

            case EWhile(cond, e):
                EWhile(dceExpr(cond), dceExpr(e));

            case EDoWhile(cond, e):
                EDoWhile(dceExpr(cond), dceExpr(e));

            case EFor(v, it, e):
                EFor(v, dceExpr(it), dceExpr(e));

            case ESwitch(e, cases, defExpr):
                var dceCases = cases.map(c -> {
                    values: c.values.map(dceExpr),
                    guard: c.guard == null ? null : dceExpr(c.guard),
                    expr: dceExpr(c.expr)
                });
                ESwitch(dceExpr(e), dceCases, defExpr == null ? null : dceExpr(defExpr));

            case EReturn(e):
                EReturn(e == null ? null : dceExpr(e));

            case EThrow(e):
                EThrow(dceExpr(e));

            case ETry(tryExpr, catches):
                var dceCatches = catches.map(c -> {
                    pattern: dceExpr(c.pattern),
                    type: c.type,
                    guard: c.guard == null ? null : dceExpr(c.guard),
                    body: dceExpr(c.body)
                });
                ETry(dceExpr(tryExpr), dceCatches);

            case EVar(name, type, initExpr, isFinal, meta):
                EVar(name, type, initExpr == null ? null : dceExpr(initExpr), isFinal, meta);

            case EAssign(target, e):
                EAssign(dceExpr(target), dceExpr(e));

            case EBinop(op, e1, e2):
                EBinop(op, dceExpr(e1), dceExpr(e2));

            case EUnop(op, e):
                EUnop(op, dceExpr(e));

            case EField(e, field):
                EField(dceExpr(e), field);

            case ESafeField(e, field):
                ESafeField(dceExpr(e), field);

            case ECall(e, args):
                ECall(dceExpr(e), args.map(dceExpr));

            case ENew(type, args):
                ENew(type, args.map(dceExpr));

            case EArrayDecl(values):
                EArrayDecl(values.map(dceExpr));

            case EObjectDecl(fields):
                EObjectDecl(fields.map(f -> {name: f.name, expr: dceExpr(f.expr)}));

            case EMapDecl(values):
                EMapDecl(values.map(v -> {key: dceExpr(v.key), value: dceExpr(v.value)}));

            case ECast(e, type):
                ECast(dceExpr(e), type);

            case EMeta(meta, e):
                EMeta(meta, dceExpr(e));

            case EAbstract(name, underlyingType, fields, methods, params, meta):
                var dceFields = fields.map(f -> {
                    name: f.name, type: f.type,
                    expr: f.expr == null ? null : dceExpr(f.expr),
                    isStatic: f.isStatic, isPublic: f.isPublic, isFinal: f.isFinal,
                    property: f.property, meta: f.meta
                });
                var dceMethods = methods.map(m -> {
                    name: m.name, args: m.args, retType: m.retType,
                    body: dceExpr(m.body),
                    isStatic: m.isStatic, isPublic: m.isPublic, meta: m.meta
                });
                EAbstract(name, underlyingType, dceFields, dceMethods, params, meta);

            // Leaf / structural nodes — pass through unchanged
            case EValue(_) | EIdent(_) | EBreak | EContinue |
                 EPackage(_) | EImport(_, _) | EUsing(_) |
                 EEnum(_, _, _) | EInterface(_, _, _, _, _, _) | ETypedef(_, _, _):
                expr.def;
        };
        return { def: def, pos: expr.pos };
    }

    /**
     * Recursively collect all identifier names that are READ in expr.
     * Only tracks reads — writes via EVar declarations are NOT counted here.
     * Call-site names, field objects, and loop variables are all counted as reads.
     */
    static function collectUsages(expr:Expr, usages:Map<String, Int>):Void {
        if (expr == null) return;
        switch (expr.def) {
            case EIdent(name):
                usages.set(name, (usages.exists(name) ? usages.get(name) : 0) + 1);

            case EVar(_, _, initExpr, _, _):
                // The variable NAME is not a usage of itself — only recurse into init
                if (initExpr != null) collectUsages(initExpr, usages);

            case EAssign(target, e):
                // The target is being written to, but we still need to track field/subscript reads
                collectUsages(target, usages);
                collectUsages(e, usages);

            case EBlock(exprs):
                for (e in exprs) collectUsages(e, usages);

            case EBinop(_, e1, e2):
                collectUsages(e1, usages);
                collectUsages(e2, usages);

            case EUnop(_, e):
                collectUsages(e, usages);

            case EField(e, _) | ESafeField(e, _):
                collectUsages(e, usages);

            case ECall(e, args):
                collectUsages(e, usages);
                for (a in args) collectUsages(a, usages);

            case ENew(_, args):
                for (a in args) collectUsages(a, usages);

            case EIf(cond, e1, e2):
                collectUsages(cond, usages);
                collectUsages(e1, usages);
                if (e2 != null) collectUsages(e2, usages);

            case EWhile(cond, e) | EDoWhile(cond, e):
                collectUsages(cond, usages);
                collectUsages(e, usages);

            case EFor(v, it, e):
                collectUsages(it, usages);
                collectUsages(e, usages);
                // v is a loop binding, not an external usage

            case ESwitch(e, cases, defExpr):
                collectUsages(e, usages);
                for (c in cases) {
                    for (val in c.values) collectUsages(val, usages);
                    if (c.guard != null) collectUsages(c.guard, usages);
                    collectUsages(c.expr, usages);
                }
                if (defExpr != null) collectUsages(defExpr, usages);

            case EReturn(e):
                if (e != null) collectUsages(e, usages);

            case EThrow(e):
                collectUsages(e, usages);

            case ETry(tryExpr, catches):
                collectUsages(tryExpr, usages);
                for (c in catches) {
                    if (c.guard != null) collectUsages(c.guard, usages);
                    collectUsages(c.body, usages);
                }

            case EArrayDecl(values):
                for (v in values) collectUsages(v, usages);

            case EObjectDecl(fields):
                for (f in fields) collectUsages(f.expr, usages);

            case EMapDecl(values):
                for (v in values) { collectUsages(v.key, usages); collectUsages(v.value, usages); }

            case ECast(e, _):
                collectUsages(e, usages);

            case EMeta(_, e):
                collectUsages(e, usages);

            case EFunction(_, _, _, body):
                collectUsages(body, usages);

            case EClass(_, fields, methods, _, _, _, _):
                for (f in fields) if (f.expr != null) collectUsages(f.expr, usages);
                for (m in methods) if (m.body != null) collectUsages(m.body, usages);

            default:
                // EValue, EBreak, EContinue, EPackage, EImport, EEnum, EInterface, ETypedef — no sub-exprs
        }
    }

    /**
     * Returns true if an expression has no observable side effects:
     *   - Pure literals: EValue, EIdent (just a read)
     *   - Pure arithmetic/logical: EBinop of pure operands (no calls, no assignment ops)
     *   - Pure unary: EUnop (non-mutating operators only)
     *   - Pure field/index reads: EField, ESafeField
     *   - Pure array/object/map literals of pure elements
     *
     * Returns false (NOT pure) for:
     *   - ECall, ENew (may have side effects)
     *   - EAssign, EUnop(++/--) (mutating)
     *   - EThrow, EReturn (control flow)
     */
    static function isPure(expr:Expr):Bool {
        if (expr == null) return true;
        return switch (expr.def) {
            case EValue(_): true;
            case EIdent(_): true;
            case EField(e, _) | ESafeField(e, _): isPure(e);
            case EBinop(op, e1, e2):
                // Assignment operators are not pure
                if (op == "=" || StringTools.endsWith(op, "=")) false;
                else isPure(e1) && isPure(e2);
            case EUnop(op, e):
                // ++ and -- are mutating
                if (op == "++" || op == "--" || op == "post++" || op == "post--") false;
                else isPure(e);
            case EArrayDecl(values): values.length == 0 || values.filter(v -> !isPure(v)).length == 0;
            case EObjectDecl(fields): fields.filter(f -> !isPure(f.expr)).length == 0;
            // Typed cast (cast(x, T)) can throw — NOT pure. Unsafe cast (cast x) without type is pure.
            case ECast(e, type): type == null && isPure(e);
            case EMeta(_, e): isPure(e);
            // Anything else (ECall, ENew, EAssign, EThrow, EReturn, blocks, loops) is NOT pure
            default: false;
        };
    }

    /**
     * Prune a flat list of block statements:
     *   1. Stop after the first terminal statement (return/throw/break/continue).
     *   2. Remove EVar declarations where the declared name is never read (usages == 0)
     *      AND the initializer expression is pure.
     *   3. Remove pure expression-statements (no side effects, result discarded).
     *      SAFETY: Never prune the last expression in a block — it may be the yield value
     *      of a comprehension or block-expression. Never prune bare EIdent reads — they
     *      commonly serve as yield values inside for/while comprehension bodies.
     */
    static function pruneBlock(exprs:Array<Expr>, usages:Map<String, Int>):Array<Expr> {
        var result:Array<Expr> = [];
        for (i in 0...exprs.length) {
            var expr = exprs[i];
            var isLast = (i == exprs.length - 1);
            switch (expr.def) {
                // Terminal statements: include this one and stop
                case EReturn(_) | EThrow(_) | EBreak | EContinue:
                    result.push(expr);
                    return result; // everything after is unreachable

                // Unused pure variable declaration: eliminate ONLY if:
                //   - it has NO type annotation (untyped init has no runtime type check), AND
                //   - the init is pure (no side effects)
                // If there's a type annotation, the runtime validates the init against the
                // declared type, which can throw — so we must NOT eliminate it.
                case EVar(name, declaredType, initExpr, _, _):
                    var useCount = usages.exists(name) ? usages.get(name) : 0;
                    var isTyped = declaredType != null;
                    var initIsPure = initExpr == null || isPure(initExpr);
                    if (useCount == 0 && !isTyped && initIsPure) {
                        // Eliminated — untyped, unused, pure init
                    } else {
                        result.push(expr);
                    }

                // Bare identifier — could be a comprehension/block yield value; always keep
                case EIdent(_):
                    result.push(expr);

                // Pure expression used as a statement: eliminate only if not last
                // (last expression in a block may be the block's return value)
                default:
                    if (!isLast && isPure(expr)) {
                        // Eliminated — pure expression discarded as statement (not last)
                    } else {
                        result.push(expr);
                    }
            }
        }
        return result;
    }
}
