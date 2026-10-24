import Cocoa

let args = CommandLine.arguments

// If invoked with a command flag, forward to running instance via DistributedNotificationCenter
if args.count > 1 {
    let cmd = args[1]
    let center = DistributedNotificationCenter.default()
    var notificationName: String? = nil
    
    switch cmd {
    case "--status":
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility Trusted:", isTrusted)
        if let target = WindowManager.shared.captureCurrentFrontmostWindow() {
            print("Front App:", target.app.localizedName ?? "nil", "pid:", target.app.processIdentifier)
            print("Window Title:", target.windowTitle)
            print("Screen Frame:", target.screen.frame, "VisibleFrame:", target.screen.visibleFrame)
        } else {
            print("No front window captured.")
        }
        exit(0)
    case "--toggle", "-t":
        notificationName = "com.fontour.lattice.toggleHUD"
    case "--show", "-s":
        notificationName = "com.fontour.lattice.showHUD"
    case "--hide":
        notificationName = "com.fontour.lattice.hideHUD"
    case "--left", "-l":
        notificationName = "com.fontour.lattice.snapLeft"
    case "--right", "-r":
        notificationName = "com.fontour.lattice.snapRight"
    case "--max", "-m":
        notificationName = "com.fontour.lattice.snapMax"
    case "--center", "-c":
        notificationName = "com.fontour.lattice.snapCenter"
    case "--next-screen", "--next", "-n":
        notificationName = "com.fontour.lattice.throwNext"
    case "--prev-screen", "--prev", "-p":
        notificationName = "com.fontour.lattice.throwPrev"
    case "--help", "-h":
        print("Lattice (Swift Edition)")
        print("Usage:")
        print("  Lattice               Launch background daemon and menu bar app")
        print("  Lattice --status      Check accessibility and frontmost window status")
        print("  Lattice --toggle      Toggle grid HUD overlay")
        print("  Lattice --left        Snap active window to left half / cycle thirds (⌘⇧←)")
        print("  Lattice --right       Snap active window to right half / cycle thirds (⌘⇧→)")
        print("  Lattice --max         Maximize active window / cycle top-half (⌘⇧↑)")
        print("  Lattice --center      Center active window / cycle sizes (⌘⇧↓)")
        print("  Lattice --next-screen Throw active window to next display (⌃⌥⌘→)")
        print("  Lattice --prev-screen Throw active window to previous display (⌃⌥⌘←)")
        exit(0)
    default:
        break
    }
    
    if let name = notificationName {
        center.postNotificationName(NSNotification.Name(name), object: nil, deliverImmediately: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
