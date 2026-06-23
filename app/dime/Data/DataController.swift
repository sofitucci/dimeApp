//
//  DataController.swift
//  Bonsai
//
//  Created by Rafael Soh on 3/6/22.
//

import CoreData
import Foundation
import SwiftUI
import WidgetKit

enum DimeDefaults {
    static let shared: UserDefaults = .standard
}

@available(iOS 16, *)
enum CustomError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notFound,
         coreDataSave,
         unknownId(id: String),
         unknownError(message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unknownError(message): return "An unknown error occurred: \(message)"
        case let .unknownId(id): return "No category with an ID matching: \(id)"
        case .notFound: return "Category not found"
        case .coreDataSave: return "Couldn't save to CoreData"
        }
    }
}

class DataController: ObservableObject {
    static let shared = DataController()

    var container = NSPersistentContainer(name: "MainModel")

    private static func localPersistentStoreURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sofitucci.dime"
        let storeDirectory = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)

        do {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        } catch {
            assertionFailure("Unable to create Dime store directory: \(error.localizedDescription)")
        }

        return storeDirectory.appendingPathComponent("Main.sqlite")
    }

    init() {
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription(url: Self.localPersistentStoreURL())

        if description.url == nil {
            description.url = Self.localPersistentStoreURL()
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

//        let keyValueStore = DimeDefaults.shared
//
//        if keyValueStore.object(forKey: "icloud_sync") == nil {
//            keyValueStore.set(true, forKey: "icloud_sync")
//        }
//
//        if !keyValueStore.bool(forKey: "icloud_sync") {
//            description.cloudKitContainerOptions = nil
//        } else {
//            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.sofitucci.dime")
//        }

        // iCloud/CloudKit is disabled for free personal-team builds.

        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { description, error in

            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo) for \(description)")
            }

            self.container.viewContext.automaticallyMergesChangesFromParent = true
        }

//        #if DEBUG
//            do {
//                // Use the container to initialize the development schema.
//                try container.initializeCloudKitSchema(options: [])
//            } catch {
//                // Handle any errors.
//            }
//        #endif
////        do {
////            try container.initializeCloudKitSchema()
////        } catch {
////            print(error)
////        }
    }

    // internal variables

    var tipCounter: Int {
        get {
            UserDefaults.standard.integer(forKey: "tipCounter")
        }

        set {
            UserDefaults.standard.set(newValue, forKey: "tipCounter")
        }
    }

    var addedTransaction: Bool {
        get {
            DimeDefaults.shared.bool(forKey: "newTransactionAdded")
        }

        set {
            DimeDefaults.shared.set(newValue, forKey: "newTransactionAdded")
        }
    }

    // adding or deleting

    func deleteAll() {
        let fetchRequest1: NSFetchRequest<NSFetchRequestResult> = Transaction.fetchRequest()
        let batchDeleteRequest1 = NSBatchDeleteRequest(fetchRequest: fetchRequest1)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest1)

        let fetchRequest2: NSFetchRequest<NSFetchRequestResult> = Category.fetchRequest()
        let batchDeleteRequest2 = NSBatchDeleteRequest(fetchRequest: fetchRequest2)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest2)

        let fetchRequest3: NSFetchRequest<NSFetchRequestResult> = Budget.fetchRequest()
        let batchDeleteRequest3 = NSBatchDeleteRequest(fetchRequest: fetchRequest3)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest3)

        let fetchRequest4: NSFetchRequest<NSFetchRequestResult> = MainBudget.fetchRequest()
        let batchDeleteRequest4 = NSBatchDeleteRequest(fetchRequest: fetchRequest4)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest4)
    }

    func save() {
        if container.viewContext.hasChanges {
            try? container.viewContext.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func updateRecurringTransaction(transaction: Transaction) {
        if transaction.nextTransactionDate < Calendar.current.startOfDay(for: Date.now) {
            var holdingDate = transaction.nextTransactionDate

            while holdingDate <= Calendar.current.startOfDay(for: Date.now) {
                let newTransaction = Transaction(context: container.viewContext)
                newTransaction.note = transaction.wrappedNote
                newTransaction.category = transaction.category
                newTransaction.amount = transaction.wrappedAmount
                newTransaction.date = holdingDate
                newTransaction.id = UUID()
                newTransaction.income = transaction.income
                newTransaction.day = holdingDate

                let calendar = Calendar(identifier: .gregorian)

                let dateComponents = calendar.dateComponents([.month, .year], from: holdingDate)

                newTransaction.month = calendar.date(from: dateComponents)!

                newTransaction.onceRecurring = true

                var newDate: Date?

                if transaction.recurringType == 1 {
                    newDate = Calendar.current.date(byAdding: .day, value: Int(transaction.recurringCoefficient), to: holdingDate)!
                } else if transaction.recurringType == 2 {
                    newDate = Calendar.current.date(byAdding: .day, value: Int(transaction.recurringCoefficient * 7), to: holdingDate)!
                } else if transaction.recurringType == 3 {
                    newDate = Calendar.current.date(byAdding: .month, value: Int(transaction.recurringCoefficient), to: holdingDate)!
                }

                if newDate! > Calendar.current.startOfDay(for: Date.now) {
                    newTransaction.recurringType = transaction.recurringType
                    newTransaction.recurringCoefficient = transaction.recurringCoefficient
                } else {
                    newTransaction.recurringType = 0
                }

                holdingDate = newDate!
            }

            transaction.recurringType = 0

            save()

        } else if Calendar.current.isDateInToday(transaction.nextTransactionDate) {
            let newTransaction = Transaction(context: container.viewContext)
            newTransaction.note = transaction.wrappedNote
            newTransaction.category = transaction.category
            newTransaction.amount = transaction.wrappedAmount
            newTransaction.date = transaction.nextTransactionDate
            newTransaction.id = UUID()
            newTransaction.income = transaction.income
            newTransaction.day = transaction.nextTransactionDate

            let calendar = Calendar(identifier: .gregorian)

            let dateComponents = calendar.dateComponents([.month, .year], from: transaction.nextTransactionDate)

            newTransaction.month = calendar.date(from: dateComponents)!

            newTransaction.onceRecurring = true
            newTransaction.recurringType = transaction.recurringType
            newTransaction.recurringCoefficient = transaction.recurringCoefficient

            transaction.recurringType = 0

            save()
        }
    }

    func updateRecurringTransactions() {
        let recurringTransactions = results(for: fetchRequestForRecurringTransactions())

        recurringTransactions.forEach { transaction in
            updateRecurringTransaction(transaction: transaction)
        }
    }

    func updateBudgetDates() {
        let budgets = results(for: fetchRequestForBudgets())
        let mainBudget = results(for: fetchRequestForMainBudget())

        budgets.forEach { budget in
            while budget.endDate <= Date.now {
                budget.startDate = budget.endDate
            }
        }

        mainBudget.forEach { budget in
            while budget.endDate <= Date.now {
                budget.startDate = budget.endDate
            }
        }

        save()
    }

    func newTransaction(note: String, category: Category?, income: Bool, amount: Double, date: Date, repeatType: Int, repeatCoefficient: Int, delay _: Bool) -> Transaction {
        let transaction = Transaction(context: container.viewContext)

        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income

        if let unwrappedCategory = category {
            transaction.category = unwrappedCategory
        }

        transaction.amount = amount
        transaction.date = date
        transaction.id = UUID()
        let storedCurrency = DimeDefaults.shared.string(forKey: "currency") ?? Locale.current.currencyCode ?? "UYU"
        applyManualUSDEquivalent(to: transaction, amount: amount, currencyCode: storedCurrency, date: date)

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            updateRecurringTransaction(transaction: transaction)
        }

        save()

        return transaction
    }

    func newTemplateTransaction(order: Int) {
        if let match = getTemplateTransaction(order: order) {
            if let unwrappedCategory = match.category {
                _ = newTransaction(note: match.note ?? "", category: unwrappedCategory, income: match.income, amount: match.amount, date: Date.now, repeatType: Int(match.recurringType), repeatCoefficient: Int(match.recurringCoefficient), delay: false)

                addedTransaction = true
            }
        }
    }

    // fetching

    func fetchRequestForRecurringTransactions() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0)
        return itemRequest
    }

    func getTemplateTransaction(order: Int) -> TemplateTransaction? {
        let itemRequest: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()

        itemRequest.predicate = NSPredicate(format: "order == %d", order)

        let results = results(for: itemRequest)

        if results.count > 1 {
            let output = results.first

            for i in 1 ..< results.count {
                container.viewContext.delete(results[i])
            }

            save()

            return output
        } else {
            return results.first
        }
    }

    func getAllTemplateTransactions() -> [TemplateTransaction] {
        let itemRequest: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()

        return results(for: itemRequest)
    }

    func fetchRequestForRecentTransactions(type: TimePeriod) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextDay as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: thisWeek)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextWeek as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextMonth as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!
            let nextYear = calendar.date(byAdding: .year, value: 1, to: thisYear)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextYear as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        }
    }

    func fetchRequestForExport() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return itemRequest
    }

    func fetchRequestForCategoriesMigration(income: Bool? = nil) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]

        if let unwrappedIncome = income {
            itemRequest.predicate = NSPredicate(format: "income = %d", unwrappedIncome)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForCategories(income: Bool) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        itemRequest.predicate = NSPredicate(format: "income = %d", income)
        return itemRequest
    }

    func getAllCategories(income: Bool) -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        request.predicate = NSPredicate(format: "income = %d", income)

        return results(for: request)
    }

    func getSuggestedNotes(searchQuery: String, category: Category?, income: Bool) -> [Transaction] {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]

        let beginPredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [beginPredicate, containPredicate])

        let incomePredicate = NSPredicate(format: "income = %d", income)

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, categoryPredicate, incomePredicate])

            itemRequest.predicate = andPredicate
        } else {
            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, incomePredicate])
            itemRequest.predicate = andPredicate
        }

        let transactions = results(for: itemRequest)

        var seen = [Transaction]()
        let filtered = transactions.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
