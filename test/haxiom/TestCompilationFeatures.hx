package haxiom;

import haxiom.Haxiom;
import haxiom.AST;

class TestCompilationFeatures {
    public static function runTests() {
        trace("Starting Haxiom Preprocessor, Optional Types, and Macros Verification Suite...");
        
        testPreprocessor();
        testOptionalFields();
        testMacros();
        testInline();
        
        trace("SUCCESS: All Haxiom preprocessor, optional type, and macro tests passed!");
    }

    static function testPreprocessor() {
        var engine = new Haxiom();
        engine.useVM = true;

        // Verify default flags
        #if js
        if (!engine.preprocessorFlags.exists("js")) throw "Expected preprocessor flag 'js' to be active on JS target";
        #elseif eval
        if (!engine.preprocessorFlags.exists("eval")) throw "Expected preprocessor flag 'eval' to be active on Eval target";
        #end

        // Define a custom flag
        engine.preprocessorFlags.set("my_feature", true);
        engine.preprocessorFlags.set("debug_mode", false);

        // Test basic #if/#else
        var script = '
            var x = 0;
            #if my_feature
            x = 100;
            #else
            x = 200;
            #end
            x;
        ';
        var res:Int = engine.interpret(script);
        if (res != 100) throw "testPreprocessor basic #if failed: expected 100, got " + res;

        // Test basic #else branch
        var script2 = '
            var x = 0;
            #if debug_mode
            x = 100;
            #else
            x = 200;
            #end
            x;
        ';
        var res2:Int = engine.interpret(script2);
        if (res2 != 200) throw "testPreprocessor basic #else failed: expected 200, got " + res2;

        // Test #elseif branch
        var script3 = '
            var x = 0;
            #if debug_mode
            x = 10;
            #elseif my_feature
            x = 20;
            #else
            x = 30;
            #end
            x;
        ';
        var res3:Int = engine.interpret(script3);
        if (res3 != 20) throw "testPreprocessor #elseif failed: expected 20, got " + res3;

        // Test nested #if directives
        var script4 = '
            var x = 0;
            #if my_feature
                #if debug_mode
                x = 1;
                #else
                x = 2;
                #end
            #else
            x = 3;
            #end
            x;
        ';
        var res4:Int = engine.interpret(script4);
        if (res4 != 2) throw "testPreprocessor nested #if failed: expected 2, got " + res4;

        // Test preprocessor expression evaluation with &&, ||, !
        var script5 = '
            var x = 0;
            #if (my_feature && !debug_mode)
            x = 500;
            #else
            x = 600;
            #end
            x;
        ';
        var res5:Int = engine.interpret(script5);
        if (res5 != 500) throw "testPreprocessor expression && ! failed: expected 500, got " + res5;

        // Test #error compilation failure
        var caughtError = false;
        try {
            var scriptErr = '
                #if my_feature
                #error "This is an expected compilation error!"
                #end
            ';
            engine.interpret(scriptErr);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("This is an expected compilation error!") != -1) {
                caughtError = true;
            }
        }
        if (!caughtError) throw "testPreprocessor #error failed: expected compilation error to be thrown";

        // Test #error inside inactive branch is ignored
        var scriptErrIgnore = '
            #if debug_mode
            #error "Should not throw!"
            #end
            var success = 42;
            success;
        ';
        var resErr:Int = engine.interpret(scriptErrIgnore);
        if (resErr != 42) throw "testPreprocessor inactive #error failed: expected 42, got " + resErr;

        trace("SUCCESS: Preprocessor tests passed.");
    }

    static function testOptionalFields() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = '
            typedef User = {
                var name:String;
                var ?age:Int;
            }
            
            class Validator {
                public static function check(u:User):String {
                    return u.name;
                }
            }
        ';
        engine.interpret(script);

        // Verify successful validation with optional field absent
        var checkFunc:Dynamic = engine.interpret("Validator.check");
        var res1 = checkFunc({ name: "Alice" });
        if (res1 != "Alice") throw "testOptionalFields missing opt field failed: expected 'Alice', got " + res1;

        // Verify successful validation with optional field present
        var res2 = checkFunc({ name: "Bob", age: 25 });
        if (res2 != "Bob") throw "testOptionalFields with opt field failed: expected 'Bob', got " + res2;

        // Verify type check failure when optional field has wrong type
        var caughtWrongType = false;
        try {
            checkFunc({ name: "Bob", age: "twenty-five" });
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("Type mismatch in field \"age\"") != -1) {
                caughtWrongType = true;
            }
        }
        if (!caughtWrongType) throw "testOptionalFields wrong type failed: expected type mismatch exception";

        // Verify type check failure when required field is missing
        var caughtMissingField = false;
        try {
            checkFunc({ age: 30 });
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("Type mismatch: object is missing field \"name\"") != -1) {
                caughtMissingField = true;
            }
        }
        if (!caughtMissingField) throw "testOptionalFields missing required field failed: expected missing field exception";

        trace("SUCCESS: Optional fields tests passed.");
    }

    static function testMacros() {
        var engine = new Haxiom();
        engine.useVM = true;

        // Define a macro static method inside a class
        var script = '
            import haxiom.AST.ExprDef;
            
            class MyMacros {
                @:haxiom.macro
                public static function double(e) {
                    // Duplicate/add the expression to itself: e + e
                    return {
                        def: ExprDef.EBinop("+", e, e),
                        pos: e.pos
                    };
                }

                @:haxiom.macro
                public static function makeInt(e) {
                    return {
                        def: ExprDef.EValue(42),
                        pos: e.pos
                    };
                }
            }

            class UsageClass {
                public static function run() {
                    var x = MyMacros.double(5); // Should expand to 5 + 5
                    var y = MyMacros.makeInt("unused"); // Should expand to 42
                    return x + y;
                }
            }
            UsageClass.run();
        ';

        var res:Int = engine.interpret(script);
        if (res != 52) throw "testMacros failed: expected 52, got " + res;

        trace("SUCCESS: Macro tests passed.");
    }

    static function testInline() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = '
            class InlineDemo {
                static inline function getOffset():Int {
                    return 100;
                }
                
                public inline function add(a:Int, b:Int):Int {
                    return a + b + getOffset();
                }
            }
            
            inline function localHelper(x:Int):Int {
                return x * 2;
            }

            var inst = new InlineDemo();
            inst.add(10, 20) + localHelper(5);
        ';

        var res:Int = engine.interpret(script);
        if (res != 140) throw "testInline failed: expected 140, got " + res;

        // Test AST mode too
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        var resAST:Int = engineAST.interpret(script);
        if (resAST != 140) throw "testInline (AST) failed: expected 140, got " + resAST;

        trace("SUCCESS: Inline modifier tests passed.");
    }
}
