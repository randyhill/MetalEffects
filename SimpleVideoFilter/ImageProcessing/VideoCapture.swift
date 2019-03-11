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

struct VideoFrame {
    let ciImage: CIImage
    let milliseconds: Int64
}

class VideoCapture {
    static let VideoSaved = Notification.Name(rawValue: "VideoCapture.VideoSaved")
    var videoFrames = [VideoFrame]()
    var fileURL : URL?
    var lastTime: Date?
    var frameSize = CGSize(width: 0, height: 0)
 
    func removeAll() {
        videoFrames.removeAll()
    }
    
    func addFrame(_ newFrame: Texture, milliseconds: Int64) {
        DbOnMainThread(false)
        var msecs:Int64 = 0
        if let lastTime = lastTime {
            let timeInterval = Date().timeIntervalSince(lastTime)
            msecs = Int64(timeInterval*1000.0)
        }
        let kciOptions = [kCIImageColorSpace: CGColorSpaceCreateDeviceRGB(),
                          kCIContextOutputPremultiplied: true,
                          kCIContextUseSoftwareRenderer: false] as [String : Any]
        guard let ciImage = CIImage(mtlTexture: newFrame.texture, options: kciOptions) else {
            return DbLog("VideoCapture:addFrame Couldn't generate ci image")
        }
        frameSize = CGSize(width: newFrame.texture.width, height: newFrame.texture.height)
        let videoFrame = VideoFrame(ciImage: ciImage, milliseconds: msecs)
        videoFrames.append(videoFrame)
        lastTime = Date()
    }
    
    // Also clears saved frames
    var startSaveTime = Date()
    func saveToDisk() {
        DbOnMainThread(false)
        guard videoFrames.count > 0 else {
            return DbLog("VideoCapture:saveToDisk, Nothing to save")
        }
        startSaveTime = Date()
        let width = Int(frameSize.width)
        let height = Int(frameSize.height)
        let videoSettings = ImagesToVideoUtils.videoSettings(width: width, height: height)
        guard let fileSaver = ImagesToVideoUtils(videoSettings: videoSettings, timeScale: 1000) else {
            return DbLog("VideoCapture:saveToDisk, could not create file saver")
        }
        fileSaver.createMovieFromVideoFrames(videoFrames) { (fileURL) in
            self.fileURL = fileURL
            self.videoFrames.removeAll()
            PHPhotoLibrary.requestAuthorization { (status) in
                switch status {
                case .authorized:
                    self.saveToCameraRoll(fileURL)
                default:
                    DbLog("Could not save video, no permissions given")
               }
            }
        }
    }
    
    func saveToCameraRoll(_ fileURL: URL) {
        DbOnMainThread(false)
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }) { saved, error in
            if let error = error {
                DbLog("Could not save video to library: \(error)")
            }
            else if saved {
                let saveTime = Date().timeIntervalSince(self.startSaveTime)
                DbLog("Took \(saveTime) seconds to save")
                NotificationCenter.default.post(Notification(name: VideoCapture.VideoSaved))
            }  else {
                DbLog("weird error saving video to library")
            }
        }
    }
}
