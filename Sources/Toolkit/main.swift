import AppKit

let toolkitDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = toolkitDelegate
application.setActivationPolicy(.accessory)
application.run()
