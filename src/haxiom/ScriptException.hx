package haxiom;

import haxiom.AST.Pos;

class ScriptException extends haxe.Exception {
    public var rawValue(default, null):Dynamic;
    public var virtualStack(default, null):Array<{method:String, pos:Pos}>;
    public var formattedStackTrace(default, null):String;
    public var line(default, null):Int;
    public var col(default, null):Int;
    public var file(default, null):String;

    public function new(rawValue:Dynamic, virtualStack:Array<{method:String, pos:Pos}>, formattedStackTrace:String, line:Int = 1, col:Int = 1, ?file:String) {
        super(formattedStackTrace);
        this.rawValue = rawValue;
        this.virtualStack = virtualStack;
        this.formattedStackTrace = formattedStackTrace;
        this.line = line;
        this.col = col;
        this.file = file;
    }
}
