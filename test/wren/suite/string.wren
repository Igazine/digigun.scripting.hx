var s = "Hello Wren"
System.print(s.startsWith("Hello")) // expect: true
System.print(s.endsWith("Wren"))   // expect: true
System.print(s.contains("Wren"))   // expect: true
System.print(s.contains("Haxe"))   // expect: false
System.print(s.count)              // expect: 10
