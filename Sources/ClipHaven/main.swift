import AppKit

let application = NSApplication.shared
let applicationDelegate = ClipHavenApplicationDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.accessory)
application.run()
