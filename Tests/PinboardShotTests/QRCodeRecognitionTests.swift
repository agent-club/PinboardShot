import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import PinboardShot

struct QRCodeRecognitionTests {
    @Test func recognizesQRCodePayload() throws {
        let payload = "https://example.com/pinboardshot?source=qr"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        let code = try #require(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            .transformed(by: CGAffineTransform(translationX: 40, y: 40))
        let bounds = CGRect(x: 0, y: 0, width: code.extent.maxX + 40, height: code.extent.maxY + 40)
        let image = code.composited(over: CIImage(color: .white).cropped(to: bounds))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let cgImage = try #require(context.createCGImage(image, from: bounds))

        #expect(try TextRecognitionService.recognizeQRCodes(in: cgImage) == [payload])
    }
}
