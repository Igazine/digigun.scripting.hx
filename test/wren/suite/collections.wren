var list = ["a", "b"]
list.add("c")
System.print(list.count) // expect: 3
System.print(list[0])    // expect: a
System.print(list[2])    // expect: c

var map = {"name": "Wren", "lang": "Script"}
System.print(map.count)        // expect: 2
System.print(map.containsKey("name")) // expect: true
System.print(map.containsKey("age"))  // expect: false
