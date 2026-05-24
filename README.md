# digigun.scripting.hx

A high-performance, modular scripting foundation for Haxe. This library is designed to provide a robust environment for embedding scripting languages into Haxe applications, enabling dynamic behavior, sandboxed execution, and highly extensible architectures.

This project delivers a **fully compliant, self-contained, and highly robust implementation of the Wren programming language** in 100% pure Haxe with **zero external dependencies**.

## Use Cases

`digigun.scripting.hx` is ideal for:
- **Plugin Systems**: Allow users to extend your application with custom logic without recompiling.
- **Extension Systems**: Build modular software where features can be hot-loaded at runtime.
- **Runtime Generated GUI**: Define and manipulate user interfaces dynamically through scriptable layouts.
- **Game Logic**: Decouple high-level game rules from the engine performance core.
- **Sandbox Execution**: Run untrusted or user-provided scripts safely within a controlled environment.

## Installation

This library follows standard Haxelib conventions. To include it in your project, add it to your `.hxml` or `project.xml`:

```hxml
-L digigun.scripting.hx
```

For local development/WIP access, you can link the repository:
```bash
haxelib dev digigun.scripting.hx path/to/repo
```
Alternatively you can checkout the repo directly with Haxelib:
```bash
haxelib git digigun.scripting.hx https://github.com/Igazine/digigun.scripting.hx
```

## Core Concepts

The library provides a set of common abstractions for:
- **AST-based Interpretation**: Clean separation between parsing and execution.
- **Foreign Function Interface (FFI)**: Seamlessly bind Haxe classes and methods to the scripting environment.
- **Module Resolution**: Configurable loading systems for handling multi-file script projects.
- **Transparent Scoping**: Robust handling of locals and globals across different execution frames.

---

## Implementation: Wren

The first fully-featured scripting engine implemented in this library is **Wren**—a small, fast, class-based concurrent scripting language (https://wren.io/).

> [!NOTE]
> #### Why Wren?
> Wren is a lightweight, fast, and embeddable scripting language with a simple syntax and a focus on performance. It is a great choice for embedding into Haxe applications due to its small footprint and ease of integration. It also lacks the *quirks* of other scripting languages (eg. ECMAScript or even TypeScript) which makes it a perfect candidate for a **scripting foundation** as it avoids many of the pitfalls of its more well-known cousins. Although Wren's syntax is different, conceptually it builds on very similar principles and foundations as Haxe, so Haxe developers can feel immediately at home with its clean, modern syntax.

> [!IMPORTANT]
> #### Performance & Interpretation Model
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
        
        // Binding a foreign method
        vm.bindForeignMethod("MyClass", "myMethod", true, 0, (args) -> {
            trace("Haxe method called!");
            return 42;
        });
    }
}
```

---

## Advanced & Premium Features

### 1. Scripting-style Traits & Interfaces
To support modular pluggable engine components, `digigun.scripting.hx` introduces a powerful runtime **Traits & Interfaces** model, natively integrated with Wren's dynamic `is` operator check:

```wren
// 1. Declare an Interface contract
class IGreetable {
    greet() { Fiber.abort("Must implement greet()") }
}

// 2. Declare a Trait (Mixin) providing shared behavior
class GreetableTrait {
    sayHello() {
        System.print("Hello " + name)
    }
}

class Person {
    construct new(name) {
        _name = name
    }
    name { _name }
    greet() {
        System.print("Hi, I am " + name)
    }
}

// Dynamically mix in the trait
Person.mixin(GreetableTrait)

// Enforce the IGreetable interface contract
Person.implements(IGreetable)

var p = Person.new("Alice")
p.greet()      // Hi, I am Alice
p.sayHello()   // Hello Alice

// The dynamic "is" type-checking check is fully recursively interface-aware!
System.print(p is Person)      // true
System.print(p is IGreetable)  // true
```

### 2. Precise Error Diagnostics & Stack Traces
Any syntax or runtime error automatically collects and generates a highly-detailed multi-line stack trace from the origin of the execution context to the script root:

```
[line 3] Runtime Error: Method nonExistent() not found on String.
  [line 3, col 6] in call
  [line 1, col 17] in call
  [line 1, col 1] in script
