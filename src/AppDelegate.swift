import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent system from auto-terminating background menu bar app
        ProcessInfo.processInfo.disableAutomaticTermination("Lattice menu bar agent")
        
        // Run as menu bar agent (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar item
        StatusBarController.shared.setup()
        
        // Start global hotkey monitoring via Carbon RegisterEventHotKey
        HotKeyManager.shared.start()
        
        // Listen for distributed commands
        setupDistributedNotifications()
        
        // Check accessibility silently (do not spam prompt dialog)
        let isTrusted = WindowManager.shared.isAccessibilityGranted()
        LogDebug("Lattice launched. AXIsProcessTrusted: \(isTrusted)")
        NSLog("[Lattice] Lattice started successfully. Accessibility trusted: \(isTrusted)")
        
        // Auto-show HUD upon launch so user immediately sees Lattice and knows how to use it!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            GridHUDController.shared.showHUD()
        }
    }
    
    private func setupDistributedNotifications() {
        let center = DistributedNotificationCenter.default()
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.toggleHUD"), object: nil, queue: .main) { _ in
            GridHUDController.shared.toggleHUD()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.showHUD"), object: nil, queue: .main) { _ in
            GridHUDController.shared.showHUD()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.hideHUD"), object: nil, queue: .main) { _ in
            GridHUDController.shared.hideHUD()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.snapLeft"), object: nil, queue: .main) { _ in
            WindowManager.shared.snapLeftHalf()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.snapRight"), object: nil, queue: .main) { _ in
            WindowManager.shared.snapRightHalf()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.snapMax"), object: nil, queue: .main) { _ in
            WindowManager.shared.snapMaximize()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.snapCenter"), object: nil, queue: .main) { _ in
            WindowManager.shared.snapCenterSmall()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.throwNext"), object: nil, queue: .main) { _ in
            WindowManager.shared.throwToNextScreen()
        }
        
        center.addObserver(forName: NSNotification.Name("com.fontour.lattice.throwPrev"), object: nil, queue: .main) { _ in
            WindowManager.shared.throwToPrevScreen()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
    }
}
