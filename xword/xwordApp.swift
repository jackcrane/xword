//
//  xwordApp.swift
//  xword
//
//  Created by Jack Crane on 4/6/26.
//

import SwiftUI

@main
struct xwordApp: App {
    @AppStorage(AppColorScheme.storageKey) private var colorSchemePreference = AppColorScheme.system.rawValue

    init() {
        CrosswordSettings.normalizeStoredMaximumGridDimension()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(selectedColorScheme)
        }
    }

    private var selectedColorScheme: ColorScheme? {
        AppColorScheme(rawValue: colorSchemePreference)?.preferredColorScheme
    }
}
