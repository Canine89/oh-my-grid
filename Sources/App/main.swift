import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)    // 메뉴바 상주, Dock 아이콘 숨김
app.run()
