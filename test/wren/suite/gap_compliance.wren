// --- Logical Operators ---
var a = true
var b = false
System.print(a && b) // expect: false
System.print(a || b) // expect: true

// Short circuiting
var sideEffect = 0
var f = Fn.new {
    sideEffect = sideEffect + 1
    return true
}
System.print(b && f.call()) // expect: false
System.print(sideEffect) // expect: 0
System.print(a || f.call()) // expect: true
System.print(sideEffect) // expect: 0
System.print(b || f.call()) // expect: true
System.print(sideEffect) // expect: 1

// --- Ternary Conditional ---
System.print(a ? "yes" : "no") // expect: yes
System.print(b ? "yes" : "no") // expect: no
System.print(a ? (b ? "nest1" : "nest2") : "outer") // expect: nest2

// --- Loop Controls ---
var i = 0
while (i < 10) {
    i = i + 1
    if (i == 3) continue
    if (i == 5) break
    System.print(i)
}
// expect: 1
// expect: 2
// expect: 4

var listFor = [10, 20, 30]
for (x in listFor) {
    if (x == 20) continue
    System.print(x)
}
// expect: 10
// expect: 30

// --- Class Variables ---
class Counter {
    construct new() {}
    static init() {
        __count = 0
    }
    static count { __count }
    static increment() {
        __count = __count + 1
    }
}
Counter.init()
System.print(Counter.count) // expect: 0
Counter.increment()
Counter.increment()
System.print(Counter.count) // expect: 2

// --- Constructor Inheritance ---
class Animal {
    construct new(name, age) {
        _name = name
        _age = age
    }
    name { _name }
    age { _age }
}
class Dog is Animal {}
var dog = Dog.new("Fido", 3)
System.print(dog.name) // expect: Fido
System.print(dog.age) // expect: 3

// --- Math Completeness ---
System.print(Math.min(5, 10)) // expect: 5
System.print(Math.max(5, 10)) // expect: 10
System.print(Math.pow(2, 3)) // expect: 8
System.print(Math.round(4.6)) // expect: 5
System.print(Math.sign(-42)) // expect: -1

// --- String Subscript & Slices ---
var str = "abcdef"
System.print(str[0]) // expect: a
System.print(str[-1]) // expect: f
System.print(str[1..3]) // expect: bcd
System.print(str[1...3]) // expect: bc

// --- String Stdlib ---
var trimmed = "  hello  ".trim()
System.print(trimmed) // expect: hello
var replaced = "apple".replace("p", "x")
System.print(replaced) // expect: axxle
var splitted = "a,b,c".split(",")
System.print(splitted.count) // expect: 3
System.print(splitted[0]) // expect: a

// --- List Subscript & Slices & Stdlib ---
var lst = [10, 20, 30, 40]
System.print(lst[-1]) // expect: 40
System.print(lst[1..2][0]) // expect: 20
lst[-1] = 99
System.print(lst[3]) // expect: 99
lst.swap(0, 3)
System.print(lst[0]) // expect: 99
System.print(lst[3]) // expect: 10
lst.clear()
System.print(lst.count) // expect: 0

// --- Map Keys & Values ---
var m = {"a": 1, "b": 2}
System.print(m.keys.count) // expect: 2
System.print(m.values.count) // expect: 2

// --- Sequence all/any ---
var seq = [1, 2, 3]
System.print(seq.all {|x| x > 0}) // expect: true
System.print(seq.all {|x| x > 1}) // expect: false
System.print(seq.any {|x| x > 2}) // expect: true
System.print(seq.any {|x| x > 5}) // expect: false

// --- List filled/addAll/remove/indexOf ---
var filledList = List.filled(3, "x")
System.print(filledList.count) // expect: 3
System.print(filledList[0]) // expect: x
System.print(filledList[2]) // expect: x

var addAllList = [1, 2]
addAllList.addAll([3, 4])
System.print(addAllList.count) // expect: 4
System.print(addAllList[2]) // expect: 3

var removedVal = addAllList.remove(3)
System.print(removedVal) // expect: 3
System.print(addAllList.count) // expect: 3
System.print(addAllList.indexOf(4)) // expect: 2
System.print(addAllList.indexOf(99)) // expect: -1

// --- Map addAll ---
var map1 = {"a": 1}
map1.addAll({"b": 2, "c": 3})
System.print(map1.count) // expect: 3
System.print(map1["b"]) // expect: 2

// --- Num Delegation ---
var num = 0
System.print(num.sin) // expect: 0
System.print(1.5.round) // expect: 2
System.print((-5).sign) // expect: -1
