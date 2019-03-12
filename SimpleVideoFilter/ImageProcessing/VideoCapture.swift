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
    let ciImage: CIImage
    let milliseconds: Int64
}

public protocol VideoCaptureProtocol {
    func getFirstFrame() -> VideoFrame?
    func frameCount() -> Int
}

class VideoCapture: VideoCaptureProtocol {
    static let VideoSaved = Notification.Name(rawValue: "VideoCapture.VideoSaved")
    var videoFrames = [VideoFrame]()
    var videoSettings: [String: Any]
    var lastFrameTime: Date?
    var writer: VideoWriter?
    var section = 0
    let syncQueue = DispatchQueue(label: "VideoCapture.Synchronization")
 
    init?(width: Int, height: Int) {
        videoSettings = VideoWriter.videoSettings(width: width, height: height)
//        if let videoWriter = VideoWriter(videoSettings: videoSettings, timeScale: 1000, delegate: self) {
//            self.writer = videoWriter
//        } else {
//            DbLog("VideoCapture:saveToDisk, could not create file saver")
//            return nil
//        }
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
            return DbLog("VideoCapture:addFrame Couldn't generate ci image")
        }
        videoFrames.append(VideoFrame(ciImage: ciImage, milliseconds: msecs))
        lastFrameTime = Date()
        
//        if videoFrames.count > 20 {
//            let frames = [videoFrames[0]]
//            saveFrames(frames, completion: {
//             })
//        }
        if writer == nil {
            if let videoWriter = VideoWriter(videoSettings: videoSettings, timeScale: 1000, delegate: self) {
                writer = videoWriter
            } else {
                DbLog("VideoCapture:saveToDisk, could not create file saver")
            }
            writer?.writeVideoFramesToMovie([], section: 1, completion: { [weak self] (fileURL) in
                self?.getCameraRollPermissions(fileURL: fileURL)
            })
        }
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
    
//    func saveFrames(_ frames: [VideoFrame], completion: @escaping () -> Void) {
//         guard videoFrames.count > 0 else {
//            return DbLog("VideoCapture:saveToDisk, Nothing to save")
//        }
//        // Arrays passed by value so removing only happens after copy is placed on stack.
//        section += 1
//        let framesSection = section
//        let copiedFrames = videoFrames[0]
//        DispatchQueue.global().async {
//            DbLog("Writing section: \(framesSection) of \(self.videoFrames.count)")
//            self.writer.writeVideoFramesToMovie([copiedFrames], section: framesSection, completion: {
//                DbLog("Wrote section: \(framesSection) of video")
//                completion()
//            })
//        }
//        videoFrames.removeAll()
//    }
    
    // Also clears saved frames
//    func saveToCameraRoll() {
//        // Save remaining frames.
//        saveFrames(videoFrames) { [weak self] in
//            DbLog("Completing file writes for \(self?.section ?? 0) sections")
//            guard let fileURL = self?.writer.fileURL else {
//                return DbLog("Camera roll save failed: no file URL")
//            }
//            // Close file
//            self?.writer.completeFileWriting {
//                // Get permission to access camera roll
//                PHPhotoLibrary.requestAuthorization { (status) in
//                    switch status {
//                    case .authorized:
//                        self?._saveToCameraRoll(fileURL)
//                    default:
//                        DbLog("Could not save video, no permissions given")
//                    }
//                }
//            }
//        }
//    }
    
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
