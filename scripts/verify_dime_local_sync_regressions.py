#!/usr/bin/env python3
"""Regression checks for Sofia's local Dime/Hermes build.

These are intentionally source-level checks because the upstream project has no
XCTest target. They guard the two failure modes Sofia hit on-device:
1. Personal-team/no-app-group builds must use a real local SQLite store URL.
2. Hermes imports must match existing categories robustly without inventing new ones.
"""
from __future__ import annotations

import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_CONTROLLER = ROOT / "app/dime/Data/DataController.swift"
ENTITLEMENTS = ROOT / "app/dime/dime.entitlements"
INFO_PLIST = ROOT / "app/dime/Info.plist"


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
        "normalizedCategoryName" in active,
        "Hermes import should normalize category names for matching existing categories.",
    )
    assert_true(
        "ambiguousCategory" in active,
        "Normalized category matching must detect ambiguous existing category names.",
    )

    print("Dime local sync regression checks passed.")


if __name__ == "__main__":
    main()
