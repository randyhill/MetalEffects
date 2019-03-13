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

public class VideoWriter: NSObject {
    var fileURL: URL
    
    static func preMakePixelBufferContext(_ videoSettings: [String : Any]) -> (buffer: CVPixelBuffer, context: CGContext)? {
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
        return (buffer, context)
    }
    
    private var videoSettings: [String : Any]
    private var timeScale: Int32
    private let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    private var pixelBufferConversionBuffer: CVPixelBuffer
    private var pixelBufferConversionContext: CGContext
    private var assetWriter: AVAssetWriter?
    private var writeInput: AVAssetWriterInput?
    private var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor?
    
    public init?(videoSettings: [String: Any], timeScale: Int32) {
        // First get temp file URL
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let tempPath = paths[0] + "/exportVideo.mp4"
        self.fileURL = URL(fileURLWithPath: tempPath)
        if FileManager.default.fileExists(atPath: tempPath) {
            do {
                try FileManager.default.removeItem(atPath: tempPath)
            } catch {
                DbLog("Remove of previous video file failed: \(error)")
            }
        }
        
        // Create writers.
        self.videoSettings = videoSettings
        self.timeScale = timeScale
        guard let pixelBufferValues = VideoWriter.preMakePixelBufferContext(videoSettings) else {
            return nil
        }
        pixelBufferConversionContext = pixelBufferValues.context
        pixelBufferConversionBuffer = pixelBufferValues.buffer
        super.init()
    }
    
    private func startWriting(_ frame: VideoFrame) {
        do {
            // Create writer for this section
            let writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            writeInput.expectsMediaDataInRealTime = true
            let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
            bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writeInput, sourcePixelBufferAttributes: bufferAttributes)
            
            let assetWriter = try AVAssetWriter(url: fileURL, fileType: AVFileType.mov)
            DbAssert(assetWriter.canAdd(writeInput))
            assetWriter.add(writeInput)
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: frame.presentTime)
            self.writeInput = writeInput
            self.assetWriter = assetWriter
        } catch {
            DbLog("Could not create asset writer: \(error)")
        }
    }

    func writeVideoFrameToMovie(_ frame: VideoFrame){
        DbOnMainThread(false)
        guard let assetWriter = assetWriter, let bufferAdapter = bufferAdapter, let writeInput = writeInput else {
            return startWriting(frame)
        }
        DbAssert(assetWriter.status == .writing)
        DbOnMainThread(false)
        guard writeInput.isReadyForMoreMediaData else {
            return DbLog("Dropped frame")
        }
        var pixelBuffer: CVPixelBuffer?
        autoreleasepool{
            DbOnMainThread(false)
            pixelBuffer = self.fillBufferFrom(cgImage: frame.cgImage, videoSettings: self.videoSettings)
        }
        if let pixelBuffer = pixelBuffer {
            bufferAdapter.append(pixelBuffer, withPresentationTime: frame.presentTime)
        } else {
            DbLog("Dropped frame: Nil buffer")
        }
    }
    
    func completeWriting(_ completion: @escaping (URL) -> Void) {
        writeInput?.markAsFinished()
        assetWriter?.finishWriting {
            DispatchQueue.main.async {
                completion(self.fileURL)
            }
        }
    }
    
    private func fillBufferFrom(cgImage: CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        UIGraphicsPushContext(pixelBufferConversionContext)
        pixelBufferConversionContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBufferConversionBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBufferConversionBuffer
    }
}
