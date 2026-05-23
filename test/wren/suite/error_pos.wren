var fn = Fn.new {
    System.print("In function")
    "string".nonExistent()
}

System.print("Calling function")
fn.call()
System.print("After function")

// expect: Calling function
// expect: In function
// expect: [line 3] Runtime Error: Method nonExistent() not found on String.
// expect: [line 3, col 6] in call
// expect: [line 1, col 17] in call
// expect: [line 1, col 1] in script
