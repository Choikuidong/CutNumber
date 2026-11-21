import AppKit
@main struct Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        defer { UserDefaults.standard.removeObject(forKey: "interfaceLanguage") }
        for language in AppLanguage.all {
            UserDefaults.standard.set(language.id, forKey: "interfaceLanguage")
            let view = AboutView(version: "1.0.4")
            view.appearance = NSAppearance(named: .aqua)
            view.layoutSubtreeIfNeeded()
            let stack = view.subviews.first as! NSStackView
            let children = stack.arrangedSubviews
            for child in children {
                let rect = child.convert(child.bounds, to: view)
                precondition(rect.width > 0 && rect.height > 0, "Empty frame: \(language.id)")
                precondition(rect.minY >= 0 && rect.maxY <= 360, "Clipped layout: \(language.id) \(rect)")
            }
            for index in 1..<children.count {
                let previous = children[index - 1].convert(children[index - 1].bounds, to: view)
                let next = children[index].convert(children[index].bounds, to: view)
                precondition(previous.minY >= next.maxY, "Overlapping groups: \(language.id)")
            }
            let brand = children[3] as! NSStackView
            let icon = brand.arrangedSubviews[0].convert(brand.arrangedSubviews[0].bounds, to: view)
            let company = brand.arrangedSubviews[1].convert(brand.arrangedSubviews[1].bounds, to: view)
            precondition(abs(icon.midY - company.midY) < 1, "Logo and text misaligned")
            precondition(AboutView.website.absoluteString == "https://applecraft.kr")
        }
        print("PASS: About layout in all 10 languages, no overlaps/clipping, centered logo/text, website URL")
    }
}
