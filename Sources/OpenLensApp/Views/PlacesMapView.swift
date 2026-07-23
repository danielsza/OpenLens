import SwiftUI
import MapKit
import OpenLensKit

/// A map of the geotagged photos in the current view (Aperture's "Places").
/// Click a pin to select that photo.
struct PlacesMapView: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360))

    private struct Pin: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private var pins: [Pin] {
        store.visiblePhotos.compactMap { photo in
            guard let lat = photo.version.latitude, let lon = photo.version.longitude else { return nil }
            return Pin(id: photo.id, name: photo.version.name,
                       coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Places").font(.headline)
                Text("\(pins.count) geotagged photo(s)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()

            if pins.isEmpty {
                Text("No geotagged photos in the current view.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(coordinateRegion: $region, annotationItems: pins) { pin in
                    MapAnnotation(coordinate: pin.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: "photo.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white, .red)
                                .shadow(radius: 2)
                            Text(pin.name).font(.caption2).padding(.horizontal, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .onTapGesture {
                            store.selectedPhotoID = pin.id
                            store.selectedPhotoIDs = [pin.id]
                        }
                    }
                }
                .onAppear { zoomToFit() }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func zoomToFit() {
        let coords = pins.map { $0.coordinate }
        guard !coords.isEmpty else { return }
        let lats = coords.map { $0.latitude }, lons = coords.map { $0.longitude }
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.5),
            longitudeDelta: max(0.02, (lons.max()! - lons.min()!) * 1.5))
        region = MKCoordinateRegion(center: center, span: span)
    }
}
