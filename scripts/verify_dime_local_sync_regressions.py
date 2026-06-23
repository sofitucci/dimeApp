#!/usr/bin/env python3
"""Regression checks for Sofia's local Dime/Hermes build.

These are intentionally source-level checks because the upstream project has no
XCTest target. They guard the failure modes Sofia hit on-device:
1. Personal-team/no-app-group builds must use a real local SQLite store URL.
2. Hermes imports must match existing categories robustly without inventing new ones.
3. Category add/edit sheets must leave enough room for the emoji keyboard.
4. Transaction row swipe-to-delete must not steal vertical scroll gestures.
5. Imported transactions should show a compact source indicator in the Log.
6. Manual entries must get the same USD-equivalent metadata that imports get.
"""
from __future__ import annotations

import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_CONTROLLER = ROOT / "app/dime/Data/DataController.swift"
LOG_VIEW = ROOT / "app/dime/Views/LogView.swift"
HOME_VIEW = ROOT / "app/dime/Views/HomeView.swift"
TRANSACTION_VIEW = ROOT / "app/dime/Views/TransactionView.swift"
NUMBER_PAD = ROOT / "app/dime/Components/Transactions/NumberPad.swift"
CATEGORY_VIEW = ROOT / "app/dime/Views/CategoryView.swift"
ENTITLEMENTS = ROOT / "app/dime/dime.entitlements"
INFO_PLIST = ROOT / "app/dime/Info.plist"
MODEL_DIR = ROOT / "app/dime/Data/MainModel.xcdatamodeld"
XCODE_PROJECT = ROOT / "app/dime.xcodeproj/project.pbxproj"


