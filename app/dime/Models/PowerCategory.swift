//
//  PowerCategory.swift
//  Bonsai
//
//  Created by Rafael Soh on 6/6/22.
//

import Foundation
import SwiftUI

struct PowerCategory: Hashable, Identifiable {
    let id: UUID
    let category: Category
    let percent: Double
    let amount: Double
}

struct SuggestedCategory: Hashable {
    let name: String
    let emoji: String

    static var expenses: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let food = SuggestedCategory(name: "Food", emoji: "🍔")
        holding.append(food)

        let transport = SuggestedCategory(name: "Transport", emoji: "🚆")
        holding.append(transport)

        let housing = SuggestedCategory(name: "Rent", emoji: "🏠")
        holding.append(housing)

        let subscriptions = SuggestedCategory(name: "Subscriptions", emoji: "🔄")
        holding.append(subscriptions)

        let groceries = SuggestedCategory(name: "Groceries", emoji: "🛒")
        holding.append(groceries)

        let coffee = SuggestedCategory(name: "Coffee", emoji: "☕")
        holding.append(coffee)

        let family = SuggestedCategory(name: "Family", emoji: "👨‍👩‍👦")
        holding.append(family)

        let utilities = SuggestedCategory(name: "Utilities", emoji: "💡")
        holding.append(utilities)

        let fashion = SuggestedCategory(name: "Fashion", emoji: "👔")
        holding.append(fashion)

        let healthcare = SuggestedCategory(name: "Healthcare", emoji: "🚑")
        holding.append(healthcare)

        let pets = SuggestedCategory(name: "Pets", emoji: "🐕")
        holding.append(pets)

        let sneakers = SuggestedCategory(name: "Sneakers", emoji: "👟")
        holding.append(sneakers)

        let gifts = SuggestedCategory(name: "Gifts", emoji: "🎁")
        holding.append(gifts)

        return holding
    }

    static var incomes: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let paycheck = SuggestedCategory(name: "Paycheck", emoji: "💰")
        holding.append(paycheck)

        let allowance = SuggestedCategory(name: "Allowance", emoji: "🤑")
        holding.append(allowance)

        let parttime = SuggestedCategory(name: "Part-Time", emoji: "💼")
        holding.append(parttime)

        let investments = SuggestedCategory(name: "Investments", emoji: "💹")
        holding.append(investments)

        let gifts = SuggestedCategory(name: "Gifts", emoji: "🧧")
        holding.append(gifts)

        let tips = SuggestedCategory(name: "Tips", emoji: "🪙")
        holding.append(tips)

        return holding
    }
}
