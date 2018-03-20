//
//  PLVLivePlayerController.m
//  PolyvIJKLivePlayer
//
//  Created by ftao on 2016/12/16.
//  Copyright © 2016年 easefun. All rights reserved.
//

#import "PLVLivePlayerController.h"
#import "PLVLivePlayerControllerSkin.h"

NSString * const PLVLivePlayerReconnectNotification = @"PLVLivePlayerReconnectNotification";
NSString * const PLVLivePlayerWillChangeToFullScreenNotification = @"PLVLivePlayerWillChangeToFullScreenNotification";
NSString * const PLVLivePlayerWillExitFullScreenNotification = @"PLVLivePlayerWillExitFullScreenNotification";

#define PlayerErrorDomain @"net.polyv.live"
#define PlayerVersion @"iOS-livePlayerSDK2.3.0+180320"

#define PLAY_MODE @"live"   // 统计后台live/vod

@interface PLVLivePlayerController ()

@property (nonatomic, strong) NSURL *contentURL;
@property (nonatomic, strong) PLVLivePlayerControllerSkin *playerSkin;

@property (nonatomic, weak) UIView *displayView;    // 引用外部的显示层
@property (nonatomic, assign) CGRect originFrame;   // 初始设置的frame

@property (nonatomic, getter=isShowCover) BOOL showCover;
@property (nonatomic, strong) IJKFFMoviePlayerController *subPlayer;

@end

@implementation PLVLivePlayerController {
    NSTimer *_liveStatusTimer;
    NSTimer *_playerPollingTimer;
    
    /** 直播服务质量/观看统计*/
    NSString *_pid;
    NSDate *_firstLoadStartDate;
    NSDate *_secondBufferStartDate;
    BOOL _isFirstLoadTimeSent;
    BOOL _isSecondBufferTimeSent;
    BOOL _isPlayerErrorSend;
    NSInteger _reportFreq;
    int _watchTimeDuration;
    int _stayTimeDuration;
}

#pragma mark - Property/rewrite

- (void)play {
    [super play];
    [self.playerSkin addVideoInfoWithDescription:@"视频加载中..."];
}

- (PLVLivePlayerControllerSkin *)playerSkin {
    if (!_playerSkin) {
        _playerSkin = [[PLVLivePlayerControllerSkin alloc] init];
    }
    return _playerSkin;
}

- (void)setFrame:(CGRect)frame {
    _frame = frame;
    self.displayView.frame = frame;
}

- (void)setChannel:(PLVLiveChannel *)channel {
    _channel = channel;
    _reportFreq = channel.reportFreq.integerValue;
}

- (void)setStreamState:(PLVLiveStreamState)streamState {
    if (streamState == PLVLiveStreamStateNoStream) {
        if (self.playerSkin.noLiveImageView.isHidden) {
            [self.playerSkin.noLiveImageView setHidden:NO];
            [self.playerSkin.indicatorView stopAnimating];
            [self.playerSkin hideVideoInfo];
            [self shutdown];    // 播放器停止
        }
        if (_streamState == PLVLiveStreamStateLive) {
            [self playWithCover];
        }
    }else if (streamState == PLVLiveStreamStateLive && _streamState == PLVLiveStreamStateNoStream) {
        [self.playerSkin.noLiveImageView setHidden:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:PLVLivePlayerReconnectNotification object:nil];
    }
    _streamState = streamState;
}

#pragma mark - Initialization methods

- (instancetype)initWithChannel:(PLVLiveChannel *)channel displayView:(UIView *)displayView playHLS:(BOOL)playHLS {
    if (playHLS) {
        self.channel = channel;
        NSURL *aUrl = [NSURL URLWithString:channel.m3u8Url]; // 拉流地址为M3U8
        return [self initWithContentURL:aUrl displayView:displayView];
    }else {
        return [self initWithChannel:channel displayView:displayView];
    }
}

