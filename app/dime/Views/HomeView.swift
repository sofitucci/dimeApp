//
//  HomeView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import ConfettiSwiftUI
import Foundation
import SwiftUI
import UserNotifications

class OverallToastPresenter: ObservableObject {
    @Published var showToast: Bool = false
}

enum DeletionType {
    case instant
    case prompt
}

class OverallTransactionManager: ObservableObject {
    @Published var toEdit: Transaction?
    @Published var toDelete: Transaction?
    @Published var showToast: Bool = false
    @Published var showPopup: Bool = false
    @Published var future: Bool = false
}

struct HomeView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    @StateObject var toastPresenter = OverallToastPresenter()
    @StateObject var transactionManager = OverallTransactionManager()
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State var currentTab = "Log"

    var topEdge: CGFloat
    var bottomEdge: CGFloat

    @State var fromURL1: Bool = false
    @State var fromURL2: Bool = false
    @State var fromURL3: Bool = false
    @State var fromURL4: Bool = false

    @State var launchAdd: Bool = false
    @State var launchSearch: Bool = false

    @State private var pendingExternalImportURL: URL?
    @State private var pendingHermesSyncConfigurationURL: URL?
    @State private var confirmedExternalImportURL: URL?
    @State private var confirmedExternalImportBatch: ExternalTransactionImportBatch?
    @State private var pendingHermesSyncEndpoint: URL?
    @State private var externalImportMessage = ""
    @State private var showExternalImportAlert = false
    @State private var showExternalImportConfirmation = false
    @State private var showHermesSyncConfigurationConfirmation = false
    @State private var isHermesSyncing = false
    @State private var hermesReadyCount = 0
    @State private var pendingHermesAutoImport = false

    @State var counter = 0

    @EnvironmentObject var tabBarManager: TabBarManager
    @Environment(\.scenePhase) var scenePhase

    @State var showPopup = false

    // Hiding Native TabBar...
    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        UITabBar.appearance().isHidden = true
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentTab) {
                LogView(
                    topEdge: topEdge,
                    bottomEdge: bottomEdge,
                    launchSearch: launchSearch,
                    isHermesSyncing: isHermesSyncing,
                    hermesReadyCount: hermesReadyCount,
                    onHermesSync: syncHermesTransactions
                )
                    .ignoresSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Log")

                InsightsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Insights")

                BudgetView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Budget")

                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Settings")
            }
            .allowsHitTesting(showPopup ? false : true)
            .environmentObject(toastPresenter)
            .environmentObject(transactionManager)

            CustomTabBar(currentTab: $currentTab, topEdge: topEdge, bottomEdge: bottomEdge, counter: $counter, launchAdd: launchAdd)
                .offset(y: tabBarManager.hideTab ? (70 + bottomEdge) : 0)

            if showPopup {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transactionManager.showPopup = false
                    }
            }

            DeleteTransactionAlert()
                .offset(y: showPopup ? 0 : 300)
                .environmentObject(transactionManager)

            if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                AppLockView()
                    .ignoresSafeArea(.all)
                    .onOpenURL { url in

                        if ExternalTransactionImporter.canHandle(url) {
                            pendingExternalImportURL = url
                        } else if HermesTransactionSyncClient.canHandleConfiguration(url) {
                            pendingHermesSyncConfigurationURL = url
                        } else if url.host == "newExpense" {
                            fromURL1 = true
                        } else if url.host == "search" {
                            fromURL2 = true
                        } else if url.host == "insights" {
                            fromURL3 = true
                        } else if url.host == "budget" {
                            fromURL4 = true
                        }
                    }
            }
        }
        .toast(isPresenting: $toastPresenter.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("checkmark.circle.fill", Color.IncomeGreen), title: "Image Saved", subTitle: "Check it out in Photos")
        })
        .toast(isPresenting: $transactionManager.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("arrow.uturn.backward.circle.fill", Color.AlertRed), title: "Log Deleted", subTitle: "Tap to Undo")
        }, onTap: {
            withAnimation(.easeInOut(duration: 0.5)) {
                moc.rollback()
            }
            transactionManager.toDelete = nil
        }, completion: {
            dataController.save()
            transactionManager.toDelete = nil
        })
        .onChange(of: transactionManager.showPopup) { newValue in
            withAnimation {
                showPopup = newValue
            }
        }
        .fullScreenCover(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .confettiCannon(counter: $counter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .onAppear {
            if appLockVM.isAppLockEnabled && fromURL1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchAdd.toggle()
                }

                fromURL1 = false
            }

            if appLockVM.isAppLockEnabled && fromURL2 {
                currentTab = "Log"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchSearch.toggle()
                }

                fromURL2 = false
            }

            if appLockVM.isAppLockEnabled && fromURL3 {
                currentTab = "Insights"
            }

            if appLockVM.isAppLockEnabled && fromURL4 {
                currentTab = "Budget"
            }
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .onChange(of: appLockVM.isAppUnLocked) { isUnlocked in
            if isUnlocked {
                handlePendingHermesSyncConfiguration()
                handlePendingExternalImport()
                consumePendingHermesAutoImport()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hermesAutoImportRequested)) { _ in
            consumePendingHermesAutoImport()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                AppDelegate.scheduleHermesRefresh()
                refreshHermesReadyBanner()
                consumePendingHermesAutoImport()
            }
        }
        .onAppear {
            refreshHermesReadyBanner()
            consumePendingHermesAutoImport()
        }
        .alert("Import Dime Transactions?", isPresented: $showExternalImportConfirmation) {
            Button("Cancel", role: .cancel) {
                confirmedExternalImportURL = nil
                confirmedExternalImportBatch = nil
            }
            Button("Import") {
                confirmExternalTransactionImport()
            }
        } message: {
            Text(externalImportMessage)
        }
        .alert("Connect Hermes Sync?", isPresented: $showHermesSyncConfigurationConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingHermesSyncEndpoint = nil
            }
            Button("Connect") {
                confirmHermesSyncConfiguration()
            }
        } message: {
            Text(externalImportMessage)
        }
        .alert("Dime Import", isPresented: $showExternalImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(externalImportMessage)
        }
    }

    private func handleURL(_ url: URL) {
        if ExternalTransactionImporter.canHandle(url) {
            if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                pendingExternalImportURL = url
                return
            }

            handleExternalTransactionImport(url)
            return
        }

        if HermesTransactionSyncClient.canHandleConfiguration(url) {
            if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                pendingHermesSyncConfigurationURL = url
                return
            }

            handleHermesSyncConfiguration(url)
            return
        }

        if url.host == "search" {
            currentTab = "Log"
        } else if url.host == "insights" {
            currentTab = "Insights"
        } else if url.host == "budget" {
            currentTab = "Budget"
        }
    }

    private func handlePendingExternalImport() {
        guard let url = pendingExternalImportURL else {
            return
        }

        pendingExternalImportURL = nil
        handleExternalTransactionImport(url)
    }

    private func handlePendingHermesSyncConfiguration() {
        guard let url = pendingHermesSyncConfigurationURL else {
            return
        }

        pendingHermesSyncConfigurationURL = nil
        handleHermesSyncConfiguration(url)
    }

    private func handleHermesSyncConfiguration(_ url: URL) {
        do {
            let syncEndpoint = try HermesTransactionSyncClient.endpoint(fromConfigurationURL: url)
            pendingHermesSyncEndpoint = syncEndpoint
            externalImportMessage = "Connect Dime to Hermes sync at \(syncEndpoint.host ?? "this endpoint")? Only connect if this setup link came from Sofia's Hermes chat."
            showHermesSyncConfigurationConfirmation = true
        } catch {
            externalImportMessage = error.localizedDescription
            showExternalImportAlert = true
        }
    }

    private func confirmHermesSyncConfiguration() {
        guard let syncEndpoint = pendingHermesSyncEndpoint else {
            return
        }

        pendingHermesSyncEndpoint = nil
        HermesTransactionSyncClient.configure(endpoint: syncEndpoint)
        externalImportMessage = "Hermes sync is connected. Tap the refresh icon on the Log screen to import pending expenses."
        showExternalImportAlert = true
    }

    private func syncHermesTransactions() {
        syncHermesTransactions(autoImport: false)
    }

    private func syncHermesTransactions(autoImport: Bool) {
        guard !isHermesSyncing else {
            return
        }

        if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
            if autoImport {
                pendingHermesAutoImport = true
                HermesSyncReadyMonitor.pendingAutoImport = true
            } else {
                externalImportMessage = "Unlock Dime before syncing Hermes expenses."
                showExternalImportAlert = true
            }
            return
        }

        isHermesSyncing = true

        Task {
            do {
                let batch = try await HermesTransactionSyncClient.fetchPendingBatch()

                await MainActor.run {
                    isHermesSyncing = false
                    if autoImport {
                        importHermesBatch(batch)
                    } else {
                        handleExternalTransactionImport(batch)
                    }
                }
            } catch {
                await MainActor.run {
                    isHermesSyncing = false
                    externalImportMessage = error.localizedDescription
                    showExternalImportAlert = true
                }
            }
        }
    }

    private func consumePendingHermesAutoImport() {
        guard HermesSyncReadyMonitor.pendingAutoImport || pendingHermesAutoImport else {
            return
        }

        pendingHermesAutoImport = false
        HermesSyncReadyMonitor.pendingAutoImport = false
        syncHermesTransactions(autoImport: true)
    }

    private func refreshHermesReadyBanner() {
        Task {
            let count = await HermesSyncReadyMonitor.check(postNotificationIfBackground: false)
            await MainActor.run {
                hermesReadyCount = count
            }
        }
    }

    private func importHermesBatch(_ batch: ExternalTransactionImportBatch) {
        do {
            let preview = try ExternalTransactionImporter.previewBatch(batch, dataController: dataController)
            guard preview.hasActionableImports else {
                hermesReadyCount = 0
                externalImportMessage = "No new Hermes expenses to import."
                showExternalImportAlert = true
                return
            }

            let result = try ExternalTransactionImporter.importBatch(batch, dataController: dataController)
            hermesReadyCount = 0
            HermesSyncReadyMonitor.pendingAutoImport = false
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [HermesSyncReadyMonitor.notificationId])
            UIApplication.shared.applicationIconBadgeNumber = 0
            externalImportMessage = result.message
            showExternalImportAlert = true
            if !result.handledExternalIds.isEmpty {
                let handledExternalIds = result.handledExternalIds
                Task {
                    try? await HermesTransactionSyncClient.acknowledgeImportedExternalIds(handledExternalIds)
                }
            }
        } catch {
            externalImportMessage = error.localizedDescription
            showExternalImportAlert = true
        }
    }

    private func handleExternalTransactionImport(_ url: URL) {
        do {
            let preview = try ExternalTransactionImporter.previewBatch(from: url, dataController: dataController)
            guard preview.hasActionableImports else {
                confirmedExternalImportBatch = nil
                confirmedExternalImportURL = nil
                externalImportMessage = "No new Hermes expenses to import."
                showExternalImportAlert = true
                return
            }

            confirmedExternalImportBatch = nil
            confirmedExternalImportURL = url
            externalImportMessage = preview.message
            showExternalImportConfirmation = true
        } catch {
            externalImportMessage = error.localizedDescription
            showExternalImportAlert = true
        }
    }

    private func handleExternalTransactionImport(_ batch: ExternalTransactionImportBatch) {
        do {
            let preview = try ExternalTransactionImporter.previewBatch(batch, dataController: dataController)

            guard preview.hasActionableImports else {
                confirmedExternalImportBatch = nil
                confirmedExternalImportURL = nil
                externalImportMessage = "No new Hermes expenses to import."
                showExternalImportAlert = true
                return
            }

            confirmedExternalImportURL = nil
            confirmedExternalImportBatch = batch
            externalImportMessage = preview.message
            showExternalImportConfirmation = true
        } catch {
            externalImportMessage = error.localizedDescription
            showExternalImportAlert = true
        }
    }

    private func confirmExternalTransactionImport() {
        let result: ExternalTransactionImportResult
        let shouldAcknowledgeHermesSync: Bool

        do {
            if let url = confirmedExternalImportURL {
                confirmedExternalImportURL = nil
                shouldAcknowledgeHermesSync = false
                result = try ExternalTransactionImporter.importBatch(from: url, dataController: dataController)
            } else if let batch = confirmedExternalImportBatch {
                confirmedExternalImportBatch = nil
                shouldAcknowledgeHermesSync = true
                result = try ExternalTransactionImporter.importBatch(batch, dataController: dataController)
            } else {
                return
            }

            externalImportMessage = result.message
            if shouldAcknowledgeHermesSync && !result.handledExternalIds.isEmpty {
                let handledExternalIds = result.handledExternalIds
                Task {
                    try? await HermesTransactionSyncClient.acknowledgeImportedExternalIds(handledExternalIds)
                }
            }
        } catch {
            externalImportMessage = error.localizedDescription
        }

        showExternalImportAlert = true
    }
}

struct AppLockView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.fill")
                .font(.system(size: 65))
                .foregroundColor(Color.DarkIcon.opacity(0.7))

            Text("App Locked")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.bottom, 30)

            Button {
                appLockVM.appLockValidation()
            } label: {
                HStack {
                    Image(systemName: "faceid")

                    Text("Unlock App")
                }
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.Outline)
                }
            }

            if appLockVM.enrollmentError {
                Text("Please re-enable Face ID access in the Settings app to unlock application.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
