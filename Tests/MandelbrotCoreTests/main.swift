import Foundation

private var failures = 0
private var assertions = 0
private func check(_ success: Bool, _ description: String, file: StaticString, line: UInt) {
    assertions += 1
    if !success { failures += 1; print("FAIL \(file):\(line): \(description)") }
}
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    check(lhs == rhs, "\(lhs) != \(rhs)", file: file, line: line)
}
func expectEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(lhs - rhs) <= accuracy, "\(lhs) differs from \(rhs) by more than \(accuracy)", file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { check(value, "Expected true", file: file, line: line) }
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { check(!value, "Expected false", file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { check(value == nil, "Expected nil", file: file, line: line) }
func expectGreater<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    check(lhs > rhs, "\(lhs) is not greater than \(rhs)", file: file, line: line)
}
func expectLess<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    check(lhs < rhs, "\(lhs) is not less than \(rhs)", file: file, line: line)
}
func expectThrows<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body(); check(false, "Expected an error", file: file, line: line) }
    catch { check(true, "", file: file, line: line) }
}
func expectNoThrow<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body(); check(true, "", file: file, line: line) }
    catch { check(false, "Unexpected error: \(error)", file: file, line: line) }
}
struct UnwrapError: Error {}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw UnwrapError() }; return value
}

let suite = MandelbrotCoreTests()
let tests: [(String, () throws -> Void)] = [
    ("Known interior and exterior points", suite.testKnownInteriorAndExteriorPoints),
    ("Conjugate symmetry", suite.testConjugateSymmetry),
    ("Cursor-anchored zoom", suite.testCursorAnchoredZoomKeepsComplexPointFixed),
    ("Aspect-correct panning", suite.testPanUsesViewportAspectAndIsReversible),
    ("Zoom bounds and invalid input", suite.testZoomBoundsAndInvalidFactors),
    ("History and branching", suite.testHistoryRoundTripAndBranching),
    ("Saved-view precision and settings", suite.testSavedViewPreservesFullPrecisionAndAllSettings),
    ("Malformed and unsupported files", suite.testRejectsInvalidAndUnsupportedFiles),
    ("Export size limits and 8K", suite.testRejectsOversizedExportAndAccepts8K),
    ("PNG and JPEG encoding", suite.testPNGAndJPEGAreRealImagesAtRequestedDimensions),
    ("Deterministic symmetric rendering", suite.testRenderingIsDeterministicAndVerticallySymmetric),
    ("Live render cancellation", suite.testCancellationBeforeAndDuringRendering)
]
for (name, run) in tests {
    let before = failures
    do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(tests.count) checks, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