```

### 3. Expanded Standard Library
- **`List` Utilities**: Added pure Wren fast in-place `sort()` and `sort(comparator)` algorithms alongside instant `first` and `last` element getters.
- **`Math` Utilities**: Added pure static `Math.clamp(value, min, max)` and `Math.lerp(a, b, t)` methods.

---

### Wren Features Supported:
- [x] Full Class & Inheritance model (with base constructor inheritance)
- [x] Implicit `this` resolution
- [x] Property Getters & Setters (with scoping rules resolving local assignments correctly)
- [x] Foreign Class & Method FFI bindings
- [x] Foreign subscript bindings (`[]` and `[]=`) for lists, maps, and classes
- [x] Short-circuiting Logic (`&&`, `||`) and Ternary Operator (`? :`)
- [x] Stateful loop redirection (`break` and `continue` with automatic stack unwinding)
- [x] Module System (`import`)
- [x] String Slicing & Interpolation
- [x] Fibers & Asymmetric Cooperative Multitasking (`Fiber.new`, `suspend`, `yield`, `transfer`, `try()`)
- [x] Standard Library (List, Map, String, Num, Bool, Null, System, Math, Range)
- [x] Traits & Interfaces (`Class.mixin` & `Class.implements`)

---

## Implementation: Haxiom

**Haxiom** is a lightweight, embeddable, sandboxed Haxe-in-Haxe dialect. It preserves standard Haxe syntax 100% while executing dynamically and safely in a fully sandboxed environment.

Haxiom is designed for Haxe developers who want an integrated scripting engine without having to learn a new language or deal with different syntax structures.

### Dynamic Type vs Strict Type Annotations

Haxiom offers the best of both worlds—flexible dynamic scripting ergonomics and strict, Haxe-standard compile-like type boundaries:

* **Dynamic Types**: Declaring variables or class fields *without* type annotations (e.g. `var x = 10;`) treats the symbol as `Dynamic`. This allows any types to be assigned or changed dynamically.
* **Strict Type Enforcement**: Declaring symbols *with* explicit type annotations (e.g. `var x:Int = 10;` or method signatures `function square(v:Int):Int`) binds a permanent type boundary. Mismatched re-assignments, parameter violations, or invalid return values will throw strict, readable runtime exceptions (e.g. `Type mismatch: expected Int but got String`).

### Usage Example

```haxe
import haxiom.Haxiom;

class Main {
    static function main() {
        var haxiom = new Haxiom();
        
        var script = '
            class Player {
                public var x(get, set):Float;
                private var _x:Float = 0.0;
                
                public function new() {}
                
                public function get_x():Float {
                    return _x + 10.0;
                }
                
                public function set_x(v:Float):Float {
                    return _x = v * 2.0;
                }
            }
            
            var p = new Player();
            p.x = 5.0; // invokes setter -> _x is set to 10.0
            trace("Property value: " + p.x); // invokes getter -> returns 20.0
            
            var m:Map<String, Int> = ["apple" => 10, "cherry" => 20];
            trace("Map access: " + m["apple"]);
        ';
        
        haxiom.interpret(script);
    }
}
```

### Haxiom Features Supported:
- [x] Full Class & Inheritance model (`extends`, constructor `super` delegation)
- [x] Implicit `this` resolution
- [x] Property Getters & Setters (`var x(get, set)`)
- [x] Map Literals (`[key => value]`) dynamically instantiated into specialized `StringMap` / `IntMap` collections
- [x] Standard `Std` library bindings (`Std.string`, `Std.parseInt`, `Std.parseFloat`, and subclass-aware `Std.isOfType`)
- [x] Strict Runtime Type Enforcement on typed variables, class fields, method arguments, and return types
- [x] Closures, lambdas, and arrow functions (`(x, y):Int -> x * y`)

---

## Testing

We verify the compiler engine specifications through the unified `TestRunner` and `TestHaxiom` suites, yielding 100% pass rates across core environments.

### Running Wren Tests
To execute tests on the **Haxe Eval** target:
```bash
haxe -L digigun.scripting.hx -cp test --run wren.TestRunner
```

To execute tests on the **JavaScript / Node.js** target:
```bash
haxe -L digigun.scripting.hx -cp test/wren -main TestWren -js bin/test_wren.js && node bin/test_wren.js
```

### Running Haxiom Tests
To execute tests on the **Haxe Eval** target:
```bash
haxe -cp src -cp test -main haxiom.TestHaxiom --interp
```

To execute tests on the **JavaScript / Node.js** target:
```bash
haxe -cp src -cp test -main haxiom.TestHaxiom -js bin/test_haxiom.js && node bin/test_haxiom.js
```

---

## License

Part of the **Digigun** ecosystem. Licensed under the MIT License.
