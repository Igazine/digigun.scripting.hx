class Object {
    toString { "[object]" }
}

class String is Object {}
class Num is Object {}
class Bool is Object {}
class Null is Object {}

class System {
    static print(value) {
        __print(value)
    }
}

class Fn is Object {
    foreign call()
    foreign call(a)
    foreign call(a, b)
    foreign call(a, b, c)
}

class Fiber is Object {
    construct new(fn) foreign
    foreign static yield()
    foreign static yield(v)
    foreign call()
    foreign call(v)
    foreign transfer()
    foreign transfer(v)
    foreign try()
    foreign error
    foreign state
    foreign static abort(msg)
}
