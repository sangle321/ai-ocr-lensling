import UIKit
import UniformTypeIdentifiers
import ImageIO

final class ShareViewController: UIViewController {
  private let status = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.text = "Preparing your photo…"
    status.numberOfLines = 0
    status.textAlignment = .center
    status.translatesAutoresizingMaskIntoConstraints = false
    let done = UIButton(type: .system)
    done.setTitle("Done", for: .normal)
    done.addTarget(self, action: #selector(finish), for: .touchUpInside)
    done.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(status); view.addSubview(done)
    NSLayoutConstraint.activate([
      status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
      status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
      done.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 24),
      done.centerXAnchor.constraint(equalTo: view.centerXAnchor)
    ])
    let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    guard let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
      status.text = "Choose one photo to read with Lensling."; return
    }
    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
      guard let self else { return }
      do {
        guard error == nil, let url,
          let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.lensling.lensling"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400
          ] as CFDictionary),
          let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.92)
        else { throw NSError(domain: "Lensling", code: 1) }
        var destination = group.appendingPathComponent("pending.jpg")
        try data.write(to: destination, options: .atomic)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        try destination.setResourceValues(resource)
        DispatchQueue.main.async { self.status.text = "Photo saved.\nOpen Lensling to recognize and translate it." }
      } catch {
        DispatchQueue.main.async { self.status.text = "Could not save this photo. Try importing it from Lensling instead." }
      }
    }
  }

  @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }
}
