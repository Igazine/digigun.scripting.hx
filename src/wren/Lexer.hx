package wren;

import wren.AST;

class Lexer {
    var input:String;
    var pos:Int = 0;
    var line:Int = 1;
    var col:Int = 1;
    var tokens:Array<Token>;
    var modeStack:Array<Int> = [-1]; // -1 for normal, >= 0 for interpolation nesting level


    public function new(input:String) {
        this.input = input;
    }

    public function tokenize():Array<Token> {
        var tokens = [];
        while (pos < input.length) {
            var char = peek();
            
            if (char == " " || char == "\r" || char == "\t") {
                advance();
                continue;
            }
            
            if (char == "\n") {
                tokens.push({ def: TNewline, pos: { line: line, col: col } });
                pos++;
                line++;
                col = 1;
                continue;
            }

            if (char == "/" && peek(1) == "/") {
                while (pos < input.length && peek() != "\n") advance();
                continue;
            }

            if (char == "/" && peek(1) == "*") {
                advance(); advance();
                var depth = 1;
                while (pos < input.length && depth > 0) {
                    if (peek() == "/" && peek(1) == "*") {
                        advance(); advance();
                        depth++;
                    } else if (peek() == "*" && peek(1) == "/") {
                        advance(); advance();
                        depth--;
                    } else {
                        advance();
                    }
                }
                continue;
            }

            var startLine = line;
            var startCol = col;

            if (isAlpha(char) || char == "_") {
                var start = pos;
                while (pos < input.length && (isAlphanumeric(peek()) || peek() == "_")) advance();
                var id = input.substring(start, pos);
                var def = switch(id) {
                    case "as": TAs;
                    case "break": TBreak;
                    case "class": TClass;
                    case "construct": TConstruct;
                    case "continue": TContinue;
                    case "else": TElse;
                    case "false": TFalse;
                    case "for": TFor;
                    case "foreign": TForeign;
                    case "if": TIf;
                    case "import": TImport;
                    case "in": TIn;
                    case "is": TIs;
                    case "null": TNull;
                    case "return": TReturn;
                    case "static": TStatic;
                    case "super": TSuper;
                    case "this": TThis;
                    case "true": TTrue;
                    case "var": TVar;
                    case "while": TWhile;
                    default: TIdent(id);
                };
                tokens.push({ def: def, pos: { line: startLine, col: startCol } });
                continue;
            }

            if (isDigit(char)) {
                var start = pos;
                if (char == "0" && (peek(1) == "x" || peek(1) == "X")) {
                    advance(); advance();
                    while (pos < input.length && isHexDigit(peek())) advance();
                    var s = input.substring(start, pos);
                    tokens.push({ def: TInt(Std.parseInt(s)), pos: { line: startLine, col: startCol } });
                    continue;
                }
                if (char == "0" && (peek(1) == "b" || peek(1) == "B")) {
                    advance(); advance();
                    while (pos < input.length && (peek() == "0" || peek() == "1")) advance();
                    var s = input.substring(start + 2, pos);
                    var val = 0;
                    for (i in 0...s.length) {
                        val = (val << 1) | (s.charAt(i) == "1" ? 1 : 0);
                    }
                    tokens.push({ def: TInt(val), pos: { line: startLine, col: startCol } });
                    continue;
                }

                while (pos < input.length && isDigit(peek())) advance();
                if (peek() == "." && isDigit(peek(1))) {
                    advance();
                    while (pos < input.length && isDigit(peek())) advance();
                }
                if (peek() == "e" || peek() == "E") {
                    advance();
                    if (peek() == "+" || peek() == "-") advance();
                    while (pos < input.length && isDigit(peek())) advance();
                }
                var s = input.substring(start, pos);
                var def = (s.indexOf(".") != -1 || s.toLowerCase().indexOf("e") != -1) ? TFloat(Std.parseFloat(s)) : TInt(Std.parseInt(s));
                tokens.push({ def: def, pos: { line: startLine, col: startCol } });
                continue;
            }


            if (char == '"') {
                advance();
                var start = pos;
                var startLine = line;
                var startCol = col;
                while (pos < input.length && peek() != '"') {
                    if (peek() == "%" && peek(1) == "(") {
                        var s = input.substring(start, pos);
                        tokens.push({ def: TString(s), pos: { line: startLine, col: startCol } });
                        tokens.push({ def: TInterpStart, pos: { line: line, col: col } });
                        advance(); advance(); // Skip %(
                        modeStack.push(0); // Start interpolation with 0 nesting
                        start = -1;
                        break;
                    }
                    if (peek() == "\n") { line++; col = 0; }
                    advance();
                }
                if (start != -1) {
                    var s = input.substring(start, pos);
                    advance(); // skip "
                    tokens.push({ def: TString(s), pos: { line: startLine, col: startCol } });
                }
                continue;
            }


            switch (char) {
                case "(": 
                    if (modeStack.length > 1) modeStack[modeStack.length-1]++;
                    add(tokens, TParenOpen);
                case ")": 
                    if (modeStack.length > 1) {
                        if (modeStack[modeStack.length-1] == 0) {
                            modeStack.pop();
                            tokens.push({ def: TInterpEnd, pos: { line: line, col: col } });
                            advance();
                            // Switch back to string mode!
                            var start = pos;
                            var startLine = line;
                            var startCol = col;
                            while (pos < input.length && peek() != '"') {
                                if (peek() == "%" && peek(1) == "(") {
                                    var s = input.substring(start, pos);
                                    tokens.push({ def: TString(s), pos: { line: startLine, col: startCol } });
                                    tokens.push({ def: TInterpStart, pos: { line: line, col: col } });
                                    advance(); advance(); // Skip %(
                                    modeStack.push(0);
                                    start = -1;
                                    break;
                                }
                                if (peek() == "\n") { line++; col = 0; }
                                advance();
                            }
                            if (start != -1) {
                                var s = input.substring(start, pos);
                                advance(); // skip "
                                tokens.push({ def: TString(s), pos: { line: startLine, col: startCol } });
                            }
                            continue;
                        } else {
                            modeStack[modeStack.length-1]--;
                        }
                    }
                    add(tokens, TParenClose);


                case "[": add(tokens, TBracketOpen);
                case "]": add(tokens, TBracketClose);
                case "{": add(tokens, TBraceOpen);
                case "}": add(tokens, TBraceClose);
                case ",": add(tokens, TComma);
                case ":": add(tokens, TColon);

                case ".":
                    if (peek(1) == "." && peek(2) == ".") {
                        add(tokens, TDotDotDot, 3);
                    } else if (peek(1) == ".") {
                        add(tokens, TDotDot, 2);
                    } else {
                        add(tokens, TDot);
                    }
                case "?": add(tokens, TQuestion);
                case "=":
                    if (peek(1) == "=") add(tokens, TEqual, 2);
                    else add(tokens, TAssign);
                case "!":
                    if (peek(1) == "=") add(tokens, TNotEqual, 2);
                    else add(tokens, TNot);
                case "<":
                    if (peek(1) == "=") add(tokens, TLessEqual, 2);
                    else if (peek(1) == "<") add(tokens, TShiftLeft, 2);
                    else add(tokens, TLess);
                case ">":
                    if (peek(1) == "=") add(tokens, TGreaterEqual, 2);
                    else if (peek(1) == ">") add(tokens, TShiftRight, 2);
                    else add(tokens, TGreater);
                case "+": add(tokens, TPlus);
                case "-": add(tokens, TMinus);
                case "*": add(tokens, TStar);
                case "/": add(tokens, TSlash);
                case "%": add(tokens, TPercent);
                case "&":
                    if (peek(1) == "&") add(tokens, TAmpersandAmpersand, 2);
                    else add(tokens, TAmpersand);
                case "|":
                    if (peek(1) == "|") add(tokens, TPipePipe, 2);
                    else add(tokens, TPipe);
                case "^": add(tokens, TCaret);
                case "~": add(tokens, TTilde);
                default:
                    advance(); // Ignore unknown
            }
        }
        tokens.push({ def: TEof, pos: { line: line, col: col } });
        return tokens;
    }

    inline function peek(offset:Int = 0):String {
        if (pos + offset >= input.length) return "";
        return input.charAt(pos + offset);
    }

    inline function advance() {
        pos++;
        col++;
    }

    inline function add(tokens:Array<Token>, def:TokenDef, len:Int = 1) {
        tokens.push({ def: def, pos: { line: line, col: col } });
        for (i in 0...len) advance();
    }

    inline function isAlpha(c:String):Bool {
        var code = c.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }

    inline function isDigit(c:String):Bool {
        var code = c.charCodeAt(0);
        return code >= 48 && code <= 57;
    }

    inline function isHexDigit(c:String):Bool {
        return isDigit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F");
    }


    inline function isAlphanumeric(c:String):Bool {
        return isAlpha(c) || isDigit(c);
    }
}
