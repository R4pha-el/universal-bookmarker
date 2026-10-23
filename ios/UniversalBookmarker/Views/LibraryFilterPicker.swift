import SwiftUI

struct LibraryFilterPicker: View {
    @Binding var selection: LibraryFilter

    var body: some View {
        Picker("Item type", selection: $selection) {
            ForEach(LibraryFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("library.filter")
    }
}
