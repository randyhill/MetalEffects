//
//  AvExtensions.swift
//  SimpleVideoFilter
//
//  Created by Randy Hill on 3/12/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import Foundation
import AVFoundation

extension AVCaptureDevice.Format {
    func matches(width: Int32, height: Int32, fps: Float64) -> Bool {
        let dimensions = CMVideoFormatDescriptionGetDimensions(self.formatDescription)
        if dimensions.height != height || dimensions.width != width {
            return false
        }
        if let frameRateRange = self.videoSupportedFrameRateRanges.first {
            return frameRateRange.minFrameRate ... frameRateRange.maxFrameRate ~= fps
        }
        return false
    }
}

extension AVCaptureDevice {
    func setSupportedFormatTo(width: Int32, height: Int32, fps: Float64) {
        if !activeFormat.matches(width: width, height: height, fps: fps) {
            for format in formats {
                if format.matches(width: width, height: height, fps: fps) {
                    do {
                        try lockForConfiguration()
                        activeFormat = format
                        unlockForConfiguration()
                    }  catch {
                        DbLog("LockForConfiguration failed with error: \(error.localizedDescription)")
                    }
                    break
                }
            }
        }
    }
    
    func setFrameRateTo(_ frameRate: Double) {
        guard let range = activeFormat.videoSupportedFrameRateRanges.first,
            range.minFrameRate...range.maxFrameRate ~= frameRate
            else {
                DbLog("Requested FPS is not supported by the device's activeFormat !")
                return
        }
        do {
            try lockForConfiguration()
            activeVideoMinFrameDuration = CMTimeMake(1, Int32(frameRate))
            activeVideoMaxFrameDuration = CMTimeMake(1, Int32(frameRate))
            unlockForConfiguration()
        } catch {
            DbLog("LockForConfiguration failed with error: \(error.localizedDescription)")
        }
    }
}
