//
//  NYTScalingImageView.m
//  NYTPhotoViewer
//
//  Created by Harrison, Andrew on 7/23/13.
//  Copyright (c) 2015 The New York Times Company. All rights reserved.
//

#import "NYTScalingImageView.h"

#import "tgmath.h"

#ifdef ANIMATED_GIF_SUPPORT
#import <FLAnimatedImage/FLAnimatedImage.h>
#endif

#import <AVFoundation/AVFoundation.h>

@interface NYTScalingImageView ()

- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_DESIGNATED_INITIALIZER;

#ifdef ANIMATED_GIF_SUPPORT
@property (nonatomic) FLAnimatedImageView *imageView;
#else
@property (nonatomic) UIImageView *imageView;
#endif

@property (nonatomic) NSURL *videoURL;

@property (nonatomic) UIView *playerView;

@property (nonatomic) AVPlayerItem *playerItem;
@property (nonatomic) AVPlayer *player;
@property (nonatomic) AVPlayerLayer *playerLayer;

@end

@implementation NYTScalingImageView

- (UIView *)contentView {
    if (self.player) {
        return self.playerView;
    }
    else {
        return self.imageView;
    }
}

#pragma mark - UIView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithImage:[UIImage new] frame:frame];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];

    if (self) {
        [self commonInitWithImage:nil imageData:nil];
    }

    return self;
}

- (void)didAddSubview:(UIView *)subview {
    [super didAddSubview:subview];
    [self centerScrollViewContents];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    
    if (self.playerLayer) {
        self.playerLayer.frame = self.playerView.bounds;
    }
    
    [self updateZoomScale];
    [self centerScrollViewContents];
}

#pragma mark - NYTScalingImageView

- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self commonInitWithImage:image imageData:nil];
    }
    
    return self;
}

- (instancetype)initWithImageData:(NSData *)imageData frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self commonInitWithImage:nil imageData:imageData];
    }
    
    return self;
}

- (instancetype)initWithVideoURL:(NSURL *)videoURL frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self commonInitWithVideoURL:videoURL];
    }
    
    return self;
}

- (void)dealloc {
    [self.player pause];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    
    [self.playerItem removeObserver:self forKeyPath:@"status"];
}

- (void)commonInitWithImage:(UIImage *)image imageData:(NSData *)imageData {
    [self setupInternalImageViewWithImage:image imageData:imageData];
    [self setupImageScrollView];
    [self updateZoomScale];
}

