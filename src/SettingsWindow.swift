import Cocoa
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private var rowsField: NSTextField!
    private var colsField: NSTextField!
    private var gapSlider: NSSlider!
    private var gapLabel: NSTextField!
    private var marginSlider: NSSlider!
    private var marginLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var loginCheckbox: NSButton!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 490),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lattice 設定"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView
        
        var y: CGFloat = window.contentView!.bounds.height - 40
        
        // 1. Title & Header
        let titleLabel = NSTextField(labelWithString: "Lattice 視窗管理偏好設定")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.frame = NSRect(x: 24, y: y, width: 400, height: 22)
        contentView.addSubview(titleLabel)
        
        y -= 40
        
        // 2. Grid Dimensions Section
        let gridSection = NSTextField(labelWithString: "📐 格線維度 (Grid Dimensions)")
        gridSection.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        gridSection.frame = NSRect(x: 24, y: y, width: 400, height: 18)
        contentView.addSubview(gridSection)
        
        y -= 32
        
        let colsTitle = NSTextField(labelWithString: "欄數 (Columns):")
        colsTitle.frame = NSRect(x: 36, y: y, width: 110, height: 20)
        contentView.addSubview(colsTitle)
        
        colsField = NSTextField(string: "\(Preferences.shared.gridColumns)")
        colsField.frame = NSRect(x: 150, y: y, width: 45, height: 22)
        colsField.isEditable = false
        contentView.addSubview(colsField)
        
        let colsStepper = NSStepper(frame: NSRect(x: 200, y: y, width: 19, height: 22))
        colsStepper.minValue = 2
        colsStepper.maxValue = 16
        colsStepper.integerValue = Preferences.shared.gridColumns
        colsStepper.target = self
        colsStepper.action = #selector(colsChanged(_:))
        contentView.addSubview(colsStepper)
        
        let rowsTitle = NSTextField(labelWithString: "列數 (Rows):")
        rowsTitle.frame = NSRect(x: 240, y: y, width: 90, height: 20)
        contentView.addSubview(rowsTitle)
        
        rowsField = NSTextField(string: "\(Preferences.shared.gridRows)")
        rowsField.frame = NSRect(x: 330, y: y, width: 45, height: 22)
        rowsField.isEditable = false
        contentView.addSubview(rowsField)
        
        let rowsStepper = NSStepper(frame: NSRect(x: 380, y: y, width: 19, height: 22))
        rowsStepper.minValue = 2
        rowsStepper.maxValue = 16
        rowsStepper.integerValue = Preferences.shared.gridRows
        rowsStepper.target = self
        rowsStepper.action = #selector(rowsChanged(_:))
        contentView.addSubview(rowsStepper)
        
        y -= 38
        
        // 3. Gap & Margin
        let gapTitle = NSTextField(labelWithString: "視窗間距 (Gap):")
        gapTitle.frame = NSRect(x: 36, y: y, width: 110, height: 20)
        contentView.addSubview(gapTitle)
        
        gapSlider = NSSlider(frame: NSRect(x: 150, y: y, width: 180, height: 20))
        gapSlider.minValue = 0
        gapSlider.maxValue = 30
        gapSlider.doubleValue = Double(Preferences.shared.windowGap)
        gapSlider.target = self
        gapSlider.action = #selector(gapChanged(_:))
        contentView.addSubview(gapSlider)
        
        gapLabel = NSTextField(labelWithString: "\(Int(Preferences.shared.windowGap)) px")
        gapLabel.frame = NSRect(x: 340, y: y, width: 60, height: 20)
        contentView.addSubview(gapLabel)
        
        y -= 32
        
        let marginTitle = NSTextField(labelWithString: "螢幕外邊距 (Margin):")
        marginTitle.frame = NSRect(x: 36, y: y, width: 125, height: 20)
        contentView.addSubview(marginTitle)
        
        marginSlider = NSSlider(frame: NSRect(x: 165, y: y, width: 165, height: 20))
        marginSlider.minValue = 0
        marginSlider.maxValue = 40
        marginSlider.doubleValue = Double(Preferences.shared.screenMargin)
        marginSlider.target = self
        marginSlider.action = #selector(marginChanged(_:))
        contentView.addSubview(marginSlider)
        
        marginLabel = NSTextField(labelWithString: "\(Int(Preferences.shared.screenMargin)) px")
        marginLabel.frame = NSRect(x: 340, y: y, width: 60, height: 20)
        contentView.addSubview(marginLabel)
        
        y -= 44
        
        // 4. Shortcut Cheatsheet Section
        let shortcutsSection = NSTextField(labelWithString: "⌨️ 快捷鍵配置 (Shortcuts)")
        shortcutsSection.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        shortcutsSection.frame = NSRect(x: 24, y: y, width: 400, height: 18)
        contentView.addSubview(shortcutsSection)
        
        y -= 26
        
        let shortcutItems = [
            ("喚醒 / 關閉 Lattice 格線", "⌃⌥Space 或 ⌘⌥Space"),
            ("視窗靠左半螢幕 (50%)", "⌘ ⇧ ←"),
            ("視窗靠右半螢幕 (50%)", "⌘ ⇧ →"),
            ("視窗最大化全螢幕 (100%)", "⌘ ⇧ ↑"),
            ("視窗置中適中 (4×4)", "⌘ ⇧ ↓")
        ]
        
        for (name, combo) in shortcutItems {
            let nLabel = NSTextField(labelWithString: name)
            nLabel.font = NSFont.systemFont(ofSize: 11)
            nLabel.textColor = NSColor.secondaryLabelColor
            nLabel.frame = NSRect(x: 36, y: y, width: 220, height: 18)
            contentView.addSubview(nLabel)
            
            let cLabel = NSTextField(labelWithString: combo)
            cLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            cLabel.alignment = .right
            cLabel.frame = NSRect(x: 260, y: y, width: 180, height: 18)
            contentView.addSubview(cLabel)
            
            y -= 20
        }
        
        y -= 24
        
        // 5. System Permissions & Auto-launch
        let sysSection = NSTextField(labelWithString: "🛡️ 系統權限與啟動")
        sysSection.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        sysSection.frame = NSRect(x: 24, y: y, width: 400, height: 18)
        contentView.addSubview(sysSection)
        
        y -= 30
        
        let isGranted = WindowManager.shared.isAccessibilityGranted()
        let permText = isGranted ? "✅ 輔助功能權限：已授權" : "⚠️ 輔助功能權限：未授權 (請點右側按鈕授權)"
        statusLabel = NSTextField(labelWithString: permText)
        statusLabel.frame = NSRect(x: 36, y: y, width: 280, height: 20)
        contentView.addSubview(statusLabel)
        
        let permBtn = NSButton(title: "檢查 / 授權", target: self, action: #selector(requestPermClicked))
        permBtn.frame = NSRect(x: 320, y: y - 2, width: 110, height: 24)
        contentView.addSubview(permBtn)
        
        y -= 36
        
        loginCheckbox = NSButton(checkboxWithTitle: "登入時自動啟動 Lattice (Launch at Login)", target: self, action: #selector(loginToggled(_:)))
        loginCheckbox.frame = NSRect(x: 36, y: y, width: 350, height: 20)
        loginCheckbox.state = Preferences.shared.launchAtLogin ? .on : .off
        contentView.addSubview(loginCheckbox)
    }
    
    @objc private func colsChanged(_ sender: NSStepper) {
        Preferences.shared.gridColumns = sender.integerValue
        colsField.stringValue = "\(sender.integerValue)"
    }
    
    @objc private func rowsChanged(_ sender: NSStepper) {
        Preferences.shared.gridRows = sender.integerValue
        rowsField.stringValue = "\(sender.integerValue)"
    }
    
    @objc private func gapChanged(_ sender: NSSlider) {
        Preferences.shared.windowGap = CGFloat(sender.doubleValue)
        gapLabel.stringValue = "\(Int(sender.doubleValue)) px"
    }
    
    @objc private func marginChanged(_ sender: NSSlider) {
        Preferences.shared.screenMargin = CGFloat(sender.doubleValue)
        marginLabel.stringValue = "\(Int(sender.doubleValue)) px"
    }
    
    @objc private func requestPermClicked() {
        WindowManager.shared.requestAccessibilityPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let isGranted = WindowManager.shared.isAccessibilityGranted()
            self?.statusLabel.stringValue = isGranted ? "✅ 輔助功能權限：已授權" : "⚠️ 輔助功能權限：未授權"
        }
    }
    
    @objc private func loginToggled(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        Preferences.shared.launchAtLogin = isEnabled
        if #available(macOS 13.0, *) {
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[Lattice] Failed to update SMAppService: \(error)")
            }
        }
    }
}
