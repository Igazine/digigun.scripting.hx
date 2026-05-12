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
haxelib git digigun.scripting.hx https://github.com/Igazine/digigun.scripting.hx
```

## 🛠️ Core Concepts

The library provides a set of common abstractions for:
- **AST-based Interpretation**: Clean separation between parsing and execution.
- **Foreign Function Interface (FFI)**: Seamlessly bind Haxe classes and methods to the scripting environment.
- **Module Resolution**: Configurable loading systems for handling multi-file script projects.
- **Transparent Scoping**: Robust handling of locals and globals across different execution frames.

---

## 🕊️ Implementation: Wren

The first fully-featured scripting engine implemented in this library is **Wren**—a small, fast, class-based concurrent scripting language (https://wren.io/).

> [!NOTE]
>
> #### Why Wren?
>
> Wren is a lightweight, fast, and embeddable scripting language with a simple syntax and a focus on performance. It is a great choice for embedding into Haxe applications due to its small footprint and ease of integration. It also lacks the *quirks* of other scripting languages (eg. ECMAScript or even TypeScript) which makes it a perfect candidate for a **scripting foundation** as it avoids many of the pitfalls of its more well-known cousins. Although Wren's syntax is different, conceptually it builds on very similar principles and foundations as Haxe, so Haxe developers can feel immediately at home with its clean, modern syntax.

> [!IMPORTANT]
>
> #### Performance & Interpretation Model
>
> This implementation utilizes a high-level **AST-based Interpreter** model rather than a Bytecode JIT or AOT compilation. While this ensures maximum compatibility across all Haxe targets (including HashLink, JavaScript, and C++), it introduces certain performance caveats:
> - **Overhead**: Every script operation involves AST traversal and dynamic dispatch, which is slower than native Haxe code or low-level bytecode VMs.
> - **Target Logic**: This library is designed for **high-level orchestration**, plugin logic, and UI definitions. It is **not recommended** for performance-critical inner loops or core engine logic where microsecond latency is required.
> - **Memory**: Interpretation involves more object allocations for frames and expressions compared to compiled models.
>
> Use this library to bring **flexibility** to your app, but keep your **heavy lifting** in native Haxe.

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
- [x] Fibers (Concurrency) - Completed, *not battle-tested*

## 🧪 Testing

The library includes a dedicated test runner for validating language specifications.

```bash
haxe test/wren/runner.hxml
```

---

## 📄 License

Part of the **Digigun** ecosystem. Licensed under the MIT License.
