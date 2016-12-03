//
//  HHHorizontalPagingView.m
//  HHHorizontalPagingView
//
//  Created by Huanhoo on 15/7/16.
//  Copyright (c) 2015年 Huanhoo. All rights reserved.
//

#import "HHHorizontalPagingView.h"
#import "DynamicItem.h"
#import <objc/runtime.h>
#import "UIView+WhenTappedBlocks.h"

NSString* kHHHorizontalScrollViewRefreshStartNotification = @"kHHHorizontalScrollViewRefreshStartNotification";
NSString* kHHHorizontalScrollViewRefreshEndNotification = @"kHHHorizontalScrollViewRefreshEndNotification";
NSString* kHHHorizontalTakeBackRefreshEndNotification = @"kHHHorizontalTakeBackRefreshEndNotification";


#pragma mark - ScrollView 分类用于刷新处理
static char khhh_isRefresh;
static char khhh_startRefresh;
@interface UIScrollView (HHHorizontalPagingView)

@property (nonatomic, assign) BOOL hhh_isRefresh;  // 刷新中
@property (nonatomic, assign) BOOL hhh_startRefresh; // 开始刷新


@end

@implementation UIScrollView (HHHorizontalPagingView)

- (void)setHhh_isRefresh:(BOOL)hhh_isRefresh{
    objc_setAssociatedObject(self,&khhh_isRefresh,[NSNumber numberWithBool:hhh_isRefresh],OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)hhh_isRefresh{
    return [objc_getAssociatedObject(self, &khhh_isRefresh) boolValue];
}

- (void)setHhh_startRefresh:(BOOL)hhh_startRefresh{
    objc_setAssociatedObject(self,&khhh_startRefresh,[NSNumber numberWithBool:hhh_startRefresh],OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)hhh_startRefresh{
    return [objc_getAssociatedObject(self, &khhh_startRefresh) boolValue];
}

@end

#pragma mark - HHHorizontalPagingView
@interface HHHorizontalPagingView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UIView             *headerView;
@property (nonatomic, strong) NSArray            *segmentButtons;
@property (nonatomic, strong) NSMutableArray<UIScrollView *>*contentViewArray;

@property (nonatomic, strong, readwrite) UIView  *segmentView;

@property (nonatomic, strong) UICollectionView   *horizontalCollectionView;

@property (nonatomic, weak)   UIScrollView       *currentScrollView;
@property (nonatomic, strong) NSLayoutConstraint *headerOriginYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerSizeHeightConstraint;
@property (nonatomic, assign) CGFloat            headerViewHeight;
@property (nonatomic, assign) CGFloat            segmentBarHeight;
@property (nonatomic, assign) BOOL               isSwitching;

@property (nonatomic, strong) NSMutableArray     *segmentButtonConstraintArray;

@property (nonatomic, strong) UIView             *currentTouchView;
@property (nonatomic, assign) CGPoint            currentTouchViewPoint;
@property (nonatomic, strong) UIButton           *currentTouchButton;
@property (nonatomic, assign) NSInteger          currenPage; // 当前页
@property (nonatomic, assign) NSInteger          currenSelectedBut; // 当前选中的But
@property (nonatomic, assign) CGFloat            pullOffset;
@property (nonatomic, assign) BOOL               isScroll;// 是否左右滚动

/**
 *  用于模拟scrollView滚动
 */
@property (nonatomic, strong) UIDynamicAnimator  *animator;
@property (nonatomic, strong) UIDynamicItemBehavior *inertialBehavior;

/**
 *  代理
 */
@property (nonatomic, weak) id<HHHorizontalPagingViewDelegate> delegate;

@end

@implementation HHHorizontalPagingView

static void *HHHorizontalPagingViewScrollContext = &HHHorizontalPagingViewScrollContext;
static void *HHHorizontalPagingViewInsetContext  = &HHHorizontalPagingViewInsetContext;
static void *HHHorizontalPagingViewPanContext    = &HHHorizontalPagingViewPanContext;
static NSString *pagingCellIdentifier            = @"PagingCellIdentifier";
static NSInteger pagingButtonTag                 = 1000;
static NSInteger pagingScrollViewTag             = 2000;

#pragma mark - HHHorizontalPagingView
- (instancetype)initWithFrame:(CGRect)frame delegate:(id<HHHorizontalPagingViewDelegate>) delegate{
    if (self = [super initWithFrame:frame]) {
        self.delegate = delegate;
        // UICollectionView
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.minimumLineSpacing          = 0.0;
        layout.minimumInteritemSpacing     = 0.0;
        layout.scrollDirection             = UICollectionViewScrollDirectionHorizontal;
        self.horizontalCollectionView = [[UICollectionView alloc] initWithFrame:frame collectionViewLayout:layout];
      
        // 应当为每一个ScrollView 注册一个唯一的Cell
        NSInteger section = [self.delegate numberOfSectionsInPagingView:self];
        [self registCellForm:0 to:section];
      
        self.horizontalCollectionView.backgroundColor                = [UIColor clearColor];
        self.horizontalCollectionView.dataSource                     = self;
        self.horizontalCollectionView.delegate                       = self;
        self.horizontalCollectionView.pagingEnabled                  = YES;
        self.horizontalCollectionView.showsHorizontalScrollIndicator = NO;
        self.horizontalCollectionView.scrollsToTop                   = NO;
        
        // iOS10 上将该属性设置为 NO，就会预取cell了
        if([self.horizontalCollectionView respondsToSelector:@selector(setPrefetchingEnabled:)]) {
            self.horizontalCollectionView.prefetchingEnabled = NO;
        }
        
        UICollectionViewFlowLayout *tempLayout = (id)self.horizontalCollectionView.collectionViewLayout;
        tempLayout.itemSize = self.horizontalCollectionView.frame.size;
        [self addSubview:self.horizontalCollectionView];
        [self configureHeaderView];
        [self configureSegmentView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(releaseCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStart:) name:kHHHorizontalScrollViewRefreshStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshEnd:) name:kHHHorizontalScrollViewRefreshEndNotification object:nil];

    }
    return self;
}


- (void)reload{
  
    self.headerView                  = [self.delegate headerViewInPagingView:self];
    self.headerViewHeight            = [self.delegate headerHeightInPagingView:self];
    self.segmentButtons              = [self.delegate segmentButtonsInPagingView:self];
    self.segmentBarHeight            = [self.delegate segmentHeightInPagingView:self];
    [self configureHeaderView];
    [self configureSegmentView];
    // 防止不友好动画
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.horizontalCollectionView reloadData];
    });
}

