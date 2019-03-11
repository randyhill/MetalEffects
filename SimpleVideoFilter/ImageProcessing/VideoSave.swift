//
//  VideoSave.swift
//  SimpleVideoFilter
//
//  Created by Randy Hill on 3/9/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

public class ImagesToVideoUtils: NSObject {
    static let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    static let tempPath = paths[0] + "/exportVideo.mp4"
    static let fileURL = URL(fileURLWithPath: tempPath)
    
    var assetWriter: AVAssetWriter
    var writeInput: AVAssetWriterInput
    var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor
    var videoSettings: [String : Any]
    var timeScale: Int32
    
    public class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            DbLog("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height]
        
        return videoSettings
    }
    
    public init?(videoSettings: [String: Any], timeScale: Int32) {
        self.videoSettings = videoSettings
        self.timeScale = timeScale
        writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.writeInput, sourcePixelBufferAttributes: bufferAttributes)
         do {
            try FileManager.default.removeItem(at: ImagesToVideoUtils.fileURL) // assetwriter doesn't remove files.
            assetWriter = try AVAssetWriter(url: ImagesToVideoUtils.fileURL, fileType: AVFileType.mov)
         } catch {
            DbLog("Could not create asset writer: \(error)")
            return nil
        }
        assetWriter.add(self.writeInput)

        super.init()
        
        if FileManager.default.fileExists(atPath: ImagesToVideoUtils.tempPath) {
            guard (try? FileManager.default.removeItem(atPath: ImagesToVideoUtils.tempPath)) != nil else {
                DbLog("remove path failed")
                return
            }
        }
    }
    
    func createMovieFromVideoFrames(_ videoFrames: [VideoFrame], completion: @escaping (URL) -> Void){
        DbOnMainThread(false)
        self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: kCMTimeZero)
        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
        var totalMilliseconds: Int64?
        var mutableFrames = videoFrames
        self.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
            while mutableFrames.count > 0 {
                if self.writeInput.isReadyForMoreMediaData {
                    let frame = mutableFrames.removeFirst()
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
                        if let cgImage = self.convertCIImageToCGImage(inputImage: frame.ciImage) {
                            sampleBuffer = self.newPixelBufferFrom(cgImage: cgImage, videoSettings: self.videoSettings)
                        } else {
                            DbLog("Warning: counld not extract one of the frames")
                        }
                    }
                    if let sampleBuffer = sampleBuffer {
                        var curMSecs: Int64 = 0
                        if let prevMilliseconds = totalMilliseconds {
                            curMSecs = prevMilliseconds + frame.milliseconds
                        }
                        let presentTime = CMTimeMake(curMSecs, self.timeScale)
                        self.bufferAdapter.append(sampleBuffer, withPresentationTime: presentTime)
                        totalMilliseconds = curMSecs
                    } else {
                        DbLog("Got Nil buffer for frame")
                    }
                }
            }
            DbLog("Was ready for media: \(self.writeInput.isReadyForMoreMediaData), frames left: \(mutableFrames.count)")
            self.writeInput.markAsFinished()
            self.assetWriter.finishWriting {
                completion(ImagesToVideoUtils.fileURL)
            }
        }
    }
    
    private func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }
    
    private func newPixelBufferFrom(cgImage: CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        var bufferOptional: CVPixelBuffer?
        guard let frameWidth = videoSettings[AVVideoWidthKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameWidth")
            return nil
        }
        guard let frameHeight = videoSettings[AVVideoHeightKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameHeight")
            return nil
        }
        let options = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options, &bufferOptional) == kCVReturnSuccess,
            let buffer = bufferOptional else {
            DbLog("newPixelBufferFrom: newPixelBuffer failed")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else {
            DbLog("context is nil")
            return nil
        }
        
        UIGraphicsPushContext(context)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}
