# iOS backend validation

The iOS implementation now uses AVFoundation, without GoogleMobileVision pods.
The existing JavaScript API, format masks, VIN validation, cancellation and
single-result iOS behavior are retained. Android sources are unchanged.

The backend uses iOS 13+ APIs. The Lynx application's iOS 16.0 deployment target
does not need to increase. The host application must provide an appropriate
`NSCameraUsageDescription` in its Info.plist.

Run the JavaScript and native C checks with Node.js 18 or newer:

```sh
npm test
```

On macOS with Xcode, include the Cordova headers to syntax-check both native
implementations with an iOS 16 deployment target:

```sh
CORDOVA_IOS_HEADERS=/path/to/cordova-ios/CordovaLib/include npm test
```

Camera permissions, real barcode/VIN detection, torch/focus, cancellation and
background/resume still require a device test. No package version is bumped by
this port; agree on a release/tag before updating consuming applications.
