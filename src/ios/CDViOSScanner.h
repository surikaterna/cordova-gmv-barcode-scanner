#import <Cordova/CDV.h>
#import "CameraViewController.h"

@interface CDViOSScanner : CDVPlugin <senddataProtocol>
@property(nonatomic, strong) CameraViewController *cameraViewController;
- (void)startScan:(CDVInvokedUrlCommand *)command;
@end
