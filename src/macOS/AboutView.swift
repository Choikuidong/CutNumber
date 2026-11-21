import AppKit

/// A centered, constraint-based layout shared by every interface language.
@MainActor final class AboutView: NSView {
    static let website = URL(string: "https://applecraft.kr")!

    init(version: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        let title = label(T("app"), size: 30, weight: .bold)
        let versionLabel = label(T("version") + version, size: 13, secondary: true)
        let date = label(T("date"), size: 11, secondary: true)
        let release = NSStackView(views: [versionLabel, date])
        release.orientation = .vertical
        release.alignment = .centerX
        release.spacing = 8
        let separator = NSBox()
        separator.boxType = .separator

        let symbol = NSImageView()
        if let url = Bundle.main.url(forResource: "AppleCraftSymbol", withExtension: "png") {
            symbol.image = NSImage(contentsOf: url)
        }
        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 32),
            symbol.heightAnchor.constraint(equalToConstant: 36)
        ])
        let company = label(T("company"), size: 18, weight: .semibold)
        let brand = NSStackView(views: [symbol, company])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 12

        let developer = label(T("developer"), size: 13, weight: .medium)

        let homepage = NSButton(title: "applecraft.kr ↗", target: self, action: #selector(openWebsite))
        homepage.isBordered = false
        homepage.font = .systemFont(ofSize: 13, weight: .medium)
        homepage.contentTintColor = .linkColor
        homepage.toolTip = Self.website.absoluteString
        let copyright = label("© 2026 Apple Craft. All rights reserved.", size: 11, secondary: true)

        let stack = NSStackView(views: [title, release, separator, brand, developer, homepage, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(20, after: release)
        stack.setCustomSpacing(23, after: separator)
        stack.setCustomSpacing(20, after: brand)
        stack.setCustomSpacing(26, after: developer)
        stack.setCustomSpacing(40, after: homepage)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.alignment = .center
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(Self.website)
    }
}
