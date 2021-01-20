package com.dealrinc.gmvScanner;

import android.util.Log;
import org.apache.cordova.CallbackContext;

public class OnReceiveBarcodeContext {

  private static volatile OnReceiveBarcodeContext sSoleInstance;
  private CallbackContext mCallbackContext;

  // private constructor.
  private OnReceiveBarcodeContext(){
      // Prevent form the reflection api.
      if (sSoleInstance != null){
          throw new RuntimeException("Use getInstance() method to get the single instance of this class.");
      }
  }

  public static OnReceiveBarcodeContext getInstance() {
      //Double check locking pattern
      if (sSoleInstance == null) { //Check for the first time
          synchronized (OnReceiveBarcodeContext.class) {   //Check for the second time.
            //if there is no instance available... create new one
            if (sSoleInstance == null) sSoleInstance = new OnReceiveBarcodeContext();
          }
      }
      return sSoleInstance;
  }

  public void setCallbackContext(CallbackContext callbackContext) {
    this.mCallbackContext = callbackContext;
  }

  public CallbackContext getCallbackContext() {
    return mCallbackContext;
  }

  public void clearCallbackContext() {
    this.mCallbackContext = null;
  }
}