import Benchmark
import Foundation

let benchmarks: @Sendable () -> Void = {
  let configuration = Benchmark.Configuration(
    metrics: [.cpuUser],
    // thresholds: [.instructions: BenchmarkThresholds(relative: [.p25: 0.5, .p50: 0.5, .p75: 0.5, .p90: 0.5])]
  )
  Benchmark(
    "Fibonacci computation",
    configuration: configuration
  ) { benchmark in
    blackHole(fibonacci(35))
  }
}

func fibonacci(_ x: Int) -> Int {
  if x <= 0 {
    return 0
  }
  if x == 1 {
    return 1
  }
  return fibonacci(x - 2) + fibonacci(x - 1)
}
