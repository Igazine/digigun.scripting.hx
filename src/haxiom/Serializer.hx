package haxiom;

import haxiom.AST.Expr;

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
}