// 注册cell
- (void)registCellForm:(NSInteger)form to:(NSInteger)to{
  
  for (NSInteger i = form; i < to; i ++) {
    [self.horizontalCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:[self cellReuseIdentifierForIndex:i]];
  }
}

- (NSString *)cellReuseIdentifierForIndex:(NSInteger)aIndex{
  return [NSString stringWithFormat:@"%@_%tu",pagingCellIdentifier,aIndex];
}

- (CGFloat)pullOffset{
    if (_pullOffset == 0) {
        _pullOffset = [self.delegate headerHeightInPagingView:self] + [self.delegate segmentHeightInPagingView:self];
    }
    return _pullOffset;
}

- (void)scrollToIndex:(NSInteger)pageIndex {
    [self segmentButtonEvent:self.segmentButtons[pageIndex]];
}

- (void)scrollEnable:(BOOL)enable {
    if(enable) {
        self.segmentView.userInteractionEnabled     = YES;
        self.horizontalCollectionView.scrollEnabled = YES;
    }else {
        self.segmentView.userInteractionEnabled     = NO;
        self.horizontalCollectionView.scrollEnabled = NO;
    }
}

- (void)configureHeaderView {
    [self.headerView removeFromSuperview];
    if(self.headerView) {
        self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.headerView];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self.headerView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self.headerView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeRight multiplier:1 constant:0]];
        self.headerOriginYConstraint = [NSLayoutConstraint constraintWithItem:self.headerView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [self addConstraint:self.headerOriginYConstraint];
        
        self.headerSizeHeightConstraint = [NSLayoutConstraint constraintWithItem:self.headerView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1 constant:self.headerViewHeight];
        [self.headerView addConstraint:self.headerSizeHeightConstraint];
        [self addGestureRecognizerAtHeaderView];
    }
}

