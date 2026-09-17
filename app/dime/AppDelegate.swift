//
//  AppDelegate.swift
//  dime
//
//  Created by Rafael Soh on 24/8/22.
//

import BackgroundTasks
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let hermesAutoImportRequested = Notification.Name("hermesAutoImportRequested")
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let hermesRefreshTaskId = "com.sofitucci.dime.hermes-sync-refresh"

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.hermesRefreshTaskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Self.handleHermesRefresh(refreshTask)
        }
        Self.scheduleHermesRefresh()
        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfiguration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = SceneDelegate.self
        return sceneConfiguration
    }

    static func scheduleHermesRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: hermesRefreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handleHermesRefresh(_ task: BGAppRefreshTask) {
        scheduleHermesRefresh()
        let work = Task {
            _ = await HermesSyncReadyMonitor.check(postNotificationIfBackground: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task {
            _ = await work.result
            task.setTaskCompleted(success: true)
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if response.notification.request.identifier == HermesSyncReadyMonitor.notificationId
            || userInfo[HermesSyncReadyMonitor.autoImportKey] as? Bool == true {
            HermesSyncReadyMonitor.pendingAutoImport = true
            NotificationCenter.default.post(name: .hermesAutoImportRequested, object: nil)
        }
        completionHandler()
    }
}
