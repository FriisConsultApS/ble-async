//
//  ContentView.swift
//  BLEConcurrency
//
//  Created by Per Friis on 30/03/2022.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var store: AsyncCBCentralManager<FCNanoBLESense>
    @State var theItem: String = "-"
    @State var isScanning: Bool = false
    @State var devices: [CBPeripheral] = []
    @State var selectedPeripheralId: CBPeripheral.ID?
    var body: some View {
        NavigationView {
            VStack {                
                List(selection: $selectedPeripheralId) {
                    ForEach(devices) { device in
                        NavigationLink {
                            SenseView(id: device.id)
                        } label: {
                            Text("Device \(device.name ??  device.identifier.uuidString)")
                        }
                    }
                    
                }
                
                if isScanning {
                    ProgressView()
                }
            }
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isScanning {
                        Button {
                            store.stopScan()
                        } label: {
                            HStack {
                                ProgressView()
                                Label("stop scan", image: "cancel.ble")
                            }
                        }
                    }
                }
                
            })
            
            .task {
                guard await store.isReady() else { return }
                isScanning = true
                
                devices.removeAll()
                
                for await device in store.devices.filter({ $0.name != nil }) {
                    devices.append(device)
                    
                }
                isScanning = false
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AsyncCBCentralManager<FCNanoBLESense>())
    }
}
