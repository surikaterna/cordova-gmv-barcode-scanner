#import "CDViOSScanner.h"

@interface CDViOSScanner ()
@property(nonatomic, copy) NSString *callback;
@property(nonatomic) BOOL scannerOpen;
@property(nonatomic) BOOL finishing;
@property(nonatomic) NSUInteger scanGeneration;
@end

@implementation CDViOSScanner

- (void)startScan:(CDVInvokedUrlCommand *)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.scannerOpen) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:@[@"SCANNER_OPEN", @"", @""]];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }
        self.scannerOpen = YES;
        self.finishing = NO;
        ++self.scanGeneration;
        self.callback = command.callbackId;
        CameraViewController *scanner = [[CameraViewController alloc] init];
        scanner.delegate = self;
        scanner.barcodeFormats = [command argumentAtIndex:0 withDefault:@1234];
        scanner.scanAreaWidth = [[command argumentAtIndex:1 withDefault:@0.5] doubleValue];
        scanner.scanAreaHeight = [[command argumentAtIndex:2 withDefault:@0.7] doubleValue];
        scanner.flashOn = [[command argumentAtIndex:4 withDefault:@NO] boolValue];
        scanner.modalPresentationStyle = UIModalPresentationFullScreen;
        self.cameraViewController = scanner;
        [self.viewController presentViewController:scanner animated:NO completion:nil];
    });
}

- (void)finishWithValue:(NSString *)value status:(CDVCommandStatus)status {
    if (!self.scannerOpen || self.finishing) return;
    self.finishing = YES;
    NSString *callback = self.callback;
    NSUInteger generation = self.scanGeneration;
    [self.cameraViewController dismissViewControllerAnimated:NO completion:^{
        if (generation != self.scanGeneration) return;
        self.scannerOpen = NO;
        self.finishing = NO;
        self.callback = nil;
        self.cameraViewController = nil;
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:status messageAsArray:@[value, @"", @""]];
        [self.commandDelegate sendPluginResult:result callbackId:callback];
    }];
}

- (void)sendResult:(NSString *)value { [self finishWithValue:value status:CDVCommandStatus_OK]; }
- (void)closeScanner { [self finishWithValue:@"USER_CANCELLED" status:CDVCommandStatus_ERROR]; }
- (void)sendError:(NSString *)error { [self finishWithValue:error status:CDVCommandStatus_ERROR]; }

- (void)onReset {
    // A CodePush/web-view reload must not leave the camera running or send a
    // result to a callback belonging to the previous JavaScript session.
    dispatch_async(dispatch_get_main_queue(), ^{
        ++self.scanGeneration;
        self.cameraViewController.delegate = nil;
        [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
        self.cameraViewController = nil;
        self.callback = nil;
        self.scannerOpen = NO;
        self.finishing = NO;
    });
}

@end
