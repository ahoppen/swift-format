//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Internal) import SwiftFormat
import SwiftParser
import SwiftSyntax

class Frontend {
  /// Provides formatter configurations for given `.swift` source files, configuration files or configuration strings.
  struct ConfigurationProvider {
    /// Loads formatter configuration files and chaches them in memory.
    private var configurationLoader: ConfigurationLoader = ConfigurationLoader()

    /// The diagnostic engine to which warnings and errors will be emitted.
    private let diagnosticsEngine: DiagnosticsEngine

    /// Creates a new instance with the given options.
    ///
    /// - Parameter diagnosticsEngine: The diagnostic engine to which warnings and errors will be emitted.
    init(diagnosticsEngine: DiagnosticsEngine) {
      self.diagnosticsEngine = diagnosticsEngine
    }

    /// Checks if all the rules in the given configuration are supported by the registry.
    ///
    /// If there are any rules that are not supported, they are emitted as a warning.
    private func checkForUnrecognizedRules(in configuration: Configuration) {
      // If any rules in the decoded configuration are not supported by the registry,
      // emit them into the diagnosticsEngine as warnings.
      // That way they will be printed out, but we'll continue execution on the valid rules.
      let invalidRules = configuration.rules.filter { !RuleRegistry.rules.keys.contains($0.key) }
      for rule in invalidRules {
        diagnosticsEngine.emitWarning("Configuration contains an unrecognized rule: \(rule.key)", location: nil)
      }
    }

    /// Returns the configuration that applies to the given `.swift` source file, when an explicit
    /// configuration path is also perhaps provided.
    ///
    /// This method also checks for unrecognized rules within the configuration.
    ///
    /// - Parameters:
    ///   - pathOrString: A string containing either the path to a configuration file that will be
    ///     loaded, JSON configuration data directly, or `nil` to try to infer it from
    ///     `swiftFileURL`.
    ///   - swiftFileURL: The path to a `.swift` file, which will be used to infer the path to the
    ///     configuration file if `configurationFilePath` is nil.
    ///
    /// - Returns: If successful, the returned configuration is the one loaded from `pathOrString` if
    ///   it was provided, or by searching in paths inferred by `swiftFileURL` if one exists, or the
    ///   default configuration otherwise. If an error occurred when reading the configuration, a
    ///   diagnostic is emitted and `nil` is returned. If neither `pathOrString` nor `swiftFileURL`
    ///   were provided, a default `Configuration()` will be returned.
    mutating func provide(
      forConfigPathOrString pathOrString: String?,
      orForSwiftFileAt swiftFileURL: URL?
    ) -> Configuration? {
      if let pathOrString = pathOrString {
        // If an explicit configuration file path was given, try to load it and fail if it cannot be
        // loaded. (Do not try to fall back to a path inferred from the source file path.)
        let configurationFileURL = URL(fileURLWithPath: pathOrString)
        do {
          let configuration = try configurationLoader.configuration(at: configurationFileURL)
          self.checkForUnrecognizedRules(in: configuration)
          return configuration
        } catch {
          // If we failed to load this from the path, try interpreting the string as configuration
          // data itself because the user might have written something like `--configuration '{...}'`,
          let data = pathOrString.data(using: .utf8)!
          if let configuration = try? Configuration(data: data) {
            return configuration
          }

          // Fail if the configuration flag was neither a valid file path nor valid configuration
          // data.
          diagnosticsEngine.emitError("Unable to read configuration: \(error.localizedDescription)")
          return nil
        }
      }

      // If no explicit configuration file path was given but a `.swift` source file path was given,
      // then try to load the configuration by inferring it based on the source file path.
      if let swiftFileURL = swiftFileURL {
        do {
          if let configuration = try configurationLoader.configuration(forPath: swiftFileURL) {
            self.checkForUnrecognizedRules(in: configuration)
            return configuration
          }
          // Fall through to the default return at the end of the function.
        } catch {
          diagnosticsEngine.emitError(
            "Unable to read configuration for \(swiftFileURL.relativePath): \(error.localizedDescription)"
          )
          return nil
        }
      } else {
        // If reading from stdin and no explicit configuration file was given,
        // walk up the file tree from the cwd to find a config.

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // Definitely a Swift file. Definitely not a directory. Shhhhhh.
        do {
          if let configuration = try configurationLoader.configuration(forPath: cwd) {
            self.checkForUnrecognizedRules(in: configuration)
            return configuration
          }
        } catch {
          diagnosticsEngine.emitError(
            "Unable to read configuration for \(cwd.relativePath): \(error.localizedDescription)"
          )
          return nil
        }
      }

      // An explicit configuration has not been given, and one cannot be found.
      // Return the default configuration.
      return Configuration()
    }
  }

  /// Represents a file to be processed by the frontend and any file-specific options associated
  /// with it.
  final class FileToProcess {
    /// An open file handle to the source code of the file.
    private let fileHandle: FileHandle

    /// A file URL representing the path to the source file being processed.
    ///
    /// It is the responsibility of the specific frontend to make guarantees about the validity of
    /// this path. For example, the formatting frontend ensures that it is a path to an existing
    /// file only when doing in-place formatting (so that the file can be replaced). In other
    /// situations, it may correspond to a different file than the underlying file handle (if
    /// standard input is used with the `--assume-filename` flag), or it may not be a valid path at
    /// all (the string `"<stdin>"`).
    let url: URL

    /// The configuration that should applied for this file.
    let configuration: Configuration

    /// the selected ranges to process
    let selection: Selection

    /// Returns the string contents of the file.
    ///
    /// The contents of the file are assumed to be UTF-8 encoded. If there is an error decoding the
    /// contents, `nil` will be returned.
    lazy var sourceText: String? = {
      let sourceData = fileHandle.readDataToEndOfFile()
      defer { fileHandle.closeFile() }
      return String(data: sourceData, encoding: .utf8)
    }()

