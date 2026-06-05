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
        var fileInfo = filename != null ? filename : "script";
        interp.lastSource = source;
        try {
            var lexer = new Lexer(source, fileInfo);
            var tokens = lexer.tokenize();
            var parser = new Parser(tokens, fileInfo);
            var ast = parser.parse();
            return Optimizer.foldConstants(ast);
        } catch (e:ScriptException) {
            if (errorHandler != null) {
                errorHandler(e);
                return null;
            }
            throw e;
        } catch (e:CompileException) {
            var codeFrame = ScriptException.makeCodeFrame(source, e.line, e.col, e.file);
            var formatted = "Compile Error: " + e.message + " at " + e.file + ":" + e.line + ":" + e.col;
            if (codeFrame != "") {
                formatted += "\n" + codeFrame;
            }
            var se = new ScriptException(e.message, [], formatted, e.line, e.col, e.file);
            if (errorHandler != null) {
                errorHandler(se);
                return null;
            }
            throw se;
        } catch (err:Dynamic) {
            var se = new ScriptException(Std.string(err), [], "Compile Error: " + Std.string(err), 1, 1, fileInfo);
            if (errorHandler != null) {
                errorHandler(se);
                return null;
            }
            throw se;
        }
    }

    public function execute<T>(ast:haxiom.AST.Expr):T {
        var result = interp.execute(ast);
        return cast result;
    }

    public function interpret<T>(source:String, ?onDone:T->Void):T {
        var ast = compile(source);
        if (ast == null) return null;
        var result:T = execute(ast);
        if (onDone != null) onDone(result);
        return result;
    }

    public function setGlobal(name:String, value:Dynamic):Void {
        interp.globals.declare(name, value);
    }
}
