//
//  PagingContentViewController.swift
//  PagingViewController
//
//  Created by Kazuhiro Hayashi on 7/2/17.
//  Copyright © 2017 Kazuhiro Hayashi. All rights reserved.
//

import UIKit

public protocol PagingContentViewControllerDelegate: class {
    func contentViewController(viewController: PagingContentViewController, willBeginManualScrollOn index: Int)
    func contentViewController(viewController: PagingContentViewController, didManualScrollOn index: Int, percent: CGFloat)
    func contentViewController(viewController: PagingContentViewController, didEndManualScrollOn index: Int)
}

extension PagingContentViewControllerDelegate {
    public func contentViewController(viewController: PagingContentViewController, willBeginManualScrollOn index: Int) {}
    public func contentViewController(viewController: PagingContentViewController, didManualScrollOn index: Int, percent: CGFloat) {}
    public func contentViewController(viewController: PagingContentViewController, didEndManualScrollOn index: Int) {}
}

public protocol PagingContentViewControllerDataSource: class {
    func numberOfItemForContentViewController(viewController: PagingContentViewController) -> Int
    func contentViewController(viewController: PagingContentViewController, viewControllerAt index: Int) -> UIViewController
}

public class PagingContentViewController: UIViewController {
    
    fileprivate var cachedViewControllers = [UIViewController?]()
    fileprivate var leftSidePageIndex = 0
    fileprivate var numberOfPages: Int = 0
    fileprivate var isExplicityScrolling = false
    
    public weak var delegate: PagingContentViewControllerDelegate?
    public weak var dataSource: PagingContentViewControllerDataSource?

    public var isEnabledPreloadContent = true
    
    public var contentOffsetRatio: CGFloat {
        return scrollView.contentOffset.x / (scrollView.contentSize.width - scrollView.bounds.width)
    }

    public var pagingPercent: CGFloat {
        return scrollView.contentOffset.x.truncatingRemainder(dividingBy: scrollView.bounds.width) / scrollView.bounds.width
    }
    
    @available(*, deprecated)
    public var currentPageIndex: Int {
        return leftSidePageIndex
    }
    
    public func reloadData(with page: Int = 0) {
        removeAll()
        
        UIView.animate(
            withDuration: 0,
            animations: { [weak self] in
                self?.view.setNeedsLayout()
                self?.view.layoutIfNeeded()
            },
            completion: { [weak self] (finish) in
                self?.initialLoad(with: page)
                self?.scroll(to: page, animated: false)
            }
        )
    }
    
    public func scroll(to page: Int, animated: Bool) {
        let offsetX = scrollView.bounds.width * CGFloat(page)
        loadPagesIfNeeded(page: page)
        leftSidePageIndex = page
        if animated {
            performSystemAnimation({ [weak self] in
                self?.scrollView.contentOffset = CGPoint(x: offsetX, y: 0)
            })
        } else {
            scrollView.contentOffset = CGPoint(x: offsetX, y: 0)
        }
    }
    
    public let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.bounces = false
        scrollView.backgroundColor = .clear
        return scrollView
    }()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        scrollView.frame = view.bounds
        scrollView.delegate = self
        view.addSubview(scrollView)
        view.addConstraints([.top, .bottom, .leading, .trailing].map {
            NSLayoutConstraint(item: scrollView, attribute: $0, relatedBy: .equal, toItem: view, attribute: $0, multiplier: 1, constant: 0)
        })
        
        view.backgroundColor = .clear
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.size.width * CGFloat(numberOfPages),
            height: scrollView.bounds.size.height
        )
        
        scrollView.contentOffset = CGPoint(x: scrollView.bounds.width * CGFloat(leftSidePageIndex), y: 0)
        
        cachedViewControllers.enumerated().forEach { (offset, vc) in
            vc?.view.frame = scrollView.bounds
            vc?.view.frame.origin.x = scrollView.bounds.width * CGFloat(offset)
        }
    }
    
    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        removeAll()
        initialLoad(with: leftSidePageIndex)
        coordinator.animate(alongsideTransition: { [weak self] (context) in
            guard let _self = self else { return }
            _self.scroll(to: _self.leftSidePageIndex, animated: false)
        }, completion: nil)
        
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    fileprivate func removeAll() {
        scrollView.subviews.forEach { $0.removeFromSuperview() }
        childViewControllers.forEach { $0.removeFromParentViewController() }
    }
    
    fileprivate func initialLoad(with page: Int) {
        numberOfPages = dataSource?.numberOfItemForContentViewController(viewController: self) ?? 0
        cachedViewControllers = Array(repeating: nil, count: numberOfPages)
        
        loadScrollView(with: page - 1)
        loadScrollView(with: page)
        loadScrollView(with: page + 1)
    }
    
    fileprivate func loadScrollView(with page: Int) {
        guard (0..<cachedViewControllers.count) ~= page else { return }
        
        if case nil = cachedViewControllers[page], let dataSource = dataSource {
            let vc = dataSource.contentViewController(viewController: self, viewControllerAt: page)
            vc.willMove(toParentViewController: self)
            addChildViewController(vc)
            vc.view.frame = scrollView.bounds
            vc.view.frame.origin.x = scrollView.bounds.width * CGFloat(page)
            scrollView.addSubview(vc.view)
            vc.didMove(toParentViewController: self)
            cachedViewControllers[page] = vc
        }
    }
}

extension PagingContentViewController: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isExplicityScrolling = true
        leftSidePageIndex = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        delegate?.contentViewController(viewController: self, willBeginManualScrollOn: leftSidePageIndex)
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isExplicityScrolling {
            leftSidePageIndex = Int(scrollView.contentOffset.x / scrollView.bounds.width)
            let leftSideContentOffset = CGFloat(leftSidePageIndex) * scrollView.bounds.width
            let percent = (scrollView.contentOffset.x - leftSideContentOffset) / scrollView.bounds.width
            let normalizedPercent = min(max(0, percent), 1)
            delegate?.contentViewController(viewController: self, didManualScrollOn: leftSidePageIndex, percent: normalizedPercent)
        }
    }
    
    public func preLoadContentIfNeeded(with scrollingPercent: CGFloat) {
        guard isEnabledPreloadContent else { return }
        
        if scrollingPercent > 0.5 {
            loadPagesIfNeeded(page: leftSidePageIndex + 1)
        } else{
            loadPagesIfNeeded()
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if isExplicityScrolling {
            leftSidePageIndex = Int(scrollView.contentOffset.x / scrollView.bounds.width)
            delegate?.contentViewController(viewController: self, didEndManualScrollOn: leftSidePageIndex)
        }
        isExplicityScrolling = false
        loadPagesIfNeeded()
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        
        if isExplicityScrolling {
            leftSidePageIndex = Int(scrollView.contentOffset.x / scrollView.bounds.width)
            delegate?.contentViewController(viewController: self, didEndManualScrollOn: leftSidePageIndex)
        }
        isExplicityScrolling = false
        loadPagesIfNeeded()
    }
    
    fileprivate func loadPagesIfNeeded(page: Int? = nil) {
        let loadingPage = page ?? leftSidePageIndex
        loadScrollView(with: loadingPage - 1)
        loadScrollView(with: loadingPage)
        loadScrollView(with: loadingPage + 1)
    }
}

private func performSystemAnimation(_ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.perform(
        .delete,
        on: [],
        options: UIViewAnimationOptions(rawValue: 0),
        animations: animations,
        completion: completion
    )
}