    init(
      fileHandle: FileHandle,
      url: URL,
      configuration: Configuration,
      selection: Selection = .infinite
    ) {
      self.fileHandle = fileHandle
      self.url = url
      self.configuration = configuration
      self.selection = selection
    }
  }

  /// Prints diagnostics to standard error, optionally with color.
  final let diagnosticPrinter: StderrDiagnosticPrinter

  /// The diagnostic engine to which warnings and errors will be emitted.
  final let diagnosticsEngine: DiagnosticsEngine

  /// Options that control the tool's configuration.
  final let configurationOptions: ConfigurationOptions

  /// Options that apply during formatting or linting.
  final let lintFormatOptions: LintFormatOptions

  /// The provider for formatter configurations.
  final var configurationProvider: ConfigurationProvider

  /// Advanced options that are useful for developing/debugging but otherwise not meant for general
  /// use.
  final var debugOptions: DebugOptions {
    [
      lintFormatOptions.debugDisablePrettyPrint ? .disablePrettyPrint : [],
      lintFormatOptions.debugDumpTokenStream ? .dumpTokenStream : [],
    ]
  }

  /// Creates a new frontend with the given options.
  ///
  /// - Parameter lintFormatOptions: Options that apply during formatting or linting.
  init(
    configurationOptions: ConfigurationOptions,
    lintFormatOptions: LintFormatOptions,
    treatWarningsAsErrors: Bool = false
  ) {
    self.configurationOptions = configurationOptions
    self.lintFormatOptions = lintFormatOptions

    self.diagnosticPrinter = StderrDiagnosticPrinter(
      colorMode: lintFormatOptions.colorDiagnostics.map { $0 ? .on : .off } ?? .auto
    )
    self.diagnosticsEngine = DiagnosticsEngine(
      diagnosticsHandlers: [diagnosticPrinter.printDiagnostic],
      treatWarningsAsErrors: treatWarningsAsErrors
    )
    self.configurationProvider = ConfigurationProvider(diagnosticsEngine: self.diagnosticsEngine)
  }

  /// Runs the linter or formatter over the inputs.
  final func run() {
    if lintFormatOptions.paths == ["-"] {
      processStandardInput()
    } else if lintFormatOptions.paths.isEmpty {
      diagnosticsEngine.emitWarning(
        """
        Running swift-format without input paths is deprecated and will be removed in the future.

        Please update your invocation to do either of the following:

        - Pass `-` to read from stdin (e.g., `cat MyFile.swift | swift-format -`).
        - Pass one or more paths to Swift source files or directories containing
          Swift source files. When passing directories, make sure to include the
          `--recursive` flag.

        For more information, use the `--help` option.
        """
      )
      processStandardInput()
    } else {
      processURLs(
        lintFormatOptions.paths.map(URL.init(fileURLWithPath:)),
        parallel: lintFormatOptions.parallel
      )
    }
  }

  /// Called by the frontend to process a single file.
  ///
  /// Subclasses must override this method to provide the actual linting or formatting logic.
  ///
  /// - Parameter fileToProcess: A `FileToProcess` that contains information about the file to be
  ///   processed.
  func processFile(_ fileToProcess: FileToProcess) {
    fatalError("Must be overridden by subclasses.")
  }

  /// Processes source content from standard input.
  private func processStandardInput() {
    let assumedUrl = lintFormatOptions.assumeFilename.map(URL.init(fileURLWithPath:))

    guard
      let configuration = configurationProvider.provide(
        forConfigPathOrString: configurationOptions.configuration,
        orForSwiftFileAt: assumedUrl
      )
    else {
      // Already diagnosed in the called method.
      return
    }

    let fileToProcess = FileToProcess(
      fileHandle: FileHandle.standardInput,
      url: assumedUrl ?? URL(fileURLWithPath: "<stdin>"),
      configuration: configuration,
      selection: Selection(offsetRanges: lintFormatOptions.offsets)
    )
    processFile(fileToProcess)
  }

  /// Processes source content from a list of files and/or directories provided as file URLs.
  private func processURLs(_ urls: [URL], parallel: Bool) {
    precondition(
      !urls.isEmpty,
      "processURLs(_:) should only be called when 'urls' is non-empty."
    )

    if parallel {
      let filesToProcess =
        FileIterator(urls: urls, followSymlinks: lintFormatOptions.followSymlinks)
        .compactMap(openAndPrepareFile)
      DispatchQueue.concurrentPerform(iterations: filesToProcess.count) { index in
        processFile(filesToProcess[index])
      }
    } else {
      FileIterator(urls: urls, followSymlinks: lintFormatOptions.followSymlinks)
        .lazy
        .compactMap(openAndPrepareFile)
        .forEach(processFile)
    }
  }

  /// Read and prepare the file at the given path for processing, optionally synchronizing
  /// diagnostic output.
  private func openAndPrepareFile(at url: URL) -> FileToProcess? {
    guard let sourceFile = try? FileHandle(forReadingFrom: url) else {
      diagnosticsEngine.emitError(
        "Unable to open \(url.relativePath): file is not readable or does not exist"
      )
      return nil
    }

    guard
      let configuration = configurationProvider.provide(
        forConfigPathOrString: configurationOptions.configuration,
        orForSwiftFileAt: url
      )
    else {
      // Already diagnosed in the called method.
      return nil
    }

    return FileToProcess(
      fileHandle: sourceFile,
      url: url,
      configuration: configuration,
      selection: Selection(offsetRanges: lintFormatOptions.offsets)
    )
  }

}
