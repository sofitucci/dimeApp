//
//  UnlockManager.swift
//  dime
//
//  Created by Rafael Soh on 15/9/22.
//

import Foundation

class UnlockManager: ObservableObject {
    enum RequestState {
        case loading
        case loaded
        case failed
    }

    struct TipProduct: Hashable {
        let productIdentifier: String
        let localizedPrice: String
        let sortPrice: Double
    }

    var canMakePayments: Bool {
        false
    }

    @Published var requestState = RequestState.failed
    @Published var purchaseCount: Int
    @Published var failedTransaction = false

    private let dataController: DataController
    var loadedProducts = [TipProduct]()

    func buy(product _: TipProduct) {
        failedTransaction = true
        revertBool()
    }

    func revertBool() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.failedTransaction = false
        }
    }

    func restore() {
        failedTransaction = true
        revertBool()
    }

    init(dataController: DataController) {
        self.dataController = dataController
        purchaseCount = dataController.tipCounter
    }
}
