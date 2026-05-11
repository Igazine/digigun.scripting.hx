package wren;

import wren.AST;
import wren.WrenTypes;


class Frame {
    public static var pool:Array<Frame> = [];

    public var expr:Expr;
    public var step:Int = 0;
    public var results:Array<Dynamic> = [];
    public var locals:Map<String, Dynamic>;
    public var obj:Dynamic = null;
    public var isBlock:Bool = false;
    public var isFunction:Bool = false;
    public var isConstruct:Bool;
    public var methodName:String;
    public var methodClass:WrenClass;
    public var globals:Map<String, Dynamic>;

    public function new() {}

    public static function get(expr:Expr, locals:Map<String, Dynamic>, isBlock:Bool = false, isFunction:Bool = false, isConstruct:Bool = false, methodName:String = null, methodClass:WrenClass = null, globals:Map<String, Dynamic> = null):Frame {
        var f = pool.length > 0 ? pool.pop() : new Frame();
        f.expr = expr;
        f.locals = locals;
        f.globals = globals;
        f.step = 0;
        f.results = [];
        f.isBlock = isBlock;
        f.isFunction = isFunction;
        f.isConstruct = isConstruct;
        f.methodName = methodName;
        f.methodClass = methodClass;
        f.obj = null;
        return f;
    }

    public function release() {
        this.expr = null;
        this.locals = null;
        this.obj = null;
        this.methodName = null;
        if (this.results.length > 0) this.results = [];

        pool.push(this);
    }

}
