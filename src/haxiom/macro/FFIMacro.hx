package haxiom.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Compiler;
#end

class FFIMacro {
    /**
     * Globally hooks all compiled classes to apply the build macro,
     * removing the need for manual package listing.
     */
    public static function initialize():Void {
        #if macro
        Compiler.addGlobalMetadata("", "@:build(haxiom.macro.FFIMacro.build())");
        
        var exposedAbstracts = new Map<String, { implClass: String, methods: Array<String>, underlying: String }>();
        
        Context.onAfterTyping(function(modules) {
            if (registryDefined) return;
            registryDefined = true;
            for (module in modules) {
                switch (module) {
                    case TAbstract(absRef):
                        var abs = absRef.get();
                        if (abs.meta.has(":haxiom.expose")) {
                            if (abs.impl != null) {
                                var implClass = abs.impl.get();
                                var fqName = abs.pack.concat([abs.name]).join(".");
                                var fqImplName = implClass.pack.concat([implClass.name]).join(".");
                                
                                var methods = [];
                                for (field in implClass.statics.get()) {
                                    methods.push(field.name);
                                }
                                
                                exposedAbstracts.set(fqName, {
                                    implClass: fqImplName,
                                    methods: methods,
                                    underlying: haxe.macro.TypeTools.toString(abs.type)
                                });
                                
                                Compiler.keep(fqImplName);
                            }
                        }
                    default:
                }
            }
            
            var initExpr = macro new Map<String, Dynamic>();
            
            var t:haxe.macro.Expr.TypeDefinition = {
                pack: ["haxiom", "macro"],
                name: "AbstractRegistry",
                pos: Context.currentPos(),
                kind: TDClass(),
                fields: [
                    {
                        name: "impls",
                        pos: Context.currentPos(),
                        kind: FVar(macro:Map<String, Dynamic>, initExpr),
                        access: [APublic, AStatic]
                    }
                ]
            };
            Context.defineType(t);
            Context.getType("haxiom.macro.AbstractRegistry");
            Compiler.keep("haxiom.macro.AbstractRegistry");
        });
        #end
    }

