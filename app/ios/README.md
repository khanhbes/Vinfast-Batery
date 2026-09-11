# iOS build notes

The iOS project is configured for iOS 15+, portrait-only, Local Network/Bonjour
Shelly discovery, location tracking and APNs background notifications. Run
`flutter create --platforms=ios .` once on macOS to materialize the generated
Runner Xcode project files, then run `flutterfire configure --platforms=ios`
to replace the placeholder Firebase app identifiers before signing.
