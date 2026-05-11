# digigun.scripting.hx

A high-performance, modular scripting foundation for Haxe. This library is designed to provide a robust environment for embedding scripting languages into Haxe applications, enabling dynamic behavior, sandboxed execution, and highly extensible architectures.

> [!IMPORTANT]
> This project is currently **Work in Progress (WIP)**. While the core infrastructure and the Wren implementation are functional, some features are still under active development.

## 🚀 Use Cases

`digigun.scripting.hx` is ideal for:
- **Plugin Systems**: Allow users to extend your application with custom logic without recompiling.
- **Extension Systems**: Build modular software where features can be hot-loaded at runtime.
- **Runtime Generated GUI**: Define and manipulate user interfaces dynamically through scriptable layouts.
- **Game Logic**: Decouple high-level game rules from the engine performance core.
- **Sandbox Execution**: Run untrusted or user-provided scripts safely within a controlled environment.

## 📦 Installation

This library follows standard Haxelib conventions. To include it in your project, add it to your `.hxml` or `project.xml`:

```hxml
-L digigun.scripting.hx
```

For local development/WIP access, you can link the repository:
```bash
haxelib dev digigun.scripting.hx path/to/repo
```
Alternativey you can checkout the repo directly:
```bash
haxelib git digigun.scripting.hx https://github.com/Igazine/digigun.scripting.hx.git
```

## 🛠️ Core Concepts

The library provides a set of common abstractions for:
- **AST-based Interpretation**: Clean separation between parsing and execution.
- **Foreign Function Interface (FFI)**: Seamlessly bind Haxe classes and methods to the scripting environment.
- **Module Resolution**: Configurable loading systems for handling multi-file script projects.
- **Transparent Scoping**: Robust handling of locals and globals across different execution frames.

---

## 🕊️ Implementation: Wren

The first fully-featured scripting engine implemented in this library is **Wren**—a small, fast, class-based concurrent scripting language.

### Usage Example

```haxe
import wren.Wren;

class Main {
    static function main() {
        var vm = new Wren();
        
        // Basic execution
        vm.interpret("System.print(\"Hello from Wren!\")");
        
        // Binding a foreign class
        vm.bindForeignMethod("MyClass", "myMethod", true, 0, (args) -> {
            trace("Haxe method called!");
            return 42;
        });
    }
}
```

### Wren Features Supported:
- [x] Full Class & Inheritance model
- [x] Implicit `this` resolution
- [x] Property Getters & Setters
- [x] Foreign Class & Method bindings
- [x] Module System (`import`)
- [x] String Interpolation
- [/] Standard Library (List, Map, String, Num, Bool) - *WIP*
- [ ] Fibers (Concurrency) - *Planned*

## 🧪 Testing

The library includes a dedicated test runner for validating language specifications.

```bash
haxe test/wren/runner.hxml
```

---

## 📄 License

Part of the **Digigun** ecosystem. Licensed under the MIT License.
