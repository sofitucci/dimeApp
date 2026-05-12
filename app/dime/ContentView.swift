//
//  ContentView.swift
//
//  Created by Rafael Soh on 3/6/22.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @EnvironmentObject var dataController: DataController

    @AppStorage("colourScheme", store: DimeDefaults.shared) var colourScheme: Int = 0
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("showNotifications", store: DimeDefaults.shared) var showNotifications: Bool = false
    @AppStorage("notificationsEnabled", store: DimeDefaults.shared) var notificationsEnabled: Bool = true

    @AppStorage("firstLaunch", store: DimeDefaults.shared) var firstLaunch: Bool = true

    // adds category orders
    @AppStorage("dataMigration1", store: DimeDefaults.shared) var dataMigration1: Bool = true

    // converts category colors to hex codes
    @AppStorage("dataMigration2", store: DimeDefaults.shared) var dataMigration2: Bool = true

    @AppStorage("currency", store: DimeDefaults.shared) var currency: String = Locale.current.currencyCode!

    @State var showIntro: Bool = false
    @State var showUpdate: Bool = false

    var center = UNUserNotificationCenter.current()

    @AppStorage("topEdge", store: DimeDefaults.shared) var savedTopEdge: Double = 30
    @AppStorage("bottomEdge", store: DimeDefaults.shared) var savedBottomEdge: Double = 15

    // updateSheetShowing

    @AppStorage("previousVersion", store: DimeDefaults.shared) var previousVersionString: String = "Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))"

    @AppStorage("showUpdateSheet", store: DimeDefaults.shared) var showUpdateSheet: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let topEdge = proxy.safeAreaInsets.top
            let bottomEdge = proxy.safeAreaInsets.bottom

            HomeView(topEdge: topEdge, bottomEdge: bottomEdge == 0 ? 15 : bottomEdge)
                .ignoresSafeArea(.all, edges: .bottom)
                .preferredColorScheme(colourScheme == 1 ? .light : colourScheme == 2 ? .dark : nil)
                .fullScreenCover(isPresented: $showIntro) {
                    WelcomeSheetView()
                }
                .fullScreenCover(isPresented: $showUpdate) {
                    UpdateAlert()
                }
                .onAppear {
                    savedTopEdge = topEdge
                    savedBottomEdge = bottomEdge
                }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
//            DimeDefaults.shared.set(false, forKey: "newTransactionAdded")
//            WidgetCenter.shared.reloadTimelines(ofKind: "TemplateTransactions")

            if appLockVM.isAppLockEnabled {
                appLockVM.appLockValidation()
            }

            let defaults =
                DimeDefaults.shared

            if defaults.object(forKey: "firstDayOfMonth") == nil {
                defaults.set(1, forKey: "firstDayOfMonth")
            }

            if firstLaunch {
                showIntro = true
                firstLaunch = false
                showUpdateSheet = false

                defaults.set(1, forKey: "firstWeekday")
                defaults.set(1, forKey: "haptics")
                defaults.set(1, forKey: "firstDayOfMonth")
                defaults.set(1, forKey: "notificationOption")
                defaults.set(false, forKey: "confetti")
                defaults.set(false, forKey: "chromatic")
                defaults.set(true, forKey: "showCents")
                defaults.set(true, forKey: "animated")

                if DimeDefaults.shared.string(forKey: "currency") == nil {
                    DimeDefaults.shared.set(Locale.current.currencyCode!, forKey: "currency")
                } else {
                    currency = DimeDefaults.shared.string(forKey: "currency")!
                }

                defaults.set(2, forKey: "numberEntryType")
            } else {
                if let holdingCurrency = DimeDefaults.shared.string(forKey: "currency") {
                    currency = holdingCurrency
                } else {
                    currency = Locale.current.currencyCode!
                    DimeDefaults.shared.set(Locale.current.currencyCode!, forKey: "currency")
                }
            }

            if dataMigration1 {
                let categoryFetch = dataController.fetchRequestForCategoriesMigration(income: false)
                let categories = dataController.results(for: categoryFetch)

                categories.forEach { category in
                    category.order = Int64(categories.firstIndex(of: category) ?? 0)
                }

                dataController.save()

                dataMigration1 = false
            }

            if dataMigration2 {
                let categoryFetch = dataController.fetchRequestForCategoriesMigration()
                let categories = dataController.results(for: categoryFetch)

                categories.forEach { category in
                    if category.income {
                        category.colour = "#76FBB1"
                    } else {
                        if Double(category.wrappedColour) != nil {
                            category.colour = Color.colourMigrationDictionary[category.wrappedColour] ?? "#FFFFFF"
                        }
                    }
                }

                dataController.save()

                dataMigration2 = false
            }

            if showUpdateSheet {
                showUpdate = true
                showUpdateSheet = false
            }

            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized {
                    if !showNotifications && notificationsEnabled == false {
                        showNotifications = true
                        notificationsEnabled = true
                        newNotification()
                    }
                } else if settings.authorizationStatus == .denied {
                    notificationsEnabled = false

                    if showNotifications {
                        showNotifications = false
                        center.removeAllPendingNotificationRequests()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                if appLockVM.isAppLockEnabled {
                    appLockVM.isAppUnLocked = false
                }
            } else if newPhase == .active {
                center.getNotificationSettings { settings in
                    if settings.authorizationStatus == .authorized {
                        if !showNotifications && notificationsEnabled == false {
                            showNotifications = true
                            notificationsEnabled = true
                            newNotification()
                        }
                    } else if settings.authorizationStatus == .denied {
                        notificationsEnabled = false

                        if showNotifications {
                            showNotifications = false
                            center.removeAllPendingNotificationRequests()
                        }
                    }
                }
            }
        }
    }
}