- (void)configureSegmentView {
    [self.segmentView removeFromSuperview];
    self.segmentView = nil;
    if(self.segmentView) {
        self.segmentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.segmentView];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeRight multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.headerView ? : self attribute:self.headerView ? NSLayoutAttributeBottom : NSLayoutAttributeTop multiplier:1 constant:0]];
        [self.segmentView addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1 constant:self.segmentBarHeight]];
    }
}

- (UIScrollView *)scrollViewAtIndex:(NSInteger)index{
    
    __block UIScrollView *scrollView = nil;
    [self.contentViewArray enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.tag == pagingScrollViewTag + index) {
            scrollView = obj;
            *stop = YES;
        }
    }];

    if (scrollView == nil) {
        scrollView = [self.delegate pagingView:self viewAtIndex:index];
        [self configureContentView:scrollView];
        scrollView.tag = pagingScrollViewTag + index;
        [self.contentViewArray addObject:scrollView];
    }
    return scrollView;
}

- (void)configureContentView:(UIScrollView *)scrollView{
    [scrollView  setContentInset:UIEdgeInsetsMake(self.headerViewHeight+self.segmentBarHeight, 0., scrollView.contentInset.bottom, 0.)];
    scrollView.alwaysBounceVertical = YES;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.contentOffset = CGPointMake(0., -self.headerViewHeight-self.segmentBarHeight);
    [scrollView.panGestureRecognizer addObserver:self forKeyPath:NSStringFromSelector(@selector(state)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:&HHHorizontalPagingViewPanContext];
    [scrollView addObserver:self forKeyPath:NSStringFromSelector(@selector(contentOffset)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:&HHHorizontalPagingViewScrollContext];
    [scrollView addObserver:self forKeyPath:NSStringFromSelector(@selector(contentInset)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:&HHHorizontalPagingViewInsetContext];
    if (scrollView == nil) {
        self.currentScrollView = scrollView;
    }
}

- (UIView *)segmentView {
    if(!_segmentView) {
        _segmentView = [[UIView alloc] init];
        [self configureSegmentButtonLayout];
    }
    return _segmentView;
}

- (void)configureSegmentButtonLayout {
    if([self.segmentButtons count] > 0) {
        
        CGFloat buttonTop    = 0.f;
        CGFloat buttonLeft   = 0.f;
        CGFloat buttonWidth  = 0.f;
        CGFloat buttonHeight = 0.f;
        if(CGSizeEqualToSize(self.segmentButtonSize, CGSizeZero)) {
            buttonWidth = [[UIScreen mainScreen] bounds].size.width/(CGFloat)[self.segmentButtons count];
            buttonHeight = self.segmentBarHeight;
        }else {
            buttonWidth = self.segmentButtonSize.width;
            buttonHeight = self.segmentButtonSize.height;
            buttonTop = (self.segmentBarHeight - buttonHeight)/2.f;
            buttonLeft = ([[UIScreen mainScreen] bounds].size.width - ((CGFloat)[self.segmentButtons count]*buttonWidth))/((CGFloat)[self.segmentButtons count]+1);
        }
        
        [_segmentView removeConstraints:self.segmentButtonConstraintArray];
        for(int i = 0; i < [self.segmentButtons count]; i++) {
            UIButton *segmentButton = self.segmentButtons[i];
            [segmentButton removeConstraints:self.segmentButtonConstraintArray];
            segmentButton.tag = pagingButtonTag+i;
            [segmentButton addTarget:self action:@selector(segmentButtonEvent:) forControlEvents:UIControlEventTouchUpInside];
            [_segmentView addSubview:segmentButton];
            
            if(i == 0) {
                [segmentButton setSelected:YES];
                self.currenPage = 0;
            }
            
            segmentButton.translatesAutoresizingMaskIntoConstraints = NO;
            
            NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:segmentButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_segmentView attribute:NSLayoutAttributeTop multiplier:1 constant:buttonTop];
            NSLayoutConstraint *leftConstraint = [NSLayoutConstraint constraintWithItem:segmentButton attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:_segmentView attribute:NSLayoutAttributeLeft multiplier:1 constant:i*buttonWidth+buttonLeft*i+buttonLeft];
            NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:segmentButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1 constant:buttonWidth];
            NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:segmentButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1 constant:buttonHeight];
            
            [self.segmentButtonConstraintArray addObject:topConstraint];
            [self.segmentButtonConstraintArray addObject:leftConstraint];
            [self.segmentButtonConstraintArray addObject:widthConstraint];
            [self.segmentButtonConstraintArray addObject:heightConstraint];
            
            [_segmentView addConstraint:topConstraint];
            [_segmentView addConstraint:leftConstraint];
            [segmentButton addConstraint:widthConstraint];
            [segmentButton addConstraint:heightConstraint];
            
            if (segmentButton.currentImage) {
                 CGFloat imageWidth = segmentButton.imageView.bounds.size.width;
                 CGFloat labelWidth = segmentButton.titleLabel.bounds.size.width;
                 segmentButton.imageEdgeInsets = UIEdgeInsetsMake(0, labelWidth + 5, 0, -labelWidth);
                 segmentButton.titleEdgeInsets = UIEdgeInsetsMake(0, -imageWidth, 0, imageWidth);
            }
        }
        
    }
}

