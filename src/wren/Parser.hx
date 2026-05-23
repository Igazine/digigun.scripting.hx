package wren;

import wren.AST;

class Parser {
    var tokens:Array<Token>;
    var pos:Int = 0;
    var scopes:Array<Map<String, Bool>> = [new Map()];

    public function new(tokens:Array<Token>) {
        this.tokens = tokens;
    }

    function pushScope() {
        scopes.push(new Map());
    }

    function popScope() {
        scopes.pop();
    }

    function declareVar(name:String) {
        if (scopes.length > 0) {
            scopes[scopes.length - 1].set(name, true);
        }
    }

    function isVarDeclared(name:String):Bool {
        var i = scopes.length - 1;
        while (i >= 0) {
            if (scopes[i].exists(name)) return true;
            i--;
        }
        return false;
    }

    function peek():Token return tokens[pos];
    function next():Token return tokens[pos++];

    function is(t:TokenDef):Bool {
        var p = peek().def;
        if (Type.enumIndex(p) != Type.enumIndex(t)) return false;
        switch [p, t] {
            case [TIdent(v1), TIdent(v2)]: return v2 == null || v1 == v2;
            default: return true;
        }
    }

    function expect(t:TokenDef) {
        if (is(t)) return next();
        var n = peek();
        throw 'Error at line ${n.pos.line}, col ${n.pos.col}: Expected $t but got ${n.def}';
    }

    function match(t:TokenDef):Bool {
        if (is(t)) {
            next();
            return true;
        }
        return false;
    }

    function skipNewlines() {
        while (is(TNewline)) next();
    }

    inline function mk(def:ExprDef, p:Pos):Expr {
        return { def: def, pos: p };
    }

    public function parse():Expr {
        var exprs = [];
        skipNewlines();
        while (!is(TEof)) {
            exprs.push(parseStatement());
            skipNewlines();
        }
        return mk(EBlock(exprs, false), { line: 1, col: 1 });
    }

    function parseStatement():Expr {
        skipNewlines();
        var t = peek();
        switch (t.def) {
            case TImport:
                next();
                var mod = switch(next().def) { case TString(v): v; default: throw "Expected module name"; };
                var imports = [];
                if (match(TFor)) {
                    while (true) {
                        var name = switch(next().def) { case TIdent(v): v; default: throw "Expected name"; };
                        var alias = name;
                        if (match(TAs)) {
                            alias = switch(next().def) { case TIdent(v): v; default: throw "Expected alias"; };
                        }
                        imports.push({ name: name, alias: alias });
                        if (match(TComma)) continue;
                        else break;
                    }
                }
                return mk(EImport(mod, imports), t.pos);
            case TVar:

                next();
                var name = switch(next().def) { case TIdent(v): v; default: throw "Expected identifier"; };
                declareVar(name);
                var expr = null;
                if (match(TAssign)) {
                    expr = parseExpr();
                }
                return mk(EVar(name, expr, false), t.pos);
            case TIf:
                next();
                expect(TParenOpen);
                var cond = parseExpr();
                expect(TParenClose);
                var e1 = parseStatement();
                var e2 = null;
                if (match(TElse)) {
                    e2 = parseStatement();
                }
                return mk(EIf(cond, e1, e2), t.pos);
            case TWhile:
                next();
                expect(TParenOpen);
                var cond = parseExpr();
                expect(TParenClose);
                var body = parseStatement();
                return mk(EWhile(cond, body), t.pos);
            case TFor:
                next();
                expect(TParenOpen);
                var vName = switch(next().def) { case TIdent(v): v; default: throw "Expected identifier"; };
                expect(TIn);
                var seq = parseExpr();
                expect(TParenClose);
                pushScope();
                declareVar(vName);
                var body = parseStatement();
                popScope();
                return mk(EFor(vName, seq, body), t.pos);
            case TReturn:

                next();
                var expr = null;
                if (!is(TNewline) && !is(TBraceClose) && !is(TEof)) {
                    expr = parseExpr();
                }
                return mk(EReturn(expr), t.pos);
            case TClass:
                return parseClass(false);
            case TForeign:
                var fpos = t.pos;
                next(); // consume foreign
                if (is(TClass)) {
                    return parseClass(true);
                }
                throw 'Expected class after foreign at ${fpos.line}:${fpos.col}, but got ${peek().def}';


            case TBraceOpen:
                next();
                pushScope();
                var exprs = [];
                skipNewlines();
                while (!is(TBraceClose) && !is(TEof)) {
                    exprs.push(parseStatement());
                    skipNewlines();
                }
                expect(TBraceClose);
                popScope();
                return mk(EBlock(exprs, true), t.pos);
            case TBreak:
                next();
                return mk(EBreak, t.pos);
            case TContinue:
                next();
                return mk(EContinue, t.pos);
            default:
                return parseExpr();
        }
    }