- (instancetype)initWithChannel:(PLVLiveChannel *)channel displayView:(UIView *)displayView {
    self.channel = channel;
    
    NSURL *aUrl = [NSURL URLWithString:channel.flvUrl]; // 默认拉流地址为FLV格式
    return [self initWithContentURL:aUrl displayView:displayView];
}

- (instancetype)initWithContentURLString:(NSString *)aUrlString displayView:(UIView *)displayView {
    NSURL *aUrl = [NSURL URLWithString:aUrlString];
    return [self initWithContentURL:aUrl displayView:displayView];
}

- (instancetype)initWithContentURL:(NSURL *)aUrl displayView:(UIView *)displayView {
    [self.playerSkin addVideoInfoWithDescription:@"初始化播放器..."];
    self.contentURL = aUrl;
    _firstLoadStartDate = [NSDate date];
    
    IJKFFOptions *options = [IJKFFOptions optionsByDefault];
    [options setPlayerOptionIntValue:1 forKey:@"videotoolbox"];
    [options setCodecOptionIntValue:IJK_AVDISCARD_DEFAULT forKey:@"skip_frame"];
    [options setCodecOptionIntValue:IJK_AVDISCARD_DEFAULT forKey:@"skip_loop_filter"];
    // drop frames when cpu is too slow
    [options setPlayerOptionIntValue:5 forKey:@"framedrop"];
    // don't limit the input buffer size (useful with realtime streams)
    [options setPlayerOptionIntValue:1 forKey:@"infbuf"]; // 无限读
    // specify how many microseconds are analyzed to probe the input (from 0 to I64_MAX)
    [options setFormatOptionValue:@"500000" forKey:@"analyzeduration"]; // 播放前的探测时间
    // set probing size (from 32 to I64_MAX)
    [options setFormatOptionValue:@"4096" forKey:@"probesize"]; // 播放前的探测Size，默认是1M
    
    self = [super initWithContentURL:aUrl withOptions:options];
    if (self) {
        [PLVLiveConfig setPlayerVersion:PlayerVersion];
        [[PLVLiveConfig sharedInstance] resetPlayerId];
        _pid = [PLVLiveConfig sharedInstance].playerId;
        
        [self prepareToPlay];
        [self setShouldAutoplay:YES];
        [self setScalingMode:IJKMPMovieScalingModeAspectFit];
        //[self setPauseInBackground:NO];   // 后台播放模式(后台音频输出，还需在工程中打开后台音乐权限UIBackgroundModes：Audio，Airplay...)
        
        self.displayView = displayView;
        self.originFrame = displayView.bounds;
        self.streamState = PLVLiveStreamStateUnknown;
        
        // 添加IJK播放器至displayView
        self.view.frame = displayView.bounds;
        self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [displayView addSubview:self.view];
        
        // 添加皮肤视图至IJK播放器
        self.playerSkin.frame = self.view.bounds;
        self.playerSkin.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.playerSkin];
        
        [self addPlayerSkinActions];
        [self configObservers];
        [self addGestureActions];
        [self addTimerEvents];
        
        [self.playerSkin.indicatorView startAnimating];
        [self.playerSkin addVideoInfoWithDescription:@"播放器初始化完成"];
    }
    return self;
}

#pragma mark - Initial configuration

