import NotabilityCore
import SwiftUI

/// An image block: the stored photo fit into the block's frame.
struct ImageBlockView: View {
    let block: CanvasBlock

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: block.frame.size.width, height: block.frame.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil, let ref = block.imageRef else { return }
        image = BlobStore.shared.data(for: ref).flatMap(UIImage.init(data:))
    }
}