- (void)segmentButtonEvent:(UIButton *)segmentButton {
    
    NSInteger clickIndex = segmentButton.tag-pagingButtonTag;
    if (clickIndex >= [self.delegate numberOfSectionsInPagingView:self]) {
        if ([self.delegate respondsToSelector:@selector(pagingView:segmentDidSelected:atIndex:)]) {
            [self.delegate pagingView:self segmentDidSelected:segmentButton atIndex:clickIndex];
        }
        return;
    }
    
    // 在当前页被点击
    if (segmentButton.selected) {
        if ([self.delegate respondsToSelector:@selector(pagingView:segmentDidSelectedSameItem:atIndex:)]) {
            [self.delegate pagingView:self segmentDidSelectedSameItem:segmentButton atIndex:clickIndex];
        }
        return;
    }
    
    // 非当前页被点击
    [self.horizontalCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:clickIndex inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
    
    if(self.currentScrollView.contentOffset.y<-(self.headerViewHeight+self.segmentBarHeight)) {
        [self.currentScrollView setContentOffset:CGPointMake(self.currentScrollView.contentOffset.x, -(self.headerViewHeight+self.segmentBarHeight)) animated:NO];
    }else {
        [self.currentScrollView setContentOffset:self.currentScrollView.contentOffset animated:NO];
    }
    
    if ([self.delegate respondsToSelector:@selector(pagingView:segmentDidSelected:atIndex:)]) {
        [self.delegate pagingView:self segmentDidSelected:segmentButton atIndex:clickIndex];
    }
    
    // 视图切换时执行代码
    [self didSwitchIndex:self.currenPage to:clickIndex];
}

- (void)adjustOffsetContentView:(UIScrollView *)scrollView {
    self.isSwitching = YES;
    CGFloat headerViewDisplayHeight = self.headerViewHeight + self.headerView.frame.origin.y;
    [scrollView layoutIfNeeded];
    
    if (headerViewDisplayHeight != self.segmentTopSpace) {// 还原位置
        [scrollView setContentOffset:CGPointMake(0, -headerViewDisplayHeight - self.segmentBarHeight)];
    }else if(scrollView.contentOffset.y < -self.segmentBarHeight) {
        [scrollView setContentOffset:CGPointMake(0, -headerViewDisplayHeight-self.segmentBarHeight)];
    }else {
        // self.segmentTopSpace
        [scrollView setContentOffset:CGPointMake(0, scrollView.contentOffset.y-headerViewDisplayHeight + self.segmentTopSpace)];
    }
    
    if ([scrollView.delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [scrollView.delegate scrollViewDidEndDragging:scrollView willDecelerate:NO];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0)), dispatch_get_main_queue(), ^{
        self.isSwitching = NO;
    });
}

