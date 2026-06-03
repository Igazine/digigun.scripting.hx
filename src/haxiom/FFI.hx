package haxiom;

class FFI {
    /**
     * Registers a native Haxe class to the Haxiom engine, making it available
     * both globally under its short name and at its fully qualified namespace path.
     */
    public static function registerClass(haxiom:Haxiom, fqName:String, cls:Class<Dynamic>):Void {
        haxiom.interp.registerFullyQualified(fqName, cls, haxiom.interp.globals);
        var parts = fqName.split(".");
        var shortName = parts[parts.length - 1];
        if (!haxiom.interp.globals.exists(shortName)) {
            haxiom.interp.globals.declare(shortName, cls);
        }
    }

    /**
     * Registers a native Haxe enum to the Haxiom engine.
     */
    public static function registerEnum(haxiom:Haxiom, fqName:String, enm:Enum<Dynamic>):Void {
        haxiom.interp.registerFullyQualified(fqName, enm, haxiom.interp.globals);
        var parts = fqName.split(".");
        var shortName = parts[parts.length - 1];
        if (!haxiom.interp.globals.exists(shortName)) {
            haxiom.interp.globals.declare(shortName, enm);
        }
    }

    /**
     * Registers a native Haxe value, instance, or function to the Haxiom engine.
     */
    public static function registerValue(haxiom:Haxiom, fqName:String, value:Dynamic):Void {
        haxiom.interp.registerFullyQualified(fqName, value, haxiom.interp.globals);
        var parts = fqName.split(".");
        var shortName = parts[parts.length - 1];
        if (!haxiom.interp.globals.exists(shortName)) {
            haxiom.interp.globals.declare(shortName, value);
        }
    }

    /**
     * Automatically registers all classes kept and compiled by the haxiom macro
     * during Haxe compilation. Reads the compiled JSON resource registry.
     */
    public static function registerExposedClasses(haxiom:Haxiom):Void {
        #if !macro
        var res = haxe.Resource.getString("haxiom_exposed_classes");
        if (res != null) {
            var list:Array<String> = haxe.Json.parse(res);
            for (fqName in list) {
                var cls = Type.resolveClass(fqName);
                if (cls != null) {
                    registerClass(haxiom, fqName, cls);
                }
            }
        }
        #end
    }
}
