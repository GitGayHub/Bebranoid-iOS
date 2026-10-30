import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

/// Настоящий QR-код для входа в Telegram (`tg://login?token=...` из `authorizationStateWaitOtherDeviceConfirmation`).
public struct TelegramQRCodeView: View {
    public let link: String

    public init(link: String) {
        self.link = link
    }

    public var body: some View {
        #if canImport(UIKit)
        if let image = Self.renderImage(link: link) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        } else {
            ProgressView()
                .tint(.white)
                .frame(height: 120)
        }
        #else
        Text(link)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
        #endif
    }

    #if canImport(UIKit)
    static func renderImage(link: String) -> UIImage? {
        guard !link.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}
