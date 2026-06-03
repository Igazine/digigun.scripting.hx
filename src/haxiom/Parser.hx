package haxiom;

import haxiom.AST;

class Parser {
    var tokens:Array<Token>;
    var pos:Int = 0;

    public function new(tokens:Array<Token>) {
        this.tokens = tokens;
    }

    public function parse():Expr {
        var exprs = [];
        while (!is(TEof)) {
            skipNewlines();
            if (is(TEof)) break;
            exprs.push(parseStatement());
            skipNewlines();
        }
        return { def: EBlock(exprs), pos: { line: 1, col: 1 } };
    }

    function parseStatement():Expr {
        skipNewlines();
        var t = peek();
        switch (t.def) {
            case TPackage:
                next();
                var path = [];
                if (!is(TSemicolon)) {
                    path.push(expectIdent());
                    while (match(TDot)) {
                        path.push(expectIdent());
                    }
                }
                match(TSemicolon);
                return mk(EPackage(path), t.pos);
            case TImport:
                next();
                var path = [];
                if (match(TStar)) {
                    path.push("*");
                } else {
                    path.push(expectIdent());
                    while (match(TDot)) {
                        if (match(TStar)) {
                            path.push("*");
                            break;
                        }
                        path.push(expectIdent());
                    }
                }
                var alias = null;
                var nextT = peek();
                switch (nextT.def) {
                    case TIdent("as"):
                        next();
                        alias = expectIdent();
                    default:
                }
                match(TSemicolon);
                return mk(EImport(path, alias), t.pos);
            case TThrow:
                next();
                var e = parseExpr();
                match(TSemicolon);
                return mk(EThrow(e), t.pos);
            case TTry:
                next();
                var tryBody = parseStatement();
                var catches = [];
                while (match(TCatch)) {
                    expect(TParenOpen);
                    var errName = expectIdent();
                    var errType = parseOptType();
                    expect(TParenClose);
                    var catchBody = parseStatement();
                    catches.push({ name: errName, type: errType, body: catchBody });
                }
                return mk(ETry(tryBody, catches), t.pos);
            case TFinal:
                next();
                match(TVar);
                var name = expectIdent();
                var vType = parseOptType();
                var expr = null;
                if (match(TAssign)) {
                    expr = parseExpr();
                }
                match(TSemicolon);
                return mk(EVar(name, vType, expr, true), t.pos);
            case TClass:
                return parseClass();
            case TInterface:
                return parseInterface();
            case TEnum:
                return parseEnum();
            case TVar:
                return parseVar();
            case TIf:
                return parseIf();
            case TWhile:
                return parseWhile();
            case TDo:
                return parseDoWhile();
            case TFor:
                return parseFor();
            case TSwitch:
                return parseSwitch();
            case TReturn:
                next();
                var e = null;
                if (!is(TSemicolon) && !is(TNewline) && !is(TBraceClose)) {
                    e = parseExpr();
                }
                match(TSemicolon);
                return mk(EReturn(e), t.pos);
            case TBreak:
                next();
                match(TSemicolon);
                return mk(EBreak, t.pos);
            case TContinue:
                next();
                match(TSemicolon);
                return mk(EContinue, t.pos);
            case TBraceOpen:
                return parseBlock();
            default:
                var e = parseExpr();
                match(TSemicolon);
                return e;
        }
    }

    function parseBlock():Expr {
        var t = expect(TBraceOpen);
        var exprs = [];
        while (!is(TBraceClose) && !is(TEof)) {
            skipNewlines();
            if (is(TBraceClose)) break;
            exprs.push(parseStatement());
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EBlock(exprs), t.pos);
    }

