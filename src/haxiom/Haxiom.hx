package haxiom;

import haxiom.Lexer;
import haxiom.Parser;
import haxiom.Interp;

class Haxiom implements common.IScriptEngine {
    public var interp:Interp;
    public var enableAstCache:Bool = true;
    public var astCache:Map<String, haxiom.AST.Expr> = new Map();
    var astCacheSize:Int = 0;

    public var moduleResolver(get, set):String->String;
    inline function get_moduleResolver() return interp.moduleResolver;
    inline function set_moduleResolver(v) return interp.moduleResolver = v;

    public var importWhitelist(get, set):Array<String>;
    inline function get_importWhitelist() return interp.importWhitelist;
    inline function set_importWhitelist(v) return interp.importWhitelist = v;

    public var errorHandler(get, set):Null<ScriptException->Void>;
    inline function get_errorHandler() return interp.errorHandler;
    inline function set_errorHandler(v) return interp.errorHandler = v;

    public var useVM(get, set):Bool;
    inline function get_useVM() return interp.useVM;
    inline function set_useVM(v) return interp.useVM = v;

    public var preprocessorFlags(get, never):Map<String, Bool>;
    inline function get_preprocessorFlags() return interp.preprocessorFlags;

    public var debugMode(get, set):Bool;
    inline function get_debugMode() return interp.debugMode;
    inline function set_debugMode(v) return interp.debugMode = v;

    public function new() {
        interp = new Interp();
        FFI.exposedModules.set("haxiom.AST", ["haxiom.ExprDef", "haxiom.TypeDecl"]);
        FFI.registerEnum(this, "haxiom.ExprDef", haxiom.AST.ExprDef);
        FFI.registerEnum(this, "haxiom.TypeDecl", haxiom.AST.TypeDecl);
    }

    public function compile(source:String, ?filename:String):haxiom.AST.Expr {
        if (enableAstCache && astCache.exists(source)) {
            return astCache.get(source);
        }
        var fileInfo = filename != null ? filename : "script";
        interp.lastSource = source;
        try {
            var lexer = new Lexer(source, fileInfo, interp.preprocessorFlags);
            var tokens = lexer.tokenize();
            var parser = new Parser(tokens, fileInfo);
            var ast = parser.parse();
            
            // Pass 1: Scan and register macro definitions in interpreter scope
            haxiom.MacroExpander.registerMacros(ast, interp);
            
            // Pass 2: Crawl AST and expand macro static calls
            ast = haxiom.MacroExpander.expand(ast, interp);
            
            var folded = Optimizer.foldConstants(ast);
            if (enableAstCache) {
                if (astCacheSize >= 1000) {
                    astCache = new Map();
                    astCacheSize = 0;
                }
                astCache.set(source, folded);
                astCacheSize++;
            }
            return folded;
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

    public function compileToBytes(source:String, ?filename:String, ?key:HXBCKey, ?debugMode:Bool = false):haxe.io.Bytes {
        if (useVM) {
            return compileToBytecodeBytes(source, filename, key, debugMode);
        }
        return compileToASTBytes(source, filename);
    }

    public function executeBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String, ?key:HXBCKey):T {
        if (useVM) {
            return executeBytecodeBytes(bytes, sourceCode, key);
        }
        return executeASTBytes(bytes, sourceCode);
    }

    public function compileToASTBytes(source:String, ?filename:String):haxe.io.Bytes {
        var ast = compile(source, filename);
        if (ast == null) return null;
        return Serializer.serializeToBytes(ast);
    }

    public function compileToBytecodeBytes(source:String, ?filename:String, ?key:HXBCKey, ?debugMode:Bool = false):haxe.io.Bytes {
        var ast = compile(source, filename);
        if (ast == null) return null;
        var chunk = BytecodeCompiler.compile(ast, null, true, false, debugMode);
        return Serializer.serializeBytecode(chunk, key);
    }

    public function executeASTBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String):T {
        if (sourceCode != null) {
            interp.lastSource = sourceCode;
        }
        var ast = Serializer.deserializeFromBytes(bytes);
        var oldUseVM = interp.useVM;
        interp.useVM = false;
        try {
            var result = execute(ast);
            interp.useVM = oldUseVM;
            return cast result;
        } catch (e:Dynamic) {
            interp.useVM = oldUseVM;
            throw e;
        }
    }

    public function executeBytecodeBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String, ?key:HXBCKey):T {
        if (sourceCode != null) {
            interp.lastSource = sourceCode;
        }
        var chunk = Serializer.deserializeBytecode(bytes, key);
        return cast interp.executeChunk(chunk);
    }

    public function setGlobal(name:String, value:Dynamic):Void {
        interp.globals.declare(name, value);
    }
}
