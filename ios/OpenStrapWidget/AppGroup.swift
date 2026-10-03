import Foundation

/// The App Group the app and this widget share. The SAME lookup lives in
/// Runner/AppDelegate.swift (`AppGroupResolver`); the two must agree or the
/// widget reads an empty store.
///
/// A sideload re-signs with the person's own Apple ID, and SideStore/AltStore
/// rename the group on the way (a free team cannot own `group.com.example…`).
/// The build-time Info.plist value is then wrong, so the real one is looked up
/// in the order a re-signed install records it:
///   1. `ALTAppGroups` — written into Info.plist by SideStore/AltStore,
///   2. the signed entitlements in `embedded.mobileprovision`,
///   3. the build-time `OpenStrapAppGroupIdentifier`.
/// Each source is read from this bundle and from the host app's bundle (an
/// extension lives at Koop.app/PlugIns/X.appex).
enum AppGroup {
  static let identifier: String = {
    let own = Bundle.main
    let hostURL = own.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    let bundles = [own, Bundle(url: hostURL)].compactMap { $0 }
    for b in bundles {
      if let g = (b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first, !g.isEmpty {
        return g
      }
    }
    for b in bundles {
      if let g = provisionedGroup(b.bundleURL) { return g }
    }
    return own.object(forInfoDictionaryKey: "OpenStrapAppGroupIdentifier") as? String
      ?? "group.com.example.openstrap"
  }()

  /// The first application group in the bundle's provisioning profile. The
  /// profile is a CMS envelope around a plain XML plist; the plist is cut out
  /// of it rather than verifying the signature (iOS already did that at install).
  private static func provisionedGroup(_ bundle: URL) -> String? {
    guard let data = try? Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
          let plist = try? PropertyListSerialization.propertyList(
            from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
          let ent = plist["Entitlements"] as? [String: Any],
          let groups = ent["com.apple.security.application-groups"] as? [String],
          let g = groups.first, !g.isEmpty
    else { return nil }
    return g
  }
}
