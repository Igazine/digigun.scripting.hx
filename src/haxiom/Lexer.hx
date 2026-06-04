package haxiom;

import haxiom.AST;

class Lexer {
    var input:String;
    var pos:Int = 0;
    var line:Int = 1;
    var col:Int = 1;

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
                        if (peek() == "\n") {
                            line++;
                            col = 0;
                        }
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
                    case "break": TBreak;
                    case "case": TCase;
                    case "class": TClass;
                    case "continue": TContinue;
                    case "default": TDefault;
                    case "do": TDo;
                    case "else": TElse;
                    case "extends": TExtends;
                    case "false": TFalse;
                    case "for": TFor;
                    case "function": TFunction;
                    case "if": TIf;
                    case "in": TIn;
                    case "new": TNew;
                    case "null": TNull;
                    case "private": TPrivate;
                    case "public": TPublic;
                    case "return": TReturn;
                    case "static": TStatic;
                    case "super": TSuper;
                    case "switch": TSwitch;
                    case "this": TThis;
                    case "true": TTrue;
                    case "var": TVar;
                    case "while": TWhile;
                    case "package": TPackage;
                    case "import": TImport;
                    case "try": TTry;
                    case "catch": TCatch;
                    case "throw": TThrow;
                    case "final": TFinal;
                    case "cast": TCast;
                    case "interface": TInterface;
                    case "implements": TImplements;
                    case "enum": TEnum;
                    case "using": TUsing;
                    case "abstract": TAbstract;
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

            if (char == '"' || char == "'") {
                var quote = char;
                advance();
                var s = "";
                while (pos < input.length && peek() != quote) {
                    var c = peek();
                    if (c == "\\") {
                        advance();
                        var nextChar = peek();
                        switch (nextChar) {
                            case "n": s += "\n";
                            case "t": s += "\t";
                            case "r": s += "\r";
                            case "\\": s += "\\";
                            case "\"": s += "\"";
                            case "'": s += "'";
                            default: s += "\\" + nextChar;
                        }
                        advance();
                    } else {
                        if (c == "\n") { line++; col = 0; }
                        s += c;
                        advance();
                    }
                }
                advance(); // Skip quote
                if (quote == "'") {
                    interpolateString(s, startLine, startCol, tokens);
                } else {
                    tokens.push({ def: TString(s), pos: { line: startLine, col: startCol } });
                }
                continue;
            }

            switch (char) {
                case "(": add(tokens, TParenOpen);
                case ")": add(tokens, TParenClose);
                case "[": add(tokens, TBracketOpen);
                case "]": add(tokens, TBracketClose);
                case "{": add(tokens, TBraceOpen);
                case "}": add(tokens, TBraceClose);
                case ",": add(tokens, TComma);
                case ".":
                    if (peek(1) == "." && peek(2) == ".") add(tokens, TDotDotDot, 3);
                    else add(tokens, TDot);
                case ";": add(tokens, TSemicolon);
                case "?":
                    if (peek(1) == ".") add(tokens, TQuestionDot, 2);
                    else if (peek(1) == "?") add(tokens, TDoubleQuestion, 2);
                    else add(tokens, TQuestion);
                case ":": add(tokens, TColon);
                
                case "+":
                    if (peek(1) == "+") add(tokens, TIncrement, 2);
                    else if (peek(1) == "=") add(tokens, TPlusAssign, 2);
                    else add(tokens, TPlus);
                case "-":
                    if (peek(1) == "-") add(tokens, TDecrement, 2);
                    else if (peek(1) == "=") add(tokens, TMinusAssign, 2);
                    else if (peek(1) == ">") add(tokens, TArrow, 2);
                    else add(tokens, TMinus);
                case "*":
                    if (peek(1) == "=") add(tokens, TStarAssign, 2);
                    else add(tokens, TStar);
                case "/":
                    if (peek(1) == "=") add(tokens, TSlashAssign, 2);
                    else add(tokens, TSlash);
                case "%":
                    if (peek(1) == "=") add(tokens, TPercentAssign, 2);
                    else add(tokens, TPercent);
                
                case "=":
                    if (peek(1) == "=") add(tokens, TEqual, 2);
                    else if (peek(1) == ">") add(tokens, TMapArrow, 2);
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
                    else if (peek(1) == ">" && peek(2) == ">") add(tokens, TUnsignedShiftRight, 3);
                    else if (peek(1) == ">") add(tokens, TShiftRight, 2);
                    else add(tokens, TGreater);
                
                case "&":
                    if (peek(1) == "&") add(tokens, TAnd, 2);
                    else add(tokens, TBitAnd);
                case "|":
                    if (peek(1) == "|") add(tokens, TOr, 2);
                    else add(tokens, TBitOr);
                case "^": add(tokens, TBitXor);
                case "~": add(tokens, TBitNot);
                
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

    function interpolateString(s:String, startLine:Int, startCol:Int, tokens:Array<Token>) {
        var len = s.length;
        var i = 0;
        var fragment = "";
        var hasTokens = false;

        inline function addToken(def:TokenDef) {
            tokens.push({ def: def, pos: { line: startLine, col: startCol } });
            hasTokens = true;
        }

        while (i < len) {
            var c = s.charAt(i);
            if (c == "$") {
                if (i + 1 < len && s.charAt(i + 1) == "$") {
                    fragment += "$";
                    i += 2;
                } else if (i + 1 < len && s.charAt(i + 1) == "{") {
                    if (fragment.length > 0) {
                        if (hasTokens) addToken(TPlus);
                        addToken(TString(fragment));
                        fragment = "";
                    }
                    var startIdx = i + 2;
                    var depth = 1;
                    var j = startIdx;
                    while (j < len && depth > 0) {
                        var ch = s.charAt(j);
                        if (ch == "{") depth++;
                        else if (ch == "}") depth--;
                        j++;
                    }
                    var exprStr = s.substring(startIdx, j - 1);
                    i = j;

                    var subLexer = new Lexer(exprStr);
                    subLexer.line = startLine;
                    subLexer.col = startCol + startIdx;
                    var subTokens = subLexer.tokenize();

                    if (hasTokens) addToken(TPlus);
                    addToken(TParenOpen);
                    for (tok in subTokens) {
                        if (tok.def != TEof) {
                            tokens.push(tok);
                            hasTokens = true;
                        }
                    }
                    addToken(TParenClose);
                } else if (i + 1 < len && (isAlpha(s.charAt(i + 1)) || s.charAt(i + 1) == "_")) {
                    if (fragment.length > 0) {
                        if (hasTokens) addToken(TPlus);
                        addToken(TString(fragment));
                        fragment = "";
                    }
                    var startIdx = i + 1;
                    var j = startIdx;
                    while (j < len && (isAlphanumeric(s.charAt(j)) || s.charAt(j) == "_")) {
                        j++;
                    }
                    var id = s.substring(startIdx, j);
                    i = j;

                    if (hasTokens) addToken(TPlus);
                    addToken(TIdent(id));
                } else {
                    fragment += "$";
                    i++;
                }
            } else {
                fragment += c;
                i++;
            }
        }

        if (fragment.length > 0 || !hasTokens) {
            if (hasTokens) addToken(TPlus);
            addToken(TString(fragment));
        }
    }
}
