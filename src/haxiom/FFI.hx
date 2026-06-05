package haxiom;

class FFI {
    public static var exposedAbstracts = new Map<String, { implClass: String, methods: Array<String>, underlying: String }>();
    public static var exposedGenerics = new Map<String, String>();
    public static var abstractImpls = new Map<String, Dynamic>();
    public static var exposedModules = new Map<String, Array<String>>();

    /**
     * Registers a native Haxe class to the Haxiom engine, making it available
     * both globally under its short name and at its fully qualified namespace path.
     */
    public static function registerClass(haxiom:Haxiom, fqName:String, cls:Class<Dynamic>):Void {
        haxiom.interp.registerFullyQualified(fqName, cls, haxiom.interp.globals);
        if (haxiom.interp.importWhitelist != null && haxiom.interp.importWhitelist.indexOf(fqName) == -1) {
            haxiom.interp.importWhitelist.push(fqName);
        }
        var parts = fqName.split(".");
        var shortName = parts[parts.length - 1];
        if (!haxiom.interp.globals.exists(shortName)) {
            haxiom.interp.globals.declare(shortName, cls);
        }
    }

    /**
     * Registers a native Haxe class under a generic type parameters signature.
     */
    public static function registerGenericInstantiation(haxiom:Haxiom, signature:String, cls:Class<Dynamic>):Void {
        exposedGenerics.set(signature, Type.getClassName(cls));
        haxiom.interp.registerFullyQualified(signature, cls, haxiom.interp.globals);
        if (haxiom.interp.importWhitelist != null && haxiom.interp.importWhitelist.indexOf(signature) == -1) {
            haxiom.interp.importWhitelist.push(signature);
        }
    }

    /**
     * Registers a native Haxe enum to the Haxiom engine.
     */
    public static function registerEnum(haxiom:Haxiom, fqName:String, enm:Enum<Dynamic>):Void {
        haxiom.interp.registerFullyQualified(fqName, enm, haxiom.interp.globals);
        if (haxiom.interp.importWhitelist != null && haxiom.interp.importWhitelist.indexOf(fqName) == -1) {
            haxiom.interp.importWhitelist.push(fqName);
        }
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
        if (haxiom.interp.importWhitelist != null && haxiom.interp.importWhitelist.indexOf(fqName) == -1) {
            haxiom.interp.importWhitelist.push(fqName);
        }
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
        // 1. Load exposed classes
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

        // 2. Load exposed abstracts
        var absRes = haxe.Resource.getString("haxiom_exposed_abstracts");
        if (absRes != null) {
            var obj:Dynamic = haxe.Json.parse(absRes);
            for (k in Reflect.fields(obj)) {
                exposedAbstracts.set(k, Reflect.field(obj, k));
            }
        }

        // 2b. Load runtime abstract implementation references from AbstractRegistry if it exists
        var registryCls = Type.resolveClass("haxiom.macro.AbstractRegistry");
        if (registryCls != null) {
            var impls:Map<String, Dynamic> = Reflect.field(registryCls, "impls");
            if (impls != null) {
                for (k in impls.keys()) {
                    abstractImpls.set(k, impls.get(k));
                }
            }
        }

        // 3. Load exposed generics
        var genRes = haxe.Resource.getString("haxiom_exposed_generics");
        if (genRes != null) {
            var obj:Dynamic = haxe.Json.parse(genRes);
            for (k in Reflect.fields(obj)) {
                exposedGenerics.set(k, Reflect.field(obj, k));
            }
        }

        // 4. Load exposed modules
        var modRes = haxe.Resource.getString("haxiom_exposed_modules");
        if (modRes != null) {
            var obj:Dynamic = haxe.Json.parse(modRes);
            for (k in Reflect.fields(obj)) {
                var arr:Array<Dynamic> = Reflect.field(obj, k);
                exposedModules.set(k, [for (item in arr) Std.string(item)]);
            }
        }
        #end
    }
}
