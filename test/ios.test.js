const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const root = path.resolve(__dirname, "..");
const ios = path.join(root, "src/ios");

function scanner() {
    const calls = [];
    const cordova = { exec: (...args) => calls.push(args), addConstructor: callback => callback() };
    const window = { cordova };
    vm.runInNewContext(fs.readFileSync(path.join(root, "www/main.js"), "utf8"), { window });
    return { instance: window.plugins.GMVBarcodeScanner, calls };
}

test("iOS registers the native AVFoundation sources without GoogleMobileVision", () => {
    const xml = fs.readFileSync(path.join(root, "plugin.xml"), "utf8");
    const platform = xml.match(/<platform name="ios">([\s\S]*?)<\/platform>/)[1];
    assert.doesNotMatch(platform, /GoogleMobileVision|podspec/);
    assert.match(platform, /framework src="AVFoundation.framework"/);
    assert.match(platform, /header-file src="src\/ios\/ScannerUtils.h"/);
    for (const file of ["CameraViewController.h", "CameraViewController.m", "CDViOSScanner.h", "CDViOSScanner.m", "ScannerUtils.h"]) {
        assert.ok(fs.existsSync(path.join(ios, file)), file);
    }
    assert.match(fs.readFileSync(path.join(ios, "CameraViewController.m"), "utf8"), /AVCaptureMetadataOutputObjectsDelegate/);
});

test("JavaScript keeps the existing native argument order and callback shape", () => {
    const { instance, calls } = scanner();
    let result;
    instance.scan({ types: { QRCode: true }, detectorSize: { width: 0.2, height: 0.3 }, multipleScan: true, flashOn: false }, (error, value) => { result = { error, value }; });
    const [success, failure, service, action, args] = calls[0];
    assert.equal(service, "cordova-gmv-barcode-scanner");
    assert.equal(action, "startScan");
    assert.deepEqual(Array.from(args), [256, 0.2, 0.3, true, false]);
    success(["barcode", "", ""]);
    assert.equal(result.error, null);
    assert.equal(result.value, "barcode");
    failure(["USER_CANCELLED", "", ""]);
    assert.equal(result.error.cancelled, true);
    failure(["SCANNER_OPEN", "", ""]);
    assert.equal(result.error.cancelled, false);
    assert.equal(result.error.message, "Scanner already open.");
});

test("VIN and licence scans keep their native format masks", () => {
    const { instance, calls } = scanner();
    instance.scanVIN(() => {});
    instance.scanLicense(() => {});
    assert.deepEqual(Array.from(calls[0][4]), [0, 0.5, 0.7]);
    assert.deepEqual(Array.from(calls[1][4]), [2048, 0.5, 0.7]);
});

test("native VIN normalization and barcode masks retain the contract", t => {
    if (spawnSync("cc", ["--version"]).status !== 0) { t.skip("C compiler unavailable"); return; }
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "gmv-native-test-"));
    t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
    const source = path.join(temp, "scanner-test.c");
    const executable = path.join(temp, "scanner-test");
    fs.writeFileSync(source, `#include <assert.h>
#include "ScannerUtils.h"
int main(void) {
    char vin[18];
    assert(GMVEffectiveFormats(0) == (GMVCode39 | GMVDataMatrix));
    assert(GMVEffectiveFormats(1234) == GMVAllFormats);
    assert(GMVEffectiveFormats(2048) == GMVPDF417);
    assert(GMVEffectiveFormats(256) == GMVQR);
    assert(GMVNormalizeVIN("1M8GDM9AXKP042788", vin));
    assert(strcmp(vin, "1M8GDM9AXKP042788") == 0);
    assert(GMVNormalizeVIN("*1m8gdm9axkp042788*", vin));
    assert(!GMVNormalizeVIN("1M8GDM9A1KP042788", vin));
    assert(!GMVNormalizeVIN("123", vin));
    assert(!GMVNormalizeVIN(NULL, vin));
    assert(GMVUPCA == 512 && GMVEAN13 == 32 && GMVCodabar == 8);
    return 0;
}
`);
    const compile = spawnSync("cc", ["-std=c11", "-Wall", "-Wextra", "-Werror", "-I", ios, source, "-o", executable], { encoding: "utf8" });
    assert.equal(compile.status, 0, compile.stderr);
    assert.equal(spawnSync(executable).status, 0);
});

