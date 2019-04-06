//
//  DockRepository.swift
//  Pock
//
//  Created by Pierluigi Galdi on 06/04/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import Defaults

protocol DockDelegate {
    func didUpdate(apps: [DockItem])
    func didUpdateBadge(for apps: [DockItem])
}

class DockRepository {
    
    /// Core
    private let delegate: DockDelegate
    private var notificationBadgeRefreshTimer: Timer!
    
    /// Running applications
    public  var allItems:            [DockItem] = []
    private var persistentItems:     [DockItem] = []
    private var runningApplications: [DockItem] = []
    
    /// Init
    init(delegate: DockDelegate) {
        self.delegate = delegate
        self.registerForNotifications()
        //self.setupNotificationBadgeRefreshTimer()
    }
    
    /// Deinit
    deinit {
        self.unregisterForNotifications()
    }
    
    /// Reload
    @objc public func reload(_ notification: NSNotification?) {
        // TODO: Analyze notification to add/edit/remove specific item instead of all dataset.
        loadPersistentItems()
        loadRunningApplications()
        loadNotificationBadges()
    }
    
    /// Unregister from notification
    private func unregisterForNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    /// Register for notification
    private func registerForNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reload(_:)),
                                                          name: NSWorkspace.willLaunchApplicationNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reload(_:)),
                                                          name: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reload(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reload(_:)),
                                                          name: NSWorkspace.didDeactivateApplicationNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reload(_:)),
                                                          name: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(self.setupNotificationBadgeRefreshTimer),
                                                          name: .didChangeNotificationBadgeRefreshRate,
                                                          object: nil)
    }
    
    /// Load running applications
    private func loadRunningApplications() {
        runningApplications.removeAll(where: { item in
            return !NSWorkspace.shared.runningApplications.contains(where: { app in
                app.bundleIdentifier == item.bundleIdentifier
            })
        })
        for app in NSWorkspace.shared.runningApplications {
            if let item = allItems.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                item.name        = app.localizedName ?? item.name
                item.icon        = app.icon ?? item.icon
                item.pid_t       = app.processIdentifier
                item.isLaunching = !app.isFinishedLaunching
            }else {
                /// Check for policy
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { continue }
                guard   let localizedName = app.localizedName,
                        let bundleURL     = app.bundleURL,
                        let icon          = app.icon else { continue }
                
                let item = DockItem(0, id, name: localizedName, path: bundleURL, icon: icon, pid_t: app.processIdentifier, launching: !app.isFinishedLaunching)
                allItems.append(item)
            }
        }
        delegate.didUpdate(apps: allItems)
    }
    
    /// Load persistent applications/folders/files
    private func loadPersistentItems() {
        /// Read data from Dock plist
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") else {
            NSLog("[Pock]: Can't read Dock preferences file")
            return
        }
        /// Read persistent apps array
        guard let apps = dict["persistent-apps"] as? [[String: Any]] else {
            NSLog("[Pock]: Can't get persistent apps")
            return
        }
        /// Iterate on apps
        for (index,app) in apps.enumerated() {
            /// Get data tile
            guard let dataTile = app["tile-data"] as? [String: Any] else { NSLog("[Pock]: Can't get app tile-data"); continue }
            /// Get app's label
            guard let label = dataTile["file-label"] as? String else { NSLog("[Pock]: Can't get app label"); continue }
            /// Get app's bundle identifier
            guard let bundleIdentifier = dataTile["bundle-identifier"] as? String else { NSLog("[Pock]: Can't get app bundle identifier"); continue }
            /// Check if item already exists
            if let item = allItems.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                item.pid_t = runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })?.pid_t ?? 0
            }else {
                /// Create item
                let item = DockItem(index,
                                    bundleIdentifier,
                                    name: label,
                                    path: nil,
                                    icon: getIcon(forBundleIdentifier: bundleIdentifier),
                                    pid_t: 0,
                                    launching: false)
                allItems.append(item)
            }
        }
        delegate.didUpdate(apps: allItems)
    }
    
    /// Load notification badges
    private func loadNotificationBadges() {
        for item in allItems {
            item.badge = PockDockHelper.sharedInstance()?.getBadgeCountForItem(withName: item.name)
        }
        let apps = persistentItems.filter({ $0.hasBadge }) + runningApplications.filter({ $0.hasBadge })
        delegate.didUpdateBadge(for: Array(apps))
    }
    
}

extension DockRepository {
    /// Get icon
    private func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil, orType type: String? = nil) -> NSImage {
        /// Check for bundle identifier first
        if bundleIdentifier != nil {
            /// Get app's absolute path
            if let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier!) {
                /// Return icon
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }
        /// Then check for path
        if path != nil {
            return NSWorkspace.shared.icon(forFile: path!)
        }
        /// Last beach, manually check on type
        var genericIconPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns"
        if type != nil {
            if type == "directory-tile" {
                genericIconPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns"
            }else if type == "TrashIcon" || type == "FullTrashIcon" {
                genericIconPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(type!).icns"
            }
        }
        /// Load image
        let genericIcon = NSImage(contentsOfFile: genericIconPath)
        /// Return icon
        return genericIcon ?? NSImage(size: .zero)
    }
    /// Launch app or open file/directory
    public func launch(bundleIdentifier: String?, completion: (Bool) -> ()) {
        /// Check if bundle identifier is valid
        guard bundleIdentifier != nil else {
            completion(false)
            return
        }
        var returnable: Bool = false
        /// Check if file path.
        if bundleIdentifier!.contains("file://") {
            /// Is path, continue as path.
            returnable = NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        }else {
            /// Launch app
            returnable = NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [NSWorkspace.LaunchOptions.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        }
        /// Return status
        completion(returnable)
    }
}

extension DockRepository {
    
    /// Update notification badge refresh timer
    @objc private func setupNotificationBadgeRefreshTimer() {
        /// Get refresh rate
        let refreshRate = defaults[.notificationBadgeRefreshInterval]
        /// Invalidate last timer
        self.notificationBadgeRefreshTimer?.invalidate()
        /// Set timer
        self.notificationBadgeRefreshTimer = Timer.scheduledTimer(withTimeInterval: refreshRate.rawValue, repeats: true, block: {  [weak self] _ in
            /// Log
            NSLog("[Pock]: Refreshing notification badge... (rate: %@)", refreshRate.toString())
            /// Reload badge and running dot
            DispatchQueue.main.async { [weak self] in
                self?.loadNotificationBadges()
            }
        })
    }
    
}
