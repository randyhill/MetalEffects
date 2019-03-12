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
    
//    func finishWriting() {
//        writeInput.markAsFinished()
//        writer.finishWriting {
//            DbLog("Finished writing section: \(self.section) to disk")
//        }
//    }
}

public class VideoWriter: NSObject {
    var fileURL: URL
    var delegate: VideoCaptureProtocol?
    
    static func preMakePixelBufferContext(_ videoSettings: [String : Any]) -> (buffer: CVPixelBuffer, context: CGContext)? {
        var bufferOptional: CVPixelBuffer?
        DbProfilePoint()
        guard let frameWidth = videoSettings[AVVideoWidthKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameWidth")
            return nil
        }
        guard let frameHeight = videoSettings[AVVideoHeightKey] as? Int else {
            DbLog("newPixelBufferFrom: could not find frameHeight")
            return nil
        }
        let options = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        DbProfilePoint()
        guard CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options, &bufferOptional) == kCVReturnSuccess,
            let buffer = bufferOptional else {
                DbLog("newPixelBufferFrom: newPixelBuffer failed")
                return nil
        }
        DbProfilePoint()
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            else {
                DbLog("context is nil")
                return nil
        }
        DbProfilePoint()
        return (buffer, context)
    }
    
    private var videoSettings: [String : Any]
    private var timeScale: Int32
    private let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    private var pixelBufferConversionBuffer: CVPixelBuffer
    private var pixelBufferConversionContext: CGContext
    private let assetWriter: AVAssetWriter
    private let writeInput: AVAssetWriterInput
    private let bufferAdapter: AVAssetWriterInputPixelBufferAdaptor
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
            guard let pixelBufferValues = VideoWriter.preMakePixelBufferContext(videoSettings) else {
                return nil
            }
            pixelBufferConversionContext = pixelBufferValues.context
            pixelBufferConversionBuffer = pixelBufferValues.buffer
            super.init()
        } catch {
            DbLog("Could not create asset writer: \(error)")
            return nil
        }
    }

    
//    fileprivate var currentWriters = [Int: SectionWriter]()
    func writeVideoFramesToMovie(_ videoFrames: [VideoFrame], section: Int, completion: @escaping (URL) -> Void){
       let sectionWriter = SectionWriter(writeInput: writeInput, bufferAdapter: bufferAdapter, writer: assetWriter, section: section)
        writeVideoFramesToWriterInput(sectionWriter) { (fileURl) in
            completion(self.fileURL)
        }
    }
    
    fileprivate func writeVideoFramesToWriterInput(_ sectionWriter: SectionWriter, completion: @escaping (URL) -> Void){
        DbOnMainThread(false)

        // Write each frame in section to file
        var totalMilliseconds: Int64?
        var frameCount = 1
        sectionWriter.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
            DbOnMainThread(false)
            while let count = self.delegate?.frameCount(), count > 0 {
                if sectionWriter.writeInput.isReadyForMoreMediaData, let frame = self.delegate?.getFirstFrame() {
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
                        DbOnMainThread(false)
                        sampleBuffer = self.fillBufferFrom(cgImage: frame.cgImage, videoSettings: self.videoSettings)
                    }
                    if let sampleBuffer = sampleBuffer {
                        var curMSecs: Int64 = 0
                        if let prevMilliseconds = totalMilliseconds {
                            curMSecs = prevMilliseconds + frame.milliseconds
                        }
                        let presentTime = CMTimeMake(curMSecs, self.timeScale)
                        DbProfilePoint()
                        sectionWriter.bufferAdapter.append(sampleBuffer, withPresentationTime: presentTime)
                        DbProfilePoint()
                        totalMilliseconds = curMSecs
                        frameCount += 1
                    } else {
                        DbLog("Got Nil buffer for frame")
                    }
                } else {
                    DbLog("Write blocked")
                }
            }
            completion(self.fileURL)
            DbPrintProfileSummary("Section frames: \(frameCount)")
        }
    }
    
    func completeWriting(_ completion: @escaping (URL) -> Void) {
        let sectionWriter = SectionWriter(writeInput: writeInput, bufferAdapter: bufferAdapter, writer: assetWriter, section: 1)
        writeVideoFramesToWriterInput(sectionWriter) { (fileURl) in
            sectionWriter.writeInput.markAsFinished()
            sectionWriter.writer.finishWriting {
                 completion(self.fileURL)
            }
        }
    }
    
//    let context = CIContext(options: nil)
//    private func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
//        DbProfilePoint()
//        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
//            DbProfilePoint()
//            return cgImage
//        }
//        return nil
//    }
    
    private func fillBufferFrom(cgImage: CGImage, videoSettings: [String : Any]) -> CVPixelBuffer? {
        DbProfilePoint()
        UIGraphicsPushContext(pixelBufferConversionContext)
        pixelBufferConversionContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBufferConversionBuffer, CVPixelBufferLockFlags(rawValue: 0))
        DbProfilePoint()
        return pixelBufferConversionBuffer
    }
}