    function parseClass(isForeign:Bool = false):Expr {

        var t = next(); // class
        var name = switch(next().def) { case TIdent(v): v; default: throw "Expected class name"; };
        var parent = null;
        if (is(TIdent("extends"))) { // Wren uses 'extends' or nothing? Actually Wren uses 'class Name is Parent'
            // Wait, Wren uses 'is' for inheritance
        }
        if (match(TIs)) {
            parent = switch(next().def) { case TIdent(v): v; default: throw "Expected parent class name"; };
        }
        
        expect(TBraceOpen);
        skipNewlines();
        var fields = [];
        var methods = [];
        
        while (!is(TBraceClose) && !is(TEof)) {
            var isStatic = match(TStatic);
            var memberT = peek();
            
            if (match(TConstruct) || (is(TForeign) && tokens[pos+1].def == TConstruct)) {
                var isForeign = match(TForeign);
                if (isForeign) match(TConstruct);
                var cName = "new";
                if (is(TIdent(null))) cName = switch(next().def) { case TIdent(v): v; default: "new"; };
                var args = parseArgs();
                if (match(TForeign)) isForeign = true;
                pushScope();
                if (args != null) {
                    for (arg in args) declareVar(arg);
                }
                var body = null;
                if (!isForeign && (is(TBraceOpen) || !is(TNewline))) {
                    body = parseStatement();
                }
                popScope();
                methods.push({ name: cName, args: args, body: body, isStatic: false, isConstruct: true, isForeign: isForeign || (body == null) });
            } else if (match(TForeign)) {
                var isMStatic = match(TStatic);
                var mName = switch(next().def) { case TIdent(v): v; default: throw "Expected method name"; };
                var mArgs = null;
                if (is(TParenOpen)) mArgs = parseArgs();
                methods.push({ name: mName, args: mArgs, body: null, isStatic: isMStatic || isStatic, isConstruct: false, isForeign: true });
            } else if (is(TIdent(null))) {
                var mName = switch(next().def) { case TIdent(v): v; default: null; };
                var args = null;
                if (match(TAssign)) {
                    // It's a setter: name=(val)
                    args = parseArgs();
                    mName += "=";
                } else if (is(TParenOpen)) {
                    args = parseArgs();
                }
                pushScope();
                if (args != null) {
                    for (arg in args) declareVar(arg);
                }
                var body = null;
                // If it's a foreign class and we don't see a body, it might be foreign?
                // Actually, Wren requires 'foreign' keyword.
                skipNewlines();
                if (is(TBraceOpen)) {
                    body = parseStatement();
                } else if (is(TNewline)) {
                    // No body? Error unless foreign.
                    // But we already checked TForeign.
                    // Let's assume it's a single-line statement body if it's not a newline.
                } else {
                    body = parseStatement();
                }
                popScope();
                methods.push({ name: mName, args: args, body: body, isStatic: isStatic, isConstruct: false, isForeign: false });
            }

            skipNewlines();

        }
        expect(TBraceClose);
        return mk(EClass(name, fields, methods, parent, isForeign), t.pos);

    }

    function parseArgs():Array<String> {
        expect(TParenOpen);
        var args = [];
        if (!is(TParenClose)) {
            while (true) {
                args.push(switch(next().def) { case TIdent(v): v; default: throw "Expected argument name"; });
                if (match(TComma)) continue;
                else break;
            }
        }
        expect(TParenClose);
        return args;
    }

    function parseExpr():Expr {
        return parseAssign();
    }

