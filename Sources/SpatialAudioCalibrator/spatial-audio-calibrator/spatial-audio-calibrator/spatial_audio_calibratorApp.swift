//
//  spatial_audio_calibratorApp.swift
//  spatial-audio-calibrator
//
//  Created by Fedir Saienko on 10.03.26.
//

import SwiftUI
import SwiftData

@main
struct spatial_audio_calibratorApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