- (void)configObservers {
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self selector:@selector(movieNaturalSizeAvailable:) name:IJKMPMovieNaturalSizeAvailableNotification object:self];
    
    [defaultCenter addObserver:self selector:@selector(mediaPlaybackIsPreparedToPlay:) name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification object:self];
    
    [defaultCenter addObserver:self selector:@selector(moviePlayerLoadStateDidChange:) name:IJKMPMoviePlayerLoadStateDidChangeNotification object:self];
    [defaultCenter addObserver:self selector:@selector(moviePlayerPlaybackStateDidChange:) name:IJKMPMoviePlayerPlaybackStateDidChangeNotification object:self];
    [defaultCenter addObserver:self selector:@selector(moviePlayerPlaybackDidFinish:) name:IJKMPMoviePlayerPlaybackDidFinishNotification object:self];
    
    [defaultCenter addObserver:self selector:@selector(moviePlayerVideoDecoderOpen:) name:IJKMPMoviePlayerVideoDecoderOpenNotification object:self];
    //[defaultCenter addObserver:self selector:@selector(moviePlayerFirstVideoFrameRendered:) name:IJKMPMoviePlayerFirstVideoFrameRenderedNotification object:self];
    //[defaultCenter addObserver:self selector:@selector(moviePlayerFirstAudioFrameRendered:) name:IJKMPMoviePlayerFirstAudioFrameRenderedNotification object:self];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [defaultCenter addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)addPlayerSkinActions {
    [self.playerSkin.returnButton addTarget:self action:@selector(returnButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.playerSkin.playButton addTarget:self action:@selector(playButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.playerSkin.pauseButton addTarget:self action:@selector(pauseButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.playerSkin.fullScreenButton addTarget:self action:@selector(fullScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.playerSkin.smallScreenButton addTarget:self action:@selector(smallScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addGestureActions {
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(screenBeClicked)];
    [self.view addGestureRecognizer:tapGesture];
}

- (void)addTimerEvents {
    _liveStatusTimer = [NSTimer scheduledTimerWithTimeInterval:6.0 target:self
                                                      selector:@selector(onTimeCheckLiveStreamState) userInfo:nil repeats:YES];
    _playerPollingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                         selector:@selector(playerPollingTimerTick) userInfo:nil repeats:YES];
    [_liveStatusTimer fire];
    // timeout logic
}

#pragma mark - Notifications

#pragma mark player
// -----------------------------------------------------------------------------
// Movie Property Notifications
- (void)movieNaturalSizeAvailable:(NSNotification *)notification {
    DLog("获取到视频信息")
}

// -----------------------------------------------------------------------------
//  MPMediaPlayback.h
- (void)mediaPlaybackIsPreparedToPlay:(NSNotification *)notification {
    [self.playerSkin addVideoInfoWithDescription:@"视频即将播放"];
}

// -----------------------------------------------------------------------------
//  MPMoviePlayerController.h
//  Movie Player Notifications

- (void)moviePlayerLoadStateDidChange:(NSNotification *)notification {
    DLog()
    if (self.loadState & IJKMPMovieLoadStateStalled) {
        [self.playerSkin.indicatorView startAnimating];
        if (_isFirstLoadTimeSent && !_isSecondBufferTimeSent) _secondBufferStartDate = [NSDate date];
    }else {
        [self.playerSkin.indicatorView stopAnimating];
    }
    
    if (self.loadState & IJKMPMovieLoadStatePlaythroughOK) {
        [self reportFirstLoading];   // 发送首次加载时长（二次缓冲时长）
    }
}

- (void)moviePlayerPlaybackStateDidChange:(NSNotification *)notification {
    if (self.playbackState==IJKMPMoviePlaybackStatePlaying) {
        DLog("开始播放")
        [self.playerSkin hideVideoInfo];
        [self.playerSkin.playButton setHidden:YES];
        [self.playerSkin.pauseButton setHidden:NO];
        [self.playerSkin.indicatorView stopAnimating];
    }else if (self.playbackState==IJKMPMoviePlaybackStateStopped || self.playbackState==IJKMPMoviePlaybackStatePaused) {
        DLog("暂停/停止播放")
        [self.playerSkin.playButton setHidden:NO];
        [self.playerSkin.pauseButton setHidden:YES];
    }
}

- (void)moviePlayerPlaybackDidFinish:(NSNotification *)notification {
    DLog()
    NSDictionary *dict = [notification userInfo];
    NSNumber *finishReason =  dict[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    switch (finishReason.integerValue) {
        case IJKMPMovieFinishReasonPlaybackEnded: {
            DLog("IJKMPMovieFinishReasonPlaybackEnded")
            [self.playerSkin.playButton setHidden:NO];
            [self.playerSkin.pauseButton setHidden:YES];
        } break;
        case IJKMPMovieFinishReasonPlaybackError: {
            DLog("IJKMPMovieFinishReasonPlaybackError")
            [self.playerSkin addVideoInfoWithDescription:@"出错啦~"];
            [self.playerSkin.indicatorView stopAnimating];
            // 重连通知只能在Error类型下，end下可能播放完但还没获取到流状态 TODO：重试次数限制
            [[NSNotificationCenter defaultCenter] postNotificationName:PLVLivePlayerReconnectNotification object:nil];
            [self playbackFailureAnalysis];   // 播放器出错分析
        } break;
        case IJKMPMovieFinishReasonUserExited: {
            DLog("IJKMPMovieFinishReasonUserExited")
        } break;
        default: break;
    }
}

// -----------------------------------------------------------------------------
//  Extend Notifications

- (void)moviePlayerVideoDecoderOpen:(NSNotification *)notifacation {
    DLog("播放器编码器打开")
}

- (void)moviePlayerFirstVideoFrameRendered:(NSNotification *)notification {
    DLog()
}

- (void)moviePlayerFirstAudioFrameRendered:(NSNotification *)notification {
    DLog()
}

#pragma mark device rotation
- (void)deviceOrientationDidChange {
    UIInterfaceOrientation interfaceOrientation = (UIInterfaceOrientation)[[UIDevice currentDevice] orientation];
    switch (interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            [self setOrientationPortrait];
            break;
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
            [self setOrientationLandscape];
        default:
            break;
    }
}

#pragma mark - 播放器点击事件处理

- (void)returnButtonClick {
    if (CGRectEqualToRect(self.view.frame, [UIScreen mainScreen].bounds)) {
        // 当前控制器旋转至竖屏
        [self setOrientation:UIInterfaceOrientationPortrait];
    }else {
        [self clearPlayer];
        if (self.returnButtonClickBlcok) self.returnButtonClickBlcok();
    }
}

- (void)playButtonClick {
    [self play];
    [self.playerSkin.playButton setHidden:YES];
    [self.playerSkin.pauseButton setHidden:NO];
    
    if (self.playButtonClickBlcok) self.playButtonClickBlcok();
}

- (void)pauseButtonClick {
    [self pause];
    [self.playerSkin.pauseButton setHidden:YES];
    [self.playerSkin.playButton setHidden:NO];
    
    if (self.pauseButtonClickBlcok) self.pauseButtonClickBlcok();
}

- (void)fullScreenButtonClick {
    [self.playerSkin.fullScreenButton setHidden:YES];
    [self.playerSkin.smallScreenButton setHidden:NO];
    
    // 当前控制器旋转至横屏
    [self setOrientation:UIInterfaceOrientationLandscapeRight];
    
    if (self.fullScreenButtonClickBlcok) self.fullScreenButtonClickBlcok();
}

- (void)smallScreenButtonClick {
    // 当前控制器旋转至竖屏
    [self setOrientation:UIInterfaceOrientationPortrait];
    
    if (self.smallScreenButtonClickBlcok) self.smallScreenButtonClickBlcok();
}

- (void)screenBeClicked {
    if (self.isShowCover) {
        if (self.coverImageBeClickedBlcok && self.channel.coverHref) {
            self.coverImageBeClickedBlcok(self.channel.coverHref);
        }
    }else {
        if (self.playerSkin.isSkinShowing) {
            [self.playerSkin animateHideSkin];
        }else {
            [self.playerSkin animateShowSkin];
        }
    }
}

#pragma mark - Public methods
// set title、screen rotation notification/callback、fullscreen style

 /// 播放暖场（视频/图片）
- (void)playWithCover {
    if (self.channel) {
        self.showCover = YES;
        if (self.channel.coverType == PLVLiveCoverTypeImage) {
            [self playWithImageCover];
        }else if (self.channel.coverType == PLVLiveCoverTypeVideo) {
            [self playWithVideoCover];
        }else {
        }
    }
}

+ (NSArray *)getSDKVersion {
    return @[PlayerVersion];
}

- (void)insertDanmuView:(UIView *)danmuView {
    [self.playerSkin insertSubview:danmuView belowSubview:self.playerSkin.topBar];
}

- (void)clearPlayer {
    [self clearSubPlayer];
    if (_liveStatusTimer) {
        [_liveStatusTimer invalidate];
        _liveStatusTimer = nil;
    }
    if (_playerPollingTimer) {
        [_playerPollingTimer invalidate];
        _playerPollingTimer = nil;
    }
    @try {
        [self shutdown];
        [self.view removeFromSuperview];
    } @catch (NSException *exception) {
        DLog("shutdown failure, exception name: %@, exception reason: %@",exception.name,exception.reason)
    }
}

#pragma mark - SubPlayer

- (void)clearSubPlayer {
    if (self.subPlayer) {
        [self.subPlayer shutdown];
        [self.subPlayer.view removeFromSuperview];
    }
}

#pragma mark - Private methods

- (void)playWithImageCover {
    __weak typeof(self)weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:self.channel.coverUrl] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error) {
            [self.playerSkin addVideoInfoWithDescription:@"暖场图片请求失败"];
            NSLog(@"暖场图片请求失败，%@",error);
        }else if ([httpResponse statusCode] == 200){
            UIImage *coverImg = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageView *coverView = [[UIImageView alloc] initWithImage:coverImg];
                coverView.frame = weakSelf.playerSkin.noLiveImageView.bounds;
                coverView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [weakSelf.playerSkin.noLiveImageView addSubview:coverView];
                [weakSelf.playerSkin.bottomBar setHidden:YES];
            });
        }else {
            NSString *errDesc =[NSString stringWithFormat:@"暖场图片请求失败，响应非200 %ld",httpResponse.statusCode];
            [self.playerSkin addVideoInfoWithDescription:errDesc];
            NSLog(@"%@",errDesc);
        }
    }] resume];
}

