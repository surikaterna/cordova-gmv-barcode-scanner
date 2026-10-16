/*
 Copyright 2016-present Google Inc. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

// API-compatible AVFoundation backend for cordova-gmv-barcode-scanner.
// No GoogleMobileVision dependency or per-frame image copying is required.
#import "CameraViewController.h"
#import "ScannerUtils.h"
#import <AVFoundation/AVFoundation.h>
#include <math.h>

@interface CameraViewController () <AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureDevice *camera;
@property(nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) dispatch_queue_t sessionQueue;
@property(nonatomic, strong) UIView *scanFrame;
@property(nonatomic, strong) UIButton *torchButton;
@property(nonatomic, strong) UIButton *cancelButton;
@property(nonatomic, strong) UILabel *instruction;
@property(atomic) BOOL active;
@property(atomic) BOOL suspended;
@property(atomic) BOOL completed;
@property(nonatomic) BOOL configured; // accessed only on sessionQueue
@end

@implementation CameraViewController

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationPortrait; }

- (UIButton *)buttonWithSymbol:(NSString *)symbol action:(SEL)action label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    button.layer.cornerRadius = 24;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.sessionQueue = dispatch_queue_create("se.surikat.barcode.capture", DISPATCH_QUEUE_SERIAL);
    self.session = [[AVCaptureSession alloc] init];
    self.metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.previewLayer];

    self.scanFrame = [[UIView alloc] init];
    self.scanFrame.layer.borderColor = UIColor.whiteColor.CGColor;
    self.scanFrame.layer.borderWidth = 3;
    self.scanFrame.layer.cornerRadius = 8;
    [self.scanFrame addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAtPoint:)]];
    [self.view addSubview:self.scanFrame];
    self.cancelButton = [self buttonWithSymbol:@"xmark" action:@selector(cancelScan) label:NSLocalizedString(@"Close scanner", nil)];
    self.torchButton = [self buttonWithSymbol:@"flashlight.on.fill" action:@selector(toggleTorch) label:NSLocalizedString(@"Toggle torch", nil)];
    self.torchButton.enabled = NO;
    self.instruction = [[UILabel alloc] init];
    self.instruction.text = NSLocalizedString(@"Place a barcode inside the frame", nil);
    self.instruction.textColor = UIColor.whiteColor;
    self.instruction.textAlignment = NSTextAlignmentCenter;
    self.instruction.numberOfLines = 2;
    [self.view addSubview:self.instruction];

    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [notifications addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(captureFailed:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.active = YES;
    self.suspended = UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
    [self startCapture];
}

- (void)viewWillDisappear:(BOOL)animated {
    self.active = NO;
    [self stopCapture];
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.metadataOutput setMetadataObjectsDelegate:nil queue:NULL];
    AVCaptureSession *session = _session;
    dispatch_queue_t queue = _sessionQueue;
    if (session && queue) dispatch_async(queue, ^{ if (session.running) [session stopRunning]; });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    self.previewLayer.frame = bounds;
    CGFloat width = isfinite(self.scanAreaWidth) && self.scanAreaWidth > 0 ? MIN(self.scanAreaWidth, 1) : 0.5;
    CGFloat height = isfinite(self.scanAreaHeight) && self.scanAreaHeight > 0 ? MIN(self.scanAreaHeight, 1) : 0.7;
    self.scanFrame.frame = CGRectMake(CGRectGetMidX(bounds) - bounds.size.width * width / 2,
                                     CGRectGetMidY(bounds) - bounds.size.height * height / 2,
                                     bounds.size.width * width, bounds.size.height * height);
    CGFloat bottom = bounds.size.height - self.view.safeAreaInsets.bottom - 68;
    self.cancelButton.frame = CGRectMake(24, bottom, 48, 48);
    self.torchButton.frame = CGRectMake(bounds.size.width - 72, bottom, 48, 48);
    self.instruction.frame = CGRectMake(20, MAX(self.view.safeAreaInsets.top + 8, self.scanFrame.frame.origin.y - 52), bounds.size.width - 40, 44);
    [self updateScanArea];
}

- (void)updateScanArea {
    AVCaptureConnection *connection = self.previewLayer.connection;
    if (!connection) return;
    if (@available(iOS 17.0, *)) {
        if ([connection isVideoRotationAngleSupported:90]) connection.videoRotationAngle = 90;
    } else if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    CGRect rect = [self.previewLayer metadataOutputRectOfInterestForRect:self.scanFrame.frame];
    AVCaptureMetadataOutput *output = self.metadataOutput;
    dispatch_async(self.sessionQueue, ^{ output.rectOfInterest = rect; });
}

- (NSArray<AVMetadataObjectType> *)requestedTypes {
    unsigned long mask = GMVEffectiveFormats(self.barcodeFormats ? self.barcodeFormats.unsignedLongValue : 1234);
    NSDictionary<AVMetadataObjectType, NSNumber *> *formats = @{
        AVMetadataObjectTypeCode128Code: @(GMVCode128),
        AVMetadataObjectTypeCode39Code: @(GMVCode39),
        AVMetadataObjectTypeCode39Mod43Code: @(GMVCode39),
        AVMetadataObjectTypeCode93Code: @(GMVCode93),
        AVMetadataObjectTypeDataMatrixCode: @(GMVDataMatrix),
        AVMetadataObjectTypeEAN13Code: @(GMVEAN13 | GMVUPCA),
        AVMetadataObjectTypeEAN8Code: @(GMVEAN8),
        AVMetadataObjectTypeInterleaved2of5Code: @(GMVITF),
        AVMetadataObjectTypeITF14Code: @(GMVITF),
        AVMetadataObjectTypeQRCode: @(GMVQR),
        AVMetadataObjectTypeUPCECode: @(GMVUPCE),
        AVMetadataObjectTypePDF417Code: @(GMVPDF417),
        AVMetadataObjectTypeAztecCode: @(GMVAztec)
    };
    NSMutableArray<AVMetadataObjectType> *types = [NSMutableArray array];
    NSArray<AVMetadataObjectType> *available = self.metadataOutput.availableMetadataObjectTypes;
    for (AVMetadataObjectType type in formats) {
        if ((mask & formats[type].unsignedLongValue) && [available containsObject:type]) [types addObject:type];
    }
    if (@available(iOS 15.4, *)) {
        if ((mask & GMVCodabar) && [available containsObject:AVMetadataObjectTypeCodabarCode]) [types addObject:AVMetadataObjectTypeCodabarCode];
    }
    return types;
}

// All capture configuration/start/stop operations run on one background queue.
- (BOOL)configureCapture {
    if (self.configured) return YES;
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPresetHigh;
    self.camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    if (!self.camera) self.camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = self.camera ? [AVCaptureDeviceInput deviceInputWithDevice:self.camera error:&error] : nil;
    if (!input || ![self.session canAddInput:input]) {
        [self.session commitConfiguration];
        [self failWithMessage:@"CAMERA_UNAVAILABLE"];
        return NO;
    }
    [self.session addInput:input];
    if (![self.session canAddOutput:self.metadataOutput]) {
        [self.session commitConfiguration];
        [self failWithMessage:@"CAMERA_OUTPUT_UNAVAILABLE"];
        return NO;
    }
    [self.session addOutput:self.metadataOutput];
    [self.metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    NSArray<AVMetadataObjectType> *types = [self requestedTypes];
    if (!types.count) {
        [self.session commitConfiguration];
        [self failWithMessage:@"NO_SUPPORTED_BARCODE_FORMATS"];
        return NO;
    }
    self.metadataOutput.metadataObjectTypes = types;
    [self.session commitConfiguration];
    self.configured = YES;
    if ([self.camera lockForConfiguration:nil]) {
        if ([self.camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) self.camera.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        if (self.flashOn && self.camera.hasTorch && [self.camera isTorchModeSupported:AVCaptureTorchModeOn]) self.camera.torchMode = AVCaptureTorchModeOn;
        [self.camera unlockForConfiguration];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.torchButton.enabled = self.camera.hasTorch;
        [self updateScanArea];
    });
    return YES;
}

- (void)startCapture {
    if (!self.active || self.suspended || self.completed) return;
    AVAuthorizationStatus authorization = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authorization == AVAuthorizationStatusNotDetermined) {
        __weak CameraViewController *weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf.active || weakSelf.completed) return;
                if (granted) [weakSelf startCapture];
                else [weakSelf failWithMessage:@"CAMERA_ACCESS_DENIED"];
            });
        }];
        return;
    }
    if (authorization != AVAuthorizationStatusAuthorized) {
        [self failWithMessage:@"CAMERA_ACCESS_DENIED"];
        return;
    }
    dispatch_async(self.sessionQueue, ^{
        if (!self.active || self.suspended || self.completed || ![self configureCapture]) return;
        if (self.active && !self.suspended && !self.completed && !self.session.running) [self.session startRunning];
    });
}

- (void)stopCapture {
    dispatch_async(self.sessionQueue, ^{
        if (self.session.running) [self.session stopRunning];
        if (self.camera.hasTorch && [self.camera lockForConfiguration:nil]) {
            self.camera.torchMode = AVCaptureTorchModeOff;
            [self.camera unlockForConfiguration];
        }
    });
}

- (void)enteredBackground:(NSNotification *)notification {
    self.suspended = YES;
    [self stopCapture];
}

- (void)becameActive:(NSNotification *)notification {
    self.suspended = NO;
    [self startCapture];
}

- (void)captureFailed:(NSNotification *)notification { [self failWithMessage:@"CAMERA_RUNTIME_ERROR"]; }

- (void)failWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completed) return;
        self.completed = YES;
        self.active = NO;
        [self stopCapture];
        [self.delegate sendError:message];
    });
}

- (void)cancelScan {
    if (self.completed) return;
    self.completed = YES;
    self.active = NO;
    [self stopCapture];
    [self.delegate closeScanner];
}

- (void)toggleTorch {
    if (!self.active || self.completed) return;
    dispatch_async(self.sessionQueue, ^{
        if (!self.active || self.completed || !self.camera.hasTorch || ![self.camera lockForConfiguration:nil]) return;
        AVCaptureTorchMode mode = self.camera.torchMode == AVCaptureTorchModeOn ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
        if ([self.camera isTorchModeSupported:mode]) self.camera.torchMode = mode;
        [self.camera unlockForConfiguration];
    });
}

- (void)focusAtPoint:(UITapGestureRecognizer *)gesture {
    CGPoint point = [self.previewLayer captureDevicePointOfInterestForPoint:[gesture locationInView:self.view]];
    dispatch_async(self.sessionQueue, ^{
        if (!self.active || self.completed || ![self.camera lockForConfiguration:nil]) return;
        if (self.camera.isFocusPointOfInterestSupported && [self.camera isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            self.camera.focusPointOfInterest = point;
            self.camera.focusMode = AVCaptureFocusModeAutoFocus;
        }
        [self.camera unlockForConfiguration];
    });
}

- (void)metadataOutput:(AVCaptureMetadataOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)objects fromConnection:(AVCaptureConnection *)connection {
    if (!self.active || self.suspended || self.completed) return;
    for (AVMetadataObject *object in objects) {
        if (![object isKindOfClass:AVMetadataMachineReadableCodeObject.class]) continue;
        AVMetadataMachineReadableCodeObject *barcode = (AVMetadataMachineReadableCodeObject *)object;
        NSString *value = barcode.stringValue;
        if (!value.length) continue;
        if (self.barcodeFormats && self.barcodeFormats.unsignedLongValue == 0) {
            char vin[18];
            if (!GMVNormalizeVIN(value.UTF8String, vin)) continue;
            value = [NSString stringWithUTF8String:vin];
        } else if ([barcode.type isEqualToString:AVMetadataObjectTypeEAN13Code]) {
            unsigned long mask = GMVEffectiveFormats(self.barcodeFormats ? self.barcodeFormats.unsignedLongValue : 1234);
            BOOL isUPCA = value.length == 13 && [value hasPrefix:@"0"];
            if (!(mask & GMVEAN13) && !isUPCA) continue;
            if ((mask & GMVUPCA) && isUPCA) value = [value substringFromIndex:1];
        }
        self.completed = YES;
        self.active = NO;
        [self stopCapture];
        [self.delegate sendResult:value];
        break;
    }
}

@end
