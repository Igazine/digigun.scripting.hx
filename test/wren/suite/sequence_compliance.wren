var list = [1, 2, 3, 4, 5]

// 1. Lazy Map & Where
var mapped = list.map {|x| x * 2}
System.print("Mapped sequence type: " + (mapped is Sequence).toString)
System.print("Mapped values: " + mapped.toList.join(", "))

var filtered = list.where {|x| x % 2 != 0}
System.print("Filtered values: " + filtered.toList.join(", "))

// 2. Skip & Take
var skippedAndTaken = list.skip(2).take(2)
System.print("Skipped and taken: " + skippedAndTaken.toList.join(", "))

// 3. Reduce & Join
var sum = list.reduce(0) {|acc, x| acc + x}
System.print("Sum: " + sum.toString)

var words = ["Haxe", "Wren", "Compliance"]
System.print("Joined: " + words.join(" - "))

// 4. String Sequence compliance
var str = "abc"
System.print("String mapped: " + str.map {|c| c + "!"}.join(""))

// 5. Range Sequence compliance
var range = 1..3
System.print("Range list: " + range.toList.join(", "))

// expect: Mapped sequence type: true
// expect: Mapped values: 2, 4, 6, 8, 10
// expect: Filtered values: 1, 3, 5
// expect: Skipped and taken: 3, 4
// expect: Sum: 15
// expect: Joined: Haxe - Wren - Compliance
// expect: String mapped: a!b!c!
// expect: Range list: 1, 2, 3