- (void)playWithVideoCover {
    if (self.channel.coverUrl) {
        IJKFFOptions *options = [IJKFFOptions optionsByDefault];
        [options setPlayerOptionIntValue:0 forKey:@"loop"];
        [options setPlayerOptionIntValue:1 forKey:@"videotoolbox"];
        [options setCodecOptionIntValue:IJK_AVDISCARD_DEFAULT forKey:@"skip_frame"];
        [options setCodecOptionIntValue:IJK_AVDISCARD_DEFAULT forKey:@"skip_loop_filter"];
        self.subPlayer = [[IJKFFMoviePlayerController alloc] initWithContentURL:[NSURL URLWithString:self.channel.coverUrl] withOptions:options];
        self.subPlayer.view.frame = self.playerSkin.noLiveImageView.bounds;
        self.subPlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self.playerSkin.noLiveImageView addSubview:self.subPlayer.view];
        
        self.subPlayer.scalingMode = IJKMPMovieScalingModeAspectFit;
        self.subPlayer.shouldAutoplay = YES;
        self.subPlayer.allowsMediaAirPlay = NO;
        [self.subPlayer prepareToPlay];
        [self.subPlayer play];
        
        [self.playerSkin.bottomBar setHidden:YES];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subPlayerDidFinish:) name:IJKMPMoviePlayerPlaybackDidFinishNotification object:self.subPlayer];
    }
}

