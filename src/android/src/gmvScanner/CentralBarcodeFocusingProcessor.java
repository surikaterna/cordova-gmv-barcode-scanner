package com.dealrinc.gmvScanner;

import android.util.Log;
import android.util.SparseArray;

import com.google.android.gms.vision.Detector;
import com.google.android.gms.vision.FocusingProcessor;
import com.google.android.gms.vision.Frame;
import com.google.android.gms.vision.Tracker;
import com.google.android.gms.vision.barcode.Barcode;

public class CentralBarcodeFocusingProcessor extends FocusingProcessor<Barcode> {
    int mWidth;
    int mHeight;

    public CentralBarcodeFocusingProcessor(Detector<Barcode> detector, Tracker<Barcode> tracker, int width, int height) {
        super(detector, tracker);
        this.mHeight = height;
        this.mWidth = width;
    }

    @Override
    public int selectFocus(Detector.Detections<Barcode> detections) {

        SparseArray<Barcode> barcodes = detections.getDetectedItems();
        Frame.Metadata meta = detections.getFrameMetadata();
        double nearestDistance = Double.MAX_VALUE;
        int id = -1;

        for (int i = 0; i < barcodes.size(); ++i) {
            int tempId = barcodes.keyAt(i);
            Barcode barcode = barcodes.get(tempId);
            float dx = Math.abs((meta.getWidth() / 2) - barcode.getBoundingBox().centerX());
            float dy = Math.abs((meta.getHeight() / 2) - barcode.getBoundingBox().centerY());

            if (dx < mWidth && dy < mHeight) {
                id = tempId;
            }

//            double distanceFromCenter =  Math.sqrt((dx * dx) + (dy * dy));
//
//            if (distanceFromCenter < nearestDistance) {
//                id = tempId;
//                nearestDistance = distanceFromCenter;
//            }
        }
        return id;
    }
}