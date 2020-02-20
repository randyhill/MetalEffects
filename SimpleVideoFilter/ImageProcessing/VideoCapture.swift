//
//  VideoFile.swift
//  MetalEffects
//
//  Created by Randy Hill on 3/9/19.
//

import UIKit
import AVFoundation
import Photos
import Accelerate

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

    private let syncQueue = DispatchQueue(label: "VideoCapture.Synchronization")
    private var metalDevice: MTLDevice
    private var context : CIContext
    private let videoWriter: VideoWriter
    private var frameCount = 0

    init?(metalDevice: MTLDevice, width: Int, height: Int) {
        self.metalDevice = metalDevice
        self.context = CIContext(mtlDevice: metalDevice, options: nil)
        let videoSettings = VideoCapture.videoSettings(width: width, height: height)
        guard let writer = VideoWriter(videoSettings: videoSettings) else {
            DbLog("Couldnt' create video writer")
            return nil
        }
        self.videoWriter = writer
    }
    
    func addFrame(_ newFrame: Texture, presentTime: CMTime) {
        DbOnMainThread(false)
        frameCount += 1
        let frameIndex = frameCount
        
        syncQueue.sync {
            DbProfilePoint()
            let kciOptions = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB(),
                              CIContextOption.outputPremultiplied: true,
                              CIContextOption.useSoftwareRenderer: false] as! [CIImageOption : Any]
            guard let ciImage = CIImage(mtlTexture: newFrame.texture, options: kciOptions) else {
                return DbLog("Couldn't generate ci image")
            }
            DbProfilePoint()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                return DbLog("Couldn't generate cg image")
            }
            DbProfilePoint()
            self.videoWriter.writeVideoFrameToMovie(VideoFrame(cgImage: cgImage, presentTime: presentTime, index: frameIndex))
            DbProfilePoint()
         }
    }
    
    func stopRecording() {
        DbPrintProfileSummary()
        syncQueue.sync {
            videoWriter.completeWriting { (fileURl) in
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
