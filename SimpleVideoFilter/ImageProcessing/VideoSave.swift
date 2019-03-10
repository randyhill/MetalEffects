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
    var frameTime: CMTime
    
    public class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            print("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height]
        
        return videoSettings
    }
    
    public init?(videoSettings: [String: Any], milliseconds: Int64) {
        self.videoSettings = videoSettings
        writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.writeInput, sourcePixelBufferAttributes: bufferAttributes)
        frameTime = CMTimeMake(milliseconds, 1000)
        do {
            try FileManager.default.removeItem(at: ImagesToVideoUtils.fileURL) // assetwriter doesn't remove files.
            assetWriter = try AVAssetWriter(url: ImagesToVideoUtils.fileURL, fileType: AVFileType.mov)
         } catch {
            print("Could not create asset writer: \(error)")
            return nil
        }
        assetWriter.add(self.writeInput)

        super.init()
        
        if FileManager.default.fileExists(atPath: ImagesToVideoUtils.tempPath) {
            guard (try? FileManager.default.removeItem(atPath: ImagesToVideoUtils.tempPath)) != nil else {
                print("remove path failed")
                return
            }
        }
    }
    
    func createMovieFromVideoFrames(_ videoFrames: [VideoFrame], completion: @escaping (URL) -> Void){
        self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: kCMTimeZero)
        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
        var currentMilliseconds: Int64?
        var mutableFrames = videoFrames
        self.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
            while mutableFrames.count > 0 {
                if self.writeInput.isReadyForMoreMediaData {
                    let frame = mutableFrames.removeFirst()
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
                        if let cgImage = frame.image.cgImageInCorrectOrientation {
                            sampleBuffer = self.newPixelBufferFrom(cgImage: cgImage, videoSettings: self.videoSettings)
                        } else {
                            print("Warning: counld not extract one of the frames")
                        }
                    }
                    if let sampleBuffer = sampleBuffer {
                        var curMSecs: Int64 = 0
                        if let mSec = currentMilliseconds {
                            print("Frame milliseconds: \(mSec)")
                            curMSecs = mSec + frame.milliseconds
                        }
                        let presentTime = CMTimeMake(curMSecs, self.frameTime.timescale)
                        print("Present time: \(presentTime)")
                        self.bufferAdapter.append(sampleBuffer, withPresentationTime: presentTime)
                        currentMilliseconds = curMSecs
                    } else {
                        print("Got Nil buffer for frame")
                    }
                }
            }
            print("Was ready for media: \(self.writeInput.isReadyForMoreMediaData), frames left: \(mutableFrames.count)")
            self.writeInput.markAsFinished()
            self.assetWriter.finishWriting {
                completion(ImagesToVideoUtils.fileURL)
            }
        }
    }
    
    func newPixelBufferFrom(cgImage:CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        var bufferOptional: CVPixelBuffer?
        guard let frameWidth = videoSettings[AVVideoWidthKey] as? Int else {
            print("newPixelBufferFrom: could not find frameWidth")
            return nil
        }
        guard let frameHeight = videoSettings[AVVideoHeightKey] as? Int else {
            print("newPixelBufferFrom: could not find frameHeight")
            return nil
        }
        let options:[String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options as CFDictionary?, &bufferOptional) == kCVReturnSuccess,
            let buffer = bufferOptional else {
            print("newPixelBufferFrom: newPixelBuffer failed")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            print("context is nil")
            return nil
        }
        
        context.concatenate(CGAffineTransform.identity)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}

extension UIImage {
    var cgImageInCorrectOrientation: CGImage? {
         UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext(), let cgImage = cgImage else {
            print("failed to get context to flip orirentation")
            return self.cgImage
        }
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        context.translateBy(x: size.width/2, y: size.height/2)
        
        // Rotate the image context, then flip hroizontally, then draw
        context.rotate(by: CGFloat.pi)
        context.scaleBy(x: -1.0, y: -1.0)
        context.draw(cgImage, in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage?.cgImage
    }
}


