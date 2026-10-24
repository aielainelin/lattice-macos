import Cocoa

final class StatusBarController {
    static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem!
    private var contextMenu: NSMenu!
    
    private init() {}
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = createGridIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Lattice - 視窗格線分割與管理 (點擊開啟，右鍵選單)"
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "顯示 Lattice 格線面板", action: #selector(showHUDAction), keyEquivalent: " ")
        showItem.keyEquivalentModifierMask = [.control, .option]
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Presets
        let leftItem = NSMenuItem(title: "靠左半螢幕", action: #selector(snapLeftAction), keyEquivalent: String(utf16CodeUnits: [0xF702], count: 1))
        leftItem.keyEquivalentModifierMask = [.command, .shift]
        leftItem.target = self
        menu.addItem(leftItem)
        
        let rightItem = NSMenuItem(title: "靠右半螢幕", action: #selector(snapRightAction), keyEquivalent: String(utf16CodeUnits: [0xF703], count: 1))
        rightItem.keyEquivalentModifierMask = [.command, .shift]
        rightItem.target = self
        menu.addItem(rightItem)
        
        let maxItem = NSMenuItem(title: "最大化全螢幕", action: #selector(snapMaxAction), keyEquivalent: String(utf16CodeUnits: [0xF700], count: 1))
        maxItem.keyEquivalentModifierMask = [.command, .shift]
        maxItem.target = self
        menu.addItem(maxItem)
        
        let centerItem = NSMenuItem(title: "置中適中視窗", action: #selector(snapCenterAction), keyEquivalent: String(utf16CodeUnits: [0xF701], count: 1))
        centerItem.keyEquivalentModifierMask = [.command, .shift]
        centerItem.target = self
        menu.addItem(centerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Multi-monitor Throw
        let nextScrItem = NSMenuItem(title: "移至下一個螢幕", action: #selector(throwNextAction), keyEquivalent: String(utf16CodeUnits: [0xF703], count: 1))
        nextScrItem.keyEquivalentModifierMask = [.control, .option, .command]
        nextScrItem.target = self
        menu.addItem(nextScrItem)
        
        let prevScrItem = NSMenuItem(title: "移至上一個螢幕", action: #selector(throwPrevAction), keyEquivalent: String(utf16CodeUnits: [0xF702], count: 1))
        prevScrItem.keyEquivalentModifierMask = [.control, .option, .command]
        prevScrItem.target = self
        menu.addItem(prevScrItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Grid Size Submenu
        let gridMenu = NSMenu()
        for (r, c) in [(4, 4), (6, 6), (8, 8), (10, 10)] {
            let item = NSMenuItem(title: "\(c) × \(r) 格線", action: #selector(changeGridSize(_:)), keyEquivalent: "")
            item.tag = c * 100 + r
            item.target = self
            gridMenu.addItem(item)
        }
        let gridSubItem = NSMenuItem(title: "格線大小 (Grid Size)", action: nil, keyEquivalent: "")
        gridSubItem.submenu = gridMenu
        menu.addItem(gridSubItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "偏好設定...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let permItem = NSMenuItem(title: "檢查輔助功能權限 (Accessibility)", action: #selector(checkPermAction), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "結束 Lattice", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.contextMenu = menu
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            GridHUDController.shared.toggleHUD()
        }
    }
    
    @objc private func showHUDAction() {
        GridHUDController.shared.toggleHUD()
    }
    
    @objc private func snapLeftAction() {
        WindowManager.shared.snapLeftHalf()
    }
    
    @objc private func snapRightAction() {
        WindowManager.shared.snapRightHalf()
    }
    
    @objc private func snapMaxAction() {
        WindowManager.shared.snapMaximize()
    }
    
    @objc private func snapCenterAction() {
        WindowManager.shared.snapCenterSmall()
    }
    
    @objc private func throwNextAction() {
        WindowManager.shared.throwToNextScreen()
    }
    
    @objc private func throwPrevAction() {
        WindowManager.shared.throwToPrevScreen()
    }
    
    @objc private func changeGridSize(_ sender: NSMenuItem) {
        let cols = sender.tag / 100
        let rows = sender.tag % 100
        Preferences.shared.gridColumns = cols
        Preferences.shared.gridRows = rows
    }
    
    @objc private func openSettingsAction() {
        SettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func checkPermAction() {
        WindowManager.shared.requestAccessibilityPrompt()
    }
    
    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
    
    // Draw 18x18 Template Icon representing Lattice 2x2 grid
    private func createGridIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let padding: CGFloat = 2.0
            let gap: CGFloat = 2.0
            let cellW = (rect.width - 2 * padding - gap) / 2.0
            let cellH = (rect.height - 2 * padding - gap) / 2.0
            
            NSColor.black.setFill()
            
            for r in 0..<2 {
                for c in 0..<2 {
                    let x = padding + CGFloat(c) * (cellW + gap)
                    let y = padding + CGFloat(r) * (cellH + gap)
                    let cellRect = NSRect(x: x, y: y, width: cellW, height: cellH)
                    let path = NSBezierPath(roundedRect: cellRect, xRadius: 1.5, yRadius: 1.5)
                    path.fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
