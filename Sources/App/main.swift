import AppKit

// 표시 언어 오버라이드는 어떤 문자열보다 먼저 설치한다(기본 영어).
MainActor.assumeIsolated { LanguageManager.install() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)    // 메뉴바 상주, Dock 아이콘 숨김
app.run()