#pragma mark - 对headerView触发滚动的两种处理
- (BOOL)pointInside:(CGPoint)point withEvent:(nullable UIEvent *)event {
    if(point.x < 10) {
        return NO;
    }
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
//    BUG -[__NSCFType isDescendantOfView:]: unrecognized selector sent to instance 0x9dd30e0
    if (![view isKindOfClass:[UIView class]]) {
        return nil;
    }
    
    if (self.isGesturesSimulate) {
        return view;
    }
    
    // 如果处于刷新中，作用在headerView上的手势不响应在currentScrollView上
    if (self.currentScrollView.hhh_isRefresh) {
        return view;
    }
    
    if ([view isDescendantOfView:self.headerView] || [view isDescendantOfView:self.segmentView]) {
        self.horizontalCollectionView.scrollEnabled = NO;
        
        self.currentTouchView = nil;
        self.currentTouchButton = nil;
        
        [self.segmentButtons enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if(obj == view) {
                self.currentTouchButton = obj;
            }
        }];
        if(!self.currentTouchButton) {
            self.currentTouchView = view;
            self.currentTouchViewPoint = [self convertPoint:point toView:self.currentTouchView];
        }else {
            return view;
        }
        
        return self.currentScrollView;
    }
    return view;
}

- (void)addGestureRecognizerAtHeaderView{
    
    if (self.isGesturesSimulate == NO) {
        return;
    }
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.headerView addGestureRecognizer:pan];
}

- (void)pan:(UIPanGestureRecognizer*)pan{
    
    CGPoint point = [pan translationInView:self.headerView];
    // 手势模拟 兼容整体下来刷新
    self.isDragging = !(pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateFailed);
    [self rollingPointy:point.y]; // 必须在self.isDragging 下面
    
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateFailed) {
        CGPoint contentOffset = self.currentScrollView.contentOffset;
        CGFloat border = - self.headerViewHeight - [self.delegate segmentHeightInPagingView:self];
        if (contentOffset.y <= border) {
            [UIView animateWithDuration:0.35 animations:^{
                self.currentScrollView.contentOffset = CGPointMake(contentOffset.x, border);
                [self layoutIfNeeded];
            }];
        }else{
            CGFloat velocity = [pan velocityInView:self.headerView].y;
            [self deceleratingAnimator:velocity];
        }
    }
    // 清零防止偏移累计
    [pan setTranslation:CGPointZero inView:self.headerView];
    
}

- (void)rollingPointy:(CGFloat)pointy{
    
    CGPoint contentOffset = self.currentScrollView.contentOffset;
    CGFloat border = - self.headerViewHeight - [self.delegate segmentHeightInPagingView:self];
    CGFloat offsety = contentOffset.y - pointy * (1/contentOffset.y * border * 0.8);
    self.currentScrollView.contentOffset = CGPointMake(contentOffset.x, offsety);
}

- (void)deceleratingAnimator:(CGFloat)velocity{
    
    if (self.inertialBehavior != nil) {
        [self.animator removeBehavior:self.inertialBehavior];
    }
    DynamicItem *item = [[DynamicItem alloc] init];
    item.center = CGPointMake(0, 0);
    // velocity是在手势结束的时候获取的竖直方向的手势速度
    UIDynamicItemBehavior *inertialBehavior = [[UIDynamicItemBehavior alloc] initWithItems:@[ item ]];
    [inertialBehavior addLinearVelocity:CGPointMake(0, velocity * 0.025) forItem:item];
    // 通过尝试取2.0比较像系统的效果
    inertialBehavior.resistance = 2;
    
    __weak typeof(self)weakSelf = self;
    CGFloat maxOffset = self.currentScrollView.contentSize.height - self.currentScrollView.bounds.size.height;
    inertialBehavior.action = ^{
        
        CGPoint contentOffset = self.currentScrollView.contentOffset;
        CGFloat speed = [weakSelf.inertialBehavior linearVelocityForItem:item].y;
        CGFloat offset = contentOffset.y -  speed;
        
        if (speed >= -0.2) {
            
            [weakSelf.animator removeBehavior:weakSelf.inertialBehavior];
            weakSelf.inertialBehavior = nil;
        }else if (offset >= maxOffset){
            
            [weakSelf.animator removeBehavior:weakSelf.inertialBehavior];
            weakSelf.inertialBehavior = nil;
            offset = maxOffset;
            [UIView animateWithDuration:0.2 animations:^{
                weakSelf.currentScrollView.contentOffset = CGPointMake(contentOffset.x, offset - speed);
                [weakSelf layoutIfNeeded];
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.25 animations:^{
                    weakSelf.currentScrollView.contentOffset = CGPointMake(contentOffset.x, offset);
                    [weakSelf layoutIfNeeded];
                }];
            }];
        }else{
            
            self.currentScrollView.contentOffset = CGPointMake(contentOffset.x, offset);
        }
    };
    self.inertialBehavior = inertialBehavior;
    [self.animator addBehavior:inertialBehavior];
}


