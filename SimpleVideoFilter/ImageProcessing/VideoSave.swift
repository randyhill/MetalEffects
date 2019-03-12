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

private struct SectionWriter {
    var writeInput: AVAssetWriterInput
    var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor
    var writer: AVAssetWriter
    var section: Int
    
    func finishWriting() {
        writeInput.markAsFinished()
        writer.finishWriting {
            DbLog("Finished writing section: \(self.section) to disk")
        }
    }
}

public class VideoWriter: NSObject {
    var fileURL: URL
    private var videoSettings: [String : Any]
    private var timeScale: Int32
    private let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    private let delegate: VideoCaptureProtocol

    public class func videoSettings(width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            DbLog("warning: video settings width must be divisible by 16")
        }
        
        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height]
        
        return videoSettings
    }
    
    let assetWriter: AVAssetWriter
    let writeInput: AVAssetWriterInput
    let bufferAdapter: AVAssetWriterInputPixelBufferAdaptor
    public init?(videoSettings: [String: Any], timeScale: Int32, delegate: VideoCaptureProtocol) {
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
        self.delegate = delegate
        
        do {
            // Create writer for this section
            writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            writeInput.expectsMediaDataInRealTime = true
            let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
            bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writeInput, sourcePixelBufferAttributes: bufferAttributes)
            
            assetWriter = try AVAssetWriter(url: fileURL, fileType: AVFileType.mov)
            assetWriter.add(writeInput)
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: kCMTimeZero)
            super.init()
        } catch {
            DbLog("Could not create asset writer: \(error)")
            return nil
        }
    }
    
//    fileprivate var currentWriters = [Int: SectionWriter]()
    func writeVideoFramesToMovie(_ videoFrames: [VideoFrame], section: Int, completion: @escaping (URL) -> Void){
//        do {
             // Create writer for this section
//            let writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
//            writeInput.expectsMediaDataInRealTime = true
//            let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
//            let bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writeInput, sourcePixelBufferAttributes: bufferAttributes)
//
//            let assetWriter = try AVAssetWriter(url: fileURL, fileType: AVFileType.mov)
//            assetWriter.add(writeInput)
//            assetWriter.startWriting()
//            assetWriter.startSession(atSourceTime: kCMTimeZero)
            let sectionWriter = SectionWriter(writeInput: writeInput, bufferAdapter: bufferAdapter, writer: assetWriter, section: section)
//            DbAssert(currentWriters[section] != nil)
//            currentWriters[section] = sectionWriter
            writeVideoFramesToWriterInput(videoFrames, sectionWriter: sectionWriter ) { (fileURl) in
                completion(self.fileURL)
            }
//        } catch {
//            DbLog("Could not create asset writer: \(error)")
//        }
    }
    
    fileprivate func writeVideoFramesToWriterInput(_ videoFrames: [VideoFrame], sectionWriter: SectionWriter, completion: @escaping (URL) -> Void){
        DbOnMainThread(false)

        // Write each frame in section to file
        var totalMilliseconds: Int64?
//        var mutableFrames = videoFrames
        var frameCount = 1
        sectionWriter.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
            DbOnMainThread(false)
            while self.delegate.frameCount() > 0 {
                if sectionWriter.writeInput.isReadyForMoreMediaData, let frame = self.delegate.getFirstFrame() {
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
                        DbOnMainThread(false)
                        if let cgImage = self.convertCIImageToCGImage(inputImage: frame.ciImage) {
                            DbOnMainThread(false)
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
                        DbProfilePoint("bufferAdapter.append 1")
                      sectionWriter.bufferAdapter.append(sampleBuffer, withPresentationTime: presentTime)
                        DbProfilePoint("bufferAdapter.append 2")
                        totalMilliseconds = curMSecs
                        frameCount += 1
                    } else {
                        DbLog("Got Nil buffer for frame")
                    }
                } else {
                    DbLog("Write blocked")
                }
            }
            DbPrintProfileSummary("Total frames: \(frameCount)")
            sectionWriter.writeInput.markAsFinished()
            sectionWriter.writer.finishWriting {
                completion(self.fileURL)
            }
        }
    }
    
    let context = CIContext(options: nil)
    private func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        DbProfilePoint("ConvertCI 1")
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            DbProfilePoint("ConvertCI 2")
            return cgImage
        }
        return nil
    }
    
    var pixelBufferConversionBuffer: CVPixelBuffer?
    var pixelBufferConversionContext: CGContext?
    private func createPixelBufferConversionBuffer() -> CVPixelBuffer? {
        var bufferOptional: CVPixelBuffer?
        DbProfilePoint("newPixelBufferFrom 1")
        guard let frameWidth = videoSettings[AVVideoWidthKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameWidth")
            return nil
        }
        guard let frameHeight = videoSettings[AVVideoHeightKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameHeight")
            return nil
        }
        let options = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        DbProfilePoint("newPixelBufferFrom 2")
        guard CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options, &bufferOptional) == kCVReturnSuccess,
            let buffer = bufferOptional else {
                DbLog("newPixelBufferFrom: newPixelBuffer failed")
                return nil
        }
        DbProfilePoint("newPixelBufferFrom 3")
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            else {
                DbLog("context is nil")
                return nil
        }
        DbProfilePoint("newPixelBufferFrom 4")
        pixelBufferConversionBuffer = buffer
        pixelBufferConversionContext = context
        return buffer
    }
    
    private func getPixelBufferValues() -> (CVPixelBuffer?, CGContext?) {
        if let buffer = pixelBufferConversionBuffer, let context = pixelBufferConversionContext {
            return (buffer, context)
        }
        if let buffer = createPixelBufferConversionBuffer(), let context = pixelBufferConversionContext {
            return (buffer, context)
        }
        return (nil, nil)
    }
    
    private func newPixelBufferFrom(cgImage: CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        var bufferOptional: CVPixelBuffer?
        DbProfilePoint("newPixelBufferFrom 1")
        DbProfilePoint("newPixelBufferFrom 1")
       let pixelBufferValues = getPixelBufferValues()
        guard let context = pixelBufferValues.1, let buffer = pixelBufferValues.0 else {
            return nil
        }
        DbProfilePoint("newPixelBufferFrom 2")

        UIGraphicsPushContext(context)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        DbProfilePoint("newPixelBufferFrom 3")
        return buffer
    }
}
