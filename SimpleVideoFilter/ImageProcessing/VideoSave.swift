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

typealias CXEMovieMakerCompletion = (URL) -> Void
typealias CXEMovieMakerUIImageExtractor = (AnyObject) -> UIImage?

public class ImagesToVideoUtils: NSObject {
    static let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    static let tempPath = paths[0] + "/exportVideo.mp4"
    static let fileURL = URL(fileURLWithPath: tempPath)
    
    var assetWriter: AVAssetWriter
    var writeInput: AVAssetWriterInput
    var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor
    var videoSettings: [String : Any]
    var frameTime: CMTime
    
    var completionBlock: CXEMovieMakerCompletion?
    var movieMakerUIImageExtractor:CXEMovieMakerUIImageExtractor?
    
    
    public class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            print("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height]
        
        return videoSettings
    }
    
    public init(videoSettings: [String: Any], milliseconds: Int64) {
        self.videoSettings = videoSettings
        self.writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        self.bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.writeInput, sourcePixelBufferAttributes: bufferAttributes)
        self.frameTime = CMTimeMake(milliseconds, 1000)
        do {
            try FileManager.default.removeItem(at: ImagesToVideoUtils.fileURL) // assetwriter doesn't remove files.
        } catch {
            print("Could not remove existing file")
        }
        self.assetWriter = try! AVAssetWriter(url: ImagesToVideoUtils.fileURL, fileType: AVFileType.mov)
//        assert(self.assetWriter.canAdd(self.writeInput), "add failed")
        self.assetWriter.add(self.writeInput)

        super.init()
        
        if FileManager.default.fileExists(atPath: ImagesToVideoUtils.tempPath) {
            guard (try? FileManager.default.removeItem(atPath: ImagesToVideoUtils.tempPath)) != nil else {
                print("remove path failed")
                return
            }
        }
    }
    
    func createMovieFromVideoFrames(_ _videoFrames: [VideoFrame], withCompletion: @escaping CXEMovieMakerCompletion){
        self.createMovieFromSource(_videoFrames, extractor: {(inputObject:AnyObject) -> UIImage? in
            return inputObject as? UIImage}, withCompletion: withCompletion)
    }
    
    func createMovieFromSource(_ videoFrames: [VideoFrame], extractor: @escaping CXEMovieMakerUIImageExtractor, withCompletion: @escaping CXEMovieMakerCompletion){
        self.completionBlock = withCompletion
        
        self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: kCMTimeZero)
        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
        var currentMilliseconds: Int64?
        var mutableFrames = videoFrames
        self.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
             print("save \(videoFrames.count) frames")
            while mutableFrames.count > 0 {
                if self.writeInput.isReadyForMoreMediaData {
                    let frame = mutableFrames.removeFirst()
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
//                        let fixedOrientation = frame.image.fixOrientation()
                        if let img = extractor(frame.image), let cgImage = img.cgImage {
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
                self.completionBlock!(ImagesToVideoUtils.fileURL)
            }
        }
    }
    
    func newPixelBufferFrom(cgImage:CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        var pxbuffer:CVPixelBuffer?
        guard let frameWidth = videoSettings[AVVideoWidthKey] as? Int else {
            print("newPixelBufferFrom: could not find frameWidth")
            return nil
        }
        guard let frameHeight = videoSettings[AVVideoHeightKey] as? Int else {
            print("newPixelBufferFrom: could not find frameHeight")
            return nil
        }
        let options:[String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxbuffer) == kCVReturnSuccess, let buffer = pxbuffer else {
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
        CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}

//
//extension UIImage {
//    func fixOrientation() -> UIImage {
//        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: self.size)
//        func rad(_ degree: Double) -> CGFloat {
//            return CGFloat(degree / 180.0 * .pi)
//        }
//
//        var rectTransform: CGAffineTransform
//         switch imageOrientation {
//        case .left:
//            rectTransform = CGAffineTransform(rotationAngle: rad(90)).translatedBy(x: 0, y: -self.size.height)
//        case .right:
//            rectTransform = CGAffineTransform(rotationAngle: rad(-90)).translatedBy(x: -self.size.width, y: 0)
//         case .down:
//            rectTransform = CGAffineTransform(rotationAngle: rad(-180)).translatedBy(x: -self.size.width, y: -self.size.height)
//         case .up:
//            rectTransform = CGAffineTransform(rotationAngle: rad(180)).translatedBy(x: -self.size.width, y: -self.size.height)
//        default:
//            rectTransform = .identity
//        }
//        rectTransform = rectTransform.scaledBy(x: self.scale, y: self.scale)
//
//        let imageRef = self.cgImage!.cropping(to: rect.applying(rectTransform))
//        let result = UIImage(cgImage: imageRef!, scale: self.scale, orientation: self.imageOrientation)
//        return result
//    }
//}