#pragma mark - Setter
- (void)setSegmentButtonSize:(CGSize)segmentButtonSize {
    _segmentButtonSize = segmentButtonSize;
    [self configureSegmentButtonLayout];
    
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
  
    return [self.delegate numberOfSectionsInPagingView:self];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    self.isSwitching = YES;
    NSString* key = [self cellReuseIdentifierForIndex:indexPath.row];
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:key forIndexPath:indexPath];
    UIScrollView *v = [self scrollViewAtIndex:indexPath.row];
  
  // 只有在cell未添加scrollView时才添加，让以下代码只在需要时执行
  if (cell.contentView.tag != v.tag) {
    
    cell.backgroundColor = [UIColor clearColor];
    for(UIView *v in cell.contentView.subviews) {
      [v removeFromSuperview];
    }
    cell.tag = v.tag;
    UIViewController *vc = [self viewControllerForView:v];
    // 如果为空表示 v还没有响应者，在部分机型上出现该问题，情况不明先这么看看
      [cell.contentView addSubview:vc.view];
      cell.tag = v.tag;
      CGFloat scrollViewHeight = vc.view.frame.size.height;
      vc.view.translatesAutoresizingMaskIntoConstraints = NO;
      [cell.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:cell.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
      [cell.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:cell.contentView attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
      [cell.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:cell.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:scrollViewHeight == 0 ? 0 : -(cell.contentView.frame.size.height-vc.view.frame.size.height)]];
      [cell.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:cell.contentView attribute:NSLayoutAttributeRight multiplier:1 constant:0]];

     [cell layoutIfNeeded];
  }
  
  
    self.currentScrollView = v;
    [self adjustOffsetContentView:v];
    return cell;
    
}

