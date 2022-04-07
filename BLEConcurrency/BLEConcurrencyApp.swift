//
//  BLEConcurrencyApp.swift
//  BLEConcurrency
//
//  Created by Per Friis on 30/03/2022.
//

import SwiftUI

@main
struct BLEConcurrencyApp: App {
    @StateObject var store = AsyncCBCentralManager<FCNanoBLESense>()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
