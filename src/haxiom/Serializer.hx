package haxiom;

import haxiom.AST.Expr;
import haxiom.VM.BytecodeChunk;

class Serializer {
    public static function serialize(expr:Expr):String {
        var s = new haxe.Serializer();
        s.useCache = true;
        s.useEnumIndex = true;
        s.serialize(expr);
        return s.toString();
    }

    public static function deserialize(str:String):Expr {
        var u = new haxe.Unserializer(str);
        return u.unserialize();
    }

    public static function serializeToBytes(expr:Expr):haxe.io.Bytes {
        var str = serialize(expr);
        return haxe.io.Bytes.ofString(str);
    }

    public static function deserializeFromBytes(bytes:haxe.io.Bytes):Expr {
        return deserialize(bytes.toString());
    }

    public static function serializeBytecode(chunk:BytecodeChunk):haxe.io.Bytes {
        var s = new haxe.Serializer();
        s.useCache = true;
        s.useEnumIndex = true;
        s.serialize(chunk);
        return haxe.io.Bytes.ofString(s.toString());
    }

    public static function deserializeBytecode(bytes:haxe.io.Bytes):BytecodeChunk {
        var u = new haxe.Unserializer(bytes.toString());
        return u.unserialize();
    }
}
