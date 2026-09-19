import SwiftUI
import FlowCore

struct ImageModelControl: View {
    @Binding var selection: ImageModel
    var body: some View {
        Picker("모델", selection: $selection) {
            ForEach(ImageModel.allCases, id: \.self) { Text($0.label).tag($0) }
        }.pickerStyle(.menu).accessibilityLabel("모델")
    }
}
