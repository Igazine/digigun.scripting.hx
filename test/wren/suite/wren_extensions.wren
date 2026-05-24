// 1. Scripting-style Traits & Interfaces
class IGreetable {
    greet() { Fiber.abort("Must implement greet()") }
}

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

// Mix in GreetableTrait
Person.mixin(GreetableTrait)

// Enforce IGreetable interface
Person.implements(IGreetable)

var p = Person.new("Alice")
p.greet()
p.sayHello()

System.print(p is Person)
System.print(p is IGreetable)
System.print(p is GreetableTrait)

// 2. Standard Library Extensions
var list = [3, 1, 4, 1, 5, 9, 2]
System.print(list.first)
System.print(list.last)

list.sort()
System.print(list.join(", "))

var list2 = ["banana", "apple", "cherry"]
list2.sort { |a, b| a < b ? 1 : (a > b ? -1 : 0) }
System.print(list2.join(", "))

System.print(Math.clamp(5, 1, 10))
System.print(Math.clamp(-5, 1, 10))
System.print(Math.clamp(15, 1, 10))

System.print(Math.lerp(10, 20, 0.5))
System.print(Math.lerp(0, 100, 0.25))

// expect: Hi, I am Alice
// expect: Hello Alice
// expect: true
// expect: true
// expect: false
// expect: 3
// expect: 2
// expect: 1, 1, 2, 3, 4, 5, 9
// expect: cherry, banana, apple
// expect: 5
// expect: 1
// expect: 10
// expect: 15
// expect: 25
