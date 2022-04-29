//
//  SenseView.swift
//  BLEConcurrency
//
//  Created by Per Friis on 06/04/2022.
//

import SwiftUI
import CoreBluetooth

struct SenseView: View {
    @EnvironmentObject var store: AsyncCBCentralManager<FCNanoBLESense>
    @Environment(\.dismiss) var dismiss

    var id: CBPeripheral.ID

    @State private var sensors: FCNanoBLESense?
    @State private var temperature: Measurement<UnitTemperature> = .init(value: .nan, unit: .celsius)
    @State private var humidity: Float = .nan
    @State private var color: Color = .black
    @State private var pressure: Measurement<UnitPressure> = .init(value: .nan, unit: .kilopascals)

    var body: some View {
        VStack {
            if sensors == nil {
                ProgressView("connecting to Sensor")
                    .controlSize(.large)
            } else {
                Text("Connected to")
                Text(sensors!.name )
                    .font(.title)

                Text(Self.measurementFormatter.string(from: temperature))
                    .font(.title2)

                Text("Humidity:\(humidity.formatted(.percent))")

                Text(Self.measurementFormatter.string(from: pressure))
                    .font(.title2)

                Circle()
                    .fill(color)
                    .overlay {
                        Image("friisconsult.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(radius: 8)
                            .foregroundColor(color)
                    }
            }
        }
        .task {
            do {
                store.stopScan()
                // waiting for the store to connect and return with an handle to the BLE device
                sensors = try await store.connect(id)

                // Wrapping the calls in tasks makes it possible to have concurrent tasks running
                Task {
                    for await temperature in sensors!.temperature {
                        self.temperature = temperature
                    }
                }

                Task {
                    for await humidity in sensors!.humidity {
                        self.humidity = humidity / 100
                    }
                }

                Task {
                    for await colorHex in sensors!.colorHex {
                        withAnimation {
                            self.color = Color(red: colorHex.red, green: colorHex.green, blue: colorHex.blue)
                        }
                    }
                }

                Task {
                    for await pressure in sensors!.pressure {
                        self.pressure = pressure
                    }
                }

            } catch {

            }
        }
        .onDisappear {
            // we need to let the device go, when we leave this view
            store.cancelConnection(sensors)
        }
        .onReceive(store.$connectionError) { _ in
            // if the connection error gets a value, we have lost the connection to the device and are getting out of here
            sensors = nil
            dismiss()
        }
    }

    static var measurementFormatter: MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }
}

struct SenseView_Previews: PreviewProvider {
    static var previews: some View {
        SenseView(id: "")
    }
}
