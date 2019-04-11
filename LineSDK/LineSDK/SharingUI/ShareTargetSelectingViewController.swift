//
//  ShareTargetSelectingViewController.swift
//
//  Copyright (c) 2016-present, LINE Corporation. All rights reserved.
//
//  You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
//  copy and distribute this software in source code or binary form for use
//  in connection with the web services and APIs provided by LINE Corporation.
//
//  As with any software that integrates with the LINE Corporation platform, your use of this software
//  is subject to the LINE Developers Agreement [http://terms2.line.me/LINE_Developers_Agreement].
//  This copyright notice shall be included in all copies or substantial portions of the software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import UIKit

protocol ShareTargetSelectingViewControllerDelegate: AnyObject {
    func shouldSearchStart(_ viewController: ShareTargetSelectingViewController) -> Bool

    func correspondingSelectedPanelViewController(for viewController: ShareTargetSelectingViewController)
        -> SelectedTargetPanelViewController
}

final class ShareTargetSelectingViewController: UITableViewController, ShareTargetTableViewStyling {

    typealias AppendingIndexRange = ColumnDataStore<ShareTarget>.AppendingIndexRange
    typealias ColumnIndex = ColumnDataStore<ShareTarget>.ColumnIndex

    var store: ColumnDataStore<ShareTarget>!
    let columnIndex: Int

    var dataAppendingObserver: NotificationToken!
    var selectingObserver: NotificationToken!
    var deselectingObserver: NotificationToken!

    weak var delegate: ShareTargetSelectingViewControllerDelegate?

    // Search
    private let searchController: ShareTargetSearchController
    private let resultViewController: ShareTargetSearchResultViewController

    init(store: ColumnDataStore<ShareTarget>, columnIndex: Int) {
        self.store = store
        self.columnIndex = columnIndex

        let resultViewController = ShareTargetSearchResultViewController(store: store)

        switch MessageShareTargetType(rawValue: columnIndex) {
        case .friends?:
            resultViewController.sectionOrder = [.friends, .groups]
        case .groups?:
            resultViewController.sectionOrder = [.groups, .friends]
        case .none:
            fatalError("The input column index should match a message share target type.")
        }

        self.resultViewController = resultViewController

        let searchController = ShareTargetSearchController(searchResultsController: resultViewController)
        self.searchController = searchController

        super.init(style: .plain)

        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupTableView()
        setupObservers()
    }

    private func setupTableView() {
        setupTableViewStyle()
        tableView.tableHeaderView = searchController.searchBar
        tableView.prefetchDataSource = self
    }

    private func setupObservers() {
        dataAppendingObserver = NotificationCenter.default.addObserver(
            forName: .columnDataStoreDidAppendData, object: store, queue: nil)
        {
            [unowned self] noti in
            self.handleDataAppended(noti)
        }

        selectingObserver = NotificationCenter.default.addObserver(
            forName: .columnDataStoreDidSelect, object: store, queue: nil)
        {
            [unowned self] noti in
            self.handleSelectingChange(noti)
        }

        deselectingObserver = NotificationCenter.default.addObserver(
            forName: .columnDataStoreDidDeselect, object: store, queue: nil)
        {
            [unowned self] noti in
            self.handleSelectingChange(noti)
        }
    }

    private func handleSelectingChange(_ notification: Notification) {
        guard let index = notification.userInfo?[LineSDKNotificationKey.selectingIndex] as? ColumnIndex else {
            assertionFailure("The `columnDataStoreSelected` notification should contain " +
                "`selectingIndex` in `userInfo`. But got `userInfo`: \(String(describing: notification.userInfo))")
            return
        }
        guard index.column == columnIndex else {
            return
        }
        let indexPath = IndexPath(row: index.row, section: 0)

        if let cell = tableView.cellForRow(at: indexPath) as? ShareTargetSelectingTableCell {
            let target = store.data(at: index)
            let selected = store.isSelected(at: index)
            cell.setShareTarget(target, selected: selected)
        }
    }

    private func handleDataAppended(_ notification: Notification) {
        guard let range =
            notification.userInfo?[LineSDKNotificationKey.appendDataIndexRange] as? AppendingIndexRange else
        {
            assertionFailure("The `columnDataStoreDidAppendData` notification should contain " +
                "`appendDataIndexRange` in `userInfo`. But got `userInfo`: \(String(describing: notification.userInfo))")
            return
        }
        guard range.column == columnIndex else {
            return
        }
        tableView.reloadData()
    }

    deinit {
        print("Deinit: \(self)")
    }
}

extension ShareTargetSelectingViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return store.data(atColumn: columnIndex).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ShareTargetSelectingTableCell.reuseIdentifier,
            for: indexPath) as! ShareTargetSelectingTableCell

        let dataIndex = ColumnIndex(column: columnIndex, row: indexPath.row)

        let target = store.data(at: dataIndex)
        let selected = store.isSelected(at: dataIndex)
        cell.setShareTarget(target, selected: selected)
        return cell
    }
}

extension ShareTargetSelectingViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let toggled = store.toggleSelect(atColumn: columnIndex, row: indexPath.row)
        if !toggled {
            popSelectingLimitAlert(max: store.maximumSelectedCount)
        }
    }
}


// MARK: - Search Results Updating
extension ShareTargetSelectingViewController: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        resultViewController.view.isHidden = false
        guard let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) else {
            return
        }
        resultViewController.searchText = text
    }
}

extension ShareTargetSelectingViewController: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        return delegate?.shouldSearchStart(self) ?? true
    }

    func continueSearch() {
        searchController.searchBar.becomeFirstResponder()
    }
}

extension ShareTargetSelectingViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        if let selectingPanel = delegate?.correspondingSelectedPanelViewController(for: self) {
            // Sync selected panel collection view content offset from selecting vc to search result vc.
            syncContentOffset(from: selectingPanel, to: resultViewController.panelViewController)
        }
    }

    func didPresentSearchController(_ searchController: UISearchController) {
        resultViewController.start()
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        if let selectingPanel = delegate?.correspondingSelectedPanelViewController(for: self) {
            // Sync selected panel collection view content offset from search result vc to selecting vc.
            syncContentOffset(from: resultViewController.panelViewController, to: selectingPanel)
        }
        resultViewController.clear()
    }

    private func syncContentOffset(from: SelectedTargetPanelViewController, to: SelectedTargetPanelViewController) {
        to.collectionViewContentOffset = from.collectionViewContentOffset
    }
}

extension UIColor {
    func image(_ size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension ShareTargetSelectingViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        indexPaths.forEach { indexPath in
            let index = ColumnIndex(column: columnIndex, row: indexPath.row)
            guard let url = store.data(at: index).avatarURL else { return }
            ImageManager.shared.getImage(url)
        }
    }
}
    





