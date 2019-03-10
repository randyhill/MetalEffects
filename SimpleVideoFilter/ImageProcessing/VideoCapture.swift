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
    let image: UIImage
    let milliseconds: Int64
}

class VideoCapture {
    var videoFrames = [VideoFrame]()
    var fileURL : URL?
    var lastTime: Date?
    
    func removeAll() {
        
    }
    
    func addFrame(_ newFrame: Texture, milliseconds: Int64) {
        guard let image = image(from: newFrame.texture) else {
            return print("VideoCapture:addFrame Couldn't generate frame")
        }
        var msecs:Int64 = 0
        if let lastTime = lastTime {
            let timeInterval = Date().timeIntervalSince(lastTime)
            msecs = Int64(timeInterval*1000.0)
        }
        let videoFrame = VideoFrame(image: image, milliseconds: msecs)
        videoFrames.append(videoFrame)
        print("Saved \(videoFrames.count) frames, \(videoFrame.milliseconds) milliseconds")
        lastTime = Date()
    }
    
    private func image(from texture: MTLTexture) -> UIImage? {
        let bytesPerPixel = 4
        
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Create an image context
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &src, width: texture.width, height: texture.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        // Creates the image from the graphics context
        guard let dstImage = context?.makeImage() else {
            print("VideoCapture:image Couldn't make image from context")
            return nil
        }
        
        // Creates the final UIImage
        return UIImage(cgImage: dstImage, scale: 0.0, orientation: .up)
    }
    
    func saveToDiskWithAverageFrameTime(_ milliseconds: Int64) {
        guard videoFrames.count > 0 else {
            return print("VideoCapture:saveToDisk, Nothing to save")
        }
        let size = videoFrames[0].image.size
        let width = Int(size.width)
        let height = Int(size.height)
        let videoSettings = ImagesToVideoUtils.videoSettings(width: width, height: height)
        let fileSaver = ImagesToVideoUtils(videoSettings: videoSettings, milliseconds: milliseconds)
        fileSaver.createMovieFromVideoFrames(videoFrames) { (fileURL) in
            self.fileURL = fileURL
            if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                if let fileSize = attr[FileAttributeKey.size] as? UInt64 {
                    print("File size: \(fileSize)")
                }
            }
            self.videoFrames.removeAll()
            PHPhotoLibrary.requestAuthorization { (status) in
                switch status {
                case .authorized:
                    self.saveToCameraRoll(fileURL)
                default:
                    print("Could not save video, no permissions given")
               }
            }
        }
    }
    
    func saveToCameraRoll(_ fileURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }) { saved, error in
            if let error = error {
                print("Could not save video to library: \(error)")
            }
            else if saved {
                print("VIDEO SAVED!")
            }  else {
                print("weird error saving video to library")
            }
        }
    }
}