    function parseClass():Expr {
        var t = expect(TClass);
        var name = expectIdent();
        var parent = null;
        if (match(TExtends)) {
            parent = expectIdent();
        }
        var interfaces = [];
        while (match(TImplements)) {
            interfaces.push(expectIdent());
        }
        expect(TBraceOpen);
        skipNewlines();
        
        var fields = [];
        var methods = [];
        
        while (!is(TBraceClose) && !is(TEof)) {
            var isStatic = false;
            var isPublic = false; // Default member visibility is private
            var isFinal = false;
            
            while (true) {
                if (match(TStatic)) {
                    isStatic = true;
                } else if (match(TPublic)) {
                    isPublic = true;
                } else if (match(TPrivate)) {
                    isPublic = false;
                } else if (match(TFinal)) {
                    isFinal = true;
                } else {
                    break;
                }
            }
            
            skipNewlines();
            var memberT = peek();
            if (memberT.def == TVar || isFinal) {
                if (memberT.def == TVar) {
                    next();
                }
                var fName = expectIdent();
                var prop = null;
                if (match(TParenOpen)) {
                    var getM = expectIdent();
                    expect(TComma);
                    var setM = expectIdent();
                    expect(TParenClose);
                    prop = { get: getM, set: setM };
                }
                var fType = parseOptType();
                var fExpr = null;
                if (match(TAssign)) {
                    fExpr = parseExpr();
                }
                match(TSemicolon);
                fields.push({ name: fName, type: fType, expr: fExpr, isStatic: isStatic, isPublic: isPublic, isFinal: isFinal, property: prop });
            } else if (memberT.def == TFunction) {
                next();
                var mName = "";
                if (match(TNew)) {
                    mName = "new";
                } else {
                    mName = expectIdent();
                }
                var mArgs = parseArgs();
                var mRetType = parseOptType();
                var mBody = parseBlock();
                methods.push({ name: mName, args: mArgs, retType: mRetType, body: mBody, isStatic: isStatic, isPublic: isPublic });
            } else {
                throw 'Unexpected token inside class ${memberT.def} at ${memberT.pos.line}:${memberT.pos.col}';
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EClass(name, fields, methods, parent, interfaces), t.pos);
    }

    function parseVar():Expr {
        var t = expect(TVar);
        var name = expectIdent();
        var vType = parseOptType();
        var expr = null;
        if (match(TAssign)) {
            expr = parseExpr();
        }
        match(TSemicolon);
        return mk(EVar(name, vType, expr), t.pos);
    }

    function parseIf():Expr {
        var t = expect(TIf);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        var e1 = parseStatement();
        var e2 = null;
        skipNewlines();
        if (match(TElse)) {
            e2 = parseStatement();
        }
        return mk(EIf(cond, e1, e2), t.pos);
    }

    function parseWhile():Expr {
        var t = expect(TWhile);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        var body = parseStatement();
        return mk(EWhile(cond, body), t.pos);
    }

    function parseDoWhile():Expr {
        var t = expect(TDo);
        var body = parseStatement();
        skipNewlines();
        expect(TWhile);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        match(TSemicolon);
        return mk(EDoWhile(cond, body), t.pos);
    }

    function parseFor():Expr {
        var t = expect(TFor);
        expect(TParenOpen);
        var vName = expectIdent();
        expect(TIn);
        var iterable = parseExpr();
        expect(TParenClose);
        var body = parseStatement();
        return mk(EFor(vName, iterable, body), t.pos);
    }

    function parseSwitch():Expr {
        var t = expect(TSwitch);
        expect(TParenOpen);
        var expr = parseExpr();
        expect(TParenClose);
        expect(TBraceOpen);
        skipNewlines();
        
        var cases = [];
        var defExpr = null;
        
        while (!is(TBraceClose) && !is(TEof)) {
            var caseT = peek();
            if (match(TCase)) {
                var values = [];
                values.push(parseExpr());
                while (match(TComma)) {
                    values.push(parseExpr());
                }
                expect(TColon);
                skipNewlines();
                var cExprs = [];
                while (!is(TCase) && !is(TDefault) && !is(TBraceClose) && !is(TEof)) {
                    cExprs.push(parseStatement());
                    skipNewlines();
                }
                cases.push({ values: values, expr: mk(EBlock(cExprs), caseT.pos) });
            } else if (match(TDefault)) {
                expect(TColon);
                skipNewlines();
                var dExprs = [];
                while (!is(TCase) && !is(TDefault) && !is(TBraceClose) && !is(TEof)) {
                    dExprs.push(parseStatement());
                    skipNewlines();
                }
                defExpr = mk(EBlock(dExprs), caseT.pos);
            } else {
                throw 'Unexpected token inside switch ${caseT.def}';
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(ESwitch(expr, cases, defExpr), t.pos);
    }

    function parseArgs():Array<{name:String, type:Null<TypeDecl>}> {
        expect(TParenOpen);
        var args = [];
        if (!is(TParenClose)) {
            var name = expectIdent();
            var type = parseOptType();
            args.push({ name: name, type: type });
            while (match(TComma)) {
                var argName = expectIdent();
                var argType = parseOptType();
                args.push({ name: argName, type: argType });
            }
        }
        expect(TParenClose);
        return args;
    }

    // --- Expression Pratt/Operator Precedence Parser ---
    
    function parseExpr():Expr {
        return parseAssign();
    }

    function parseAssign():Expr {
        var e = parseTernary();
        var t = peek();
        if (match(TAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, rhs), t.pos);
        } else if (match(TPlusAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("+", e, rhs), t.pos)), t.pos);
        } else if (match(TMinusAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("-", e, rhs), t.pos)), t.pos);
        } else if (match(TStarAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("*", e, rhs), t.pos)), t.pos);
        } else if (match(TSlashAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("/", e, rhs), t.pos)), t.pos);
        }
        return e;
    }

    function parseTernary():Expr {
        var e = parseCoalesce();
        var t = peek();
        if (match(TQuestion)) {
            var e1 = parseExpr();
            expect(TColon);
            var e2 = parseTernary();
            return mk(EBinop("?", e, mk(EBinop(":", e1, e2), t.pos)), t.pos);
        }
        return e;
    }

    function parseCoalesce():Expr {
        var e = parseOr();
        var t = peek();
        while (match(TDoubleQuestion)) {
            var e2 = parseOr();
            e = mk(EBinop("??", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseOr():Expr {
        var e = parseAnd();
        var t = peek();
        while (match(TOr)) {
            var e2 = parseAnd();
            e = mk(EBinop("||", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseAnd():Expr {
        var e = parseEquality();
        var t = peek();
        while (match(TAnd)) {
            var e2 = parseEquality();
            e = mk(EBinop("&&", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseEquality():Expr {
        var e = parseRelation();
        var t = peek();
        while (is(TEqual) || is(TNotEqual)) {
            var op = match(TEqual) ? "==" : "!=";
            var e2 = parseRelation();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseRelation():Expr {
        var e = parseInterval();
        var t = peek();
        while (is(TLess) || is(TLessEqual) || is(TGreater) || is(TGreaterEqual) || is(TIn)) {
            var op = "";
            if (match(TLess)) op = "<";
            else if (match(TLessEqual)) op = "<=";
            else if (match(TGreater)) op = ">";
            else if (match(TGreaterEqual)) op = ">=";
            else if (match(TIn)) op = "in";
            
            var e2 = parseInterval();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseInterval():Expr {
        var e = parseShift();
        var t = peek();
        while (match(TDotDotDot)) {
            var e2 = parseShift();
            e = mk(EBinop("...", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseShift():Expr {
        var e = parseBitwise();
        var t = peek();
        while (is(TShiftLeft) || is(TShiftRight) || is(TUnsignedShiftRight)) {
            var op = "";
            if (match(TShiftLeft)) op = "<<";
            else if (match(TShiftRight)) op = ">>";
            else if (match(TUnsignedShiftRight)) op = ">>>";
            
            var e2 = parseBitwise();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseBitwise():Expr {
        var e = parseAdditive();
        var t = peek();
        while (is(TBitAnd) || is(TBitOr) || is(TBitXor)) {
            var op = "";
            if (match(TBitAnd)) op = "&";
            else if (match(TBitOr)) op = "|";
            else if (match(TBitXor)) op = "^";
            
            var e2 = parseAdditive();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseAdditive():Expr {
        var e = parseMultiplicative();
        var t = peek();
        while (is(TPlus) || is(TMinus)) {
            var op = match(TPlus) ? "+" : { match(TMinus); "-"; };
            var e2 = parseMultiplicative();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseMultiplicative():Expr {
        var e = parseUnary();
        var t = peek();
        while (is(TStar) || is(TSlash) || is(TPercent)) {
            var op = "";
            if (match(TStar)) op = "*";
            else if (match(TSlash)) op = "/";
            else if (match(TPercent)) op = "%";
            
            var e2 = parseUnary();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseUnary():Expr {
        var t = peek();
        if (match(TNot)) {
            return mk(EUnop("!", parseUnary()), t.pos);
        } else if (match(TMinus)) {
            return mk(EUnop("-", parseUnary()), t.pos);
        } else if (match(TBitNot)) {
            return mk(EUnop("~", parseUnary()), t.pos);
        } else if (match(TIncrement)) {
            return mk(EUnop("++", parseUnary()), t.pos);
        } else if (match(TDecrement)) {
            return mk(EUnop("--", parseUnary()), t.pos);
        }
        return parsePostfix();
    }

    function parsePostfix():Expr {
        var e = parsePrimary();
        while (true) {
            var t = peek();
            if (match(TDot)) {
                var field = expectIdent();
                e = mk(EField(e, field), t.pos);
            } else if (match(TQuestionDot)) {
                var field = expectIdent();
                e = mk(ESafeField(e, field), t.pos);
            } else if (is(TParenOpen)) {
                var args = parseCallArgs();
                e = mk(ECall(e, args), t.pos);
            } else if (match(TBracketOpen)) {
                var index = parseExpr();
                expect(TBracketClose);
                e = mk(EBinop("[]", e, index), t.pos);
            } else if (match(TIncrement)) {
                e = mk(EUnop("post++", e), t.pos);
            } else if (match(TDecrement)) {
                e = mk(EUnop("post--", e), t.pos);
            } else {
                break;
            }
        }
        return e;
    }

    function parseCallArgs():Array<Expr> {
        expect(TParenOpen);
        var args = [];
        if (!is(TParenClose)) {
            args.push(parseExpr());
            while (match(TComma)) {
                args.push(parseExpr());
            }
        }
        expect(TParenClose);
        return args;
    }

    function parsePrimary():Expr {
        var t = peek();
        switch (t.def) {
            case TCast:
                next();
                if (match(TParenOpen)) {
                    var e = parseExpr();
                    if (match(TComma)) {
                        var type = parseType();
                        expect(TParenClose);
                        return mk(ECast(e, type), t.pos);
                    } else {
                        expect(TParenClose);
                        return mk(ECast(e, null), t.pos);
                    }
                } else {
                    return mk(ECast(parsePostfix(), null), t.pos);
                }
            case TInt(v):
                next();
                return mk(EValue(v), t.pos);
            case TFloat(v):
                next();
                return mk(EValue(v), t.pos);
            case TString(v):
                next();
                return mk(EValue(v), t.pos);
            case TTrue:
                next();
                return mk(EValue(true), t.pos);
            case TFalse:
                next();
                return mk(EValue(false), t.pos);
            case TNull:
                next();
                return mk(EValue(null), t.pos);
            case TThis:
                next();
                return mk(EIdent("this"), t.pos);
            case TSuper:
                next();
                return mk(EIdent("super"), t.pos);
            case TNew:
                next();
                return parsePostfix();
            case TIdent(v):
                next();
                // Check if it's an arrow function: arg -> body
                if (match(TArrow)) {
                    var body = parseExpr();
                    return mk(EFunction(null, [{ name: v, type: null }], null, body), t.pos);
                }
                return mk(EIdent(v), t.pos);
            case TParenOpen:
                next();
                // Check for lambda: (a, b) -> body or (a, b):Type -> body
                var checkpoint = pos;
                var lambdaArgs = [];
                var ok = true;
                if (!is(TParenClose)) {
                    if (isIdent(peek())) {
                        var name = expectIdent();
                        var type = parseOptType();
                        lambdaArgs.push({ name: name, type: type });
                        while (match(TComma)) {
                            if (isIdent(peek())) {
                                var argName = expectIdent();
                                var argType = parseOptType();
                                lambdaArgs.push({ name: argName, type: argType });
                            } else {
                                ok = false;
                                break;
                            }
                        }
                    } else {
                        ok = false;
                    }
                }
                if (ok && is(TParenClose)) {
                    next(); // consume TParenClose
                    var retType = parseOptType(false); // skip/parse return type annotation if present
                    if (is(TArrow)) {
                        expect(TArrow);
                        var body = parseExpr();
                        return mk(EFunction(null, lambdaArgs, retType, body), t.pos);
                    }
                }
                // Backtrack if not lambda
                pos = checkpoint;
                var e = parseExpr();
                expect(TParenClose);
                return e;
            case TFunction:
                next();
                var name = null;
                if (isIdent(peek())) {
                    name = expectIdent();
                }
                var args = parseArgs();
                var retType = parseOptType();
                var body = parseBlock();
                return mk(EFunction(name, args, retType, body), t.pos);
            case TBracketOpen:
                next();
                if (is(TBracketClose)) {
                    next();
                    return mk(EArrayDecl([]), t.pos);
                }
                var first = parseExpr();
                if (match(TMapArrow)) {
                    var val = parseExpr();
                    var pairs = [{ key: first, value: val }];
                    while (match(TComma)) {
                        var k = parseExpr();
                        expect(TMapArrow);
                        var v = parseExpr();
                        pairs.push({ key: k, value: v });
                    }
                    expect(TBracketClose);
                    return mk(EMapDecl(pairs), t.pos);
                } else {
                    var values = [first];
                    while (match(TComma)) {
                        values.push(parseExpr());
                    }
                    expect(TBracketClose);
                    return mk(EArrayDecl(values), t.pos);
                }
            case TBraceOpen:
                next();
                skipNewlines();
                // Check if it's object literal or block
                var checkpoint = pos;
                var isObj = false;
                if (isIdent(peek()) && tokens[pos+1].def == TColon) {
                    isObj = true;
                } else if (is(TBraceClose)) {
                    isObj = true;
                }
                pos = checkpoint;
                if (isObj) {
                    var fields = [];
                    if (!is(TBraceClose)) {
                        var fName = expectIdent();
                        expect(TColon);
                        var fExpr = parseExpr();
                        fields.push({ name: fName, expr: fExpr });
                        while (match(TComma)) {
                            skipNewlines();
                            if (is(TBraceClose)) break;
                            var name = expectIdent();
                            expect(TColon);
                            var expr = parseExpr();
                            fields.push({ name: name, expr: expr });
                        }
                    }
                    skipNewlines();
                    expect(TBraceClose);
                    return mk(EObjectDecl(fields), t.pos);
                } else {
                    // It's a block
                    pos = checkpoint;
                    var exprs = [];
                    while (!is(TBraceClose) && !is(TEof)) {
                        skipNewlines();
                        if (is(TBraceClose)) break;
                        exprs.push(parseStatement());
                        skipNewlines();
                    }
                    expect(TBraceClose);
                    return mk(EBlock(exprs), t.pos);
                }
            default:
                throw 'Unexpected token ${t.def} at ${t.pos.line}:${t.pos.col}';
        }
    }

    // --- Parser Helpers ---

    function parseOptType(allowArrow:Bool = true):Null<TypeDecl> {
        if (match(TColon)) {
            return parseType(allowArrow);
        }
        return null;
    }

    function parseType(allowArrow:Bool = true):TypeDecl {
        if (match(TParenOpen)) {
            var args = [];
            while (!is(TParenClose) && !is(TEof)) {
                args.push(parseType(allowArrow));
                if (match(TComma)) {}
            }
            expect(TParenClose);
            if (allowArrow && match(TArrow)) {
                var ret = parseType(allowArrow);
                return TFun(args, ret);
            }
            if (args.length == 1) return args[0];
            throw "Invalid type parenthesization";
        }
        
        var path = [expectIdent()];
        while (match(TDot)) {
            path.push(expectIdent());
        }
        
        var params = [];
        if (match(TLess)) {
            params.push(parseType(allowArrow));
            while (match(TComma)) {
                params.push(parseType(allowArrow));
            }
            expect(TGreater);
        }
        
        var baseType = TPath(path, params);
        
        if (allowArrow && match(TArrow)) {
            var ret = parseType(allowArrow);
            return TFun([baseType], ret);
        }
        
        return baseType;
    }

    inline function peek(offset:Int = 0):Token {
        if (pos + offset >= tokens.length) return tokens[tokens.length - 1];
        return tokens[pos + offset];
    }

    inline function next():Token {
        var t = tokens[pos];
        if (pos < tokens.length - 1) pos++;
        return t;
    }

    inline function is(def:TokenDef):Bool {
        return Type.enumIndex(peek().def) == Type.enumIndex(def);
    }

    inline function match(def:TokenDef):Bool {
        if (is(def)) {
            next();
            return true;
        }
        return false;
    }

    function expect(def:TokenDef):Token {
        var t = peek();
        if (is(def)) {
            next();
            return t;
        }
        throw 'Expected ${def} but got ${t.def} at ${t.pos.line}:${t.pos.col}';
    }

    function isIdent(t:Token):Bool {
        return switch (t.def) {
            case TIdent(_): true;
            default: false;
        };
    }

    function expectIdent():String {
        var t = peek();
        return switch (t.def) {
            case TIdent(v):
                next();
                v;
            default:
                throw 'Expected identifier but got ${t.def} at ${t.pos.line}:${t.pos.col}';
        };
    }

    function skipNewlines() {
        while (match(TNewline)) {}
    }

    inline function mk(def:ExprDef, pos:Pos):Expr {
        return { def: def, pos: pos };
    }

    function parseInterface():Expr {
        var t = expect(TInterface);
        var name = expectIdent();
        var parents = [];
        if (match(TExtends)) {
            parents.push(expectIdent());
            while (match(TComma)) {
                parents.push(expectIdent());
            }
        }
        expect(TBraceOpen);
        skipNewlines();
        var methods = [];
        while (!is(TBraceClose) && !is(TEof)) {
            while (match(TPublic) || match(TPrivate) || match(TStatic)) {}
            expect(TFunction);
            var mName = expectIdent();
            var mArgs = parseArgs();
            var mRetType = parseOptType();
            var mBody = null;
            if (is(TBraceOpen)) {
                mBody = parseStatement();
            } else {
                match(TSemicolon);
            }
            methods.push({ name: mName, args: mArgs, retType: mRetType, body: mBody });
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EInterface(name, methods, parents), t.pos);
    }

    function parseEnum():Expr {
        var t = expect(TEnum);
        var name = expectIdent();
        expect(TBraceOpen);
        skipNewlines();
        var constructors = [];
        while (!is(TBraceClose) && !is(TEof)) {
            var cName = expectIdent();
            var cArgs = null;
            if (match(TParenOpen)) {
                cArgs = [];
                if (!is(TParenClose)) {
                    var aName = expectIdent();
                    var aType = parseOptType();
                    cArgs.push({ name: aName, type: aType });
                    while (match(TComma)) {
                        var nextName = expectIdent();
                        var nextType = parseOptType();
                        cArgs.push({ name: nextName, type: nextType });
                    }
                }
                expect(TParenClose);
            }
            constructors.push({ name: cName, args: cArgs });
            match(TSemicolon);
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EEnum(name, constructors), t.pos);
    }
}
