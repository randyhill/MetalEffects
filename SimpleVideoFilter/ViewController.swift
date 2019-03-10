import UIKit
import AVFoundation

class ViewController: UIViewController, CameraDelegate {
    
    @IBOutlet weak var renderView: RenderView!
    @IBOutlet weak var FPSLabel: UILabel!
    @IBOutlet weak var recordButton: UIButton!
    var camera:Camera!
    var saturation = SaturationAdjustment()
    var brightness = BrightnessAdjustment()
    var contrast = ContrastAdjustment()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        do {
            recordButton.layer.cornerRadius = 8
            
            camera = try Camera(sessionPreset: .vga640x480)
            camera.delegate = self
            camera.runBenchmark = true
            // camera --> brightness --> saturation --> contrast --> renderView
            camera.addTarget(brightness)
            camera.addTarget(saturation)
            camera.addTarget(contrast)
            camera.addTarget(renderView)
            camera.startCapture()
        } catch {
            fatalError("Could not initialize rendering pipeline: \(error)")
        }
    }
    
    func didCaptureBuffer(_ sampleBuffer: CMSampleBuffer) {
    }
    
    let startTime = Date()
    func frameTime(average: Double, current: Double) {
        let fps = Int(1000.0/current)
        let timeInterval = Date().timeIntervalSince(startTime)
        let string = String(format: "Time: %.02, Ave: %.02f, Current: %.02f", Double(timeInterval), average, current)
        print(string)
        //print("Time: \(timeInterval) average: \(average) current: \(current)")
        DispatchQueue.main.async {
            self.FPSLabel.text = "FPS: \(fps)"
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func toggleRecording(_ sender: UIButton) {
        camera.isRecording = !camera.isRecording
        let title = camera.isRecording ? "Stop Recording" : "Record Video"
        DispatchQueue.main.async {
            sender.setTitle(title, for: .normal)
        }
    }
    
    @IBAction func saturationChanged(_ sender: Any) {
        guard let slider = sender as? UISlider else { return }
        saturation.saturation = slider.value
    }
    
    @IBAction func contrastChanged(_ sender: Any) {
        guard let slider = sender as? UISlider else { return }
        contrast.contrast = 1 - slider.value
    }
    
    @IBAction func brightnessChanged(_ sender: Any) {
        guard let slider = sender as? UISlider else { return }
        brightness.brightness = slider.value
    }
}