- (void)subPlayerDidFinish:(NSNotification *)notification {
    DLog()
    NSDictionary *dict = [notification userInfo];
    NSNumber *finishReason =  dict[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    if (finishReason.integerValue == IJKMPMovieFinishReasonPlaybackError) {
        [self.playerSkin addVideoInfoWithDescription:@"暖场视频播放失败"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.playerSkin hideVideoInfo];
        });
    }
}

- (void)onTimeCheckLiveStreamState {
    [PLVLiveAPI isLiveWithStream:self.channel.stream completion:^(PLVLiveStreamState streamState) {
        [self setStreamState:streamState];
    } failure:^(PLVLiveErrorCode errorCode, NSString *description) {
        NSLog(@"获取流状态失败 %@",description);
    }];
}

- (void)setOrientation:(UIInterfaceOrientation)orientation {
    if ([[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
        SEL selector = NSSelectorFromString(@"setOrientation:");
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:[UIDevice currentDevice]];
        int val = orientation;
        [invocation setArgument:&val atIndex:2];
        [invocation invoke];
    }
}

- (void)setOrientationLandscape {
    [[NSNotificationCenter defaultCenter] postNotificationName:PLVLivePlayerWillChangeToFullScreenNotification object:self];    // 发送全屏通知
    [UIView animateWithDuration:0.3 animations:^{
        self.frame = [UIScreen mainScreen].bounds;
        [self.playerSkin changeToFullScreen];
        // 发送全屏通知
    } completion:^(BOOL finished) {
        [self.playerSkin.fullScreenButton setHidden:YES];
        [self.playerSkin.smallScreenButton setHidden:NO];
    }];
}

- (void)setOrientationPortrait {
    [[NSNotificationCenter defaultCenter] postNotificationName:PLVLivePlayerWillExitFullScreenNotification object:self];    // 发送退出全屏通知
    [UIView animateWithDuration:0.3 animations:^{
        self.frame = self.originFrame;
        [self.playerSkin changeToSmallScreen];
    } completion:^(BOOL finished) {
        [self.playerSkin.smallScreenButton setHidden:YES];
        [self.playerSkin.fullScreenButton setHidden:NO];
    }];
}

#pragma mark - 直播服务质量统计Qos/ViewLog

- (void)reportFirstLoading {
    if (_isFirstLoadTimeSent) {
        [self reportSecondBuffer];
        return;
    }
    _isFirstLoadTimeSent = YES;
    
    double diffTime = [[NSDate date] timeIntervalSinceDate:_firstLoadStartDate];
    [PLVLiveReporter reportLoadingWithChannel:self.channel pid:_pid time:(int)floor(diffTime*1000)];
}

- (void)reportSecondBuffer {
    if (_isSecondBufferTimeSent) return;
    _isSecondBufferTimeSent = YES;
    
    double diffTime = [[NSDate date] timeIntervalSinceDate:_secondBufferStartDate];
    [PLVLiveReporter reportBufferWithChannel:self.channel pid:_pid time:(int)floor(diffTime*1000)];
}

- (void)playbackFailureAnalysis {
    if (_isPlayerErrorSend) return;
    _isPlayerErrorSend = YES;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:self.contentURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSInteger responseCode = [(NSHTTPURLResponse *)response statusCode];    // 服务器响应的状态码
        NSString *errorCode = [NSString new];                                   // 播放错误代码
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"null" forKey:NSLocalizedDescriptionKey];
        NSError *playErr = [NSError errorWithDomain:PlayerErrorDomain code:-100 userInfo:userInfo]; // 播放错误内容描述
        
        if (error) {
            errorCode = @"load_livevideo_failure";  // 加载直播失败
            playErr = error;
        }else if (responseCode != 200) {
            if (responseCode == 403) {
                errorCode = @"stream_403_error";    // 加载403错误
            }else {
                errorCode = @"stream_NOT200_error"; // 加载非200错误
            }
        }else {
            errorCode = @"other_error";             // 其他播放问题
        }
        NSString *errormsg = [NSString stringWithFormat:@"code:%ld,reason:%@",(long)playErr.code,playErr.localizedDescription];
        [PLVLiveReporter reportErrorWithChannel:self.channel pid:_pid uri:self.contentURL.absoluteString status:[NSString stringWithFormat:@"%ld",(long)responseCode] errorcode:errorCode errormsg:errormsg];
    }] resume];
}

- (void)playerPollingTimerTick {
    ++ _stayTimeDuration;
    if (self.playbackState & IJKMPMoviePlaybackStatePlaying) {
        ++ _watchTimeDuration;
        if ( _watchTimeDuration%_reportFreq == 0) {
            [PLVLiveReporter playStatusWithChannel:self.channel pid:_pid flow:0 pd:_watchTimeDuration sd:_stayTimeDuration param3:PLAY_MODE];
        }
    }
}

#pragma mark - dealloc
- (void)dealloc {
    DLog()
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

@end
