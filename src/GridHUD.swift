import Cocoa

// MARK: - Custom HUD Panel
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Grid HUD Controller
final class GridHUDController {
    static let shared = GridHUDController()
    
    private var hudPanel: HUDPanel?
    private var gridView: GridView?
    private var currentTarget: WindowTarget?
    private var selectedScreenIndex: Int = 0
    
    private init() {}
    
    var isVisible: Bool {
        return hudPanel?.isVisible ?? false
    }
    
    func toggleHUD() {
        if isVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }
    
    func showHUD() {
        // 1. Capture target window before bringing HUD up
        let target = WindowManager.shared.captureCurrentFrontmostWindow()
        self.currentTarget = target
        LogDebug("showHUD called. target: \(target?.app.localizedName ?? "nil"), isTrusted: \(WindowManager.shared.isAccessibilityGranted())")
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        let activeScreen = target?.screen ?? getScreenUnderMouse() ?? screens[0]
        self.selectedScreenIndex = screens.firstIndex(of: activeScreen) ?? 0
        
        let panel = getOrCreatePanel()
        
        // Update grid view with current settings & target
        gridView?.configure(
            target: target,
            screen: activeScreen,
            screenIndex: selectedScreenIndex,
            totalScreens: screens.count
        )
        
        // Position panel at center of activeScreen
        let panelSize = panel.frame.size
        let screenFrame = activeScreen.frame
        let panelX = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2.0
        let panelY = screenFrame.origin.y + (screenFrame.height - panelSize.height) / 2.0
        
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        panel.makeKey()
    }
    
    func hideHUD() {
        guard let panel = hudPanel, panel.isVisible else { return }
        panel.orderOut(nil)
    }
    
    func cycleScreen(delta: Int) {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        selectedScreenIndex = (selectedScreenIndex + delta + screens.count) % screens.count
        let screen = screens[selectedScreenIndex]
        
        if let panel = hudPanel {
            let panelSize = panel.frame.size
            let screenFrame = screen.frame
            let panelX = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2.0
            let panelY = screenFrame.origin.y + (screenFrame.height - panelSize.height) / 2.0
            panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }
        
        gridView?.configure(
            target: currentTarget,
            screen: screen,
            screenIndex: selectedScreenIndex,
            totalScreens: screens.count
        )
    }
    
    func setGridSize(rows: Int, cols: Int) {
        Preferences.shared.gridRows = rows
        Preferences.shared.gridColumns = cols
        let screens = NSScreen.screens
        let screen = screens.indices.contains(selectedScreenIndex) ? screens[selectedScreenIndex] : screens[0]
        gridView?.configure(
            target: currentTarget,
            screen: screen,
            screenIndex: selectedScreenIndex,
            totalScreens: screens.count
        )
    }
    
    func applySelection(colStart: Int, colEnd: Int, rowStart: Int, rowEnd: Int) {
        LogDebug("applySelection called: cols \(colStart)..\(colEnd), rows \(rowStart)..\(rowEnd)")
        let screens = NSScreen.screens
        let screen = screens.indices.contains(selectedScreenIndex) ? screens[selectedScreenIndex] : screens[0]
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        WindowManager.shared.snapTarget(
            target: currentTarget,
            colStart: colStart,
            colEnd: colEnd,
            rowStart: rowStart,
            rowEnd: rowEnd,
            totalCols: cols,
            totalRows: rows,
            customScreen: screen
        )
        hideHUD()
    }
    
    private func getScreenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSPointInRect(loc, $0.frame) })
    }
    
    private func getOrCreatePanel() -> HUDPanel {
        if let panel = hudPanel {
            return panel
        }
        
        let width: CGFloat = 480
        let height: CGFloat = 460
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        
        let panel = HUDPanel(
            contentRect: rect,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        
        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1.0
        visualEffect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        
        let gView = GridView(frame: rect)
        visualEffect.addSubview(gView)
        gView.autoresizingMask = [.width, .height]
        
        panel.contentView = visualEffect
        self.hudPanel = panel
        self.gridView = gView
        
        return panel
    }
}

// MARK: - Interactive Grid View
final class GridView: NSView {
    private var target: WindowTarget?
    private var screen: NSScreen?
    private var screenIndex: Int = 0
    private var totalScreens: Int = 1
    
    // Grid Selection State
    private var startCol: Int?
    private var startRow: Int?
    private var currentCol: Int?
    private var currentRow: Int?
    private var hoverCol: Int?
    private var hoverRow: Int?
    private var isDragging: Bool = false
    
    // Tracking Area
    private var trackingArea: NSTrackingArea?
    
