package wren;

import wren.AST;

typedef WrenMethod = {args:Array<String>, body:Expr, isStatic:Bool, isConstruct:Bool, isForeign:Bool};

class WrenClass {
    public var name:String;
    public var fields:Array<String>;
    public var methods:Map<String, WrenMethod>;
    public var parent:WrenClass;
    public var isForeign:Bool;
    public var globals:Map<String, Dynamic>;

    public function new(name:String, fields:Array<String>, methods:Map<String, WrenMethod>, ?parent:WrenClass, isForeign:Bool = false, ?globals:Map<String, Dynamic>) {
        this.name = name;
        this.fields = fields;
        this.methods = methods;
        this.parent = parent;
        this.isForeign = isForeign;
        this.globals = globals;
    }
}

class WrenInstance {
    public var cls:WrenClass;
    public var fields:Map<String, Dynamic>;
    public var native:Dynamic;
    
    public function new(cls:WrenClass) {
        this.cls = cls;
        this.fields = new Map();
    }
}

class WrenFn {
    public var args:Array<String>;
    public var body:Expr;
    public var closure:Map<String, Dynamic>;
    public var globals:Map<String, Dynamic>;
    
    public function new(args:Array<String>, body:Expr, closure:Map<String, Dynamic>, ?globals:Map<String, Dynamic>) {
        this.args = args;
        this.body = body;
        this.closure = closure;
        this.globals = globals;
    }
}

enum FiberState {
    Starting;
    Running;
    Suspended;
    Aborted;
    Done;
}

class WrenFiber extends WrenInstance {
    public var stack:Array<Frame> = [];
    public var caller:WrenFiber;
    public var state:FiberState = Starting;
    public var error:Dynamic;

    public function new(?cls:WrenClass) {
        super(cls);
    }
}
