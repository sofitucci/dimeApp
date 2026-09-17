//
//  Helper.swift
//  dime
//
//  Created by Rafael Soh on 13/8/22.
//

import Foundation

enum DimeCurrencyConversion {
    static var cachedUSDToUYURate: Double?

    static func normalizedCurrency(_ rawValue: String?) -> String? {
        guard let currency = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !currency.isEmpty else {
            return nil
        }

        return currency
    }

    static func appCurrencyCode() -> String {
        let stored = DimeDefaults.shared.string(forKey: "currency")?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let stored, !stored.isEmpty {
            return stored
        }

        return Locale.current.currencyCode?.uppercased() ?? "UYU"
    }

    static func refresh(from transactions: [Transaction]) {
        let ranked = transactions.filter { $0.exchangeRate > 0 && $0.exchangeRate.isFinite }
        guard let best = ranked.max(by: { lhs, rhs in
            let left = lhs.exchangeRateDate ?? lhs.date ?? .distantPast
            let right = rhs.exchangeRateDate ?? rhs.date ?? .distantPast
            return left < right
        }) else {
            return
        }

        cachedUSDToUYURate = best.exchangeRate
    }
}

extension Transaction {
    var wrappedAmount: Double {
        displayAmount(in: DimeCurrencyConversion.appCurrencyCode())
    }

    func displayAmount(in targetCurrency: String, fallbackUSDToUYURate: Double? = DimeCurrencyConversion.cachedUSDToUYURate) -> Double {
        let target = DimeCurrencyConversion.normalizedCurrency(targetCurrency) ?? targetCurrency.uppercased()
        let original = DimeCurrencyConversion.normalizedCurrency(originalCurrency)
        let converted = DimeCurrencyConversion.normalizedCurrency(convertedCurrency)
        let rowRate = exchangeRate > 0 && exchangeRate.isFinite ? exchangeRate : nil
        let rate = rowRate ?? fallbackUSDToUYURate

        if let original, original == target, originalAmount > 0, originalAmount.isFinite {
            return originalAmount
        }

        if let converted, converted == target, convertedAmount > 0, convertedAmount.isFinite {
            return convertedAmount
        }

        if let rate, rate > 0 {
            if let original, originalAmount > 0, originalAmount.isFinite {
                if original == "USD", target == "UYU" {
                    return originalAmount * rate
                }
                if original == "UYU", target == "USD" {
                    return originalAmount / rate
                }
            }

            if let converted, convertedAmount > 0, convertedAmount.isFinite {
                if converted == "USD", target == "UYU" {
                    return convertedAmount * rate
                }
                if converted == "UYU", target == "USD" {
                    return convertedAmount / rate
                }
            }

            if target == "USD" {
                return amount / rate
            }
        }

        return amount
    }

    var wrappedDate: Date {
        date ?? Date.now
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedCategoryName: String {
        category?.wrappedName ?? ""
    }

    var wrappedExternalSource: String {
        externalSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var externalSourceLabel: String? {
        let label = wrappedExternalSource
        return label.isEmpty ? nil : label
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }

    var nextTransactionDate: Date {
        if recurringType == 1 {
            return Calendar.current.date(byAdding: .day, value: Int(recurringCoefficient), to: day ?? Date.now)!
        } else if recurringType == 2 {
            return Calendar.current.date(byAdding: .day, value: Int(recurringCoefficient * 7), to: day ?? Date.now)!
        } else if recurringType == 3 {
            return Calendar.current.date(byAdding: .month, value: Int(recurringCoefficient), to: day ?? Date.now)!
        }

        return date ?? Date.now
    }
}

extension TemplateTransaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }
}

extension Category {
    var wrappedColour: String {
        colour ?? "#FFFFFF"
    }

    var wrappedEmoji: String {
        emoji ?? "😄️"
    }

    var wrappedName: String {
        name ?? ""
    }

    var wrappedDate: Date {
        dateCreated ?? Date.now
    }

    var fullName: String {
        wrappedEmoji + "  " + wrappedName
    }

    var allTransactions: [Transaction] {
        let set = transactions as? Set<Transaction> ?? []
        return set.sorted {
            $0.wrappedDate < $1.wrappedDate
        }
    }

    var transactionCount: Int {
        transactions?.count ?? 0
    }
}

public extension Budget {
    var wrappedColour: String {
        category?.wrappedColour ?? "#FFFFFF"
    }

    var wrappedName: String {
        category?.wrappedName ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var fullName: String {
        return wrappedEmoji + " " + wrappedName
    }

    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }
        return startDate ?? Date.now
    }
}

public extension MainBudget {
    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }

        return startDate ?? Date.now
    }
}
