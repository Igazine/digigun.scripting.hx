package haxiom;

typedef Pos = {
    var line:Int;
    var col:Int;
    var ?file:String;
}

enum TokenDef {
    TEof;
    TNewline;
    TIdent(v:String);
    TInt(v:Int);
    TFloat(v:Float);
    TString(v:String);
    
    // Keywords
    TBreak;
    TCase;
    TClass;
    TContinue;
    TDefault;
    TDo;
    TElse;
    TExtends;
    TFalse;
    TFor;
    TFunction;
    TIf;
    TIn;
    TNew;
    TNull;
    TPrivate;
    TPublic;
    TReturn;
    TStatic;
    TSuper;
    TSwitch;
    TThis;
    TTrue;
    TVar;
    TWhile;
    TImport;
    TTry;
    TCatch;
    TThrow;
    TFinal;
    TCast;
    TPackage;
    TInterface;
    TImplements;
    TEnum;
    
    // Operators
    TPlus;
    TMinus;
    TStar;
    TSlash;
    TPercent;
    TIncrement;
    TDecrement;
    
    TAssign;
    TPlusAssign;
    TMinusAssign;
    TStarAssign;
    TSlashAssign;
    TPercentAssign;
    
    TEqual;
    TNotEqual;
    TLess;
    TLessEqual;
    TGreater;
    TGreaterEqual;
    
    TAnd;
    TOr;
    TNot;
    
    TBitAnd;
    TBitOr;
    TBitXor;
    TBitNot;
    TShiftLeft;
    TShiftRight;
    TUnsignedShiftRight;
    
    TQuestion;
    TColon;
    TDot;
    TComma;
    TSemicolon;
    
    TParenOpen;
    TParenClose;
    TBracketOpen;
    TBracketClose;
    TBraceOpen;
    TBraceClose;
    
    TMapArrow; // =>
    TArrow;    // ->
    TDotDotDot;
    TDoubleQuestion;
    TQuestionDot;
}

typedef Token = {
    var def:TokenDef;
    var pos:Pos;
}

enum TypeDecl {
    TPath(path:Array<String>, params:Array<TypeDecl>);
    TFun(args:Array<TypeDecl>, ret:TypeDecl);
    TAnonymous(fields:Array<{name:String, type:TypeDecl}>);
}

enum ExprDef {
    EValue(v:Dynamic);
    EIdent(v:String);
    EVar(name:String, type:Null<TypeDecl>, ?expr:Expr, ?isFinal:Bool);
    EAssign(target:Expr, expr:Expr);
    EBinop(op:String, e1:Expr, e2:Expr);
    EUnop(op:String, e:Expr);
    
    EField(e:Expr, field:String);
    ECall(e:Expr, args:Array<Expr>);
    
    EArrayDecl(values:Array<Expr>);
    EObjectDecl(fields:Array<{name:String, expr:Expr}>);
    EMapDecl(values:Array<{key:Expr, value:Expr}>);
    
    EClass(name:String, 
           fields:Array<{name:String, type:Null<TypeDecl>, expr:Expr, isStatic:Bool, isPublic:Bool, isFinal:Bool, ?property:{get:String, set:String}}>, 
           methods:Array<{name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, body:Expr, isStatic:Bool, isPublic:Bool}>, 
           ?parent:String,
           ?interfaces:Array<String>);

    EBlock(exprs:Array<Expr>);
    EFunction(?name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, body:Expr);
    
    EIf(cond:Expr, e1:Expr, ?e2:Expr);
    EWhile(cond:Expr, e:Expr);
    EDoWhile(cond:Expr, e:Expr);
    EFor(v:String, it:Expr, e:Expr);
    ESwitch(expr:Expr, cases:Array<{values:Array<Expr>, expr:Expr}>, ?defExpr:Expr);
    EReturn(?e:Expr);
    EBreak;
    EContinue;
    
    EPackage(path:Array<String>);
    EImport(path:Array<String>, ?alias:String);
    EThrow(expr:Expr);
    ETry(tryExpr:Expr, catches:Array<{name:String, type:Null<TypeDecl>, body:Expr}>);
    ECast(expr:Expr, ?type:TypeDecl);
    EInterface(name:String, methods:Array<{name:String, args:Array<{name:String, type:Null<TypeDecl>}>, retType:Null<TypeDecl>, ?body:Null<Expr>}>, ?parents:Array<String>);
    EEnum(name:String, constructors:Array<{name:String, args:Null<Array<{name:String, type:Null<TypeDecl>}>>}>);
    ESafeField(e:Expr, field:String);
}

typedef Expr = {
    var def:ExprDef;
    var pos:Pos;
}
