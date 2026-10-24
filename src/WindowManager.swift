import Cocoa
import ApplicationServices

struct WindowTarget {
    let app: NSRunningApplication
    let windowElement: AXUIElement
    let screen: NSScreen
    let windowTitle: String
}

final class WindowManager {
    static let shared = WindowManager()
    
    // Cached target window when HUD is summoned
    var capturedTarget: WindowTarget?
    
    private init() {}
    
    // Check if accessibility permission is granted
    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    // Prompt for accessibility permission if not granted
    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // Capture frontmost application window (excluding self)
    @discardableResult
    func captureCurrentFrontmostWindow() -> WindowTarget? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        
        // 1. Find true Z-order top window from WindowServer
        var targetPID: pid_t? = nil
        var targetWindowName: String? = nil
        
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowList {
                let layer = win[kCGWindowLayer as String] as? Int ?? 0
                let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
                let owner = win[kCGWindowOwnerName as String] as? String ?? ""
                let bounds = win[kCGWindowBounds as String] as? [String: Any]
                let width = bounds?["Width"] as? CGFloat ?? 0
                let height = bounds?["Height"] as? CGFloat ?? 0
                
                // Regular app window layer, not self, not Dock/system server, and substantial size
                if layer == 0 && pid != ownPID && owner != "Window Server" && owner != "Dock" && width > 150 && height > 150 {
                    targetPID = pid
                    targetWindowName = win[kCGWindowName as String] as? String
                    break
                }
            }
        }
        
        var frontApp: NSRunningApplication?
        if let pid = targetPID {
            frontApp = NSRunningApplication(processIdentifier: pid)
        }
        
        // Fallback to frontmostApplication if not found
        if frontApp == nil {
            if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != ownPID {
                frontApp = f
            } else {
                frontApp = NSWorkspace.shared.runningApplications.first {
                    $0.processIdentifier != ownPID && $0.activationPolicy == .regular && !$0.isTerminated
                }
            }
        }
        
        guard let app = frontApp else {
            LogDebug("captureCurrentFrontmostWindow: No frontApp found")
            capturedTarget = nil
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var selectedWinElement: AXUIElement?
        
        // 1. Try focused window
        var focusedRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let win = focusedRef {
            let el = win as! AXUIElement
            if isStandardWindow(el) {
                selectedWinElement = el
            }
        }
        
        // 2. Try main window
        if selectedWinElement == nil {
            var mainRef: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
               let win = mainRef {
                let el = win as! AXUIElement
                if isStandardWindow(el) {
                    selectedWinElement = el
                }
            }
        }
        
        // 3. Try window list (filter for AXStandardWindow or largest window)
        if selectedWinElement == nil {
            var windowsListRef: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsListRef) == .success,
               let list = windowsListRef as? [AXUIElement], !list.isEmpty {
                // Find first AXStandardWindow
                selectedWinElement = list.first { isStandardWindow($0) }
                // Fallback to largest window
                if selectedWinElement == nil {
                    selectedWinElement = list.first
                }
            }
        }
        
        guard let winElement = selectedWinElement else {
            LogDebug("captureCurrentFrontmostWindow: No standard window found for app \(app.localizedName ?? "") (pid \(app.processIdentifier))")
            capturedTarget = nil
            return nil
        }
        
        // Window Title
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(winElement, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? targetWindowName ?? (app.localizedName ?? "Window")
        
        // Determine which screen contains this window
        let screen = getScreenForWindow(winElement)
        
        LogDebug("captureCurrentFrontmostWindow: Success! App: \(app.localizedName ?? ""), Title: \(title), Screen: \(screen.frame)")
        let target = WindowTarget(
            app: app,
            windowElement: winElement,
            screen: screen,
            windowTitle: title
        )
        self.capturedTarget = target
        return target
    }
    
    private func isStandardWindow(_ el: AXUIElement) -> Bool {
        var subroleRef: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            if subrole == "AXStandardWindow" { return true }
            if subrole == "AXDialog" || subrole == "AXSystemDialog" { return false }
        }
        var sizeRef: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeVal = sizeRef {
            var sz = CGSize.zero
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
            return sz.width > 200 && sz.height > 200
        }
        return true
    }
    
    // Find the screen containing the given window
    func getScreenForWindow(_ winElement: AXUIElement) -> NSScreen {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(winElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(winElement, kAXSizeAttribute as CFString, &sizeRef)
        
        var axPoint = CGPoint.zero
        var axSize = CGSize.zero
        if let posVal = posRef { AXValueGetValue(posVal as! AXValue, .cgPoint, &axPoint) }
        if let sizeVal = sizeRef { AXValueGetValue(sizeVal as! AXValue, .cgSize, &axSize) }
        
        guard let primaryScreen = NSScreen.screens.first else {
            return NSScreen.main ?? NSScreen()
        }
        
        let primaryHeight = primaryScreen.frame.height
        // Convert AX coordinate (origin at top-left of primary screen) to AppKit coordinate (origin at bottom-left)
        let windowCenterAX = CGPoint(x: axPoint.x + axSize.width / 2.0, y: axPoint.y + axSize.height / 2.0)
        let windowCenterAppKit = NSPoint(x: windowCenterAX.x, y: primaryHeight - windowCenterAX.y)
        
        for screen in NSScreen.screens {
            if NSPointInRect(windowCenterAppKit, screen.frame) {
                return screen
            }
        }
        
        // Fallback to screen where mouse currently is
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSPointInRect(mouseLocation, screen.frame) {
                return screen
            }
        }
        
        return NSScreen.main ?? primaryScreen
    }
    
    // Resize and position window based on grid partition
    func snapTarget(
        target: WindowTarget?,
        colStart: Int,
        colEnd: Int,
        rowStart: Int,
        rowEnd: Int,
        totalCols: Int,
        totalRows: Int,
        customScreen: NSScreen? = nil
    ) {
        guard let target = target ?? capturedTarget ?? captureCurrentFrontmostWindow() else {
            LogDebug("snapTarget: Failed! No target available. Beeping.")
            NSSound.beep()
            return
        }
        
        LogDebug("snapTarget: Snapping app \(target.app.localizedName ?? "") to cols \(colStart)..\(colEnd), rows \(rowStart)..\(rowEnd)")
        
        let screen = customScreen ?? target.screen
        let winElement = target.windowElement
        
        let visibleFrame = screen.visibleFrame
        let prefs = Preferences.shared
        let gap = prefs.windowGap
        let margin = prefs.screenMargin
        
        // Effective screen bounds with margin
        let effectiveX = visibleFrame.origin.x + margin
        let effectiveY = visibleFrame.origin.y + margin
        let effectiveWidth = max(100.0, visibleFrame.size.width - 2 * margin)
        let effectiveHeight = max(100.0, visibleFrame.size.height - 2 * margin)
        
        let safeCols = max(1, totalCols)
        let safeRows = max(1, totalRows)
        
        let clampedColStart = min(max(0, colStart), safeCols - 1)
        let clampedColEnd = min(max(clampedColStart, colEnd), safeCols - 1)
        let clampedRowStart = min(max(0, rowStart), safeRows - 1)
        let clampedRowEnd = min(max(clampedRowStart, rowEnd), safeRows - 1)
        
        let selCols = CGFloat(clampedColEnd - clampedColStart + 1)
        let selRows = CGFloat(clampedRowEnd - clampedRowStart + 1)
        
        let colUnit = effectiveWidth / CGFloat(safeCols)
        let rowUnit = effectiveHeight / CGFloat(safeRows)
        
        // Calculate target rect in AppKit coordinates
        var targetX = effectiveX + CGFloat(clampedColStart) * colUnit
        var targetWidth = selCols * colUnit
        
        // Y coordinate: Row 0 is at top
        let topEdgeAppKit = effectiveY + effectiveHeight - CGFloat(clampedRowStart) * rowUnit
        var targetHeight = selRows * rowUnit
        var targetY = topEdgeAppKit - targetHeight
        
        // Apply window gap
        if gap > 0 {
            targetX += gap / 2.0
            targetY += gap / 2.0
            targetWidth -= gap
            targetHeight -= gap
        }
        
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        
        // Convert to AX coordinates
        var axPoint = CGPoint(
            x: round(targetX),
            y: round(primaryHeight - (targetY + targetHeight))
        )
        var axSize = CGSize(
            width: round(targetWidth),
            height: round(targetHeight)
        )
        
        // Set position and size
        if let posVal = AXValueCreate(.cgPoint, &axPoint) {
            AXUIElementSetAttributeValue(winElement, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(winElement, kAXSizeAttribute as CFString, sizeVal)
        }
        // Second pass for position in case window constrained minimum size
        if let posVal = AXValueCreate(.cgPoint, &axPoint) {
            AXUIElementSetAttributeValue(winElement, kAXPositionAttribute as CFString, posVal)
        }
        
        // Activate target application
        if #available(macOS 14.0, *) {
            target.app.activate()
        } else {
            target.app.activate(options: [.activateIgnoringOtherApps])
        }
    }
    
    // MARK: - Multi-Monitor Throw (跨螢幕快速投遞)
    
    func throwToNextScreen() {
        throwToScreen(delta: 1)
    }
    
    func throwToPrevScreen() {
        throwToScreen(delta: -1)
    }
    
    private func throwToScreen(delta: Int) {
        guard let target = captureCurrentFrontmostWindow() else {
            LogDebug("throwToScreen: No frontmost window found")
            NSSound.beep()
            return
        }
        
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            LogDebug("throwToScreen: Only 1 screen available, cannot throw")
            NSSound.beep()
            return
        }
        
        let curScreen = target.screen
        let curIdx = screens.firstIndex(of: curScreen) ?? 0
        let nextIdx = (curIdx + delta + screens.count) % screens.count
        let nextScreen = screens[nextIdx]
        
        let winElement = target.windowElement
        
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(winElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(winElement, kAXSizeAttribute as CFString, &sizeRef)
        
        var curAXPoint = CGPoint.zero
        var curAXSize = CGSize.zero
        if let posVal = posRef { AXValueGetValue(posVal as! AXValue, .cgPoint, &curAXPoint) }
        if let sizeVal = sizeRef { AXValueGetValue(sizeVal as! AXValue, .cgSize, &curAXSize) }
        
        guard let primaryScreen = screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        
        // Convert AX coordinate to AppKit Y
        let curWinAppKitY = primaryHeight - (curAXPoint.y + curAXSize.height)
        let curVis = curScreen.visibleFrame
        
        // Relative proportions within curScreen.visibleFrame
        let relX = (curAXPoint.x - curVis.origin.x) / max(1.0, curVis.width)
        let relY = (curWinAppKitY - curVis.origin.y) / max(1.0, curVis.height)
        let relW = curAXSize.width / max(1.0, curVis.width)
        let relH = curAXSize.height / max(1.0, curVis.height)
        
        // Map to nextScreen.visibleFrame
        let nextVis = nextScreen.visibleFrame
        let newW = min(nextVis.width, max(150.0, round(relW * nextVis.width)))
        let newH = min(nextVis.height, max(150.0, round(relH * nextVis.height)))
        var newX = nextVis.origin.x + round(relX * nextVis.width)
        var newY = nextVis.origin.y + round(relY * nextVis.height)
        
        // Keep within bounds
        if newX + newW > nextVis.maxX { newX = nextVis.maxX - newW }
        if newX < nextVis.minX { newX = nextVis.minX }
        if newY + newH > nextVis.maxY { newY = nextVis.maxY - newH }
        if newY < nextVis.minY { newY = nextVis.minY }
        
        var newAXPoint = CGPoint(
            x: round(newX),
            y: round(primaryHeight - (newY + newH))
        )
        var newAXSize = CGSize(width: round(newW), height: round(newH))
        
        if let posVal = AXValueCreate(.cgPoint, &newAXPoint) {
            AXUIElementSetAttributeValue(winElement, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &newAXSize) {
            AXUIElementSetAttributeValue(winElement, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &newAXPoint) {
            AXUIElementSetAttributeValue(winElement, kAXPositionAttribute as CFString, posVal)
        }
        
        LogDebug("throwToScreen: Moved '\(target.windowTitle)' from Screen #\(curIdx + 1) to Screen #\(nextIdx + 1)")
        
        if #available(macOS 14.0, *) {
            target.app.activate()
        } else {
            target.app.activate(options: [.activateIgnoringOtherApps])
        }
    }
    
    // MARK: - Repeated Hotkey Cycling (連續按鍵循環)
    
    private enum CycleAction {
        case left, right, max, center
    }
    private var lastCycleAction: CycleAction?
    private var lastCycleTime: Date = .distantPast
    private var currentCycleStep: Int = 0
    private let cycleTimeout: TimeInterval = 1.3
    
    func snapLeftCycle() {
        let now = Date()
        if lastCycleAction == .left && now.timeIntervalSince(lastCycleTime) < cycleTimeout {
            currentCycleStep = (currentCycleStep + 1) % 3
        } else {
            currentCycleStep = 0
        }
        lastCycleAction = .left
        lastCycleTime = now
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        switch currentCycleStep {
        case 0: // Left 1/2
            let half = cols / 2
            snapTarget(target: nil, colStart: 0, colEnd: half - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        case 1: // Left 2/3
            let twoThirds = max(1, Int(round(Double(cols) * 2.0 / 3.0)))
            snapTarget(target: nil, colStart: 0, colEnd: twoThirds - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        case 2: // Left 1/3
            let oneThird = max(1, Int(round(Double(cols) / 3.0)))
            snapTarget(target: nil, colStart: 0, colEnd: oneThird - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        default:
            break
        }
    }
    
    func snapRightCycle() {
        let now = Date()
        if lastCycleAction == .right && now.timeIntervalSince(lastCycleTime) < cycleTimeout {
            currentCycleStep = (currentCycleStep + 1) % 3
        } else {
            currentCycleStep = 0
        }
        lastCycleAction = .right
        lastCycleTime = now
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        switch currentCycleStep {
        case 0: // Right 1/2
            let half = cols / 2
            snapTarget(target: nil, colStart: half, colEnd: cols - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        case 1: // Right 2/3
            let twoThirds = max(1, Int(round(Double(cols) * 2.0 / 3.0)))
            let start = cols - twoThirds
            snapTarget(target: nil, colStart: start, colEnd: cols - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        case 2: // Right 1/3
            let oneThird = max(1, Int(round(Double(cols) / 3.0)))
            let start = cols - oneThird
            snapTarget(target: nil, colStart: start, colEnd: cols - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        default:
            break
        }
    }
    
    func snapMaxCycle() {
        let now = Date()
        if lastCycleAction == .max && now.timeIntervalSince(lastCycleTime) < cycleTimeout {
            currentCycleStep = (currentCycleStep + 1) % 3
        } else {
            currentCycleStep = 0
        }
        lastCycleAction = .max
        lastCycleTime = now
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        switch currentCycleStep {
        case 0: // Full Maximize
            snapTarget(target: nil, colStart: 0, colEnd: cols - 1, rowStart: 0, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        case 1: // Top Half
            let halfRows = max(1, rows / 2)
            snapTarget(target: nil, colStart: 0, colEnd: cols - 1, rowStart: 0, rowEnd: halfRows - 1, totalCols: cols, totalRows: rows)
        case 2: // Bottom Half
            let halfRows = max(1, rows / 2)
            snapTarget(target: nil, colStart: 0, colEnd: cols - 1, rowStart: halfRows, rowEnd: rows - 1, totalCols: cols, totalRows: rows)
        default:
            break
        }
    }
    
    func snapCenterCycle() {
        let now = Date()
        if lastCycleAction == .center && now.timeIntervalSince(lastCycleTime) < cycleTimeout {
            currentCycleStep = (currentCycleStep + 1) % 3
        } else {
            currentCycleStep = 0
        }
        lastCycleAction = .center
        lastCycleTime = now
        
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        
        switch currentCycleStep {
        case 0: // Medium Center (e.g. 66% width, 75% height)
            let colStart = max(1, cols / 6)
            let colEnd = min(cols - 2, cols - 1 - colStart)
            let rowStart = max(1, rows / 6)
            let rowEnd = min(rows - 2, rows - 1 - rowStart)
            snapTarget(target: nil, colStart: colStart, colEnd: colEnd, rowStart: rowStart, rowEnd: rowEnd, totalCols: cols, totalRows: rows)
        case 1: // Large Center (~85% width)
            let colStart = max(0, cols / 12)
            let colEnd = min(cols - 1, cols - 1 - colStart)
            let rowStart = max(0, rows / 12)
            let rowEnd = min(rows - 1, rows - 1 - rowStart)
            snapTarget(target: nil, colStart: colStart, colEnd: colEnd, rowStart: rowStart, rowEnd: rowEnd, totalCols: cols, totalRows: rows)
        case 2: // Compact Center (~50% width, ~60% height)
            let colWidth = max(2, cols / 2)
            let colStart = (cols - colWidth) / 2
            let colEnd = colStart + colWidth - 1
            let rowHeight = max(2, Int(round(Double(rows) * 0.6)))
            let rowStart = (rows - rowHeight) / 2
            let rowEnd = rowStart + rowHeight - 1
            snapTarget(target: nil, colStart: colStart, colEnd: colEnd, rowStart: rowStart, rowEnd: rowEnd, totalCols: cols, totalRows: rows)
        default:
            break
        }
    }
    
    // MARK: - Direct Preset Slots 1~9 (數字鍵 1~9 快速槽)
    
    func getPresetSlotCoordinates(slot: Int, cols: Int, rows: Int) -> (colStart: Int, colEnd: Int, rowStart: Int, rowEnd: Int) {
        switch slot {
        case 1: // Left 1/3
            let w = max(1, Int(round(Double(cols) / 3.0)))
            return (0, w - 1, 0, rows - 1)
        case 2: // Center 1/3
            let w = max(1, Int(round(Double(cols) / 3.0)))
            let start = (cols - w) / 2
            return (start, start + w - 1, 0, rows - 1)
        case 3: // Right 1/3
            let w = max(1, Int(round(Double(cols) / 3.0)))
            return (cols - w, cols - 1, 0, rows - 1)
        case 4: // Left 1/2
            let half = cols / 2
            return (0, half - 1, 0, rows - 1)
        case 5: // Focused Center
            let w = max(2, Int(round(Double(cols) * 0.66)))
            let start = (cols - w) / 2
            let h = max(2, Int(round(Double(rows) * 0.75)))
            let rStart = (rows - h) / 2
            return (start, start + w - 1, rStart, rStart + h - 1)
        case 6: // Right 1/2
            let half = cols / 2
            return (half, cols - 1, 0, rows - 1)
        case 7: // Left 2/3
            let w = max(1, Int(round(Double(cols) * 2.0 / 3.0)))
            return (0, w - 1, 0, rows - 1)
        case 8: // Maximize
            return (0, cols - 1, 0, rows - 1)
        case 9: // Right 2/3
            let w = max(1, Int(round(Double(cols) * 2.0 / 3.0)))
            return (cols - w, cols - 1, 0, rows - 1)
        default:
            return (0, cols - 1, 0, rows - 1)
        }
    }
    
    func snapPresetSlot(_ slot: Int) {
        let cols = Preferences.shared.gridColumns
        let rows = Preferences.shared.gridRows
        let coords = getPresetSlotCoordinates(slot: slot, cols: cols, rows: rows)
        snapTarget(
            target: nil,
            colStart: coords.colStart,
            colEnd: coords.colEnd,
            rowStart: coords.rowStart,
            rowEnd: coords.rowEnd,
            totalCols: cols,
            totalRows: rows
        )
    }
    
    // Quick presets (backward compatible)
    func snapLeftHalf() {
        snapLeftCycle()
    }
    
    func snapRightHalf() {
        snapRightCycle()
    }
    
    func snapMaximize() {
        snapMaxCycle()
    }
    
    func snapCenterSmall() {
        snapCenterCycle()
    }
}