#pragma mark - Observer
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(__unused id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    
    if(context == &HHHorizontalPagingViewPanContext) {
        self.isDragging = YES;
        self.horizontalCollectionView.scrollEnabled = YES;
        UIGestureRecognizerState state = [change[NSKeyValueChangeNewKey] integerValue];
        //failed说明是点击事件
        if(state == UIGestureRecognizerStateFailed) {
            if(self.currentTouchButton) {
                [self segmentButtonEvent:self.currentTouchButton];
            }else if(self.currentTouchView) {
                [self.currentTouchView viewWasTappedPoint:self.currentTouchViewPoint];
            }
            self.currentTouchView = nil;
            self.currentTouchButton = nil;
        }else if (state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateEnded) {
            self.isDragging = NO;
        }
        
    }else if (context == &HHHorizontalPagingViewScrollContext) {
        
        self.currentTouchView = nil;
        self.currentTouchButton = nil;
        if (self.isSwitching) {
            return;
        }
        
        // 触发如果不是当前 ScrollView 不予响应
        if (object != self.currentScrollView) {
            return;
        }
        
        if ([self.delegate respondsToSelector:@selector(pagingView:scrollViewDidScroll:)]) {
            [self.delegate pagingView:self scrollViewDidScroll:self.currentScrollView];
        }
        
        CGFloat oldOffsetY          = [change[NSKeyValueChangeOldKey] CGPointValue].y;
        CGFloat newOffsetY          = [change[NSKeyValueChangeNewKey] CGPointValue].y;
        CGFloat deltaY              = newOffsetY - oldOffsetY;
        
        CGFloat headerViewHeight    = self.headerViewHeight;
        CGFloat headerDisplayHeight = self.headerViewHeight+self.headerOriginYConstraint.constant;
        
        CGFloat py = 0;
        if(deltaY >= 0) {    //向上滚动
            
            if(headerDisplayHeight - deltaY <= self.segmentTopSpace) {
                py = -headerViewHeight+self.segmentTopSpace;
            }else {
                py = self.headerOriginYConstraint.constant - deltaY;
            }
            if(headerDisplayHeight <= self.segmentTopSpace) {
                py = -headerViewHeight+self.segmentTopSpace;
            }
            
            if (!self.allowPullToRefresh) {
                self.headerOriginYConstraint.constant = py;
                
            }else if (py < 0 && !self.currentScrollView.hhh_isRefresh && !self.currentScrollView.hhh_startRefresh) {
                self.headerOriginYConstraint.constant = py;
                
            }else{
                
                if (self.currentScrollView.contentOffset.y >= -headerViewHeight -  self.segmentBarHeight) {
                    self.currentScrollView.hhh_startRefresh = NO;
                }
                self.headerOriginYConstraint.constant = 0;
            }
            
            
        }else {            //向下滚动
            
            if (headerDisplayHeight+self.segmentBarHeight < -newOffsetY) {
                py = -self.headerViewHeight-self.segmentBarHeight-self.currentScrollView.contentOffset.y;
                
                if (!self.allowPullToRefresh) {
                    self.headerOriginYConstraint.constant = py;
                    
                }else if (py <0) {
                    self.headerOriginYConstraint.constant = py;
                } else{
                    self.currentScrollView.hhh_startRefresh = YES;
                    self.headerOriginYConstraint.constant = 0;
                }
            }
            
        }
        
        
        if (self.headerOriginYConstraint.constant > 0) {
            
            self.contentOffset = CGPointMake(0, -self.headerOriginYConstraint.constant);
            NSLog(@"contentOffset %f",self.contentOffset.y);
            if (!self.allowPullToRefresh && [self.delegate respondsToSelector:@selector(pagingView:scrollTopOffset:)]) {
                [self.delegate pagingView:self scrollTopOffset:-self.headerOriginYConstraint.constant];
            }
        }
        
        
    }else if(context == &HHHorizontalPagingViewInsetContext) {
        
        if(self.allowPullToRefresh || self.currentScrollView.contentOffset.y > -self.segmentBarHeight) {
            return;
        }
        [UIView animateWithDuration:0.2 animations:^{
            self.headerOriginYConstraint.constant = -self.headerViewHeight-self.segmentBarHeight-self.currentScrollView.contentOffset.y;
            [self layoutIfNeeded];
            [self.headerView layoutIfNeeded];
            [self.segmentView layoutIfNeeded];
        }];
        
    }
    
}

- (void)refreshStart:(NSNotification *)notification{
    UIScrollView *obj = notification.object;
    [self.contentViewArray enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull scrollView, NSUInteger idx, BOOL * _Nonnull stop) {
      if (obj == scrollView) {
        scrollView.hhh_startRefresh = YES;
        scrollView.hhh_isRefresh = YES;
        *stop = YES;
      }
    }];
}

- (void)refreshEnd:(NSNotification *)notification{
    UIScrollView *obj = notification.object;
    [self.contentViewArray enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull scrollView, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj == scrollView) {
            scrollView.hhh_startRefresh = NO;
            scrollView.hhh_isRefresh = NO;
            *stop = YES;
        }
    }];
}


