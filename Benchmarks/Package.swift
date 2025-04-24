// swift-tools-version: 5.8
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCertificates open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftCertificates project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftCertificates project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
  name: "benchmarks",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    // .package(name: "swift-format", path: "../"),
    .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.11.1"),
  ],
  targets: [
    .executableTarget(
      name: "MyBenchmark",
      dependencies: [
        .product(name: "Benchmark", package: "package-benchmark"),
        // .product(name: "SwiftFormat", package: "swift-format"),
      ],
      path: "Benchmarks/MyBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ]
)
