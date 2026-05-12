class Test {
    static run() {
        var list = [1, 2, 3]
        for (x in list) {
            System.print(x)
        }
    }
}
Test.run()
// expect: 1
// expect: 2
// expect: 3