// 视图切换时执行代码
- (void)didSwitchIndex:(NSInteger)aIndex to:(NSInteger)toIndex{
    
    self.currenPage = toIndex;
    self.currentScrollView = [self scrollViewAtIndex:toIndex];
    
    if (aIndex == toIndex) {
        return;
    }
  
    UIScrollView *oldScrollView = [self scrollViewAtIndex:aIndex];
    if (oldScrollView.hhh_isRefresh) {
        oldScrollView.hhh_startRefresh = NO;
        oldScrollView.hhh_isRefresh = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:kHHHorizontalTakeBackRefreshEndNotification object:[self scrollViewAtIndex:aIndex]];
    }
    
    [self setSelectedButPage:toIndex];
    [self removeCacheScrollView];
  
    if ([self.delegate respondsToSelector:@selector(pagingView:didSwitchIndex:to:)]) {
      [self.delegate pagingView:self didSwitchIndex:aIndex to:toIndex];
    }
  
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {

    self.isScroll = YES;
    CGFloat offsetpage = scrollView.contentOffset.x/[[UIScreen mainScreen] bounds].size.width;
    CGFloat py = fabs((int)offsetpage - offsetpage);
    if ( py <= 0.3 || py >= 0.7) {
        return;
    }

    NSInteger currentPage = self.currenSelectedBut;
    if (offsetpage - currentPage > 0) {
        if (py > 0.55) {
           [self setSelectedButPage:currentPage + 1];
        }
    }else{
        if (py < 0.45) {
            [self setSelectedButPage:currentPage - 1];
        }
    }

}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {

    if (!self.isScroll) { // 是否左右滚动  防止上下滚动的触发
        return;
    }
    
    self.isScroll = NO;
    NSInteger currentPage = scrollView.contentOffset.x/[[UIScreen mainScreen] bounds].size.width;
    [self didSwitchIndex:self.currenPage to:currentPage];
}

- (void)setSelectedButPage:(NSInteger)buttonPage{
    for(UIButton *b in self.segmentButtons) {
        if(b.tag - pagingButtonTag == buttonPage) {
            [b setSelected:YES];
        }else {
            [b setSelected:NO];
        }
    }
    self.currenSelectedBut = buttonPage;
}

- (void)removeCacheScrollView{
    
    if (self.contentViewArray.count <= self.maxCacheCout) {
        return;
    }
    [self releaseCache];
}

- (void)releaseCache{
    NSInteger currentCount = self.currentScrollView.tag;
    [self.contentViewArray enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull scrollView, NSUInteger idx, BOOL * _Nonnull stop) {
        if (labs(scrollView.tag - currentCount) > 1) {
            [self removeScrollView:scrollView];
        }
    }];
}

- (void)removeScrollView:(UIScrollView *)scrollView{
  
  [self removeObserverFor:scrollView];
  [self.contentViewArray removeObject:scrollView];
  UIViewController *vc = [self viewControllerForView:scrollView];
  vc.view.tag = 0;
  scrollView.superview.tag = 0;
  vc.view.superview.tag = 0;
  [scrollView removeFromSuperview];
  [vc.view removeFromSuperview];
  [vc removeFromParentViewController];
}

- (UIViewController *)viewControllerForView:(UIView *)view {
    for (UIView* next = view; next; next = next.superview) {
        UIResponder *nextResponder = [next nextResponder];
        if ([nextResponder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)nextResponder;
        }
    }
    return nil;
}

- (void)removeObserverFor:(UIScrollView *)scrollView{
    [scrollView.panGestureRecognizer removeObserver:self forKeyPath:NSStringFromSelector(@selector(state)) context:&HHHorizontalPagingViewPanContext];
    [scrollView removeObserver:self forKeyPath:NSStringFromSelector(@selector(contentOffset)) context:&HHHorizontalPagingViewScrollContext];
    [scrollView removeObserver:self forKeyPath:NSStringFromSelector(@selector(contentInset)) context:&HHHorizontalPagingViewInsetContext];
}

- (void)dealloc {
    [self.contentViewArray enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self removeObserverFor:obj];
    }];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - 懒加载
- (UIDynamicAnimator *)animator{
    if (!_animator) {
        _animator = [[UIDynamicAnimator alloc] init];
    }
    return _animator;
}

- (NSMutableArray *)segmentButtonConstraintArray{
    if (!_segmentButtonConstraintArray) {
        _segmentButtonConstraintArray = [NSMutableArray array];
    }
    return _segmentButtonConstraintArray;
}

- (NSMutableArray<UIScrollView *> *)contentViewArray{
    if (!_contentViewArray) {
        _contentViewArray = [[NSMutableArray alloc] init];
    }
    return _contentViewArray;
}

- (CGFloat)maxCacheCout{
    if (_maxCacheCout == 0) {
        _maxCacheCout = 3;
    }
    return _maxCacheCout;
}

@end

