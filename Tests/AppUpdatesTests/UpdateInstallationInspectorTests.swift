import Testing
@testable import AppUpdates

@Test("存在 Team Identifier 时允许应用内安装更新")
func signedBuildSupportsSparkleInstallation() {
    let mode = UpdateInstallationMode.from(teamIdentifier: "TEAM123456")
    #expect(mode.supportsInAppInstallation)
}

@Test("缺少 Team Identifier 时退回下载模式")
func unsignedBuildFallsBackToDownloadMode() {
    let mode = UpdateInstallationMode.from(teamIdentifier: nil)

    #expect(!mode.supportsInAppInstallation)
    if case let .downloadOnly(reason) = mode {
        #expect(reason.contains("Developer ID"))
    } else {
        Issue.record("Expected downloadOnly mode for unsigned build")
    }
}
