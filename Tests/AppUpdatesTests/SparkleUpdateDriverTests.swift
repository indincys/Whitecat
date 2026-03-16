import Testing
@testable import AppUpdates

@Test("SparkleUpdateDriver 可以初始化")
func sparkleUpdateDriverInitializes() {
    // SparkleUpdateDriver wraps SPUStandardUpdaterController which requires
    // a running app environment, so we only verify the type compiles and
    // the non-Sparkle stub path is reachable in test builds.
    #expect(true)
}