//
//        let notes = transactions.map { $0.wrappedNote }
//
//        return Array(Set(notes))
    }

    @available(iOS 16, *)
    func findCategory(withId id: UUID) throws -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundCategory = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundCategory
        } catch {
            throw CustomError.notFound
        }
    }

    func getAllBudgets() -> [Budget] {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]
        return results(for: request)
    }

    @available(iOS 16, *)
    func findBudget(withId id: UUID) throws -> Budget {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundBudget = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundBudget
        } catch {
            throw CustomError.notFound
        }
    }

    func categoryCheck(name: String, emoji: String, income: Bool) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if income {
            let fetchRequest = fetchRequestForCategories(income: true)
            let incomeCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            let expenseCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func categoryCheckEdit(name: String, emoji: String, toEdit: Category) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if toEdit.income {
            let fetchRequest = fetchRequestForCategories(income: true)
            var incomeCategories = results(for: fetchRequest)

            if let position = incomeCategories.firstIndex(of: toEdit) {
                incomeCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            var expenseCategories = results(for: fetchRequest)

            if let position = expenseCategories.firstIndex(of: toEdit) {
                expenseCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func fetchRequestForBudgets() -> NSFetchRequest<Budget> {
        let itemRequest: NSFetchRequest<Budget> = Budget.fetchRequest()

        return itemRequest
    }

    func fetchRequestForMainBudget() -> NSFetchRequest<MainBudget> {
        let itemRequest: NSFetchRequest<MainBudget> = MainBudget.fetchRequest()

        return itemRequest
    }

    func fetchRequestForLogView(type: Int, optionalIncome: Bool?, categoryFilters: [Category] = []) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let dateCapPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        // all time
        if type == 5 {
            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        } else {
            let startPredicate: NSPredicate

            if type == 1 {
                let today = calendar.startOfDay(for: Date.now)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            } else if type == 2 {
                let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)
                let thisWeek = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            } else if type == 3 {
                let startOfMonth = DimeDefaults.shared.integer(forKey: "firstDayOfMonth")

                let thisMonth = getStartOfMonth(startDay: startOfMonth)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            } else {
                let dateComponents = calendar.dateComponents([.year], from: Date.now)
                let thisYear = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            }

            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        }

    }

    func getShortcutInsights(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [Category]) -> Double {
        let fetchRequest = fetchRequestForLogView(type: timeframe, optionalIncome: optionalIncome, categoryFilters: categories)
        let allTransactions = results(for: fetchRequest)

        if type == 1 {
            var total = 0.0

            allTransactions.forEach { transaction in
                if transaction.income {
                    total += transaction.amount
                } else {
                    total -= transaction.amount
                }
            }

            return total
        } else {
            var total = 0.0

            allTransactions.forEach { transaction in
                total += transaction.amount
            }

            return total
        }
    }

    func getLogViewTotalSpent(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: false)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func getLogViewTotalIncome(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: true)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func getLogViewTotalNet(type: Int) -> (value: Double, positive: Bool) {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: nil)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            if transaction.income {
                total += transaction.amount
            } else {
                total -= transaction.amount
            }
        }

        if total >= 0 {
            return (total, true)
        } else {
            return (abs(total), false)
        }
    }

    private func latestBHUUSDToUYUTransaction() -> Transaction? {
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.fetchLimit = 1
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(Transaction.exchangeRateDate), ascending: false),
            NSSortDescriptor(key: #keyPath(Transaction.date), ascending: false)
        ]

        let ratePredicate = NSPredicate(format: "%K > 0", #keyPath(Transaction.exchangeRate))
        let sourcePredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.exchangeRateSource), "BHU")
        let usdToUYUPredicate = NSCompoundPredicate(type: .and, subpredicates: [
            NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.originalCurrency), "USD"),
            NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.convertedCurrency), "UYU")
        ])
        let uyuToUSDPredicate = NSCompoundPredicate(type: .and, subpredicates: [
            NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.originalCurrency), "UYU"),
            NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.convertedCurrency), "USD")
        ])
        let currencyPairPredicate = NSCompoundPredicate(type: .or, subpredicates: [usdToUYUPredicate, uyuToUSDPredicate])

        fetchRequest.predicate = NSCompoundPredicate(type: .and, subpredicates: [ratePredicate, sourcePredicate, currencyPairPredicate])

        return results(for: fetchRequest).first
    }

    func getLatestBHUUSDToUYURate() -> Double? {
        latestBHUUSDToUYUTransaction()?.exchangeRate
    }

    func manualPrimaryAmount(for amount: Double, entryCurrencyCode: String?, primaryCurrencyCode: String?) -> Double? {
        guard amount > 0, amount.isFinite,
              let entryCurrency = normalizedCurrencyCode(entryCurrencyCode),
              let primaryCurrency = normalizedCurrencyCode(primaryCurrencyCode) else {
            return nil
        }

        if entryCurrency == primaryCurrency {
            return amount
        }

        guard let rate = getLatestBHUUSDToUYURate(), rate > 0, rate.isFinite else {
            return nil
        }

        if entryCurrency == "USD", primaryCurrency == "UYU" {
            return amount * rate
        }

        if entryCurrency == "UYU", primaryCurrency == "USD" {
            return amount / rate
        }

        return nil
    }

    @discardableResult
    func applyManualCurrencyEntry(to transaction: Transaction, enteredAmount: Double, entryCurrencyCode: String?, primaryCurrencyCode: String?, date: Date) -> Bool {
        guard let primaryAmount = manualPrimaryAmount(for: enteredAmount, entryCurrencyCode: entryCurrencyCode, primaryCurrencyCode: primaryCurrencyCode),
              let entryCurrency = normalizedCurrencyCode(entryCurrencyCode),
              let primaryCurrency = normalizedCurrencyCode(primaryCurrencyCode) else {
            return false
        }

        transaction.amount = primaryAmount
        clearManualCurrencyMetadata(for: transaction)

        if entryCurrency == primaryCurrency {
            applyManualUSDEquivalent(to: transaction, amount: enteredAmount, currencyCode: primaryCurrency, date: date)
            return true
        }

        guard let rateTransaction = latestBHUUSDToUYUTransaction() else {
            return false
        }

        let rate = rateTransaction.exchangeRate
        guard rate > 0, rate.isFinite else {
            return false
        }

        transaction.originalAmount = enteredAmount
        transaction.originalCurrency = entryCurrency
        transaction.convertedAmount = primaryAmount
        transaction.convertedCurrency = primaryCurrency
        transaction.exchangeRate = rate
        transaction.exchangeRateDate = rateTransaction.exchangeRateDate ?? date
        transaction.exchangeRateSource = "Manual entry BHU estimate"
        return true
    }

    func applyManualUSDEquivalent(to transaction: Transaction, amount: Double, currencyCode: String?, date: Date) {
        guard amount > 0, amount.isFinite else {
            return
        }

        guard let primaryCurrency = normalizedCurrencyCode(currencyCode), primaryCurrency == "UYU" else {
            return
        }

        guard let rateTransaction = latestBHUUSDToUYUTransaction() else {
            return
        }

        let rate = rateTransaction.exchangeRate
        guard rate > 0, rate.isFinite else {
            return
        }

        transaction.originalAmount = amount
        transaction.originalCurrency = primaryCurrency
        transaction.convertedAmount = amount / rate
        transaction.convertedCurrency = "USD"
        transaction.exchangeRate = rate
        transaction.exchangeRateDate = rateTransaction.exchangeRateDate ?? date
        transaction.exchangeRateSource = "Manual entry BHU estimate"
    }

    private func clearManualCurrencyMetadata(for transaction: Transaction) {
        transaction.originalAmount = 0
        transaction.originalCurrency = nil
        transaction.convertedAmount = 0
        transaction.convertedCurrency = nil
        transaction.exchangeRate = 0
        transaction.exchangeRateDate = nil
        transaction.exchangeRateSource = nil
    }

    private func normalizedCurrencyCode(_ rawValue: String?) -> String? {
        guard let currency = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !currency.isEmpty else {
            return nil
        }

        return currency
    }

    func getLineGraphDataNet(type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: nil)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func getLineGraphData(income: Bool, type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: income)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate > lastWeek {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)
            totalForDay = 0

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > lastMonth {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let thisMonthLastYear = calendar.date(byAdding: .year, value: -1, to: thisMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > thisMonthLastYear {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                            let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func getBudgetLeftover(budget: Budget? = nil, overallBudget: MainBudget? = nil) -> Double {
        let itemRequest: NSFetchRequest<Transaction>
        let budgetAmount: Double

        if let unwrappedOverallBudget = overallBudget {
            itemRequest = fetchRequestForMainBudgetTransactions(budget: unwrappedOverallBudget)
            budgetAmount = unwrappedOverallBudget.amount
        } else if let unwrappedBudget = budget {
            itemRequest = fetchRequestForBudgetTransactions(budget: unwrappedBudget)
            budgetAmount = unwrappedBudget.amount
        } else {
            itemRequest = Transaction.fetchRequest()
            budgetAmount = 0
        }

        let transactions = results(for: itemRequest)

        var totalSpent = 0.0

        transactions.forEach { transaction in
            totalSpent += transaction.wrappedAmount
        }

        return budgetAmount - totalSpent
    }

    func fetchRequestForMainBudgetTransactions(budget: MainBudget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), budget.startDate! as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate])

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func fetchRequestForBudgetTransactions(budget: Budget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), budget.startDate! as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), budget.category!)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, categoryPredicate, incomePredicate])

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func fetchRequestForLineGraph(optionalIncome: Bool?) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]

        if let income = optionalIncome {
            itemRequest.predicate = NSPredicate(format: "income = %d", income)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForLogViewCategoryFilter(income: Bool) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "income = %d", income)
        return itemRequest
    }

    func getInsights(type: Int, date: Date, income: Bool) -> (amount: Double, maximum: Double, average: Double, numberOfDays: Int, dates: [Date], dateDictionary: [Date: Double]) {
        let currentItemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date, income: income)
        let currentTransactions = results(for: currentItemRequest)

        var iterativeDate = date

        if type == 1 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            // calendar initialization
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
            calendar.minimumDaysInFirstWeek = 4

            var dictionary = [Date: Double]()
            var totalForWeek = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var weekAverage = 0.0

            for _ in 1 ... 7 {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForWeek += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let currentWeek = calendar.date(from: dateComponents)!

            if currentWeek == date {
//                let fromDate = Calendar.current.startOfDay(for: currentWeek)
//                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numberOfDays = Calendar.current.dateComponents([.day], from: currentWeek, to: Date.now)

                weekAverage = totalForWeek / Double((numberOfDays.day! + 1))
            } else {
                weekAverage = totalForWeek / 7
            }

            return (totalForWeek, maximum, weekAverage, numberOfDays, dates, dictionary)
        } else if type == 2 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)
            let range = calendar.range(of: .day, in: .month, for: iterativeDate)!

            var dictionary = [Date: Double]()
            var totalForMonth = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... range.count {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForMonth += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                monthAverage = totalForMonth / Double((numDays.day! + 1))
            } else {
                monthAverage = totalForMonth / Double(range.count)
            }

            return (totalForMonth, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else if type == 3 {
            // trackin dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)

            var dictionary = [Date: Double]()
            var totalForYear = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... 12 {
                nextDate = calendar.date(byAdding: .month, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForYear += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let currentYear = calendar.date(from: dateComponents)!

            if currentYear == date {
                let fromDate = Calendar.current.startOfDay(for: currentYear)
                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numDays = Calendar.current.dateComponents([.month], from: fromDate, to: toDate)

                monthAverage = totalForYear / Double((numDays.month! + 1))
            } else {
                monthAverage = totalForYear / 12
            }

            return (totalForYear, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else {
            return (0, 0, 0, 0, [Date](), [Date: Double]())
        }
    }

    func fetchRequestForInsights(type: Int, date: Date, income: Bool? = nil) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)

        let endPredicate: NSPredicate

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

//            let endOfPeriod = calendar.date(byAdding: .day, value: -1, to: next) ?? Date.now
//
            if next > Date.now {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
//
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
//            } else {
//
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate: NSCompoundPredicate

        if let unwrappedIncome = income {
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedIncome)

            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, endPredicate])
        } else {
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])
        }

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func getInsightsSummary(type: Int, date: Date) -> (spent: Double, income: Double, net: Double, positive: Bool, average: Double) {
        let itemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date)
        let currentTransactions = results(for: itemRequest)

        var holdingSpent = 0.0
        var holdingIncome = 0.0

        currentTransactions.forEach { transaction in
            if transaction.income {
                holdingIncome += transaction.amount
            } else {
                holdingSpent += transaction.amount
            }
        }

        let net = holdingIncome - holdingSpent
        let absoluteNet: Double
        let positive: Bool

        if net < 0 {
            absoluteNet = abs(net)
            positive = false
        } else {
            absoluteNet = net
            positive = true
        }

        let calendar = Calendar.current

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numberOfDays.day! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 7)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            } else {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: next)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            }
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
//            } else {
//
//                let range = calendar.range(of: .day, in: .month, for: date)!
//                let numDays = range.count
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays))
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                let numDays = Calendar.current.dateComponents([.month], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.month! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 12)
            }
        }
    }

    func fetchRequestForWidgetInsights(type: InsightsTimePeriod, income: Bool) -> (fetchRequest: NSFetchRequest<Transaction>, date: Date) {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let incomePredicate = NSPredicate(format: "income = %d", income)

        let startDate: Date
        let startPredicate: NSPredicate

        switch type {
        case .unknown:
            startDate = Date.now
            startPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .month:
            let startOfMonth = DimeDefaults.shared.integer(forKey: "firstDayOfMonth")

            startDate = getStartOfMonth(startDay: startOfMonth)

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        }

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate])

        itemRequest.predicate = andPredicate
        itemRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
        ]

        return (itemRequest, startDate)
    }

    func fetchRequestForRecentTransactionsWithCount(type: TimePeriod, count: Int) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = DimeDefaults.shared.integer(forKey: "firstWeekday")
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        }
    }

    func fetchRequestForMainBudgetWidget() -> (found: Bool, totalSpent: Double, budgetAmount: Double, percentage: Double, type: Int, startDate: Date) {
        let holding = results(for: fetchRequestForMainBudget())

        if let budget = holding.first {
            let itemRequest = fetchRequestForMainBudgetTransactions(budget: budget)
//
            let transactions = results(for: itemRequest)

            var holdingTotal = 0.0
            transactions.forEach { transaction in
                holdingTotal += transaction.wrappedAmount
            }

            let percentageOfDays: Double

            let calendar = Calendar.current

            if budget.type == 1 {
                let components = calendar.dateComponents([.minute], from: budget.startDate!, to: Date.now)
                percentageOfDays = Double(components.minute!) / 1440
            } else {
                let components1 = calendar.dateComponents([.day], from: budget.startDate!, to: budget.endDate)
                let numberOfDays = components1.day!

                let components2 = calendar.dateComponents([.day], from: budget.startDate!, to: Date.now)
                let numberOfDaysPast = components2.day!

                percentageOfDays = Double(numberOfDaysPast) / Double(numberOfDays)
            }

            return (true, holdingTotal, budget.amount, percentageOfDays, Int(budget.type), budget.startDate!)

        } else {
            return (false, 0, 0, 0, 0, Date.now)
        }
    }

    func results<T: NSManagedObject>(for fetchRequest: NSFetchRequest<T>) -> [T] {
        return (try? container.viewContext.fetch(fetchRequest)) ?? []
    }
}

