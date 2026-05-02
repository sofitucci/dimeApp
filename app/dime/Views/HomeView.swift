//
//  HomeView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import ConfettiSwiftUI
import Foundation
import SwiftUI

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
    @State private var confirmedExternalImportURL: URL?
    @State private var externalImportMessage = ""
    @State private var showExternalImportAlert = false
    @State private var showExternalImportConfirmation = false

    @State var counter = 0

    @EnvironmentObject var tabBarManager: TabBarManager

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
                LogView(topEdge: topEdge, bottomEdge: bottomEdge, launchSearch: launchSearch)
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
                handlePendingExternalImport()
            }
        }
        .alert("Import Dime Transactions?", isPresented: $showExternalImportConfirmation) {
            Button("Cancel", role: .cancel) {
                confirmedExternalImportURL = nil
            }
            Button("Import") {
                confirmExternalTransactionImport()
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

    private func handleExternalTransactionImport(_ url: URL) {
        do {
            let preview = try ExternalTransactionImporter.previewBatch(from: url, dataController: dataController)
            confirmedExternalImportURL = url
            externalImportMessage = preview.message
            showExternalImportConfirmation = true
        } catch {
            externalImportMessage = error.localizedDescription
            showExternalImportAlert = true
        }
    }

    private func confirmExternalTransactionImport() {
        guard let url = confirmedExternalImportURL else {
            return
        }

        confirmedExternalImportURL = nil

        do {
            let result = try ExternalTransactionImporter.importBatch(from: url, dataController: dataController)
            externalImportMessage = result.message
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
