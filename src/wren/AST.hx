package wren;

typedef Pos = {
    var line:Int;
    var col:Int;
    var ?file:String;
}

enum TokenDef {
    TInterpStart;
    TInterpEnd;
    TColon;
    TEof;
    TNewline;
    
    // Keywords
    TAs;
    TBreak;
    TClass;
    TConstruct;
    TContinue;
    TElse;
    TFalse;
    TFor;
    TForeign;
    TIf;
    TImport;
    TIn;
    TIs;
    TNull;
    TReturn;
    TStatic;
    TSuper;
    TThis;
    TTrue;
    TVar;
    TWhile;
    
    // Literals
    TIdent(v:String);
    TInt(v:Int);
    TFloat(v:Float);
    TString(v:String);
    
    // Operators
    TParenOpen;
    TParenClose;
    TBraceOpen;
    TBraceClose;
    TBracketOpen;
    TBracketClose;
    TComma;
    TDot;
    TDotDot;
    TDotDotDot;
    TQuestion;
    TAssign;
    TEqual;
    TNotEqual;
    TLess;
    TGreater;
    TLessEqual;
    TGreaterEqual;
    TPlus;
    TMinus;
    TStar;
    TSlash;
    TPercent;
    TNot;
    TAmpersand;
    TPipe;
    TCaret;
    TTilde;
    TAmpersandAmpersand;
    TPipePipe;
    TShiftLeft;
    TShiftRight;
}

typedef Token = {
    var def:TokenDef;
    var pos:Pos;
}

enum ExprDef {
    EValue(v:Dynamic);
    EIdent(v:String);
    EVar(name:String, ?expr:Expr, isStatic:Bool);
    EAssign(target:Expr, expr:Expr);
    EBinop(op:String, e1:Expr, e2:Expr);
    EUnop(op:String, e:Expr);
    ECall(e:Expr, method:String, args:Array<Expr>); // Wren is message-based: obj.method(args)
    EGet(e:Expr, field:String);
    ESet(e:Expr, field:String, value:Expr);
    EArrayDecl(values:Array<Expr>);
    EMapDecl(keys:Array<Expr>, values:Array<Expr>);
    EBlock(exprs:Array<Expr>, isScope:Bool);
    EClosure(args:Array<String>, body:Expr);

    EIf(cond:Expr, e1:Expr, ?e2:Expr);
    EWhile(cond:Expr, e:Expr);
    EFor(v:String, it:Expr, e:Expr);
    EReturn(?e:Expr);
    EClass(name:String, 
           fields:Array<{name:String, expr:Expr, isStatic:Bool}>, 
           methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool, isConstruct:Bool, isForeign:Bool}>, 
           ?parent:String,
           isForeign:Bool);

    ESuper(method:String, args:Array<Expr>);
    EThis;
    EImport(module:String, imports:Array<{name:String, alias:String}>);
    EInterpolation(exprs:Array<Expr>);
}


typedef Expr = {
    var def:ExprDef;
    var pos:Pos;
}
