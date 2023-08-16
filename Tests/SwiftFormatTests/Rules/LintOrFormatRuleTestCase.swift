import SwiftFormatConfiguration
import SwiftOperators
import SwiftParser
import SwiftSyntax
import XCTest

@_spi(Rules) @_spi(Testing) import SwiftFormat
@_spi(Testing) import _SwiftFormatTestSupport

class LintOrFormatRuleTestCase: DiagnosingTestCase {
  /// Performs a lint using the provided linter rule on the provided input.
  ///
  /// - Parameters:
  ///   - type: The metatype of the lint rule you wish to perform.
  ///   - input: The input code.
  ///   - file: The file the test resides in (defaults to the current caller's file)
  ///   - line:  The line the test resides in (defaults to the current caller's line)
  final func performLint<LintRule: SyntaxLintRule>(
    _ type: LintRule.Type,
    input: String,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let sourceFileSyntax = try! restoringLegacyTriviaBehavior(
      OperatorTable.standardOperators.foldAll(Parser.parse(source: input))
        .as(SourceFileSyntax.self)!)

    // Force the rule to be enabled while we test it.
    var configuration = Configuration.forTesting
    configuration.rules[type.ruleName] = true
    let context = makeContext(sourceFileSyntax: sourceFileSyntax, configuration: configuration)

    // If we're linting, then indicate that we want to fail for unasserted diagnostics when the test
    // is torn down.
    shouldCheckForUnassertedDiagnostics = true

    let linter = type.init(context: context)
    linter.walk(sourceFileSyntax)
  }

  /// Asserts that the result of applying a formatter to the provided input code yields the output.
  ///
  /// This method should be called by each test of each rule.
  ///
  /// - Parameters:
  ///   - formatType: The metatype of the format rule you wish to apply.
  ///   - input: The unformatted input code.
  ///   - expected: The expected result of formatting the input code.
  ///   - checkForUnassertedDiagnostics: Fail the test if there are any unasserted linter
  ///     diagnostics.
  ///   - configuration: The configuration to use when formatting (or nil to use the default).
  ///   - file: The file the test resides in (defaults to the current caller's file)
  ///   - line:  The line the test resides in (defaults to the current caller's line)
  final func XCTAssertFormatting(
    _ formatType: SyntaxFormatRule.Type,
    input: String,
    expected: String,
    checkForUnassertedDiagnostics: Bool = false,
    configuration: Configuration? = nil,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let sourceFileSyntax = try! restoringLegacyTriviaBehavior(
      OperatorTable.standardOperators.foldAll(Parser.parse(source: input))
        .as(SourceFileSyntax.self)!)

    // Force the rule to be enabled while we test it.
    var configuration = configuration ?? Configuration.forTesting
    configuration.rules[formatType.ruleName] = true
    let context = makeContext(sourceFileSyntax: sourceFileSyntax, configuration: configuration)

    shouldCheckForUnassertedDiagnostics = checkForUnassertedDiagnostics
    let formatter = formatType.init(context: context)
    let actual = formatter.visit(sourceFileSyntax)
    XCTAssertStringsEqualWithDiff(actual.description, expected, file: file, line: line)
  }
}