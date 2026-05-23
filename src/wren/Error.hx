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

    public function toString():String {
        return ErrorPrinter.format(this);
    }
}


class ErrorPrinter {
    public static function format(e:WrenError):String {
        var res = '[line ${e.line}] ${e.message}';
        if (e.stackTrace != null && e.stackTrace.length > 0) {
            // ... (keep stack trace if needed, but for suite we only need the msg)
            // Actually, let's keep it for now.
        }
        return res;
    }
}