    override var acceptsFirstResponder: Bool { true }
    
    // CRITICAL: Must accept first mouse so clicks work without needing to activate first
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    // CRITICAL: Disable window dragging by mouse down so dragging selects grid cells
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    func configure(target: WindowTarget?, screen: NSScreen, screenIndex: Int, totalScreens: Int) {
        self.target = target
        self.screen = screen
        self.screenIndex = screenIndex
        self.totalScreens = totalScreens
        self.startCol = nil
        self.startRow = nil
        self.currentCol = nil
        self.currentRow = nil
        self.hoverCol = nil
        self.hoverRow = nil
        self.isDragging = false
        needsDisplay = true
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        self.trackingArea = ta
    }
    
    // Layout Constants
    private var hasPermissionWarning: Bool {
        return !WindowManager.shared.isAccessibilityGranted()
    }
    
    private var headerHeight: CGFloat {
        return hasPermissionWarning ? 94.0 : 66.0
    }
    private let footerHeight: CGFloat = 78.0
    private let gridPadding: CGFloat = 20.0
    private let cellSpacing: CGFloat = 4.0
    
    private var gridRect: NSRect {
        let x = gridPadding
        let y = footerHeight
        let w = bounds.width - 2 * gridPadding
        let h = bounds.height - headerHeight - footerHeight
        return NSRect(x: x, y: y, width: w, height: h)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        drawHeader()
        drawGrid()
        drawFooter()
    }
    