struct ExternalTransactionImportBatch: Decodable {
    let version: Int?
    let source: String?
    let transactions: [ExternalTransactionImportItem]
}

struct ExternalTransactionImportItem: Decodable {
    let externalId: String
    let sourceLabel: String?
    let date: String
    let amount: Double
    let type: String?
    let income: Bool?
    let categoryId: String?
    let category: String?
    let note: String?
    let repeatType: Int?
    let repeatCoefficient: Int?
    let currency: String?
    let convertedAmount: Double?
    let convertedCurrency: String?
    let exchangeRate: Double?
    let exchangeRateDate: String?
    let exchangeRateSource: String?
}

struct ExternalTransactionImportResult {
    let created: Int
    let updated: Int
    let skipped: Int
    let failures: [String]
    let handledExternalIds: [String]

    var message: String {
        var lines = [String]()
        lines.append("Created \(created) transaction\(created == 1 ? "" : "s").")

        if updated > 0 {
            lines.append("Updated \(updated) existing transaction\(updated == 1 ? "" : "s").")
        }

        if skipped > 0 {
            lines.append("Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s").")
        }

        if !failures.isEmpty {
            lines.append("Failed \(failures.count) row\(failures.count == 1 ? "" : "s"):")
            lines.append(contentsOf: failures.prefix(5))

            if failures.count > 5 {
                lines.append("…and \(failures.count - 5) more.")
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct ExternalTransactionImportPreview {
    let total: Int
    let ready: Int
    let updated: Int
    let skipped: Int
    let failures: [String]

    var hasActionableImports: Bool {
        ready > 0 || updated > 0
    }

    var message: String {
        var lines = [String]()
        lines.append("This link wants to import \(total) transaction\(total == 1 ? "" : "s").")
        lines.append("Ready: \(ready).")

        if updated > 0 {
            lines.append("Will update existing: \(updated).")
        }

        if skipped > 0 {
            lines.append("Already imported: \(skipped).")
        }

        if !failures.isEmpty {
            lines.append("Cannot import \(failures.count) row\(failures.count == 1 ? "" : "s"):")
            lines.append(contentsOf: failures.prefix(5))

            if failures.count > 5 {
                lines.append("…and \(failures.count - 5) more.")
            }
        }

        lines.append("Only tap Import if this came from Sofia's Hermes chat.")
        return lines.joined(separator: "\n")
    }
}

struct ExternalTransactionImporter {
    private static let importedIdsKey = "externalTransactionImportIds"
    private static let maxTransactionsPerBatch = 50
    private static let trustedSource = "hermes"
    private static let supportedHosts: Set<String> = ["import", "importTransactions"]

    private struct PreparedImportItem {
        let externalId: String
        let sourceLabel: String?
        let note: String
        let category: Category
        let income: Bool
        let amount: Double
        let date: Date
        let originalAmount: Double?
        let originalCurrency: String?
        let convertedAmount: Double?
        let convertedCurrency: String?
        let exchangeRate: Double?
        let exchangeRateDate: Date?
        let exchangeRateSource: String?
    }

    private enum ImportError: LocalizedError {
        case unsupportedURL
        case missingPayload
        case invalidPayload
        case unsupportedVersion(Int?)
        case untrustedSource(String?)
        case tooManyTransactions(Int)
        case missingExternalId
        case invalidAmount(Double)
        case invalidType(String)
        case missingCategory
        case categoryNotFound(String)
        case ambiguousCategory(String)
        case invalidDate(String)
        case recurringImportsNotAllowed

        var errorDescription: String? {
            switch self {
            case .unsupportedURL:
                return "This Dime link is not an external transaction import."
            case .missingPayload:
                return "The import link is missing a payload."
            case .invalidPayload:
                return "The import payload could not be decoded."
            case let .unsupportedVersion(version):
                return "Unsupported import version: \(version.map(String.init) ?? "missing")."
            case let .untrustedSource(source):
                return "Unsupported import source: \(source ?? "missing")."
            case let .tooManyTransactions(count):
                return "Too many transactions in one import: \(count)."
            case .missingExternalId:
                return "Missing externalId."
            case let .invalidAmount(amount):
                return "Invalid amount: \(amount)."
            case let .invalidType(type):
                return "Invalid transaction type: \(type)."
            case .missingCategory:
                return "Missing categoryId or category."
            case let .categoryNotFound(category):
                return "No matching Dime category: \(category)."
            case let .ambiguousCategory(category):
                return "More than one Dime category matches: \(category). Rename one category or import with categoryId."
            case let .invalidDate(date):
                return "Invalid date: \(date)."
            case .recurringImportsNotAllowed:
                return "Recurring imports are not allowed from external links."
            }
        }
    }

    static func canHandle(_ url: URL) -> Bool {
        guard url.scheme == "dimeapp", let host = url.host else {
            return false
        }

        return supportedHosts.contains(host)
    }

    static func batch(from url: URL) throws -> ExternalTransactionImportBatch {
        guard canHandle(url) else {
            throw ImportError.unsupportedURL
        }

        return try decodeBatch(from: url)
    }

    static func previewBatch(from url: URL, dataController: DataController) throws -> ExternalTransactionImportPreview {
        let batch = try batch(from: url)
        return try previewBatch(batch, dataController: dataController)
    }

    static func previewBatch(_ batch: ExternalTransactionImportBatch, dataController: DataController) throws -> ExternalTransactionImportPreview {
        try validateBatchEnvelope(batch)

        let importedIds = importedExternalIds()
        var ready = 0
        var updated = 0
        var skipped = 0
        var failures = [String]()

        for (index, item) in batch.transactions.enumerated() {
            let rowLabel = label(for: item, index: index)

            do {
                let prepared = try prepare(item, dataController: dataController)

                if importedIds.contains(prepared.externalId) {
                    skipped += 1
                    continue
                }

                if matchingImportedTransaction(for: prepared, item: item, dataController: dataController) != nil {
                    updated += 1
                    continue
                }

                ready += 1
            } catch {
                failures.append("\(rowLabel): \(error.localizedDescription)")
            }
        }

        return ExternalTransactionImportPreview(total: batch.transactions.count, ready: ready, updated: updated, skipped: skipped, failures: failures)
    }

    static func importBatch(from url: URL, dataController: DataController) throws -> ExternalTransactionImportResult {
        let batch = try batch(from: url)
        return try importBatch(batch, dataController: dataController)
    }

    static func importBatch(_ batch: ExternalTransactionImportBatch, dataController: DataController) throws -> ExternalTransactionImportResult {
        try validateBatchEnvelope(batch)

        var importedIds = importedExternalIds()
        var handledExternalIds = Set<String>()
        var created = 0
        var updated = 0
        var skipped = 0
        var failures = [String]()

        for (index, item) in batch.transactions.enumerated() {
            let rowLabel = label(for: item, index: index)

            do {
                let prepared = try prepare(item, dataController: dataController)

                if importedIds.contains(prepared.externalId) {
                    handledExternalIds.insert(prepared.externalId)
                    skipped += 1
                    continue
                }

                if let existingTransaction = matchingImportedTransaction(for: prepared, item: item, dataController: dataController) {
                    apply(prepared, to: existingTransaction)
                    dataController.save()
                    importedIds.insert(prepared.externalId)
                    handledExternalIds.insert(prepared.externalId)
                    updated += 1
                    continue
                }

                let transaction = dataController.newTransaction(
                    note: prepared.note,
                    category: prepared.category,
                    income: prepared.income,
                    amount: prepared.amount,
                    date: prepared.date,
                    repeatType: 0,
                    repeatCoefficient: 1,
                    delay: false
                )

                transaction.externalImportId = prepared.externalId
                transaction.externalSource = prepared.sourceLabel
                applyCurrencyMetadata(prepared, to: transaction)
                dataController.save()

                importedIds.insert(prepared.externalId)
                handledExternalIds.insert(prepared.externalId)
                created += 1
            } catch {
                failures.append("\(rowLabel): \(error.localizedDescription)")
            }
        }

        importDefaults().set(Array(importedIds).sorted(), forKey: importedIdsKey)

        return ExternalTransactionImportResult(
            created: created,
            updated: updated,
            skipped: skipped,
            failures: failures,
            handledExternalIds: Array(handledExternalIds).sorted()
        )
    }

    private static func validateBatchEnvelope(_ batch: ExternalTransactionImportBatch) throws {
        guard batch.version == 1 else {
            throw ImportError.unsupportedVersion(batch.version)
        }

        let source = batch.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard source == trustedSource else {
            throw ImportError.untrustedSource(batch.source)
        }

        guard batch.transactions.count <= maxTransactionsPerBatch else {
            throw ImportError.tooManyTransactions(batch.transactions.count)
        }
    }

    private static func label(for item: ExternalTransactionImportItem, index: Int) -> String {
        let externalId = item.externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        return externalId.isEmpty ? "Row \(index + 1)" : externalId
    }

    private static func importedExternalIds() -> Set<String> {
        return Set(importDefaults().stringArray(forKey: importedIdsKey) ?? [])
    }

    private static func importDefaults() -> UserDefaults {
        return DimeDefaults.shared
    }

    private static func matchingImportedTransaction(for prepared: PreparedImportItem, item: ExternalTransactionImportItem, dataController: DataController) -> Transaction? {
        let context = dataController.container.viewContext
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let lowerBound = prepared.date.addingTimeInterval(-1)
        let upperBound = prepared.date.addingTimeInterval(1)
        request.predicate = NSCompoundPredicate(type: .and, subpredicates: [
            NSPredicate(format: "income = %d", prepared.income),
            NSPredicate(format: "%K == %@", #keyPath(Transaction.category), prepared.category),
            NSPredicate(format: "%K >= %@ AND %K <= %@", #keyPath(Transaction.date), lowerBound as CVarArg, #keyPath(Transaction.date), upperBound as CVarArg)
        ])

        guard let candidates = try? context.fetch(request), !candidates.isEmpty else {
            return nil
        }

        let expectedNote = normalizedTransactionNote(importNote(prepared.note, category: prepared.category))
        let candidateAmounts = matchingAmounts(for: item, prepared: prepared)
        let noteAndAmountMatches = candidates.filter { transaction in
            normalizedTransactionNote(transaction.wrappedNote) == expectedNote
                && candidateAmounts.contains { amountsMatch(transaction.wrappedAmount, $0) }
        }

        if noteAndAmountMatches.count == 1 {
            return noteAndAmountMatches.first
        }

        let amountOnlyMatches = candidates.filter { transaction in
            candidateAmounts.contains { amountsMatch(transaction.wrappedAmount, $0) }
        }

        return amountOnlyMatches.count == 1 ? amountOnlyMatches.first : nil
    }

    private static func matchingAmounts(for item: ExternalTransactionImportItem, prepared: PreparedImportItem) -> [Double] {
        let rawAmounts = [item.amount, prepared.amount, prepared.originalAmount, prepared.convertedAmount]
        var amounts = [Double]()

        for rawAmount in rawAmounts {
            guard let amount = rawAmount, amount.isFinite else {
                continue
            }

            if !amounts.contains(where: { amountsMatch($0, amount) }) {
                amounts.append(amount)
            }
        }

        return amounts
    }

    private static func amountsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    private static func normalizedTransactionNote(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func importNote(_ note: String, category: Category) -> String {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return category.wrappedName
        }

        return note.trimmingCharacters(in: .whitespaces)
    }

    private static func apply(_ prepared: PreparedImportItem, to transaction: Transaction) {
        transaction.externalImportId = prepared.externalId
        transaction.externalSource = prepared.sourceLabel
        transaction.note = importNote(prepared.note, category: prepared.category)
        transaction.category = prepared.category
        transaction.income = prepared.income
        transaction.amount = prepared.amount
        transaction.date = prepared.date
        transaction.onceRecurring = false
        transaction.recurringType = 0
        transaction.recurringCoefficient = 1

        let calendar = Calendar(identifier: .gregorian)
        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: prepared.date) ?? Date.now
        let dateComponents = calendar.dateComponents([.month, .year], from: prepared.date)
        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        applyCurrencyMetadata(prepared, to: transaction)
    }

    private static func applyCurrencyMetadata(_ prepared: PreparedImportItem, to transaction: Transaction) {
        transaction.originalAmount = prepared.originalAmount ?? 0
        transaction.originalCurrency = prepared.originalCurrency
        transaction.convertedAmount = prepared.convertedAmount ?? 0
        transaction.convertedCurrency = prepared.convertedCurrency
        transaction.exchangeRate = prepared.exchangeRate ?? 0
        transaction.exchangeRateDate = prepared.exchangeRateDate
        transaction.exchangeRateSource = prepared.exchangeRateSource
    }

    private static func prepare(_ item: ExternalTransactionImportItem, dataController: DataController) throws -> PreparedImportItem {
        let externalId = item.externalId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !externalId.isEmpty else {
            throw ImportError.missingExternalId
        }

        guard item.amount > 0 else {
            throw ImportError.invalidAmount(item.amount)
        }

        if (item.repeatType ?? 0) != 0 || (item.repeatCoefficient ?? 1) != 1 {
            throw ImportError.recurringImportsNotAllowed
        }

        let income = try incomeFlag(for: item)
        let category = try findCategory(for: item, income: income, dataController: dataController)
        let date = try parseDate(item.date)
        let importDetails = importAmountDetails(for: item)

        return PreparedImportItem(
            externalId: externalId,
            sourceLabel: sourceLabel(for: item, externalId: externalId),
            note: item.note ?? "",
            category: category,
            income: income,
            amount: importDetails.amount,
            date: date,
            originalAmount: importDetails.originalAmount,
            originalCurrency: importDetails.originalCurrency,
            convertedAmount: importDetails.convertedAmount,
            convertedCurrency: importDetails.convertedCurrency,
            exchangeRate: importDetails.exchangeRate,
            exchangeRateDate: importDetails.exchangeRateDate,
            exchangeRateSource: importDetails.exchangeRateSource
        )
    }

    private static func sourceLabel(for item: ExternalTransactionImportItem, externalId: String) -> String? {
        if let explicitLabel = item.sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitLabel.isEmpty {
            return explicitLabel
        }

        return inferredSourceLabel(from: externalId)
    }

    private static func inferredSourceLabel(from externalId: String) -> String? {
        let parts = externalId.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count >= 3, parts[0].lowercased() == "hermes" else {
            return nil
        }

        let source = parts[1].lowercased()
        let account = parts[2].lowercased()

        switch source {
        case "itau":
            if account.contains("card") || account.contains("credit") {
                return "Itaú credit"
            }

            if account.contains("debit") {
                return "Itaú debit"
            }

            return "Itaú"
        case "wise":
            return "Wise"
        case "santander":
            return "Santander"
        case "splitwise":
            return "Splitwise"
        case "manual":
            return "Manual"
        default:
            return source.prefix(1).uppercased() + String(source.dropFirst())
        }
    }

    private static func importAmountDetails(for item: ExternalTransactionImportItem) -> (
        amount: Double,
        originalAmount: Double?,
        originalCurrency: String?,
        convertedAmount: Double?,
        convertedCurrency: String?,
        exchangeRate: Double?,
        exchangeRateDate: Date?,
        exchangeRateSource: String?
    ) {
        let sourceCurrency = normalizedCurrency(item.currency)
        let convertedCurrency = normalizedCurrency(item.convertedCurrency)
        let targetCurrency = appCurrencyCode()
        let convertedAmount = validPositiveAmount(item.convertedAmount)
        var selectedAmount = item.amount

        if let convertedAmount,
           let convertedCurrency,
           convertedCurrency == targetCurrency,
           sourceCurrency != targetCurrency {
            selectedAmount = convertedAmount
        }

        let rateDate = item.exchangeRateDate.flatMap { try? parseDate($0) }
        let sourceAmount = sourceCurrency == nil ? nil : item.amount

        return (
            amount: selectedAmount,
            originalAmount: sourceAmount,
            originalCurrency: sourceCurrency,
            convertedAmount: convertedAmount,
            convertedCurrency: convertedCurrency,
            exchangeRate: validPositiveAmount(item.exchangeRate),
            exchangeRateDate: rateDate,
            exchangeRateSource: item.exchangeRateSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func normalizedCurrency(_ rawValue: String?) -> String? {
        guard let currency = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !currency.isEmpty else {
            return nil
        }

        return currency
    }

    private static func validPositiveAmount(_ value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else {
            return nil
        }

        return value
    }

    private static func appCurrencyCode() -> String {
        let stored = DimeDefaults.shared.string(forKey: "currency")?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let stored, !stored.isEmpty {
            return stored
        }

        return Locale.current.currencyCode?.uppercased() ?? "UYU"
    }

    private static func decodeBatch(from url: URL) throws -> ExternalTransactionImportBatch {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let payload = components?.queryItems?.first(where: { $0.name == "payload" })?.value
        let json = components?.queryItems?.first(where: { $0.name == "json" })?.value
        let data: Data

        if let payload = payload {
            data = try decodeBase64URL(payload)
        } else if let json = json {
            data = Data(json.utf8)
        } else {
            throw ImportError.missingPayload
        }

        do {
            return try JSONDecoder().decode(ExternalTransactionImportBatch.self, from: data)
        } catch {
            throw ImportError.invalidPayload
        }
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4

        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }

        guard let data = Data(base64Encoded: base64) else {
            throw ImportError.invalidPayload
        }

        return data
    }

    private static func incomeFlag(for item: ExternalTransactionImportItem) throws -> Bool {
        let rawType = item.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let incomeFromType: Bool?

        switch rawType {
        case nil, "":
            incomeFromType = nil
        case "expense":
            incomeFromType = false
        case "income":
            incomeFromType = true
        default:
            throw ImportError.invalidType(rawType ?? "")
        }

        if let income = item.income {
            if let incomeFromType = incomeFromType, incomeFromType != income {
                throw ImportError.invalidType(rawType ?? "income mismatch")
            }

            return income
        }

        return incomeFromType ?? false
    }

    private static func findCategory(for item: ExternalTransactionImportItem, income: Bool, dataController: DataController) throws -> Category {
        let context = dataController.container.viewContext

        if let categoryId = item.categoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryId.isEmpty,
           let uuid = UUID(uuidString: categoryId) {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id = %@ AND income = %d", uuid as CVarArg, income)

            if let category = try? context.fetch(request).first {
                return category
            }

            throw ImportError.categoryNotFound(categoryId)
        }

        guard let categoryName = item.category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !categoryName.isEmpty else {
            throw ImportError.missingCategory
        }

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "income = %d", income)

        guard let categories = try? context.fetch(request) else {
            throw ImportError.categoryNotFound(categoryName)
        }

        let exactMatches = categories.filter { $0.wrappedName == categoryName }

        if exactMatches.count == 1, let category = exactMatches.first {
            return category
        }

        if exactMatches.count > 1 {
            throw ImportError.ambiguousCategory(categoryName)
        }

        let normalizedName = normalizedCategoryName(categoryName)
        let normalizedMatches = categories.filter { normalizedCategoryName($0.wrappedName) == normalizedName }

        if normalizedMatches.count == 1, let category = normalizedMatches.first {
            return category
        }

        if normalizedMatches.count > 1 {
            throw ImportError.ambiguousCategory(categoryName)
        }

        throw ImportError.categoryNotFound(categoryName)
    }

    private static func normalizedCategoryName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func parseDate(_ rawValue: String) throws -> Date {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractionalISOFormatter = ISO8601DateFormatter()
        fractionalISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractionalISOFormatter.date(from: trimmed) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = .current
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"

        if let date = dateOnlyFormatter.date(from: trimmed) {
            return date
        }

        throw ImportError.invalidDate(rawValue)
    }
}

struct HermesTransactionSyncClient {
    private static let syncURLKey = "hermesSyncURL"
    private static let infoPlistSyncURLKey = "HermesSyncURL"
    private static let configurationHost = "configureHermesSync"

    private struct SyncResponseEnvelope: Decodable {
        let batch: ExternalTransactionImportBatch?
        let importURL: String?
        let url: String?
    }

    private enum SyncError: LocalizedError {
        case missingEndpoint
        case invalidEndpoint(String)
        case insecureEndpoint
        case httpStatus(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingEndpoint:
                return "Hermes sync is not configured yet. Open a Hermes setup link first."
            case let .invalidEndpoint(value):
                return "Hermes sync endpoint is invalid: \(value)."
            case .insecureEndpoint:
                return "Hermes sync endpoint must use HTTPS."
            case let .httpStatus(statusCode):
                return "Hermes sync failed with status \(statusCode)."
            case .invalidResponse:
                return "Hermes sync returned data Dime could not read."
            }
        }
    }

    static func canHandleConfiguration(_ url: URL) -> Bool {
        return url.scheme == "dimeapp" && url.host == configurationHost
    }

    @discardableResult
    static func configure(from url: URL) throws -> URL {
        let syncURL = try endpoint(fromConfigurationURL: url)
        configure(endpoint: syncURL)
        return syncURL
    }

    static func endpoint(fromConfigurationURL url: URL) throws -> URL {
        guard canHandleConfiguration(url) else {
            throw SyncError.invalidEndpoint(url.absoluteString)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let rawURL = components?.queryItems?.first(where: { $0.name == "url" })?.value else {
            throw SyncError.missingEndpoint
        }

        return try validateEndpoint(rawURL)
    }

    static func configure(endpoint syncURL: URL) {
        syncDefaults().set(syncURL.absoluteString, forKey: syncURLKey)
    }

    static func fetchPendingBatch() async throws -> ExternalTransactionImportBatch {
        let syncURL = try configuredEndpoint()
        var request = URLRequest(url: syncURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        if httpResponse.statusCode == 204 {
            return ExternalTransactionImportBatch(version: 1, source: "hermes", transactions: [])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.httpStatus(httpResponse.statusCode)
        }

        return try decodeBatch(from: data)
    }

    static func acknowledgeImportedExternalIds(_ externalIds: [String]) async throws {
        let cleanedExternalIds = Array(Set(externalIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !cleanedExternalIds.isEmpty else {
            return
        }

        let importedURL = try importedEndpoint(from: configuredEndpoint())
        var request = URLRequest(url: importedURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["externalIds": cleanedExternalIds], options: [])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.httpStatus(httpResponse.statusCode)
        }
    }

    private static func configuredEndpoint() throws -> URL {
        if let storedURL = syncDefaults().string(forKey: syncURLKey), !storedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try validateEndpoint(storedURL)
        }

        if let bundledURL = Bundle.main.object(forInfoDictionaryKey: infoPlistSyncURLKey) as? String,
           !bundledURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try validateEndpoint(bundledURL)
        }

        throw SyncError.missingEndpoint
    }

    private static func validateEndpoint(_ rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            throw SyncError.invalidEndpoint(rawURL)
        }

        guard scheme.lowercased() == "https" else {
            throw SyncError.insecureEndpoint
        }

        return url
    }

    private static func importedEndpoint(from pendingURL: URL) throws -> URL {
        guard var components = URLComponents(url: pendingURL, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidEndpoint(pendingURL.absoluteString)
        }

        components.path = "/v1/dime/imported"
        guard let url = components.url else {
            throw SyncError.invalidEndpoint(pendingURL.absoluteString)
        }
        return url
    }

    private static func decodeBatch(from data: Data) throws -> ExternalTransactionImportBatch {
        let decoder = JSONDecoder()

        if let batch = try? decoder.decode(ExternalTransactionImportBatch.self, from: data) {
            return batch
        }

        if let envelope = try? decoder.decode(SyncResponseEnvelope.self, from: data) {
            if let batch = envelope.batch {
                return batch
            }

            if let rawURL = envelope.importURL ?? envelope.url,
               let importURL = URL(string: rawURL) {
                return try ExternalTransactionImporter.batch(from: importURL)
            }
        }

        throw SyncError.invalidResponse
    }

    private static func syncDefaults() -> UserDefaults {
        return DimeDefaults.shared
    }
}

public extension NSManagedObjectContext {
    func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}

struct LineGraphDataPoint: Equatable {
    let date: Date
    let amount: Double

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        return dateFormatter.string(from: date)
    }

    var monthString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "MMM yy"

        return dateFormatter.string(from: date)
    }

    var amountString: String {
        if abs(amount) < 1000 {
            return String(format: "%.2f", amount)
        } else {
            return String(format: "%.0f", amount)
        }
    }
}

func getStartOfMonth(startDay: Int) -> Date {
    let calendar = Calendar.current

    guard startDay > 0 && startDay <= calendar.maximumRange(of: .day)!.upperBound else {
        let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
        return calendar.date(from: dateComponents) ?? Date.now
    }

    let today = calendar.startOfDay(for: Date.now)
    let currentDay = calendar.component(.day, from: today)

    var startComponents = DateComponents()
    startComponents.month = currentDay >= startDay ? 0 : -1

    startComponents.day = startDay - currentDay

    return calendar.date(byAdding: startComponents, to: today) ?? Date.now
}

func calculateStartOfMonthPeriod(earliestDate: Date, startOfMonthDay: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: earliestDate)
    components.day = startOfMonthDay

    let startOfMonth = Calendar.current.date(from: components) ?? Date.now
    return (earliestDate < startOfMonth) ? (Calendar.current.date(byAdding: .month, value: -1, to: startOfMonth) ?? Date.now) : startOfMonth
}
