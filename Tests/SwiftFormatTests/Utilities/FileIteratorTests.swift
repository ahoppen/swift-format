@_spi(Internal) import SwiftFormat
import XCTest

final class FileIteratorTests: XCTestCase {
  private var tmpdir: URL!

  override func setUpWithError() throws {
    tmpdir = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: FileManager.default.temporaryDirectory,
      create: true
    )

    // Create a simple file tree used by the tests below.
    try touch("project/real1.swift")
    try touch("project/real2.swift")
    try touch("project/.hidden.swift")
    try touch("project/.build/generated.swift")
    try symlink("project/link.swift", to: "project/.hidden.swift")
    try symlink("project/rellink.swift", relativeTo: ".hidden.swift")
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: tmpdir)
  }

  func testNoFollowSymlinks() throws {
    #if os(Windows) && compiler(<5.10)
    try XCTSkipIf(true, "Foundation does not follow symlinks on Windows")
    #endif
    let seen = allFilesSeen(iteratingOver: [tmpdir], followSymlinks: false)
    XCTAssertEqual(seen.count, 2)
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/real1.swift") })
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/real2.swift") })
  }

  func testFollowSymlinks() throws {
    #if os(Windows) && compiler(<5.10)
    try XCTSkipIf(true, "Foundation does not follow symlinks on Windows")
    #endif
    let seen = allFilesSeen(iteratingOver: [tmpdir], followSymlinks: true)
    XCTAssertEqual(seen.count, 3)
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/real1.swift") })
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/real2.swift") })
    // Hidden but found through the visible symlink project/link.swift
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/.hidden.swift") })
  }

  func testTraversesHiddenFilesIfExplicitlySpecified() throws {
    #if os(Windows) && compiler(<5.10)
    try XCTSkipIf(true, "Foundation does not follow symlinks on Windows")
    #endif
    let seen = allFilesSeen(
      iteratingOver: [tmpURL("project/.build"), tmpURL("project/.hidden.swift")],
      followSymlinks: false
    )
    XCTAssertEqual(seen.count, 2)
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/.build/generated.swift") })
      XCTAssertTrue(seen.contains { $0.path.hasSuffix("project/.hidden.swift") })
  }

  func testDoesNotFollowSymlinksIfFollowSymlinksIsFalseEvenIfExplicitlySpecified() {
    // Symlinks are not traversed even if `followSymlinks` is false even if they are explicitly
    // passed to the iterator. This is meant to avoid situations where a symlink could be hidden by
    // shell expansion; for example, if the user writes `swift-format --no-follow-symlinks *`, if
    // the current directory contains a symlink, they would probably *not* expect it to be followed.
    let seen = allFilesSeen(
      iteratingOver: [tmpURL("project/link.swift"), tmpURL("project/rellink.swift")],
      followSymlinks: false
    )
    XCTAssertTrue(seen.isEmpty)
  }

    func testDoesNotTrimFirstCharacterOfPathIfRunningInRoot() throws {
      // Make sure that we don't drop the begining of the path if we are running in root.
      // https://github.com/swiftlang/swift-format/issues/862
        FileManager.default.changeCurrentDirectoryPath("/")
        let seen = allFilesSeen(iteratingOver: [tmpdir], followSymlinks: false)
        XCTAssertEqual(seen.count, 2)
        XCTAssertTrue(seen.contains { $0.path.hasPrefix("/private/var") })
        XCTAssertTrue(seen.contains { $0.path.hasPrefix("/private/var") })
    }

    func testShowsRelativePaths() throws {
      // Make sure that we still show the relative path if using them.
      // https://github.com/swiftlang/swift-format/issues/862
        FileManager.default.changeCurrentDirectoryPath(tmpdir.path)
        let seen = allFilesSeen(iteratingOver: [URL(fileURLWithPath: ".")], followSymlinks: false)
        XCTAssertEqual(seen.count, 2)
        XCTAssertTrue(seen.contains { $0.relativePath == "project/real1.swift" })
        XCTAssertTrue(seen.contains { $0.relativePath == "project/real2.swift" })
    }
}

extension FileIteratorTests {
  /// Returns a URL to a file or directory in the test's temporary space.
  private func tmpURL(_ path: String) -> URL {
    return tmpdir.appendingPathComponent(path, isDirectory: false)
  }

  /// Create an empty file at the given path in the test's temporary space.
  private func touch(_ path: String) throws {
    let fileURL = tmpURL(path)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    struct FailedToCreateFileError: Error {
      let url: URL
    }
    if !FileManager.default.createFile(atPath: fileURL.path, contents: Data()) {
      throw FailedToCreateFileError(url: fileURL)
    }
  }

  /// Create a absolute symlink between files or directories in the test's temporary space.
  private func symlink(_ source: String, to target: String) throws {
    try FileManager.default.createSymbolicLink(
      at: tmpURL(source),
      withDestinationURL: tmpURL(target)
    )
  }

  /// Create a relative symlink between files or directories in the test's temporary space.
  private func symlink(_ source: String, relativeTo target: String) throws {
    try FileManager.default.createSymbolicLink(
      atPath: tmpURL(source).path,
      withDestinationPath: target
    )
  }

  /// Computes the list of all files seen by using `FileIterator` to iterate over the given URLs.
  private func allFilesSeen(iteratingOver urls: [URL], followSymlinks: Bool) -> [URL] {
    let iterator = FileIterator(urls: urls, followSymlinks: followSymlinks)
    var seen: [URL] = []
    for next in iterator {
      seen.append(next)
    }
    return seen
  }
}