    #if macro
    static var registryDefined = false;
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
        }
        
        // Always register onGenerate to capture all compiled types at the end of compilation
        if (!registeredOnGenerate) {
            registeredOnGenerate = true;
            Context.onGenerate(function(types) {
                var exposedAbstracts = new Map<String, { implClass: String, methods: Array<String>, underlying: String }>();
                var exposedGenerics = new Map<String, String>();
                var genericBases = [];
                var exposedModules = new Map<String, Array<String>>();
                
                // 1. Scan for all exposed classes, generic base definitions, and abstracts
                for (type in types) {
                    var pack:Array<String> = [];
                    var name:String = "";
                    var module:String = "";
                    
                    switch (type) {
                        case TInst(classRef, _):
                            var cls = classRef.get();
                            pack = cls.pack;
                            name = cls.name;
                            module = cls.module;
                            
                            var fqName = cls.pack.concat([cls.name]).join(".");
                            if (cls.meta.has(":haxiom.expose")) {
                                if (exposedClasses.indexOf(fqName) == -1) {
                                    exposedClasses.push(fqName);
                                }
                                if (cls.params.length > 0) {
                                    genericBases.push(cls);
                                }
                            }
                        case TEnum(enumRef, _):
                            var enm = enumRef.get();
                            pack = enm.pack;
                            name = enm.name;
                            module = enm.module;
                        case TType(defRef, _):
                            var tdef = defRef.get();
                            pack = tdef.pack;
                            name = tdef.name;
                            module = tdef.module;
                        case TAbstract(abstractRef, _):
                            var abs = abstractRef.get();
                            pack = abs.pack;
                            name = abs.name;
                            module = abs.module;
                            
                            if (abs.meta.has(":haxiom.expose")) {
                                var fqName = abs.pack.concat([abs.name]).join(".");
                                if (abs.impl != null) {
                                    var implClass = abs.impl.get();
                                    var fqImplName = implClass.pack.concat([implClass.name]).join(".");
                                    
                                    var methods = [];
                                    for (field in implClass.statics.get()) {
                                        methods.push(field.name);
                                    }
                                    
                                    exposedAbstracts.set(fqName, {
                                        implClass: fqImplName,
                                        methods: methods,
                                        underlying: haxe.macro.TypeTools.toString(abs.type)
                                    });
                                    
                                    // Keep the implementation class via Compiler.keep
                                    Compiler.keep(fqImplName);
                                    
                                    // Add @:keep to abstract implementation class and its fields to prevent DCE pruning
                                    if (!implClass.meta.has(":keep")) {
                                        implClass.meta.add(":keep", [], implClass.pos);
                                    }

                                    for (field in implClass.statics.get()) {
                                        if (!field.meta.has(":keep")) {
                                            field.meta.add(":keep", [], field.pos);
                                        }
                                    }
                                }
                            }
                        default:
                            continue;
                    }
                    
                    if (module != null && module != "") {
                        var runtimePath = pack.concat([name]).join(".");
                        var list = exposedModules.get(module);
                        if (list == null) {
                            list = [];
                            exposedModules.set(module, list);
                        }
                        if (list.indexOf(runtimePath) == -1) {
                            list.push(runtimePath);
                        }
                    }
                }
                
                // 2. Discover generated generic instantiations (e.g. MyClass_String)
                for (type in types) {
                    switch (type) {
                        case TInst(classRef, _):
                            var cls = classRef.get();
                            for (base in genericBases) {
                                // Must be in same package and name starts with base.name + "_"
                                if (cls.pack.join(".") == base.pack.join(".") && cls.name.indexOf(base.name + "_") == 0) {
                                    var baseFq = base.pack.concat([base.name]).join(".");
                                    var clsFq = cls.pack.concat([cls.name]).join(".");
                                    
                                    // Suffix represents the parameter types (e.g., String, Int, or package_Subpackage_Type)
                                    var suffix = cls.name.substr(base.name.length + 1);
                                    
                                    // Replace underscores with dots to rebuild signature
                                    var paramPart = suffix.split("_").join(".");
                                    var genericSig = baseFq + "<" + paramPart + ">";
                                    
                                    exposedGenerics.set(genericSig, clsFq);
                                    
                                    // Keep the generated class and its fields/methods
                                    if (!cls.meta.has(":keep")) {
                                        cls.meta.add(":keep", [], cls.pos);
                                    }
                                    if (cls.constructor != null) {
                                        cls.constructor.get().meta.add(":keep", [], cls.pos);
                                    }
                                    for (field in cls.fields.get()) {
                                        if (!field.meta.has(":keep")) {
                                            field.meta.add(":keep", [], field.pos);
                                        }
                                    }
                                    for (field in cls.statics.get()) {
                                        if (!field.meta.has(":keep")) {
                                            field.meta.add(":keep", [], field.pos);
                                        }
                                    }
                                }
                            }
                        default:
                    }
                }
                
                // 3. Serialize and embed registries as compiled resources
                var classesJson = haxe.Json.stringify(exposedClasses);
                Context.addResource("haxiom_exposed_classes", haxe.io.Bytes.ofString(classesJson));
                
                var abstractsObj = {};
                for (k in exposedAbstracts.keys()) {
                    Reflect.setField(abstractsObj, k, exposedAbstracts.get(k));
                }
                var abstractsJson = haxe.Json.stringify(abstractsObj);
                Context.addResource("haxiom_exposed_abstracts", haxe.io.Bytes.ofString(abstractsJson));
                
                var genericsObj = {};
                for (k in exposedGenerics.keys()) {
                    Reflect.setField(genericsObj, k, exposedGenerics.get(k));
                }
                var genericsJson = haxe.Json.stringify(genericsObj);
                Context.addResource("haxiom_exposed_generics", haxe.io.Bytes.ofString(genericsJson));
                
                var modulesObj = {};
                for (k in exposedModules.keys()) {
                    Reflect.setField(modulesObj, k, exposedModules.get(k));
                }
                var modulesJson = haxe.Json.stringify(modulesObj);
                Context.addResource("haxiom_exposed_modules", haxe.io.Bytes.ofString(modulesJson));
            });
        }

        
        return null;
    }
    #end
}
