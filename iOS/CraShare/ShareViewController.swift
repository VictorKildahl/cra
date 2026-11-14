import CraCore
import UIKit
import UniformTypeIdentifiers

/// "Cra" in other apps' share sheets: Arc Search's "Saved" screen, measured from TidBITS'
/// April 2024 screenshot. A heart with a check, "Saved", a picker of where the link goes (it
/// remembers the last place), and Done. Done keeps the link in the App Group's inbox for the app;
/// swiping the sheet down leaves without saving, as in Arc Search.
final class ShareViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let backdrop = SavedBackdropView()
    private let heart = UIImageView()
    private let check = UIImageView()
    private let savedLabel = UILabel()
    private let picker = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    private var link: URL?
    private var linkTitle = ""
    private var destination: MobileShareInbox.Destination = .tabs

    private var inboxFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MobileShareInbox.appGroup)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(backdrop)

        heart.image = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 92, weight: .regular))
        heart.tintColor = .white
        heart.contentMode = .center
        view.addSubview(heart)
        // The check in the heart, in the purple measured there (#a260c0).
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .heavy))
        check.tintColor = UIColor(red: 0xa2 / 255, green: 0x60 / 255, blue: 0xc0 / 255, alpha: 1)
        check.contentMode = .center
        view.addSubview(check)

        savedLabel.text = "Saved"
        savedLabel.textColor = .white
        savedLabel.textAlignment = .center
        let heavy = UIFont.systemFont(ofSize: 46, weight: .heavy)
        savedLabel.font = heavy.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 46) } ?? heavy
        view.addSubview(savedLabel)

        picker.showsMenuAsPrimaryAction = true
        picker.accessibilityIdentifier = "share-destination"
        view.addSubview(picker)

        var done = UIButton.Configuration.filled()
        done.baseBackgroundColor = UIColor(red: 0, green: 0x01 / 255, blue: 0x93 / 255, alpha: 1)
        done.baseForegroundColor = .white
        done.background.cornerRadius = 14
        done.attributedTitle = AttributedString("Done", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 20, weight: .semibold)]))
        doneButton.configuration = done
        doneButton.accessibilityIdentifier = "share-done"
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneButton)

        if let folder = inboxFolder {
            destination = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.lastDestination } ?? .tabs
        }
        updatePicker()
        loadLink()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        backdrop.frame = bounds
        let mid = bounds.midY
        heart.frame = CGRect(x: bounds.midX - 55, y: mid - 108 - 50, width: 110, height: 100)
        check.frame = heart.frame.offsetBy(dx: 0, dy: -4)
        savedLabel.frame = CGRect(x: 0, y: mid - 36 - 30, width: bounds.width, height: 60)
        picker.frame = CGRect(x: bounds.midX - 119.5, y: mid + 50 - 23.5, width: 239, height: 47)
        let doneWidth = min(334, bounds.width - 40)
        doneButton.frame = CGRect(x: bounds.midX - doneWidth / 2, y: bounds.height - 66 - 53, width: doneWidth, height: 53)
    }

    /// The capsule: the place's glyph and name with up and down chevrons; a tap lists the places.
    private func updatePicker() {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: destination.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        config.imagePadding = 12
        config.attributedTitle = AttributedString(destination.label, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 44)
        picker.configuration = config
        picker.contentHorizontalAlignment = .leading
        picker.accessibilityValue = destination.label
        if picker.viewWithTag(7) == nil {
            let chevrons = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
            chevrons.tintColor = .white
            chevrons.tag = 7
            chevrons.translatesAutoresizingMaskIntoConstraints = false
            picker.addSubview(chevrons)
            NSLayoutConstraint.activate([
                chevrons.trailingAnchor.constraint(equalTo: picker.trailingAnchor, constant: -18),
                chevrons.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            ])
        }
        picker.menu = UIMenu(children: MobileShareInbox.Destination.allCases.map { place in
            UIAction(title: place.label, image: UIImage(systemName: place.symbol), state: place == destination ? .on : .off) { [weak self] _ in
                self?.destination = place
                self?.updatePicker()
            }
        })
    }

    /// The shared page: a URL item, with the host app's title for it when there is one.
    private func loadLink() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        linkTitle = items.first?.attributedContentText?.string ?? items.first?.attributedTitle?.string ?? ""
        guard let provider = items.flatMap({ $0.attachments ?? [] }).first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            doneButton.isEnabled = false
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            DispatchQueue.main.async { self?.link = url }
        }
    }

    @objc private func doneTapped() {
        if let link, let folder = inboxFolder {
            let title = linkTitle
            let place = destination
            MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in
                inbox.save(url: link.absoluteString, title: title, to: place, at: Date())
            }
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Swiped down: nothing is saved.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

/// The sheet's colours as TidBITS' screenshot shows them: blue-violet at the top (#1500c7), a
/// lavender glow on the left (#7c57da), purple in the middle (#6d1aa0), red at the right (#ee2241)
/// and blue again at the bottom (#3240e0). Arc Search's is a mesh; this lays three gradients over
/// each other to come close.
final class SavedBackdropView: UIView {
    private let base = CAGradientLayer()
    private let lavender = CAGradientLayer()
    private let red = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        base.colors = [rgb(0x1500c7), rgb(0x5a20b8), rgb(0x6d1aa0), rgb(0x3240e0)].map(\.cgColor)
        base.locations = [0, 0.4, 0.62, 1]
        lavender.type = .radial
        lavender.colors = [rgb(0x8a6ae0).cgColor, rgb(0x8a6ae0).withAlphaComponent(0).cgColor]
        lavender.startPoint = CGPoint(x: 0.1, y: 0.45)
        lavender.endPoint = CGPoint(x: 0.75, y: 0.8)
        red.type = .radial
        red.colors = [rgb(0xee2241).cgColor, rgb(0xd0307a).withAlphaComponent(0.6).cgColor, rgb(0xd0307a).withAlphaComponent(0).cgColor]
        red.locations = [0, 0.45, 1]
        red.startPoint = CGPoint(x: 1, y: 0.55)
        red.endPoint = CGPoint(x: 0.25, y: 0.95)
        for layer in [base, lavender, red] { self.layer.addSublayer(layer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for layer in [base, lavender, red] { layer.frame = bounds }
    }

    private func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
