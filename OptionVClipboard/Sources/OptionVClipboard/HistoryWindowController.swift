import AppKit

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Constants {
        static let windowWidth: CGFloat = 560
        static let windowHeight: CGFloat = 420
        static let contentInset: CGFloat = 16
        static let rowHeight: CGFloat = 44
        static let searchFieldHeight: CGFloat = 28
        static let hintLabelHeight: CGFloat = 18
    }

    private let searchField = HistorySearchField(frame: .zero)
    private let tableView = HistoryTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let hintLabel = NSTextField(labelWithString: "Enter or Cmd+C copies. Double-click pastes.")

    private var allItems: [ClipboardItem] = []
    private var filteredItems: [ClipboardItem] = []
    private var copyHandler: ((ClipboardItem) -> Bool)?
    private var pasteHandler: ((ClipboardItem) -> Bool)?
    private var hasCenteredWindow = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.windowWidth, height: Constants.windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.title = "History"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = false

        super.init(window: panel)

        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        items: [ClipboardItem],
        onCopy: @escaping (ClipboardItem) -> Bool,
        onPaste: @escaping (ClipboardItem) -> Bool
    ) {
        copyHandler = onCopy
        pasteHandler = onPaste
        searchField.stringValue = ""
        updateItems(items)

        guard let window else {
            return
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if hasCenteredWindow == false {
            window.center()
            hasCenteredWindow = true
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func closePicker() {
        window?.orderOut(nil)
    }

    private func configureContent() {
        guard let window else {
            return
        }

        let rootView = NSView(frame: .zero)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize)
        searchField.onMoveSelection = { [weak self] direction in
            self?.moveSelection(by: direction)
        }
        searchField.onSelect = { [weak self] in
            self?.copySelection()
        }
        searchField.onCopy = { [weak self] in
            self?.copySelection()
        }
        searchField.onDismiss = { [weak self] in
            self?.closePicker()
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .regular
        searchField.frame.size.height = Constants.searchFieldHeight

        let searchContainer = NSView(frame: .zero)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: Constants.searchFieldHeight)
        ])

        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = Constants.rowHeight
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.onDoubleClickRow = { [weak self] row in
            self?.pasteRow(row)
        }
        tableView.onSelect = { [weak self] in
            self?.copySelection()
        }
        tableView.onCopy = { [weak self] in
            self?.copySelection()
        }
        tableView.onDismiss = { [weak self] in
            self?.closePicker()
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HistoryColumn"))
        column.resizingMask = .autoresizingMask
        column.width = Constants.windowWidth - (Constants.contentInset * 2)
        tableView.addTableColumn(column)
        tableView.autoresizingMask = [.width]
        tableView.frame = NSRect(x: 0, y: 0, width: column.width, height: Constants.rowHeight)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(searchContainer)
        stackView.addArrangedSubview(scrollView)
        stackView.addArrangedSubview(hintLabel)

        rootView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Constants.contentInset),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Constants.contentInset),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Constants.contentInset),
            stackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Constants.contentInset),
            hintLabel.heightAnchor.constraint(equalToConstant: Constants.hintLabelHeight),
            scrollView.heightAnchor.constraint(
                equalToConstant: Constants.windowHeight - (
                    Constants.contentInset * 2
                        + Constants.searchFieldHeight
                        + Constants.hintLabelHeight
                        + 24
                )
            )
        ])

        tableView.reloadData()
    }

    private func updateItems(_ items: [ClipboardItem]) {
        allItems = items
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            filteredItems = allItems
        } else {
            let loweredQuery = trimmedQuery.lowercased()
            filteredItems = allItems.filter { item in
                item.text.lowercased().contains(loweredQuery) || (item.source?.lowercased().contains(loweredQuery) ?? false)
            }
        }

        tableView.frame.size.height = max(CGFloat(filteredItems.count) * Constants.rowHeight, Constants.rowHeight)
        tableView.reloadData()
        selectDefaultRowIfNeeded()
    }

    private func selectDefaultRowIfNeeded() {
        guard filteredItems.isEmpty == false else {
            tableView.deselectAll(nil)
            return
        }

        let currentSelection = tableView.selectedRow
        if currentSelection < 0 || currentSelection >= filteredItems.count {
            selectRow(0)
        }
    }

    private func selectRow(_ row: Int) {
        guard filteredItems.indices.contains(row) else {
            tableView.deselectAll(nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func moveSelection(by offset: Int) {
        guard filteredItems.isEmpty == false else {
            return
        }

        let currentRow = tableView.selectedRow
        let nextRow: Int
        if currentRow < 0 {
            nextRow = offset > 0 ? 0 : filteredItems.count - 1
        } else {
            nextRow = min(max(currentRow + offset, 0), filteredItems.count - 1)
        }

        selectRow(nextRow)
    }

    private func copySelection() {
        guard let item = selectedItem else {
            return
        }

        if copyHandler?(item) == true {
            closePicker()
        }
    }

    private func pasteRow(_ row: Int) {
        selectRow(row)
        guard let item = selectedItem else {
            return
        }

        closePicker()
        _ = pasteHandler?(item)
    }

    private var selectedItem: ClipboardItem? {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else {
            return nil
        }

        return filteredItems[row]
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cellView: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = .systemFont(ofSize: NSFont.systemFontSize)
            textField.textColor = .labelColor

            cellView.textField = textField
            cellView.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        }

        cellView.textField?.stringValue = displayString(for: filteredItems[row])
        return cellView
    }

    private func displayString(for item: ClipboardItem) -> String {
        let sourcePrefix = item.source.map { "[\($0)] " } ?? ""
        let collapsedText = item.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sourcePrefix + collapsedText
    }
}

private final class HistorySearchField: NSSearchField {
    var onMoveSelection: ((Int) -> Void)?
    var onSelect: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.isCommandC {
            onCopy?()
            return
        }

        switch event.keyCode {
        case 53:
            onDismiss?()
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onSelect?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class HistoryTableView: NSTableView {
    var onDoubleClickRow: ((Int) -> Void)?
    var onSelect: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDismiss: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.isCommandC {
            onCopy?()
            return
        }

        switch event.keyCode {
        case 53:
            onDismiss?()
        case 125:
            super.keyDown(with: event)
        case 126:
            super.keyDown(with: event)
        case 36, 76:
            onSelect?()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        guard event.clickCount >= 2, clickedRow >= 0 else {
            return
        }

        onDoubleClickRow?(clickedRow)
    }
}

private extension NSEvent {
    var isCommandC: Bool {
        keyCode == 8 && modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }
}
