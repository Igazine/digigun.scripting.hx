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
                
            case EEnum(name, constructors):
                EEnum(name, constructors);
                
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
}
