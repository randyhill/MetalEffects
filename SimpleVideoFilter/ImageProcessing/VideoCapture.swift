//
//  VideoFile.swift
//  SimpleVideoFilter
//
//  Created by Randy Hill on 3/9/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

public struct VideoFrame {
    let cgImage: CGImage
    let presentTime: CMTime
    let index: Int
}

class VideoCapture {
    private class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            DbLog("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,  // not jpeg
                                           AVVideoWidthKey: height,
                                           AVVideoHeightKey: width]
        
        return videoSettings
    }
    static let VideoSaved = Notification.Name(rawValue: "VideoCapture.VideoSaved")
    var videoFrames = [VideoFrame]()
    var videoSettings: [String: Any]
    private let syncQueue = DispatchQueue(label: "VideoCapture.Synchronization")
    private var isWriting = true
    private var metalDevice: MTLDevice
    private var context : CIContext
    private let videoWriter: VideoWriter

    init?(metalDevice: MTLDevice, width: Int, height: Int) {
        self.metalDevice = metalDevice
        self.context = CIContext(mtlDevice: metalDevice, options: nil)
        self.videoSettings = VideoCapture.videoSettings(width: width, height: height)
        guard let writer = VideoWriter(videoSettings: videoSettings, timeScale: 1000) else {
            DbLog("Couldnt' create video writer")
            return nil
        }
        self.videoWriter = writer
        self.startTime = CACurrentMediaTime()
//        print("Start seconds: \(startTime)")
    }
    
    let startTime: Double
    func addFrame(_ newFrame: Texture, presentTime: CMTime) {
        DbOnMainThread(false)
//        guard presentTime.seconds > startTime else {
//            return DbLog("Don't use frames that started before we inited")
//        }
        guard isWriting else {
            return DbLog("Don't save frame, no longer writing")
        }
        print("Media seconds: \(CACurrentMediaTime()), presentTime: \(presentTime.seconds))")

        _frameCount += 1
        let frameIndex = _frameCount
        syncQueue.sync {
            // Save as CIImage to minimize processing time until it's saved.
            let kciOptions = [kCIImageColorSpace: CGColorSpaceCreateDeviceRGB(),
                              kCIContextOutputPremultiplied: true,
                              kCIContextUseSoftwareRenderer: false] as [String : Any]
            guard let ciImage = CIImage(mtlTexture: newFrame.texture, options: kciOptions) else {
                return DbLog("Couldn't generate ci image")
            }
            guard let cgImage = self.convertCIImageToCGImage(inputImage: ciImage) else {
                return DbLog("Couldn't generate cg image")
            }
            let secondsFromStart = presentTime.seconds - startTime
            DbLog("Saving frame: \(frameIndex) at offset: \(secondsFromStart)")
            self.videoWriter.writeVideoFrameToMovie(VideoFrame(cgImage: cgImage, presentTime: presentTime, index: frameIndex))
        }
    }
    
    private func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        DbProfilePoint()
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            DbProfilePoint()
            return cgImage
        }
        return nil
    }
    
    var _frameCount = 0
    private func frameCount() -> Int {
        return _frameCount
    }
    
    func stopRecording() {
        syncQueue.sync {
            self.isWriting = false
            DbPrintProfileSummary("Finished writing: \(frameCount()) frames")
            videoWriter.completeWriting { (fileURl) in
                DbLog("Finished writing file")
                self.getCameraRollPermissions(fileURL: fileURl)
            }
        }
    }
    
    private func getCameraRollPermissions(fileURL: URL) {
        PHPhotoLibrary.requestAuthorization { (status) in
            switch status {
            case .authorized:
                self._saveToCameraRoll(fileURL)
            default:
                DbLog("Could not save video, no permissions given")
            }
        }
    }
    
    private func _saveToCameraRoll(_ fileURL: URL) {
        DbOnMainThread(false)
        DbLog("Writing file to camera roll")
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { saved, error in
                if let error = error {
                    DbLog("Could not save video to library: \(error)")
                }
                else if saved {
                    NotificationCenter.default.post(Notification(name: VideoCapture.VideoSaved))
                }  else {
                    DbLog("weird error saving video to library")
                }
            }
    }
}