    // MARK: - Drawing Sections
    private func drawHeader() {
        // App Icon & Title
        let iconRect = NSRect(x: 20, y: bounds.height - 52, width: 32, height: 32)
        if let icon = NSImage(contentsOfFile: Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns") ?? NSApp.applicationIconImage {
            icon.draw(in: iconRect)
        }
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        "Lattice".draw(at: NSPoint(x: 60, y: bounds.height - 34), withAttributes: titleAttrs)
        
        // Target Window Label
        let targetText: String
        if let target = target {
            let appName = target.app.localizedName ?? "應用程式"
            let winTitle = target.windowTitle.isEmpty ? "" : " - \(target.windowTitle)"
            targetText = "縮放目標：\(appName)\(winTitle)"
        } else {
            targetText = "未偵測到作用中視窗（請先點一下要調整的視窗）"
        }
        
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.70)
        ]
        let truncated = targetText.count > 34 ? String(targetText.prefix(32)) + "..." : targetText
        truncated.draw(at: NSPoint(x: 60, y: bounds.height - 50), withAttributes: subtitleAttrs)
        
        // Grid Size Buttons on top-right: 4x4, 6x6, 8x8, 10x10
        let currentCols = Preferences.shared.gridColumns
        let sizes = [(4, 4), (6, 6), (8, 8), (10, 10)]
        var btnX = bounds.width - 20 - CGFloat(sizes.count * 44)
        let btnY = bounds.height - 38
        
        for (r, c) in sizes {
            let isCurrent = (currentCols == c && Preferences.shared.gridRows == r)
            let btnRect = NSRect(x: btnX, y: btnY, width: 40, height: 22)
            let path = NSBezierPath(roundedRect: btnRect, xRadius: 5, yRadius: 5)
            
            if isCurrent {
                NSColor.controlAccentColor.setFill()
            } else {
                NSColor(white: 1.0, alpha: 0.14).setFill()
            }
            path.fill()
            
            let label = "\(c)×\(r)"
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: isCurrent ? .bold : .regular),
                .foregroundColor: isCurrent ? NSColor.white : NSColor(white: 1.0, alpha: 0.8)
            ]
            let textSize = label.size(withAttributes: textAttrs)
            let textOrigin = NSPoint(
                x: btnRect.origin.x + (btnRect.width - textSize.width) / 2.0,
                y: btnRect.origin.y + (btnRect.height - textSize.height) / 2.0
            )
            label.draw(at: textOrigin, withAttributes: textAttrs)
            btnX += 44
        }
        
        // Permission Warning Banner if not granted
        if hasPermissionWarning {
            let bannerRect = NSRect(x: 16, y: bounds.height - 86, width: bounds.width - 32, height: 26)
            let bPath = NSBezierPath(roundedRect: bannerRect, xRadius: 6, yRadius: 6)
            NSColor.systemOrange.withAlphaComponent(0.25).setFill()
            bPath.fill()
            NSColor.systemOrange.setStroke()
            bPath.lineWidth = 1.0
            bPath.stroke()
            
            let warnAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.systemOrange
            ]
            "⚠️ 尚未取得輔助功能權限，請點此授權以啟用縮放".draw(
                at: NSPoint(x: bannerRect.origin.x + 10, y: bannerRect.origin.y + 6),
                withAttributes: warnAttrs
            )
        }
    }
    
    private func drawGrid() {
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        let gRect = gridRect
        
        let totalSpacingW = cellSpacing * CGFloat(cols - 1)
        let totalSpacingH = cellSpacing * CGFloat(rows - 1)
        
        let cellW = (gRect.width - totalSpacingW) / CGFloat(cols)
        let cellH = (gRect.height - totalSpacingH) / CGFloat(rows)
        
        var selMinCol: Int?
        var selMaxCol: Int?
        var selMinRow: Int?
        var selMaxRow: Int?
        
        if let sc = startCol, let sr = startRow, let cc = currentCol, let cr = currentRow {
            selMinCol = min(sc, cc)
            selMaxCol = max(sc, cc)
            selMinRow = min(sr, cr)
            selMaxRow = max(sr, cr)
        }
        
        for r in 0..<rows {
            for c in 0..<cols {
                let x = gRect.origin.x + CGFloat(c) * (cellW + cellSpacing)
                let y = gRect.origin.y + gRect.height - CGFloat(r + 1) * cellH - CGFloat(r) * cellSpacing
                let cellRect = NSRect(x: x, y: y, width: cellW, height: cellH)
                let cellPath = NSBezierPath(roundedRect: cellRect, xRadius: 4, yRadius: 4)
                
                let isSelected: Bool
                if let minC = selMinCol, let maxC = selMaxCol, let minR = selMinRow, let maxR = selMaxRow {
                    isSelected = (c >= minC && c <= maxC && r >= minR && r <= maxR)
                } else {
                    isSelected = false
                }
                
                let isHovered = (hoverCol == c && hoverRow == r && !isDragging)
                
                if isSelected {
                    let gradient = NSGradient(
                        starting: NSColor(red: 0.10, green: 0.55, blue: 1.0, alpha: 0.95),
                        ending: NSColor(red: 0.0, green: 0.40, blue: 0.92, alpha: 0.95)
                    )
                    gradient?.draw(in: cellPath, angle: -45)
                    
                    NSColor(red: 0.45, green: 0.82, blue: 1.0, alpha: 1.0).setStroke()
                    cellPath.lineWidth = 1.5
                    cellPath.stroke()
                } else if isHovered {
                    NSColor(white: 1.0, alpha: 0.28).setFill()
                    cellPath.fill()
                    NSColor(white: 1.0, alpha: 0.4).setStroke()
                    cellPath.lineWidth = 1.0
                    cellPath.stroke()
                } else {
                    NSColor(white: 1.0, alpha: 0.12).setFill()
                    cellPath.fill()
                    NSColor(white: 1.0, alpha: 0.10).setStroke()
                    cellPath.lineWidth = 1.0
                    cellPath.stroke()
                }
            }
        }
        
        // Show selection dimension badge if dragging
        if let minC = selMinCol, let maxC = selMaxCol, let minR = selMinRow, let maxR = selMaxRow {
            let selWCount = maxC - minC + 1
            let selHCount = maxR - minR + 1
            let pctW = Int(round(Double(selWCount) / Double(cols) * 100.0))
            let pctH = Int(round(Double(selHCount) / Double(rows) * 100.0))
            let badgeText = "\(selWCount) × \(selHCount) 格 (\(pctW)% 寬 × \(pctH)% 高)"
            
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let badgeSize = badgeText.size(withAttributes: badgeAttrs)
            let badgeRect = NSRect(
                x: gRect.origin.x + (gRect.width - badgeSize.width - 24) / 2.0,
                y: gRect.origin.y + (gRect.height - badgeSize.height - 12) / 2.0,
                width: badgeSize.width + 24,
                height: badgeSize.height + 12
            )
            
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
            NSColor(white: 0.0, alpha: 0.82).setFill()
            badgePath.fill()
            NSColor(white: 1.0, alpha: 0.35).setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()
            
            badgeText.draw(
                at: NSPoint(x: badgeRect.origin.x + 12, y: badgeRect.origin.y + 6),
                withAttributes: badgeAttrs
            )
        }
    }
    
    private func drawFooter() {
        // Quick Presets Buttons: Left Half, Right Half, Maximize, Center
        let presets = [
            ("左半 [4]", 0),
            ("右半 [6]", 1),
            ("最大化 [8]", 2),
            ("置中 [5]", 3)
        ]
        
        let totalW = bounds.width - 40
        let spacing: CGFloat = 8
        let btnW = (totalW - spacing * CGFloat(presets.count - 1)) / CGFloat(presets.count)
        let btnH: CGFloat = 30
        let btnY: CGFloat = 38
        
        for (i, (label, _)) in presets.enumerated() {
            let bx = 20 + CGFloat(i) * (btnW + spacing)
            let bRect = NSRect(x: bx, y: btnY, width: btnW, height: btnH)
            let path = NSBezierPath(roundedRect: bRect, xRadius: 6, yRadius: 6)
            
            NSColor(white: 1.0, alpha: 0.16).setFill()
            path.fill()
            NSColor(white: 1.0, alpha: 0.15).setStroke()
            path.lineWidth = 1.0
            path.stroke()
            
            let pAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let tSize = label.size(withAttributes: pAttrs)
            let pt = NSPoint(
                x: bRect.origin.x + (bRect.width - tSize.width) / 2.0,
                y: bRect.origin.y + (bRect.height - tSize.height) / 2.0
            )
            label.draw(at: pt, withAttributes: pAttrs)
        }
        
        // Hint text at bottom
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.65)
        ]
        let hint = "💡 拖曳劃格 • 數字鍵 1~9 (1/3/7/9 三分屏, 4/6 半屏, 8 全螢幕) • Tab 換螢幕 • Esc 關閉"
        let hSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: NSPoint(x: (bounds.width - hSize.width) / 2.0, y: 14), withAttributes: hintAttrs)
    }
    
    // MARK: - Mouse Coordinate Helpers
    private func cellAt(point: NSPoint) -> (col: Int, row: Int)? {
        let gRect = gridRect
        guard gRect.contains(point) else { return nil }
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        let totalSpacingW = cellSpacing * CGFloat(cols - 1)
        let totalSpacingH = cellSpacing * CGFloat(rows - 1)
        let cellW = (gRect.width - totalSpacingW) / CGFloat(cols)
        let cellH = (gRect.height - totalSpacingH) / CGFloat(rows)
        
        let relX = point.x - gRect.origin.x
        let relY = gRect.origin.y + gRect.height - point.y // from top downwards
        
        let col = Int(relX / (cellW + cellSpacing))
        let row = Int(relY / (cellH + cellSpacing))
        
        let safeCol = min(max(0, col), cols - 1)
        let safeRow = min(max(0, row), rows - 1)
        return (safeCol, safeRow)
    }
    
    // MARK: - Mouse Events
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if let (c, r) = cellAt(point: loc) {
            if hoverCol != c || hoverRow != r {
                hoverCol = c
                hoverRow = r
                needsDisplay = true
            }
        } else {
            if hoverCol != nil || hoverRow != nil {
                hoverCol = nil
                hoverRow = nil
                needsDisplay = true
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        hoverCol = nil
        hoverRow = nil
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        LogDebug("GridView mouseDown at \(loc)")
        
        // Check permission warning click
        if hasPermissionWarning {
            let bannerRect = NSRect(x: 16, y: bounds.height - 86, width: bounds.width - 32, height: 26)
            if bannerRect.contains(loc) {
                WindowManager.shared.requestAccessibilityPrompt()
                return
            }
        }
        
        // Check grid size buttons
        let sizes = [(4, 4), (6, 6), (8, 8), (10, 10)]
        var btnX = bounds.width - 20 - CGFloat(sizes.count * 44)
        let btnY = bounds.height - 38
        for (r, c) in sizes {
            let btnRect = NSRect(x: btnX, y: btnY, width: 40, height: 22)
            if btnRect.contains(loc) {
                GridHUDController.shared.setGridSize(rows: r, cols: c)
                return
            }
            btnX += 44
        }
        
        // Check preset buttons in footer
        let totalW = bounds.width - 40
        let spacing: CGFloat = 8
        let btnW = (totalW - spacing * 3) / 4.0
        let btnH: CGFloat = 30
        let presetY: CGFloat = 38
        
        let presets = [
            NSRect(x: 20 + 0 * (btnW + spacing), y: presetY, width: btnW, height: btnH),
            NSRect(x: 20 + 1 * (btnW + spacing), y: presetY, width: btnW, height: btnH),
            NSRect(x: 20 + 2 * (btnW + spacing), y: presetY, width: btnW, height: btnH),
            NSRect(x: 20 + 3 * (btnW + spacing), y: presetY, width: btnW, height: btnH)
        ]
        
        if presets[0].contains(loc) {
            WindowManager.shared.snapLeftHalf()
            GridHUDController.shared.hideHUD()
            return
        } else if presets[1].contains(loc) {
            WindowManager.shared.snapRightHalf()
            GridHUDController.shared.hideHUD()
            return
        } else if presets[2].contains(loc) {
            WindowManager.shared.snapMaximize()
            GridHUDController.shared.hideHUD()
            return
        } else if presets[3].contains(loc) {
            WindowManager.shared.snapCenterSmall()
            GridHUDController.shared.hideHUD()
            return
        }
        
        // Grid Dragging Start
        if let (c, r) = cellAt(point: loc) {
            isDragging = true
            startCol = c
            startRow = r
            currentCol = c
            currentRow = r
            needsDisplay = true
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let loc = convert(event.locationInWindow, from: nil)
        
        let gRect = gridRect
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        let totalSpacingW = cellSpacing * CGFloat(cols - 1)
        let totalSpacingH = cellSpacing * CGFloat(rows - 1)
        let cellW = (gRect.width - totalSpacingW) / CGFloat(cols)
        let cellH = (gRect.height - totalSpacingH) / CGFloat(rows)
        
        let relX = min(max(0, loc.x - gRect.origin.x), gRect.width - 1)
        let relY = min(max(0, gRect.origin.y + gRect.height - loc.y), gRect.height - 1)
        
        let c = Int(relX / (cellW + cellSpacing))
        let r = Int(relY / (cellH + cellSpacing))
        
        let clampedC = min(max(0, c), cols - 1)
        let clampedR = min(max(0, r), rows - 1)
        
        if currentCol != clampedC || currentRow != clampedR {
            currentCol = clampedC
            currentRow = clampedR
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        LogDebug("GridView mouseUp, isDragging: \(isDragging)")
        guard isDragging,
              let sc = startCol, let sr = startRow,
              let cc = currentCol, let cr = currentRow else {
            isDragging = false
            needsDisplay = true
            return
        }
        
        isDragging = false
        let minC = min(sc, cc)
        let maxC = max(sc, cc)
        let minR = min(sr, cr)
        let maxR = max(sr, cr)
        
        GridHUDController.shared.applySelection(
            colStart: minC,
            colEnd: maxC,
            rowStart: minR,
            rowEnd: maxR
        )
    }
    
    // MARK: - Animated Preset Slot Trigger
    private func applyPresetSlotAnimated(slot: Int) {
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        let coords = WindowManager.shared.getPresetSlotCoordinates(slot: slot, cols: cols, rows: rows)
        
        // Visually highlight corresponding cells in grid
        self.startCol = coords.colStart
        self.currentCol = coords.colEnd
        self.startRow = coords.rowStart
        self.currentRow = coords.rowEnd
        self.needsDisplay = true
        
        // Brief flash, then snap and close HUD
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            GridHUDController.shared.applySelection(
                colStart: coords.colStart,
                colEnd: coords.colEnd,
                rowStart: coords.rowStart,
                rowEnd: coords.rowEnd
            )
            self?.startCol = nil
            self?.currentCol = nil
            self?.startRow = nil
            self?.currentRow = nil
        }
    }
    
    // MARK: - Keyboard Events in HUD
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            GridHUDController.shared.hideHUD()
            return
        }
        
        let chars = event.charactersIgnoringModifiers ?? ""
        
        // 1. Number keys 1~9: Preset Slots
        if let first = chars.first, let digit = Int(String(first)), (1...9).contains(digit) {
            applyPresetSlotAnimated(slot: digit)
            return
        }
        
        // 2. Letters and symbols
        switch chars.lowercased() {
        case " ": // Space -> Maximize
            applyPresetSlotAnimated(slot: 8)
            return
        case "c": // Center
            applyPresetSlotAnimated(slot: 5)
            return
        case "l": // Left half
            applyPresetSlotAnimated(slot: 4)
            return
        case "r": // Right half
            applyPresetSlotAnimated(slot: 6)
            return
        case "m", "f": // Maximize
            applyPresetSlotAnimated(slot: 8)
            return
        case "n", "\t": // Next screen
            GridHUDController.shared.cycleScreen(delta: 1)
            return
        case "p": // Prev screen
            GridHUDController.shared.cycleScreen(delta: -1)
            return
        default:
            break
        }
        
        // 3. Arrow keys
        if event.keyCode == 123 { // Left Arrow
            applyPresetSlotAnimated(slot: 4)
        } else if event.keyCode == 124 { // Right Arrow
            applyPresetSlotAnimated(slot: 6)
        } else if event.keyCode == 126 { // Up Arrow
            applyPresetSlotAnimated(slot: 8)
        } else if event.keyCode == 125 { // Down Arrow
            applyPresetSlotAnimated(slot: 5)
        } else {
            super.keyDown(with: event)
        }
    }
}