def active_swift(source: str) -> str:
    """Remove simple Swift line comments for checks that must ignore old code."""
    return "\n".join(line.split("//", 1)[0] for line in source.splitlines())


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    source = DATA_CONTROLLER.read_text()
    active = active_swift(source)

    with ENTITLEMENTS.open("rb") as f:
        entitlements = plistlib.load(f)
    with INFO_PLIST.open("rb") as f:
        info = plistlib.load(f)

    assert_true(
        "com.apple.security.application-groups" not in entitlements,
        "Personal-team build should not declare App Groups.",
    )
    assert_true(
        "com.apple.developer.icloud-container-identifiers" not in entitlements,
        "Personal-team build should not declare CloudKit entitlements.",
    )
    assert_true(
        "UIBackgroundModes" not in info or "remote-notification" not in info.get("UIBackgroundModes", []),
        "Personal-team build should not use remote-notification background mode.",
    )

    assert_true(
        re.search(r"static\s+let\s+shared\s*:\s*UserDefaults\s*=\s*\.standard", active) is not None,
        "DimeDefaults.shared must use standard UserDefaults when App Groups are disabled.",
    )
    assert_true(
        "UserDefaults(suiteName:" not in active,
        "Local build must not depend on app-group UserDefaults.",
    )

    assert_true(
        "private static func localPersistentStoreURL()" in active,
        "DataController must define an explicit local persistent-store URL.",
    )
    assert_true(
        "NSPersistentStoreDescription(url: Self.localPersistentStoreURL())" in active
        and re.search(
            r"if\s+description\.url\s*==\s*nil\s*\{\s*description\.url\s*=\s*Self\.localPersistentStoreURL\(\)",
            active,
            re.S,
        ) is not None,
        "DataController must preserve the default store URL and provide an explicit local SQLite fallback before loading stores.",
    )
    assert_true(
        "let description = NSPersistentStoreDescription()" not in active,
        "Do not replace NSPersistentContainer's default store description with a blank URL-less one.",
    )
    assert_true(
        "containerURL(forSecurityApplicationGroupIdentifier" not in active,
        "Local build must not put Core Data in an unavailable App Group container.",
    )
    assert_true(
        "NSPersistentCloudKitContainer(" not in active,
        "Local build should not use NSPersistentCloudKitContainer.",
    )
    assert_true(
        "cloudKitContainerOptions" not in active,
        "Local build should not enable CloudKit store options.",
    )
    assert_true(
        "description.shouldMigrateStoreAutomatically = true" in active
        and "description.shouldInferMappingModelAutomatically = true" in active,
        "Core Data model updates must use lightweight migration so installed apps update in place instead of acting like fresh installs.",
    )
    assert_true(
        (MODEL_DIR / "MainModel 2.xcdatamodel/contents").exists()
        and (MODEL_DIR / "MainModel 3.xcdatamodel/contents").exists()
        and (MODEL_DIR / "MainModel 4.xcdatamodel/contents").exists(),
        "Keep MainModel 2, 3, and 4 in the model bundle so existing stores can migrate.",
    )
    current_version = (MODEL_DIR / ".xccurrentversion").read_text()
    project_source = XCODE_PROJECT.read_text()
    assert_true(
        "MainModel 4.xcdatamodel" in current_version
        and "currentVersion = D6C0FFEE2E01010200F7F751 /* MainModel 4.xcdatamodel */;" in project_source,
        "MainModel 4 must be the current model version while preserving prior model versions for migration.",
    )
    main_model_4 = (MODEL_DIR / "MainModel 4.xcdatamodel/contents").read_text()
    assert_true(
        'attribute name="externalImportId"' in main_model_4
        and 'attribute name="externalSource"' in main_model_4,
        "Transaction model must persist the external import ID and human-readable source label.",
    )

    assert_true(
        "normalizedCategoryName" in active,
        "Hermes import should normalize category names for matching existing categories.",
    )
    assert_true(
        "ambiguousCategory" in active,
        "Normalized category matching must detect ambiguous existing category names.",
    )
    assert_true(
        "matchingImportedTransaction" in active
        and "Updated \\(updated) existing transaction" in active
        and "Will update existing" in active,
        "Hermes reimports must update legacy/untracked matching rows so metadata repairs can be applied once.",
    )
    duplicate_skip_before_update_checks = re.findall(
        r"if\s+importedIds\.contains\(prepared\.externalId\)\s*\{.*?skipped\s*\+=\s*1.*?continue\s*\}\s*if\s+(?:let\s+existingTransaction\s*=\s*)?matchingImportedTransaction",
        active,
        re.S,
    )
    assert_true(
        len(duplicate_skip_before_update_checks) >= 2,
        "Hermes imports must skip already-imported external IDs before matching/updating existing transactions, so refreshes do not overwrite rows after import.",
    )
    assert_true(
        "matchingAmounts(for item" in active
        and "prepared.originalAmount" in active
        and "prepared.convertedAmount" in active,
        "Duplicate Hermes matching must consider both old original amounts and new converted amounts for USD/UYU repairs.",
    )
    assert_true(
        "let sourceLabel: String?" in active
        and "transaction.externalImportId = prepared.externalId" in active
        and "transaction.externalSource = prepared.sourceLabel" in active
        and "inferredSourceLabel(from externalId" in active
        and "Itaú credit" in active
        and "Itaú debit" in active
        and "Santander" in active
        and "Wise" in active,
        "Hermes imports must persist a source label inferred from the external ID for display in the transaction list.",
    )
    assert_true(
        "getLatestBHUUSDToUYURate" in active
        and "exchangeRateSource" in active
        and "USD" in active
        and "UYU" in active,
        "DataController must expose the latest BHU USD/UYU rate from imported transaction metadata for approximate totals.",
    )

    home_source = HOME_VIEW.read_text()
    home_active = active_swift(home_source)
    assert_true(
        "preview.hasActionableImports" in home_active
        and "No new Hermes expenses to import." in home_active,
        "Hermes sync must not present an Import confirmation when the fetched batch only contains already-imported external IDs.",
    )
    assert_true(
        "acknowledgeImportedExternalIds" in active
        and "handledExternalIds" in active
        and "/v1/dime/imported" in active
        and "shouldAcknowledgeHermesSync" in home_active,
        "After a confirmed Hermes sync import, Dime must acknowledge handled external IDs so the server stops offering them in later refreshes.",
    )

    log_source = LOG_VIEW.read_text()
    log_active = active_swift(log_source)
    assert_true(
        "usdEquivalentText" in log_active
        and "getLatestBHUUSDToUYURate" in log_active
        and "approx. USD" in log_active
        and "insightsType == 1" in log_active,
        "Log net total must show an approximate USD equivalent only for the big net-total header.",
    )
    assert_true(
        "private func isDeleteSwipeIntent" in log_active
        and "rowSwipeMinimumDistance" in log_active
        and "rowSwipeAxisRatio" in log_active
        and "abs(value.translation.height)" in log_active,
        "Transaction row swipe-to-delete must require clear horizontal intent before reacting, so vertical scrolls are not captured.",
    )
    assert_true(
        "DragGesture(minimumDistance: rowSwipeMinimumDistance" in log_active,
        "Transaction row swipe-to-delete must use a minimum drag distance instead of starting on tiny diagonal scroll movement.",
    )
    assert_true(
        "TransactionSourceIndicator" in log_active
        and "transaction.externalSourceLabel" in log_active
        and "Imported from" in log_active,
        "Transaction rows must show a compact source indicator for Hermes-imported expenses.",
    )
    assert_true(
        "if value.translation.width < 0 {\n                        withAnimation {\n                            offset = value.translation.width" not in log_active,
        "Transaction rows must not move left for any tiny negative horizontal translation during vertical scroll.",
    )

    transaction_source = TRANSACTION_VIEW.read_text()
    transaction_active = active_swift(transaction_source)
    number_pad_source = NUMBER_PAD.read_text()
    number_pad_active = active_swift(number_pad_source)
    assert_true(
        "displayCurrencyCode: selectedEntryCurrencyCode" in transaction_active
        and "manualCurrencyPicker" in transaction_active
        and "Enter amount in \\(currencyCode)" in transaction_active
        and "USD" in transaction_active
        and "UYU" in transaction_active,
        "Manual TransactionView adds must expose an obvious USD/UYU entry-currency picker next to the amount field.",
    )
    assert_true(
        "var displayCurrencyCode: String? = nil" in number_pad_active
        and "effectiveCurrencyCode" in number_pad_active,
        "NumberPadTextView must allow TransactionView to display the selected manual-entry currency instead of always using the app currency.",
    )
    assert_true(
        "manualPrimaryAmount(for: price, entryCurrencyCode: submittedEntryCurrencyCode" in transaction_active
        and "applyManualCurrencyEntry(" in transaction_active
        and "entryAmount(for: transaction, entryCurrencyCode:" in transaction_active,
        "TransactionView must validate, save, and edit manual USD entries using converted primary-currency amounts.",
    )
    assert_true(
        "func manualPrimaryAmount" in active
        and "entryCurrency == \"USD\", primaryCurrency == \"UYU\"" in active
        and "return amount * rate" in active
        and "entryCurrency == \"UYU\", primaryCurrency == \"USD\"" in active
        and "return amount / rate" in active,
        "DataController must convert manual entries between USD and UYU with the latest BHU USD/UYU rate.",
    )
    assert_true(
        "func applyManualCurrencyEntry" in active
        and "transaction.originalAmount = enteredAmount" in active
        and "transaction.originalCurrency = entryCurrency" in active
        and "transaction.convertedAmount = primaryAmount" in active
        and "transaction.convertedCurrency = primaryCurrency" in active
        and "Manual entry BHU estimate" in active,
        "DataController must persist the entered USD/UYU amount plus converted primary amount and BHU-rate metadata.",
    )
    assert_true(
        "func applyManualUSDEquivalent" in active
        and "transaction.originalAmount = amount" in active
        and "transaction.originalCurrency = primaryCurrency" in active
        and "transaction.convertedAmount = amount / rate" in active
        and "transaction.convertedCurrency = \"USD\"" in active,
        "DataController must still apply a latest-BHU-rate USD equivalent to manually created non-USD transactions.",
    )

    category_source = CATEGORY_VIEW.read_text()
    category_active = active_swift(category_source)
    assert_true(
        ".presentationDetents([.height(270)])" not in category_active,
        "Category add/edit sheets must not be locked to a 270pt sheet that the emoji keyboard covers.",
    )
    assert_true(
        "private let categorySheetDetents" in category_active and ".large" in category_active,
        "Category add/edit sheets need a shared taller detent set with a large fallback.",
    )
    assert_true(
        "emojiTextField.becomeFirstResponder()" not in category_active,
        "EmojiTextField must not auto-open the emoji keyboard before the user taps it.",
    )

    print("Dime local sync regression checks passed.")


if __name__ == "__main__":
    main()
