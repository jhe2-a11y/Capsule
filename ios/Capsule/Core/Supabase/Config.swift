import Foundation

enum AppConfig {
    static let supabaseURL: URL = {
        guard let s = bundleString("SUPABASE_URL"), let u = URL(string: s) else {
            fatalError("Config.plist missing SUPABASE_URL")
        }
        return u
    }()

    static let supabaseAnonKey: String = {
        guard let s = bundleString("SUPABASE_ANON_KEY") else {
            fatalError("Config.plist missing SUPABASE_ANON_KEY")
        }
        return s
    }()

    static let universalLinkHost: String = {
        bundleString("UNIVERSAL_LINK_HOST") ?? "capsule.app"
    }()

    private static func bundleString(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }
}
