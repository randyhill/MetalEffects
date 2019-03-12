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
    let milliseconds: Int64
}

public protocol VideoCaptureProtocol {
    func getFirstFrame() -> VideoFrame?
    func frameCount() -> Int
}

class VideoCapture: VideoCaptureProtocol {
    private class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            DbLog("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg,
                                           AVVideoWidthKey: width,
                                           AVVideoHeightKey: height]
        
        return videoSettings
    }
    static let VideoSaved = Notification.Name(rawValue: "VideoCapture.VideoSaved")
    var videoFrames = [VideoFrame]()
    var videoSettings: [String: Any]
    var lastFrameTime: Date?
    var writer: VideoWriter?
    var section = 0
    let syncQueue = DispatchQueue(label: "VideoCapture.Synchronization")
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
        videoWriter.delegate = self
    }
    
    func addFrame(_ newFrame: Texture) {
        DbOnMainThread(false)
        
        // Calculate time since last frame
        var msecs:Int64 = 0
        if let lastTime = lastFrameTime {
            let timeInterval = Date().timeIntervalSince(lastTime)
            msecs = Int64(timeInterval*1000.0)
        }
        
        // Save as CIImage to minimize processing time until it's saved.
        let kciOptions = [kCIImageColorSpace: CGColorSpaceCreateDeviceRGB(),
                          kCIContextOutputPremultiplied: true,
                          kCIContextUseSoftwareRenderer: false] as [String : Any]
        guard let ciImage = CIImage(mtlTexture: newFrame.texture, options: kciOptions) else {
            return DbLog("Couldn't generate ci image")
        }
        guard let cgImage = convertCIImageToCGImage(inputImage: ciImage) else {
            return DbLog("Couldn't generate cg image")
        }
        videoFrames.append(VideoFrame(cgImage: cgImage, milliseconds: msecs))
        lastFrameTime = Date()
        
        writer?.writeVideoFramesToMovie([], section: 1, completion: { [weak self] (fileURL) in
            self?.getCameraRollPermissions(fileURL: fileURL)
        })
        
//        if videoFrames.count > 20, writer == nil {
//            if let videoWriter = VideoWriter(videoSettings: videoSettings, timeScale: 1000, delegate: self) {
//                writer = videoWriter
//            } else {
//                DbLog("VideoCapture:saveToDisk, could not create file saver")
//            }
//            writer?.writeVideoFramesToMovie([], section: 1, completion: { [weak self] (fileURL) in
//                self?.getCameraRollPermissions(fileURL: fileURL)
//            })
//        }
    }
    
    private func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        DbProfilePoint()
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            DbProfilePoint()
            return cgImage
        }
        return nil
    }
    
    func addFrame(_ newFrame: VideoFrame) {
//        syncQueue.async {
            self.videoFrames.append(newFrame)
//        }
    }
    
    func getFirstFrame() -> VideoFrame? {
        var firstFrame: VideoFrame?
//        syncQueue.sync {
            firstFrame = videoFrames.removeFirst()
//        }
        return firstFrame
    }
    
    func frameCount() -> Int {
        var count = 0
//        syncQueue.sync {
            count = videoFrames.count
//        }
        return count
    }
    
    func stopRecording() {
        videoWriter.completeWriting { [weak self] (fileURl) in
            DbLog("Finished writing file")
            self?.getCameraRollPermissions(fileURL: fileURl)
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
