//
//  FTPageController.m
//  FTPageController
//
//  Created by ftao on 04/01/2018.
//  Copyright © 2018 easefun. All rights reserved.
//

#import "FTPageController.h"
#import "FTTitleViewCell.h"

#define kWidth [UIScreen mainScreen].bounds.size.width
//#define kHeight [UIScreen mainScreen].bounds.size.height

static NSString *TitleCellIdentifier = @"PageTitleCell";

@interface FTPageController () <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UIPageViewControllerDataSource,UIPageViewControllerDelegate>

@property (nonatomic, strong) NSArray *titles;
@property (nonatomic, strong) NSArray *controllers;

@property (nonatomic, strong) UICollectionView *titleCollectionView;
@property (nonatomic, strong) UIPageViewController *pageViewController;

@property (nonatomic) NSUInteger nextIndex;

@end

@implementation FTPageController

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles controllers:(NSArray<UIViewController *> *)controllers {
    self = [super init];
    if (self) {
        self.titles = [[NSArray alloc] initWithArray:titles];
        self.controllers = [[NSArray alloc] initWithArray:controllers];
        
        [self setupPageController];
        [self setupTitles];
    }
    return self;
}

#pragma mark -

-(void)setupTitles {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    self.titleCollectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, kWidth, topBarHeight) collectionViewLayout:layout];
    self.titleCollectionView.backgroundColor = [UIColor whiteColor];
    self.titleCollectionView.dataSource = self;
    self.titleCollectionView.delegate = self;
    self.titleCollectionView.allowsSelection = YES;
    [self.view addSubview:self.titleCollectionView];
    
    [self.titleCollectionView registerNib:[UINib nibWithNibName:@"FTTitleViewCell" bundle:nil] forCellWithReuseIdentifier:TitleCellIdentifier];
}

-(void)setupPageController {
    self.pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:nil];
    self.pageViewController.view.frame = CGRectMake(0, topBarHeight, kWidth, CGRectGetHeight(self.view.bounds)-topBarHeight);
    self.pageViewController.dataSource = self;
    self.pageViewController.delegate =self;
    NSArray *initControllers = @[self.controllers[0]];
    [self.pageViewController setViewControllers:initControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    [self.view addSubview:self.pageViewController.view];
    [self addChildViewController:self.pageViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
}

//-(void)viewDidAppear:(BOOL)animated{
//    [super viewDidAppear:animated];
//    [self selectedTitle:0];
//}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - <UICollectionViewDataSource>

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.titles.count;
}

-(UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    FTTitleViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TitleCellIdentifier forIndexPath:indexPath];
    cell.titleLabel.text = self.titles[indexPath.item];
    [cell setClicked:!indexPath.item];
    return cell;
}

#pragma mark - UICollectionViewLayout

-(CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return  CGSizeMake((kWidth-20)/(self.titles.count), CGRectGetHeight(collectionView.bounds));
}

-(UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(0, 10, 0, 10);
}

#pragma mark - UICollectionViewDeleaget

-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    // 清除标题选中状态，滑动切换时遗留的状态
    for (int i=0; i<self.titles.count; i++) {
        FTTitleViewCell *cell = (FTTitleViewCell *)[collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        [cell setClicked:NO];
    }
    
    FTTitleViewCell *cell = (FTTitleViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
    [cell setClicked:YES];
    
    // 跳转到指定页面
    NSArray *initControllers = @[self.controllers[indexPath.item]];
    [self.pageViewController setViewControllers:initControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
}

-(void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    FTTitleViewCell *cell = (FTTitleViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
    [cell setClicked:NO];
}

#pragma mark - <UIPageViewControllerDataSource>

-(UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
    NSUInteger index = [self indexOfViewController:viewController];
    if (index ==  NSNotFound ) {
        return nil;
    }
    if (index == 0 && self.circulation) {
        return [self viewControllerAtIndex:(self.controllers.count-1)];
    }
    index --;
    
    return [self viewControllerAtIndex:index];
}

-(UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
    NSUInteger index = [self indexOfViewController:viewController];
    if (index == NSNotFound ) {
        return nil;
    }
    index ++;
    
    if (index == self.controllers.count && self.circulation) {
        return [self viewControllerAtIndex:0];
    }
    if (index > self.controllers.count) {
        return nil;
    }
    
    return [self viewControllerAtIndex:index];
}

#pragma mark - <UIPageViewControllerDelegate>

-(void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray *)pendingViewControllers {
    NSUInteger index = [self indexOfViewController:pendingViewControllers.firstObject];
    self.nextIndex = index;
}

-(void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed {
    if (completed) {
        // 隐藏上次标题的指示器
        NSUInteger index = [self indexOfViewController:previousViewControllers.firstObject];
        [self deselectTitle:index];
        // 显示当前标题指示器
        [self selectedTitle:self.nextIndex];
    }
}

#pragma mark - Private methods

//（视图加载之后设置）
-(void)selectedTitle:(NSUInteger)index{
    NSIndexPath *selectedPath = [NSIndexPath indexPathForItem:index inSection:0];
    [self.titleCollectionView selectItemAtIndexPath:selectedPath animated:NO scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];
    FTTitleViewCell *cell = (FTTitleViewCell *)[self.titleCollectionView cellForItemAtIndexPath:selectedPath];
    [cell setClicked:YES];
}

-(void)deselectTitle:(NSUInteger)index{
    NSIndexPath *deselectedPath = [NSIndexPath indexPathForItem:index inSection:0];
    [self.titleCollectionView deselectItemAtIndexPath:deselectedPath animated:NO];
    FTTitleViewCell *cell = (FTTitleViewCell *)[self.titleCollectionView cellForItemAtIndexPath:deselectedPath];
    [cell setClicked:NO];
}

-(UIViewController *)viewControllerAtIndex:(NSUInteger)index {
    if (index == NSNotFound || index >=self.controllers.count ) {
        return nil;
    }
    return self.controllers[index];
}

-(NSUInteger)indexOfViewController:(UIViewController *)viewController {
    return [self.controllers indexOfObject:viewController];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
