class A {
    construct new() {}
    method() { System.print("A method") }
}

class B is A {
    construct new() {
        super()
    }
    method() {
        super.method()
        System.print("B method")
    }
}

var b = B.new()
b.method()
// expect: A method
// expect: B method
