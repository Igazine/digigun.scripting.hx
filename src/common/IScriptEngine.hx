package common;

/**
 * Standard interface for embeddable scripting hosts.
 */
interface IScriptEngine {
    /**
     * Interpret the given script source code and return the result.
     */
    function interpret(source:String, ?onDone:Dynamic->Void):Dynamic;

    /**
     * Register a global variable or utility in the scripting environment.
     */
    function setGlobal(name:String, value:Dynamic):Void;
}