    function parseAssign():Expr {
        var e = parseTernary();
        if (match(TAssign)) {
            var val = parseAssign();
            switch (e.def) {
                case ECall(obj, "[]", args):
                    args.push(val);
                    return mk(ECall(obj, "[]=", args), e.pos);
                case ECall(obj, method, args) if (args.length == 0):
                    // Desugar obj.name = val to obj.name=(val)
                    return mk(ECall(obj, method + "=", [val]), e.pos);
                case EIdent(v):
                    // If it's a field (starting with _) or a lexically declared variable, it's a direct assignment
                    if (v.charAt(0) == "_" || isVarDeclared(v)) return mk(EAssign(e, val), e.pos);
                    // Otherwise it's a setter call on 'this'
                    return mk(ECall(mk(EThis, e.pos), v + "=", [val]), e.pos);
                default:
                    return mk(EAssign(e, val), e.pos);
            }

        }
        return e;
    }

    function parseTernary():Expr {
        var e = parseBinary(0);
        if (match(TQuestion)) {
            var e1 = parseTernary();
            expect(TColon);
            var e2 = parseTernary();
            return mk(ETernary(e, e1, e2), e.pos);
        }
        return e;
    }


    function parseBinary(prec:Int):Expr {
        var e = parseUnary();
        while (true) {

            var op = getOp(peek().def);
            if (op == null) break;
            var p = getPrecedence(op);
            if (p <= prec) break;
            next();
            if (op == "&&") {
                e = mk(ELogicalAnd(e, parseBinary(p)), e.pos);
            } else if (op == "||") {
                e = mk(ELogicalOr(e, parseBinary(p)), e.pos);
            } else {
                e = mk(EBinop(op, e, parseBinary(p)), e.pos);
            }
        }
        return e;
    }

    function parseUnary():Expr {
        if (match(TNot) || match(TMinus) || match(TTilde)) {
            var op = tokens[pos-1].def == TNot ? "!" : (tokens[pos-1].def == TMinus ? "-" : "~");
            return mk(EUnop(op, parseUnary()), tokens[pos-1].pos);
        }
        return parsePrimary();
    }


    function getOp(t:TokenDef):String {

        return switch (t) {
            case TPlus: "+";
            case TMinus: "-";
            case TStar: "*";
            case TSlash: "/";
            case TEqual: "==";
            case TNotEqual: "!=";
            case TLess: "<";
            case TGreater: ">";
            case TLessEqual: "<=";
            case TGreaterEqual: ">=";
            case TPercent: "%";
            case TIs: "is";
            case TDotDot: "..";
            case TDotDotDot: "...";
            case TAmpersand: "&";
            case TPipe: "|";
            case TCaret: "^";
            case TAmpersandAmpersand: "&&";
            case TPipePipe: "||";
            case TShiftLeft: "<<";
            case TShiftRight: ">>";
            default: null;




        }
    }

    function getPrecedence(op:String):Int {
        return switch (op) {
            case "||": 5;
            case "&&": 6;
            case "==", "!=": 10;
            case "<", ">", "<=", ">=", "is": 20;
            case "..", "...": 25;
            case "|": 30;
            case "^": 40;
            case "&": 50;
            case "<<", ">>": 60;
            case "+", "-": 70;
            case "*", "/", "%": 80;
            default: 0;

        }
    }




    function parseBraceExpr(t:Token):Expr {
        var start = pos;
        skipNewlines();
        if (is(TBraceClose)) {
            next();
            return mk(EMapDecl([], []), t.pos);
        }
        
        // Check for closure parameters: |a, b|
        var closureArgs = [];
        if (match(TPipe)) {
            while (!match(TPipe)) {
                closureArgs.push(switch(next().def) { case TIdent(v): v; default: throw "Expected argument name"; });
                match(TComma);
            }
        }

        // If it's a statement block starting with a keyword or newline, parse it as a block of statements.
        if (is(TNewline) || is(TIf) || is(TWhile) || is(TFor) || is(TReturn) || is(TVar)) {
            pushScope();
            for (arg in closureArgs) declareVar(arg);
            var exprs = [];
            while (!is(TBraceClose) && !is(TEof)) {
                exprs.push(parseStatement());
                skipNewlines();
            }
            expect(TBraceClose);
            popScope();
            return mk(EClosure(closureArgs, mk(EBlock(exprs, true), t.pos)), t.pos);
        }

        pushScope();
        for (arg in closureArgs) declareVar(arg);
        var k = parseExpr();
        if (match(TColon)) {
            popScope(); // Pop the scope since it's a map declaration, not a block/closure!
            var keys = [k];
            var vals = [parseExpr()];
            while (match(TComma)) {
                keys.push(parseExpr());
                expect(TColon);
                vals.push(parseExpr());
            }
            expect(TBraceClose);
            return mk(EMapDecl(keys, vals), t.pos);
        } else {
            var exprs = [k];
            skipNewlines();
            while (!is(TBraceClose) && !is(TEof)) {
                exprs.push(parseStatement());
                skipNewlines();
            }
            expect(TBraceClose);
            popScope();
            return mk(EClosure(closureArgs, mk(EBlock(exprs, true), t.pos)), t.pos);
        }
    }

