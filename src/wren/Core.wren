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
