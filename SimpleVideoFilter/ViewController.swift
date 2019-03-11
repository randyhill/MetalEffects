import UIKit
import AVFoundation

class ViewController: UIViewController, CameraDelegate {
    
    @IBOutlet weak var renderView: RenderView!
    @IBOutlet weak var FPSLabel: UILabel!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var messageView: UILabel!
    var camera:Camera!
    var saturation = SaturationAdjustment()
    var brightness = BrightnessAdjustment()
    var contrast = ContrastAdjustment()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        do {
            recordButton.layer.cornerRadius = 8
            messageView.isHidden = true
            messageView.layer.cornerRadius = 8
            messageView.layer.masksToBounds = true

            camera = try Camera(sessionPreset: .hd1920x1080)
            camera.delegate = self
             // camera --> brightness --> saturation --> contrast --> renderView
            camera.addTarget(brightness)
            camera.addTarget(saturation)
            camera.addTarget(contrast)
            camera.addTarget(renderView)
            camera.startCapture()
            
            NotificationCenter.default.addObserver(self, selector: #selector(videoSaved), name: VideoCapture.VideoSaved, object: nil)
        } catch {
            fatalError("Could not initialize rendering pipeline: \(error)")
        }
    }
    
    @objc func videoSaved() {
        DispatchQueue.main.async {
            self.messageView.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 , execute: {
                self.messageView.isHidden = true
            })
        }
    }
    
     func averageFrameTime(_ average: Double) {
        DispatchQueue.main.async {
            self.FPSLabel.text = "FPS: \(Int(average))"
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

