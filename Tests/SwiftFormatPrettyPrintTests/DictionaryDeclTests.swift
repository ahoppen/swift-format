import SwiftSyntax

@testable import SwiftFormatPrettyPrint

public class DictionaryDeclTests: PrettyPrintTestCase {
  public func testBasicDictionaries() {
    let input =
      """
      let a = [1: "a", 2: "b", 3: "c",]
      let a: [Int: String] = [1: "a", 2: "b", 3: "c"]
      let a = [10000: "abc", 20000: "def", 30000: "ghi"]
      let a = [10000: "abc", 20000: "def", 30000: "ghij"]
      let a: [Int: String] = [1: "a", 2: "b", 3: "c", 4: "d"]
      let a: [Int: String] = [1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f", 7: "g"]
      let a: [Int: String] = [1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f", 7: "g",]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g", 8: "i",
      ]
      """

    let expected =
      """
      let a = [1: "a", 2: "b", 3: "c"]
      let a: [Int: String] = [1: "a", 2: "b", 3: "c"]
      let a = [10000: "abc", 20000: "def", 30000: "ghi"]
      let a = [
        10000: "abc", 20000: "def", 30000: "ghij",
      ]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d",
      ]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g",
      ]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g",
      ]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g", 8: "i",
      ]

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testNoTrailingCommasInTypes() {
    let input =
      """
      let a = [SomeVeryLongKeyType: SomePrettyLongValueType]()
      """

    let expected =
      """
      let a = [
        SomeVeryLongKeyType: SomePrettyLongValueType
      ]()

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testWhitespaceOnlyDoesNotChangeTrailingComma() {
    let input =
      """
      let a = [1: "a", 2: "b", 3: "c",]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g", 8: "i"
      ]
      """

    assertPrettyPrintEqual(
      input: input, expected: input + "\n", linelength: 50, whitespaceOnly: true)
  }

  public func testTrailingCommaDiagnostics() {
    let input =
      """
      let a = [1: "a", 2: "b", 3: "c",]
      let a: [Int: String] = [
        1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f",
        7: "g", 8: "i"
      ]
      """

    assertPrettyPrintEqual(
      input: input, expected: input + "\n", linelength: 50, whitespaceOnly: true)

    XCTAssertDiagnosed(Diagnostic.Message.removeTrailingComma, line: 1, column: 32)
    XCTAssertDiagnosed(Diagnostic.Message.addTrailingComma, line: 4, column: 17)
  }
}
