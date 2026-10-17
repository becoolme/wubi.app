import Cocoa
import InputMethodKit

let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "Mobi_Connection"
guard let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    NSLog("Mobi: could not start the input method server")
    exit(1)
}

InputSources.migrate()
Updater.shared.start()
Dictionary.preparePinyin()

let app = NSApplication.shared
app.run()
