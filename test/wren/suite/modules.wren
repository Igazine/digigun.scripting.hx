import "mod_a" for Value, Greeter

System.print(Value) // expect: Module A Value
Greeter.sayHello()  // expect: Hello from Module A

import "mod_a" for Value as Alias
System.print(Alias) // expect: Module A Value
