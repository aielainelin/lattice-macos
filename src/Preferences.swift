import Foundation
import Cocoa

final class Preferences {
    static let shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let kGridRows = "Lattice_GridRows"
    private let kGridColumns = "Lattice_GridColumns"
    private let kWindowGap = "Lattice_WindowGap"
    private let kScreenMargin = "Lattice_ScreenMargin"
    private let kLaunchAtLogin = "Lattice_LaunchAtLogin"
    
    var gridRows: Int {
        get {
            let val = defaults.integer(forKey: kGridRows)
            return val > 0 ? val : 6
        }
        set {
            defaults.set(newValue, forKey: kGridRows)
        }
    }
    
    var gridColumns: Int {
        get {
            let val = defaults.integer(forKey: kGridColumns)
            return val > 0 ? val : 6
        }
        set {
            defaults.set(newValue, forKey: kGridColumns)
        }
    }
    
    var windowGap: CGFloat {
        get {
            return CGFloat(defaults.double(forKey: kWindowGap))
        }
        set {
            defaults.set(Double(newValue), forKey: kWindowGap)
        }
    }
    
    var screenMargin: CGFloat {
        get {
            return CGFloat(defaults.double(forKey: kScreenMargin))
        }
        set {
            defaults.set(Double(newValue), forKey: kScreenMargin)
        }
    }
    
    var launchAtLogin: Bool {
        get {
            return defaults.bool(forKey: kLaunchAtLogin)
        }
        set {
            defaults.set(newValue, forKey: kLaunchAtLogin)
        }
    }
    
    private init() {
        defaults.register(defaults: [
            kGridRows: 6,
            kGridColumns: 6,
            kWindowGap: 0.0,
            kScreenMargin: 0.0,
            kLaunchAtLogin: false
        ])
    }
}
