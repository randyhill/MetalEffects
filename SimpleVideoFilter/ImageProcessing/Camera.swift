import Foundation
import AVFoundation
import Metal

public protocol CameraDelegate {
    func averageFrameTime(_ average: Double)
}

public enum PhysicalCameraLocation {
    case backFacing
    case frontFacing
    
    func imageOrientation() -> ImageOrientation {
        switch self {
        case .backFacing: return .landscapeRight
        case .frontFacing: return .landscapeLeft
        }
    }
    
    func captureDevicePosition() -> AVCaptureDevice.Position {
        switch self {
        case .backFacing: return .back
        case .frontFacing: return .front
        }
    }
    
    func device() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for:AVMediaType.video)
        for case let device in devices {
            if (device.position == self.captureDevicePosition()) {
                return device
            }
        }
        
        return AVCaptureDevice.default(for: AVMediaType.video)
    }
}

public struct CameraError: Error {
}

public class Camera: NSObject, ImageSource, AVCaptureVideoDataOutputSampleBufferDelegate {

    public var location:PhysicalCameraLocation {
        didSet {
            // TODO: Swap the camera locations, framebuffers as needed
        }
    }
    public let targets = TargetContainer()
    public var delegate: CameraDelegate?
    public let captureSession:AVCaptureSession
    let inputCamera:AVCaptureDevice!
    let videoInput:AVCaptureDeviceInput!
    let videoOutput:AVCaptureVideoDataOutput!
    var videoTextureCache: CVMetalTextureCache?
    
    let frameRenderingSemaphore = DispatchSemaphore(value:1)
    let cameraProcessingQueue = DispatchQueue.global()
    let cameraFrameProcessingQueue = DispatchQueue(
        label: "com.cameraFrameProcessingQueue",
        attributes: [])
    
    var framesSinceLastCheck = 0
    var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    private var _isRecording = false
    var isRecording : Bool {
        get { return _isRecording }
        set (newValue) {
            _isRecording = newValue
            if _isRecording {
                recordedFrames.removeAll()
            } else {
                // Save to camera roll
                recordedFrames.saveToDisk()            }
        }
    }
    private var recordedFrames = VideoCapture()
    
    public init(sessionPreset:AVCaptureSession.Preset,
                cameraDevice:AVCaptureDevice? = nil,
                location:PhysicalCameraLocation = .backFacing,
                captureAsYUV:Bool = false) throws
    {
        self.location = location
        
        self.captureSession = AVCaptureSession()
        self.captureSession.beginConfiguration()
        
        if let cameraDevice = cameraDevice {
            self.inputCamera = cameraDevice
        } else {
            if let device = location.device() {
                self.inputCamera = device
                inputCamera.set(frameRate: 60)
            } else {
                self.videoInput = nil
                self.videoOutput = nil
                self.inputCamera = nil
                super.init()
                throw CameraError()
            }
        }
        
        do {
            self.videoInput = try AVCaptureDeviceInput(device:inputCamera)
        } catch {
            self.videoInput = nil
            self.videoOutput = nil
            super.init()
            throw error
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        }
        
        // Add the video frame output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = false
        
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_32BGRA))]
        
        if (captureSession.canAddOutput(videoOutput)) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.sessionPreset = sessionPreset
        captureSession.commitConfiguration()
        
        super.init()
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                          nil,
                                          sharedMetalRenderingDevice.device,
                                          nil,
                                          &videoTextureCache)
        
        videoOutput.setSampleBufferDelegate(self, queue:cameraProcessingQueue)
    }
    
    deinit {
        cameraFrameProcessingQueue.sync {
            self.stopCapture()
            self.videoOutput?.setSampleBufferDelegate(nil, queue:nil)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        DbOnMainThread(false)
        DbProfilePoint("1")
        guard (frameRenderingSemaphore.wait(timeout:DispatchTime.now()) == DispatchTimeoutResult.success) else {
            return DbLog("Semaphore Error")
        }
        guard let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return DbLog("Couldn't get image buffer")
        }
        let frameStartTime = CFAbsoluteTimeGetCurrent()
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        DbProfilePoint("2")
        cameraFrameProcessingQueue.async {
            DbProfilePoint("3")
            CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            DbProfilePoint("4")

            var textureRef:CVMetalTexture? = nil
            let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                              self.videoTextureCache!,
                                                              cameraFrame,
                                                              nil,
                                                              .bgra8Unorm,
                                                              bufferWidth,
                                                              bufferHeight,
                                                              0,
                                                              &textureRef)
            
            DbProfilePoint("5")
            if let concreteTexture = textureRef,
                let cameraTexture = CVMetalTextureGetTexture(concreteTexture) {
                let inputTexture = Texture(orientation: self.location.imageOrientation(), texture: cameraTexture)
                let outputTexture = self.updateTargetsWithTexture(inputTexture)
                DbProfilePoint("6")
                if self.isRecording {
                    let frameTime = (CFAbsoluteTimeGetCurrent() - frameStartTime)
                    self.recordedFrames.addFrame(outputTexture, milliseconds: Int64(1000*frameTime))
                }
            
                // Benchmarking FPS
                let timeSinceLastCheck = CFAbsoluteTimeGetCurrent() - self.lastCheckTime
                self.framesSinceLastCheck += 1
                if (timeSinceLastCheck > 1.0) {
                    let average = Double(self.framesSinceLastCheck)/timeSinceLastCheck
                    self.delegate?.averageFrameTime(average)
                    self.resetBenchmarks()
                }
            }

            self.frameRenderingSemaphore.signal()
            DbProfilePoint("7")
        }
        DbProfilePoint("8")
    }
    
    private func resetBenchmarks() {
        lastCheckTime = CFAbsoluteTimeGetCurrent()
        framesSinceLastCheck = 0
    }
    
    public func startCapture() {
        resetBenchmarks()
 
        if (!captureSession.isRunning) {
            captureSession.startRunning()
        }
    }
    
    public func stopCapture() {
        if (captureSession.isRunning) {
            captureSession.stopRunning()
        }
    }
    
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // Not needed for camera
    }
}

extension AVCaptureDevice {
    func set(frameRate: Double) {
        guard let range = activeFormat.videoSupportedFrameRateRanges.first,
            range.minFrameRate...range.maxFrameRate ~= frameRate
            else {
                DbLog("Requested FPS is not supported by the device's activeFormat !")
                return
        }
        
        do { try lockForConfiguration()
            activeVideoMinFrameDuration = CMTimeMake(1, Int32(frameRate))
            activeVideoMaxFrameDuration = CMTimeMake(1, Int32(frameRate))
            unlockForConfiguration()
        } catch {
            DbLog("LockForConfiguration failed with error: \(error.localizedDescription)")
        }
    }
}
