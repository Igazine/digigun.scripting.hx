package haxiom.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

class FFIMacro {
    #if macro
    static var exposedClasses:Array<String> = [];
    static var registeredOnGenerate = false;

    public static function build():Array<Field> {
        var localClass = Context.getLocalClass();
        if (localClass == null) return null;
        
        var cls = localClass.get();
        
        // Check if the class has @:haxiom.expose metadata
        var hasMeta = cls.meta.has(":haxiom.expose");
        if (hasMeta) {
            // Add @:keep to the class if not already present
            if (!cls.meta.has(":keep")) {
                cls.meta.add(":keep", [], cls.pos);
            }
            
            // Add @:keep to constructor to prevent DCE pruning it
            if (cls.constructor != null) {
                cls.constructor.get().meta.add(":keep", [], cls.pos);
            }
            
            var fields = Context.getBuildFields();
            for (f in fields) {
                if (f.meta == null) {
                    f.meta = [];
                }
                var hasKeep = false;
                for (m in f.meta) {
                    if (m.name == ":keep") {
                        hasKeep = true;
                        break;
                    }
                }
                if (!hasKeep) {
                    f.meta.push({ name: ":keep", pos: f.pos });
                }
            }
            
            var fqName = cls.pack.concat([cls.name]).join(".");
            if (exposedClasses.indexOf(fqName) == -1) {
                exposedClasses.push(fqName);
            }
            
            if (!registeredOnGenerate) {
                registeredOnGenerate = true;
                Context.onGenerate(function(types) {
                    // Embed the list of exposed classes as a compiled resource
                    var json = haxe.Json.stringify(exposedClasses);
                    Context.addResource("haxiom_exposed_classes", haxe.io.Bytes.ofString(json));
                });
            }
            
            return fields;
        }
        
        return null;
    }
    #end
}
