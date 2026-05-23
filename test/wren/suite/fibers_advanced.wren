var main = Fiber.current
System.print("main state: " + main.state)
System.print("main isDone: " + main.isDone)

var f1 = Fiber.new {
  System.print("f1 started")
  return "result of f1"
}

System.print("f1 state: " + f1.state)
System.print("f1 isDone: " + f1.isDone)

var res1 = f1.try()
System.print("res1: " + res1)
System.print("f1 state: " + f1.state)
System.print("f1 isDone: " + f1.isDone)

var f2 = Fiber.new {
  System.print("f2 started")
  var val = Fiber.suspend()
  System.print("f2 resumed with: " + val)
  return "f2 finished"
}

System.print("f2 state: " + f2.state)
f2.call()
System.print("f2 suspended state: " + f2.state)
var res2 = f2.call("hello suspend")
System.print("res2: " + res2)
System.print("f2 state: " + f2.state)
System.print("f2 isDone: " + f2.isDone)

var f3 = Fiber.new {
  System.print("f3 started")
  System.print("f3 current state: " + Fiber.current.state)
  main.transfer("from f3")
  System.print("should not be reached")
}

var res3 = f3.call()
System.print("res3: " + res3)
System.print("f3 state: " + f3.state)
System.print("f3 isDone: " + f3.isDone)

// expect: main state: running
// expect: main isDone: false
// expect: f1 state: suspended
// expect: f1 isDone: false
// expect: f1 started
// expect: res1: result of f1
// expect: f1 state: done
// expect: f1 isDone: true
// expect: f2 state: suspended
// expect: f2 started
// expect: f2 suspended state: suspended
// expect: f2 resumed with: hello suspend
// expect: res2: f2 finished
// expect: f2 state: done
// expect: f2 isDone: true
// expect: f3 started
// expect: f3 current state: running
// expect: res3: from f3
// expect: f3 state: suspended
// expect: f3 isDone: false
