package com.dealrinc.gmvScanner;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.CordovaInterface;

import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.vision.barcode.Barcode;

import javax.security.auth.callback.Callback;


/**
 * This class echoes a string called from JavaScript.
 */
public class CDVAndroidScanner extends CordovaPlugin {

    protected CallbackContext mCallbackContext;

    BroadcastReceiver receiver;

    IntentFilter filter;

    private static final int RC_BARCODE_CAPTURE = 9001;
    private static final String TAG = "CDVAndroidScanner";

    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        super.initialize(cordova, webView);
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        Context context = cordova.getActivity().getApplicationContext();
        mCallbackContext = callbackContext;
        if (action.equals("startScan")) {

            class OneShotTask implements Runnable {
                private Context context;
                private JSONArray args;
                private OneShotTask(Context ctx, JSONArray as) { context = ctx; args = as; }
                public void run() {
                    openNewActivity(context, args);
                }
            }
            Thread t = new Thread(new OneShotTask(context, args));
            t.start();
            return true;
        } else if (action.equals("stopScan")) {
            mCallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, "Cancelled"));
            this.cordova.getActivity().finish();
        }
        return false;
    }

    private void openNewActivity(Context context, JSONArray args) {
        Intent intent = new Intent(context, SecondaryActivity.class);
        intent.putExtra("DetectionTypes", args.optInt(0, 1234));
        intent.putExtra("ViewFinderWidth", args.optDouble(1, .925));
        intent.putExtra("ViewFinderHeight", args.optDouble(2, .3));
        intent.putExtra("MultipleScan", args.optBoolean(3, true));
        intent.putExtra("FlashOn", args.optBoolean(4, true));
        intent.putExtra("PortraitOnly", args.optBoolean(5, true));

        Log.d(TAG, intent.toString());
        
        OnReceiveBarcodeContext onReceiveBarcodeContext = OnReceiveBarcodeContext.getInstance();
        onReceiveBarcodeContext.setCallbackContext(mCallbackContext);
        this.cordova.setActivityResultCallback(this);
        this.cordova.startActivityForResult(this, intent, RC_BARCODE_CAPTURE);
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode == CommonStatusCodes.ERROR) {
            Log.d(TAG, "Exit barcode scanner");
            String err = data.getStringExtra("err");
            JSONArray result = new JSONArray();
            result.put(err);
            result.put("");
            result.put("");
            mCallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, result));
        }
        else if (requestCode == RC_BARCODE_CAPTURE) {
            if (resultCode == CommonStatusCodes.SUCCESS) {
                Intent d = new Intent();
                if (data != null) {
                    Barcode barcode = data.getParcelableExtra(BarcodeCaptureActivity.BarcodeObject);
                    JSONArray result = new JSONArray();
                    result.put(barcode.rawValue);
                    result.put("");
                    result.put("");
                    PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
                    mCallbackContext.sendPluginResult(pluginResult);
                    Log.d(TAG, "Barcode read: " + barcode.displayValue);
                }
            } else {
                String err = data.getParcelableExtra("err");
                JSONArray result = new JSONArray();
                result.put(err);
                result.put("");
                result.put("");
                mCallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, result));
            }
        }
    }

    @Override
    public void onRestoreStateForActivityResult(Bundle state, CallbackContext callbackContext) {
        mCallbackContext = callbackContext;
    }
    
/*
    private void startScan(CallbackContext callbackContext) {
		Intent intent = new Intent(this, MainActivity.class);
		//intent.putExtra(BarcodeCaptureActivity.AutoFocus, autoFocus.isChecked());
		//intent.putExtra(BarcodeCaptureActivity.UseFlash, useFlash.isChecked());

		startActivityForResult(intent, RC_BARCODE_CAPTURE);

        if (true) {
			callbackContext.success("Test response!!!!");
        } else {
            callbackContext.error("Expected one non-empty string argument.");
        }
    }*/
}
