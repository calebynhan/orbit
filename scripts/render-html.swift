// Renders a local HTML file to a PNG at 2x using WebKit. Used for README/site images.
//   swift scripts/render-html.swift <url> <width> <height> <out.png>
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 5, let url = URL(string: args[1]), let w = Double(args[2]), let h = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: render-html.swift <url> <width> <height> <out.png>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[4])
// Top-level guard bindings aren't visible to the class below; copy them into globals.
let pageURL = url, pageWidth = w, pageHeight = h, outputURL = out

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), styleMask: [.borderless], backing: .buffered, defer: false)

    func start() {
        window.contentView = view
        window.orderBack(nil)
        view.navigationDelegate = self
        view.load(URLRequest(url: pageURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give web fonts a moment to arrive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: pageWidth * 2)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write(Data("snapshot failed: \(error?.localizedDescription ?? "unknown")\n".utf8))
                    exit(1)
                }
                do { try png.write(to: outputURL); print("wrote \(outputURL.path) \(rep.pixelsWide)x\(rep.pixelsHigh)") } catch { print(error); exit(1) }
                exit(0)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("load failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.start()
app.run()
