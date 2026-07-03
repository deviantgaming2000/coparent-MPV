import SwiftUI
import MapKit

struct ExchangeRecordEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var locationManager = ExchangeLocationManager()
    @State private var exchangeDate = Date()
    @State private var role: ExchangeRole = .receivingChild
    @State private var timing: ExchangeTiming = .onTime
    @State private var minutesOffset = 15

    let onSaveRoutine: (ExchangeRecord) -> Void
    let onExpandIncident: (ExchangeRecord, IncidentDraft) -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exchange Record")
                        .font(.title2.bold())
                    Text("Save a routine exchange quickly. Add more detail only if something noteworthy happened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Captured automatically") {
                VStack(alignment: .leading, spacing: 16) {
                    if let coordinate {
                        ExchangeLocationMapView(coordinate: coordinate)
                    }

                    ExchangeCaptureRow(label: "Date and time", value: DateFormatter.factTrailDateTime.string(from: exchangeDate))
                    Divider().opacity(0.35)
                    ExchangeCaptureRow(label: "Time zone", value: TimeZone.current.identifier)
                    Divider().opacity(0.35)
                    ExchangeCaptureRow(label: "GPS", value: coordinateDescription)
                    Divider().opacity(0.35)
                    ExchangeCaptureRow(label: "Address", value: locationManager.address)
                    Divider().opacity(0.35)

                    HStack(spacing: 10) {
                        if locationManager.isCapturing {
                            ProgressView()
                        } else {
                            Image(systemName: locationManager.latitude == nil ? "location" : "location.fill")
                                .foregroundStyle(locationManager.latitude == nil ? Color.secondary : FactTrailTheme.primaryAction(for: colorScheme))
                        }
                        Text(locationManager.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        locationManager.captureLocation()
                    } label: {
                        Label("Refresh Location", systemImage: "location.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailGlassButtonStyle())
                    .disabled(locationManager.isCapturing)
                }
                .padding(16)
                .factTrailGlassCard(cornerRadius: 28)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("What is your role?") {
                Picker("Role", selection: $role) {
                    ForEach(ExchangeRole.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Was the exchange on time?") {
                Picker("Timing", selection: $timing) {
                    ForEach(ExchangeTiming.allCases) { timing in
                        Text(timing.rawValue).tag(timing)
                    }
                }
                .pickerStyle(.segmented)

                if timing != .onTime {
                    Stepper(value: $minutesOffset, in: 1...240) {
                        Text("About \(minutesOffset) minute\(minutesOffset == 1 ? "" : "s")")
                    }
                }
            }

            Section("Was anything unusual during this exchange?") {
                Button {
                    onSaveRoutine(makeRecord())
                    dismiss()
                } label: {
                    Label("No, Save Exchange", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailPrimaryButtonStyle())
                .controlSize(.large)

                Button {
                    let record = makeRecord()
                    onExpandIncident(record, record.incidentDraft())
                } label: {
                    Label("Yes, Document More", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
                .controlSize(.large)
            }
        }
        .factTrailFormBackground()
        .navigationTitle("Exchange Record")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            exchangeDate = Date()
            locationManager.captureLocation()
        }
    }

    private var coordinateDescription: String {
        guard let coordinate else {
            return "Not captured"
        }

        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = locationManager.latitude,
              let longitude = locationManager.longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func makeRecord() -> ExchangeRecord {
        ExchangeRecord(
            exchangeDate: exchangeDate,
            timeZoneIdentifier: TimeZone.current.identifier,
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            address: locationManager.address,
            role: role,
            timing: timing,
            minutesOffset: timing == .onTime ? nil : minutesOffset
        )
    }
}

private struct ExchangeLocationMapView: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            ),
            interactionModes: [.pan, .zoom]
        ) {
            Marker("Exchange location", coordinate: coordinate)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityLabel("Map showing captured exchange location")
    }
}

private struct ExchangeCaptureRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayValue)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not captured" : trimmed
    }
}
