package wren;

class WrenError {
    public var message:String;
    public var line:Int;
    public var col:Int;
    public var file:String;
    public var stackTrace:Array<String>;

    public function new(message:String, line:Int, col:Int, ?file:String, ?stackTrace:Array<String>) {
        this.message = message;
        this.line = line;
        this.col = col;
        this.file = file;
        this.stackTrace = stackTrace;
    }
}


class ErrorPrinter {
    public static function format(e:WrenError):String {
        var res = 'Error: ${e.message} at ${e.file != null ? e.file : "unknown"}:${e.line}:${e.col}';
        if (e.stackTrace != null && e.stackTrace.length > 0) {
            res += "\nStack trace:\n  " + e.stackTrace.join("\n  ");
        }
        return res;
    }
}