test("torch preference is reapplied after capture starts and tracks user toggles", () => {
    const source = fs.readFileSync(path.join(ios, "CameraViewController.m"), "utf8");
    function method(signature) {
        const start = source.indexOf(signature);
        assert.ok(start >= 0, signature);
        const end = source.indexOf("\n- (", start + signature.length);
        return source.slice(start, end < 0 ? undefined : end);
    }
    const start = method("- (void)startCapture");
    const stop = method("- (void)stopCapture");
    const toggle = method("- (void)toggleTorch");
    const apply = method("- (void)applyTorchPreference");
    const configure = method("- (BOOL)configureCapture");
    assert.match(configure, /if \(self.configured\) return YES/);
    assert.ok(start.indexOf("[self configureCapture]") < start.indexOf("[self applyTorchPreference]"));
    assert.ok(start.indexOf("[self.session startRunning]") < start.indexOf("[self applyTorchPreference]"));
    assert.match(apply, /self.flashOn \? AVCaptureTorchModeOn : AVCaptureTorchModeOff/);
    assert.match(apply, /self.suspended/);
    assert.match(stop, /self.camera.torchMode = AVCaptureTorchModeOff/);
    assert.doesNotMatch(stop, /self.flashOn\s*=/);
    assert.match(toggle, /self.flashOn = mode == AVCaptureTorchModeOn/);
    assert.match(toggle, /self.suspended/);
});

test("camera UI availability checks compile for a pre-iOS 13 host", { skip: process.platform !== "darwin" }, t => {
    const sdk = spawnSync("xcrun", ["--sdk", "iphoneos", "--show-sdk-path"], { encoding: "utf8" });
    if (sdk.status !== 0) { t.skip("iPhoneOS SDK unavailable"); return; }
    const cache = fs.mkdtempSync(path.join(os.tmpdir(), "gmv-availability-test-"));
    t.after(() => fs.rmSync(cache, { recursive: true, force: true }));
    const compile = spawnSync("xcrun", ["clang", "-fsyntax-only", "-fobjc-arc", "-fmodules", "-fblocks", "-Werror=unguarded-availability", "-Werror=unguarded-availability-new", "-target", "arm64-apple-ios9.0", "-isysroot", sdk.stdout.trim(), "-fmodules-cache-path=" + cache, path.join(ios, "CameraViewController.m")], { encoding: "utf8", timeout: 60000 });
    assert.equal(compile.status, 0, compile.stderr || String(compile.error));
});

test("AVFoundation implementations compile for iOS 16 with Cordova headers", {
    skip: process.platform !== "darwin" || !process.env.CORDOVA_IOS_HEADERS
}, t => {
    const sdk = spawnSync("xcrun", ["--sdk", "iphoneos", "--show-sdk-path"], { encoding: "utf8" });
    if (sdk.status !== 0) { t.skip("iPhoneOS SDK unavailable"); return; }
    const cache = fs.mkdtempSync(path.join(os.tmpdir(), "gmv-syntax-test-"));
    t.after(() => fs.rmSync(cache, { recursive: true, force: true }));
    for (const file of ["CameraViewController.m", "CDViOSScanner.m"]) {
        const compile = spawnSync("xcrun", ["clang", "-fsyntax-only", "-fobjc-arc", "-fmodules", "-fblocks", "-target", "arm64-apple-ios16.0", "-isysroot", sdk.stdout.trim(), "-fmodules-cache-path=" + cache, "-I", process.env.CORDOVA_IOS_HEADERS, path.join(ios, file)], { encoding: "utf8", timeout: 60000 });
        assert.equal(compile.status, 0, compile.stderr || String(compile.error));
    }
});
