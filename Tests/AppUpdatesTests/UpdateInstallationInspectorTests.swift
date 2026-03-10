import Testing
@testable import AppUpdates

@Test("存在 Team Identifier 时允许应用内安装更新")
func signedBuildSupportsSparkleInstallation() {
    let mode = UpdateInstallationMode.from(teamIdentifier: "TEAM123456")
    #expect(mode.supportsInAppInstallation)
    #expect(mode.usesSparkle)
}

@Test("缺少 Team Identifier 时切换到内置安装器")
func unsignedBuildFallsBackToSelfManagedInstaller() {
    let mode = UpdateInstallationMode.from(teamIdentifier: nil)

    #expect(mode.supportsInAppInstallation)
    #expect(!mode.usesSparkle)
    if case let .selfManaged(reason) = mode {
        #expect(reason.contains("Developer ID"))
    } else {
        Issue.record("Expected selfManaged mode for unsigned build")
    }
}