- (void)commonInitWithVideoURL:(NSURL *)videoURL {
    self.videoURL = videoURL;
    
    self.playerView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.playerView.hidden = YES;
    self.playerView.userInteractionEnabled = NO;
    self.playerView.backgroundColor = [UIColor blackColor];
    
    [self addSubview:self.playerView];
    
    self.contentSize = self.playerView.bounds.size;
    
    self.playerItem = [AVPlayerItem playerItemWithURL:videoURL];
    
    [self.playerItem addObserver:self forKeyPath:@"status" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
    
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    [self.playerView.layer addSublayer:self.playerLayer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePlayerItemDidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];

    [self.player play];
    
    [self updateZoomScale];
    [self centerScrollViewContents];
}

- (void)handlePlayerItemDidPlayToEndTime:(NSNotification *)notification {
    if (notification && notification.object == self.playerItem) {
        [self.player seekToTime:kCMTimeZero];
        [self.player play];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self.playerItem && change && [keyPath isEqualToString:@"status"]) {
        NSNumber *newValue = change[NSKeyValueChangeNewKey];
        
        if (newValue) {
            AVPlayerStatus status = (AVPlayerStatus)newValue.integerValue;
            
            if (status == AVPlayerStatusReadyToPlay) {
                CGSize naturalSize = self.playerItem.asset.naturalSize;

                CGRect newPlayerViewFrame = CGRectMake(0.0, 0.0, naturalSize.width, naturalSize.height);
                
                self.playerView.transform = CGAffineTransformIdentity;
                self.playerView.frame = newPlayerViewFrame;
                self.playerLayer.frame = newPlayerViewFrame;
                self.contentSize = newPlayerViewFrame.size;
                
                [self updateZoomScale];
                [self centerScrollViewContents];
                
                [self setNeedsLayout];
                [self layoutIfNeeded];
                
                self.playerView.hidden = NO;
                
                if (self.loadingDelegate && [self.loadingDelegate respondsToSelector:@selector(scalingImageView:didFinishedLoadingVideoAtURL:)]) {
                    [self.loadingDelegate scalingImageView:self didFinishedLoadingVideoAtURL:self.videoURL];
                }
            }
        }
    }
}

#pragma mark - Setup

- (void)setupInternalImageViewWithImage:(UIImage *)image imageData:(NSData *)imageData {
    UIImage *imageToUse = image ?: [UIImage imageWithData:imageData];

#ifdef ANIMATED_GIF_SUPPORT
    self.imageView = [[FLAnimatedImageView alloc] initWithImage:imageToUse];
#else
    self.imageView = [[UIImageView alloc] initWithImage:imageToUse];
#endif
    [self updateImage:imageToUse imageData:imageData];
    
    [self addSubview:self.imageView];
}

- (void)updateImage:(UIImage *)image {
    [self updateImage:image imageData:nil];
}

- (void)updateImageData:(NSData *)imageData {
    [self updateImage:nil imageData:imageData];
}

- (void)updateImage:(UIImage *)image imageData:(NSData *)imageData {
#ifdef DEBUG
#ifndef ANIMATED_GIF_SUPPORT
    if (imageData != nil) {
        NSLog(@"[NYTPhotoViewer] Warning! You're providing imageData for a photo, but NYTPhotoViewer was compiled without animated GIF support. You should use native UIImages for non-animated photos. See the NYTPhoto protocol documentation for discussion.");
    }
#endif // ANIMATED_GIF_SUPPORT
#endif // DEBUG

    UIImage *imageToUse = image ?: [UIImage imageWithData:imageData];

    // Remove any transform currently applied by the scroll view zooming.
    self.imageView.transform = CGAffineTransformIdentity;
    self.imageView.image = imageToUse;
    
#ifdef ANIMATED_GIF_SUPPORT
    // It's necessarry to first assign the UIImage so calulations for layout go right (see above)
    self.imageView.animatedImage = [[FLAnimatedImage alloc] initWithAnimatedGIFData:imageData];
#endif
    
    self.imageView.frame = CGRectMake(0, 0, imageToUse.size.width, imageToUse.size.height);
    
    self.contentSize = imageToUse.size;
    
    [self updateZoomScale];
    [self centerScrollViewContents];
}

- (void)setupImageScrollView {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = NO;
    self.bouncesZoom = YES;
    self.decelerationRate = UIScrollViewDecelerationRateFast;
}

- (void)stopPlaying {
    if (!self.player) {
        return;
    }
    
    [self.player pause];
    [self.player seekToTime:kCMTimeZero];
}

- (void)beginPlaying {
    if (!self.player) {
        return;
    }
    
    [self.player seekToTime:kCMTimeZero];
    [self.player play];
}

- (void)updateZoomScale {
    CGRect scrollViewFrame = self.bounds;
    
    if (self.playerLayer) {
        CGFloat scaleWidth = 1.0;
        CGFloat scaleHeight = 1.0;
        
        if (!CGSizeEqualToSize(self.playerItem.asset.naturalSize, CGSizeZero)) {
            CGSize naturalSize = self.playerItem.asset.naturalSize;
            scaleWidth = scrollViewFrame.size.width / naturalSize.width;
            scaleHeight = scrollViewFrame.size.height / naturalSize.height;
        }
        
        CGFloat minScale = MIN(scaleWidth, scaleHeight);
        
        self.minimumZoomScale = minScale;
        self.maximumZoomScale = MAX(minScale, self.maximumZoomScale);
        
        self.zoomScale = self.minimumZoomScale;
        
        // scrollView.panGestureRecognizer.enabled is on by default and enabled by
        // viewWillLayoutSubviews in the container controller so disable it here
        // to prevent an interference with the container controller's pan gesture.
        //
        // This is enabled in scrollViewWillBeginZooming so panning while zoomed-in
        // is unaffected.
        self.panGestureRecognizer.enabled = NO;
    }
#ifdef ANIMATED_GIF_SUPPORT
    else if (self.imageView.animatedImage || self.imageView.image) {
#else
    else if (self.imageView.image) {
#endif
        CGFloat scaleWidth = scrollViewFrame.size.width / self.imageView.image.size.width;
        CGFloat scaleHeight = scrollViewFrame.size.height / self.imageView.image.size.height;
        
        CGFloat minScale = MIN(scaleWidth, scaleHeight);
        
        self.minimumZoomScale = minScale;
        self.maximumZoomScale = MAX(minScale, self.maximumZoomScale);
        
        self.zoomScale = self.minimumZoomScale;
        
        // scrollView.panGestureRecognizer.enabled is on by default and enabled by
        // viewWillLayoutSubviews in the container controller so disable it here
        // to prevent an interference with the container controller's pan gesture.
        //
        // This is enabled in scrollViewWillBeginZooming so panning while zoomed-in
        // is unaffected.
        self.panGestureRecognizer.enabled = NO;
    }
}

#pragma mark - Centering

- (void)centerScrollViewContents {
    CGFloat horizontalInset = 0;
    CGFloat verticalInset = 0;
    
    if (self.contentSize.width < CGRectGetWidth(self.bounds)) {
        horizontalInset = (CGRectGetWidth(self.bounds) - self.contentSize.width) * 0.5;
    }
    
    if (self.contentSize.height < CGRectGetHeight(self.bounds)) {
        verticalInset = (CGRectGetHeight(self.bounds) - self.contentSize.height) * 0.5;
    }
    
    if (self.window.screen.scale < 2.0) {
        horizontalInset = __tg_floor(horizontalInset);
        verticalInset = __tg_floor(verticalInset);
    }
    
    // Use `contentInset` to center the contents in the scroll view. Reasoning explained here: http://petersteinberger.com/blog/2013/how-to-center-uiscrollview/
    self.contentInset = UIEdgeInsetsMake(verticalInset, horizontalInset, verticalInset, horizontalInset);
}

@end
