//
//  VideoFile.swift
//  SimpleVideoFilter
//
//  Created by Randy Hill on 3/9/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import UIKit
import Photos
import Accelerate

class VideoCapture {
    var videoFrames = [UIImage]()
    
    func removeAll() {
        
    }
    
    func addFrame(_ newFrame: Texture) {
        guard let image = image(from: newFrame.texture) else {
            return print("VideoCapture:addFrame Couldn't generate frame")
        }
        videoFrames.append(image)
    }
    
    private func image(from texture: MTLTexture) -> UIImage? {
        let bytesPerPixel = 4
        
        // The total number of bytes of the texture
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        
        // The number of bytes for each image row
        let bytesPerRow = texture.width * bytesPerPixel
        
        // An empty buffer that will contain the image
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        // Gets the bytes from the texture
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Creates an image context
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
    
    func saveToDisk() {
        
    }
    
    func saveToCameraRoll() {
        
    }
}
