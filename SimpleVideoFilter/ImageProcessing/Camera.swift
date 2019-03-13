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
    let inputCamera:AVCaptureDevice
    let videoInput:AVCaptureDeviceInput
    let videoOutput:AVCaptureVideoDataOutput
    var videoTextureCache: CVMetalTextureCache?
    
    let frameRenderingSemaphore = DispatchSemaphore(value:1)
    let cameraProcessingQueue = DispatchQueue.global()
    let cameraFrameProcessingQueue = DispatchQueue(
        label: "com.cameraFrameProcessingQueue",
        attributes: [])
    
    // Benchmarking FPS
    var framesSinceLastCheck = 0
    var lastCheckTime = CFAbsoluteTimeGetCurrent()
    
    // Recording to disk/camera roll
    private var videoRecorder:  VideoCapture?
    var isRecording : Bool {
        get { return videoRecorder != nil }

    }

    public init?(sessionPreset:AVCaptureSession.Preset,
                location:PhysicalCameraLocation = .backFacing,
                captureAsYUV:Bool = false)
    {
        // Init all of self before calling super.
        self.location = location
        self.captureSession = AVCaptureSession()
        guard let device = location.device() else {
            DbLog("Error initializing device")
            return nil
        }
        self.inputCamera = device
        
        do {
            self.videoInput = try AVCaptureDeviceInput(device:inputCamera)
         } catch {
            DbLog("Error initializing video input: \(error)")
            return nil
        }
        videoOutput = AVCaptureVideoDataOutput()
        
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device,  nil,  &videoTextureCache) != kCVReturnSuccess {
            DbLog("Couldn't allocate metal texture cache")
            return nil
        }
        super.init()

        // Everything allocated, now configure session
        self.captureSession.beginConfiguration()
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        }
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_32BGRA))]
        
        if (captureSession.canAddOutput(videoOutput)) {
            captureSession.addOutput(videoOutput)
        }
        captureSession.sessionPreset = sessionPreset
        
        // Do this last matters, changing inputs after setting FPS will reset to defaults.
        inputCamera.setSupportedFormatTo(width: 1920, height: 1080, fps: 60.0)
        inputCamera.setFrameRateTo(60.0)

        captureSession.commitConfiguration()
    
        videoOutput.setSampleBufferDelegate(self, queue:cameraProcessingQueue)
    }
    
    deinit {
        cameraFrameProcessingQueue.sync {
            self.stopCapture()
            self.videoOutput.setSampleBufferDelegate(nil, queue:nil)
        }
    }
    
    func startRecording() {
        guard videoRecorder == nil else {
            return DbLog("Trying to start video recording when already started")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(inputCamera.activeFormat.formatDescription)
        print("Init seconds: \(CACurrentMediaTime()))")
        videoRecorder = VideoCapture(metalDevice: sharedMetalRenderingDevice.device, width: Int(dimensions.width), height: Int(dimensions.height))
    }

    func stopRecording() {
        guard let videoRecorder = videoRecorder else {
            return DbLog("Trying to stop video recording when already stopped")
        }
        videoRecorder.stopRecording()
        self.videoRecorder = nil
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        print("Capture  seconds: \(CACurrentMediaTime()) presentation:\(presentationTime.seconds)")
        
        guard (frameRenderingSemaphore.wait(timeout:DispatchTime.now()) == DispatchTimeoutResult.success) else {
            return DbLog("Semaphore Error")
        }
        guard let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return DbLog("Couldn't get image buffer")
        }
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        cameraFrameProcessingQueue.async {
            CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            var textureRef:CVMetalTexture? = nil
            guard let videoTextureCache = self.videoTextureCache, CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, videoTextureCache, cameraFrame, nil, .bgra8Unorm, bufferWidth, bufferHeight, 0, &textureRef) == kCVReturnSuccess else {
                DbLog("Failed to create texture from frame.")
                return
            }
            
            if let concreteTexture = textureRef, let cameraTexture = CVMetalTextureGetTexture(concreteTexture) {
                // Process texture through effects to create outputTexture
                let inputTexture = Texture(orientation: self.location.imageOrientation(), texture: cameraTexture)
                let outputTexture = self.updateTargetsWithTexture(inputTexture)
                if let videoRecorder = self.videoRecorder {
                    videoRecorder.addFrame(outputTexture, presentTime: presentationTime)
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
        }
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

extension AVCaptureDevice.Format {
     func matches(width: Int32, height: Int32, fps: Float64) -> Bool {
        let dimensions = CMVideoFormatDescriptionGetDimensions(self.formatDescription)
        if dimensions.height != height || dimensions.width != width {
            return false
        }
        if let frameRateRange = self.videoSupportedFrameRateRanges.first {
            return frameRateRange.minFrameRate ... frameRateRange.maxFrameRate ~= fps
        }
        return false
    }
}

extension AVCaptureDevice {
    func setSupportedFormatTo(width: Int32, height: Int32, fps: Float64) {
        if !activeFormat.matches(width: width, height: height, fps: fps) {
            for format in formats {
                if format.matches(width: width, height: height, fps: fps) {
                    do {
                        try lockForConfiguration()
                        activeFormat = format
                        unlockForConfiguration()
                    }  catch {
                        DbLog("LockForConfiguration failed with error: \(error.localizedDescription)")
                    }
                    break
                }
             }
        }
    }
    
    func setFrameRateTo(_ frameRate: Double) {
        guard let range = activeFormat.videoSupportedFrameRateRanges.first,
            range.minFrameRate...range.maxFrameRate ~= frameRate
        else {
            DbLog("Requested FPS is not supported by the device's activeFormat !")
            return
        }
        do {
            try lockForConfiguration()
            activeVideoMinFrameDuration = CMTimeMake(1, Int32(frameRate))
            activeVideoMaxFrameDuration = CMTimeMake(1, Int32(frameRate))
            unlockForConfiguration()
        } catch {
            DbLog("LockForConfiguration failed with error: \(error.localizedDescription)")
        }
    }
}