    function parsePrimary():Expr {
        var t = next();
        switch (t.def) {
            case TInt(v): return parseAccess(mk(EValue(v), t.pos));
            case TFloat(v): return parseAccess(mk(EValue(v), t.pos));

            case TString(v):
                var exprs = [mk(EValue(v), t.pos)];
                while (is(TInterpStart)) {
                    next();
                    exprs.push(parseExpr());
                    expect(TInterpEnd);
                    if (is(TString(null))) {
                        var t2 = next();
                        switch(t2.def) { case TString(v2): exprs.push(mk(EValue(v2), t2.pos)); default: };
                    }
                }
                if (exprs.length > 1) return parseAccess(mk(EInterpolation(exprs), t.pos));
                return parseAccess(mk(EValue(v), t.pos));


            case TTrue: return parseAccess(mk(EValue(true), t.pos));
            case TFalse: return parseAccess(mk(EValue(false), t.pos));
            case TNull: return parseAccess(mk(EValue(null), t.pos));
            case TThis: return parseAccess(mk(EThis, t.pos));


            case TIdent(v): 
                var e = if (v.charAt(0) == "_") {
                    mk(EGet(mk(EThis, t.pos), v), t.pos);
                } else {
                    mk(EIdent(v), t.pos);
                };
                return parseAccess(e);


            case TParenOpen:
                var e = parseExpr();
                expect(TParenClose);
                return parseAccess(e);
            case TSuper:
                var method = "new";
                if (match(TDot)) {
                    method = switch(next().def) { case TIdent(v): v; default: throw "Expected method name"; };
                }
                var args = null;
                if (is(TParenOpen)) args = parseCallArgs();
                return mk(ESuper(method, args), t.pos);


            case TBracketOpen:
                var values = [];
                skipNewlines();
                if (!is(TBracketClose)) {
                    while (true) {
                        values.push(parseExpr());
                        if (match(TComma)) continue;
                        else break;
                    }
                }
                expect(TBracketClose);
                return parseAccess(mk(EArrayDecl(values), t.pos));
            case TBraceOpen:
                return parseAccess(parseBraceExpr(t));




            default: throw 'Unexpected token ${t.def} at ${t.pos.line}:${t.pos.col}';
        }
    }

    function parseAccess(e:Expr):Expr {
        while (true) {
            if (match(TDot)) {
                var method = switch(next().def) { case TIdent(v): v; default: throw "Expected method name"; };
                var args = null;
                if (is(TParenOpen)) args = parseCallArgs();
                e = mk(ECall(e, method, args), e.pos);
            } else if (match(TBracketOpen)) {
                var args = [];
                if (!is(TBracketClose)) {
                    while (true) {
                        args.push(parseExpr());
                        if (match(TComma)) continue;
                        else break;
                    }
                }
                expect(TBracketClose);
                e = mk(ECall(e, "[]", args), e.pos);
            } else if (is(TParenOpen)) {
                var args = parseCallArgs();
                switch (e.def) {
                    case EIdent(v):
                        e = mk(ECall(mk(EThis, e.pos), v, args), e.pos);
                    default:
                        e = mk(ECall(e, "call", args), e.pos);
                }
            } else if (is(TBraceOpen)) {
                var block = parseBraceExpr(next());
                switch (e.def) {
                    case ECall(obj, method, args):
                        if (args == null) {
                            e = mk(ECall(obj, method, [block]), e.pos);
                        } else {
                            args.push(block);
                        }
                    case EIdent(v):
                        e = mk(ECall(mk(EThis, e.pos), v, [block]), e.pos);
                    default:
                        e = mk(ECall(e, "call", [block]), e.pos);
                }
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
            while (true) {
                args.push(parseExpr());
                if (match(TComma)) continue;
                else break;
            }
        }
        expect(TParenClose);
        return args;
    }
}
