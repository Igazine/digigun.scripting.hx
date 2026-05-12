var f = Fiber.new {
    System.print("Fiber start")
    Fiber.abort("Error in fiber")
}

var error = f.try()
if (error == null) {
    System.print("Result: null")
} else {
    System.print("Result: " + error)
}
if (f.error == null) {
    System.print("State: null")
} else {
    System.print("State: " + f.error)
}

// expect: Fiber start
// expect: Result: Error in fiber
// expect: State: Error in fiber
