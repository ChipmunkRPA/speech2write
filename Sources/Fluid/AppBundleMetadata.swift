import Foundation

enum AppBundleMetadata {
    static let appDisplayName = "Speech2Write"
    static let organizationName = "CPA Automation"
    static let websiteURLString = "https://cpaautomation.ai"
    static let repositoryURLString = "https://github.com/ChipmunkRPA/speech2write"
}

extension Bundle {
    var fluidAppDisplayName: String {
        let displayName = self.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = self.object(forInfoDictionaryKey: "CFBundleName") as? String
        return [displayName, bundleName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? AppBundleMetadata.appDisplayName
    }
}
