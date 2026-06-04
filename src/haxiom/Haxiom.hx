package haxiom;

import haxiom.Lexer;
import haxiom.Parser;
import haxiom.Interp;

class Haxiom implements common.IScriptEngine {
    public var interp:Interp;

    public var moduleResolver(get, set):String->String;
    inline function get_moduleResolver() return interp.moduleResolver;
    inline function set_moduleResolver(v) return interp.moduleResolver = v;

    public var importWhitelist(get, set):Array<String>;
    inline function get_importWhitelist() return interp.importWhitelist;
    inline function set_importWhitelist(v) return interp.importWhitelist = v;

    public var errorHandler(get, set):Null<ScriptException->Void>;
    inline function get_errorHandler() return interp.errorHandler;
    inline function set_errorHandler(v) return interp.errorHandler = v;

    public function new() {
        interp = new Interp();
    }

    public function compile(source:String, ?filename:String):haxiom.AST.Expr {
        var lexer = new Lexer(source);
        var tokens = lexer.tokenize();
        if (filename != null) {
            for (t in tokens) {
                t.pos.file = filename;
            }
        }
        var parser = new Parser(tokens);
        var ast = parser.parse();
        return Optimizer.foldConstants(ast);
    }

    public function execute<T>(ast:haxiom.AST.Expr):T {
        var result = interp.execute(ast);
        return cast result;
    }

    public function interpret<T>(source:String, ?onDone:T->Void):T {
        var ast = compile(source);
        var result:T = execute(ast);
        if (onDone != null) onDone(result);
        return result;
    }

    public function setGlobal(name:String, value:Dynamic):Void {
        interp.globals.declare(name, value);
    }
}
