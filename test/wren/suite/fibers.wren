var f = Fiber.new {
  System.print("Fiber start")
  Fiber.yield()
  System.print("Fiber resumed")
  var res = Fiber.yield("Yielded value")
  System.print("Value from call: " + res)
  System.print("Fiber end")
  return "Return value"
}

System.print("Calling fiber")
f.call() 
// expect: Calling fiber
// expect: Fiber start

System.print("Back in main")
f.call()
// expect: Back in main
// expect: Fiber resumed

System.print("Resuming with value")
var finalRes = f.call("Hello from main")
// expect: Resuming with value
// expect: Value from call: Hello from main
// expect: Fiber end

System.print("Final result: " + finalRes)
// expect: Final result: Return value
