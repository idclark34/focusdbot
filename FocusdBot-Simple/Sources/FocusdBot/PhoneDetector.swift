@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML
import AppKit
import SwiftUI

// MARK: - Phone Detector
/// Detects phone usage via camera using Vision framework
@MainActor
class PhoneDetector: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "phoneDetectorEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "phoneDetectorEnabled")
            if isEnabled {
                startDetection()
            } else {
                stopDetection()
            }
        }
    }
    
    @Published var phoneDetected: Bool = false
    @Published var cameraActive: Bool = false
    @Published var permissionGranted: Bool = false
    @Published var lastDetectionTime: Date?
    @Published var confidenceLevel: Float = 0.0
    
    // MARK: - Camera Properties
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "com.focusdbot.video", qos: .userInitiated)
    
    // MARK: - Detection Settings
    private let detectionInterval: TimeInterval = 0.5 // Process 2 frames per second
    nonisolated(unsafe) private var lastProcessedTime: Date = .distantPast
    private let confidenceThreshold: Float = 0.6 // 60% confidence to trigger
    private let cooldownPeriod: TimeInterval = 2.0 // Avoid rapid false positives
    
    // MARK: - Vision Properties
    nonisolated(unsafe) private var visionRequest: VNRequest?
    private let visionQueue = DispatchQueue(label: "com.focusdbot.vision", qos: .userInitiated)
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkCameraPermission()
        setupVisionDetection()
    }
    
    deinit {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
    }
    
    // MARK: - Vision Setup
    private func setupVisionDetection() {
        // Try to use a custom Core ML model if available
        // Otherwise, fall back to Vision's built-in object detection
        
        // Option 1: Try to load custom YOLO model (if user added it)
        if let modelURL = Bundle.main.url(forResource: "YOLOv3Tiny", withExtension: "mlmodelc") ??
                          Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") {
            do {
                let model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
                let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                    self?.handleVisionResults(request: request, error: error)
                }
                request.imageCropAndScaleOption = .scaleFill
                self.visionRequest = request
                print("[PhoneDetector] Custom ML model loaded successfully")
                return
            } catch {
                print("[PhoneDetector] Could not load custom model: \(error.localizedDescription)")
            }
        }
        
        // Option 2: Use Vision's built-in object recognition
        let request = VNRecognizeAnimalsRequest { [weak self] request, error in
            // This won't detect phones directly, but we'll use it as a fallback
            // In production, you'd want to use a proper COCO-trained model
            self?.handleBuiltInVisionResults(request: request, error: error)
        }
        self.visionRequest = request
        print("[PhoneDetector] Using built-in Vision detection (limited functionality)")
    }
    
    // MARK: - Permission Handling
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            Task { @MainActor in
                self.permissionGranted = true
            }
        case .notDetermined:
            requestCameraPermission()
        case .denied, .restricted:
            Task { @MainActor in
                self.permissionGranted = false
            }
        @unknown default:
            Task { @MainActor in
                self.permissionGranted = false
            }
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.permissionGranted = granted
                if granted && (self?.isEnabled ?? false) {
                    self?.startDetection()
                }
            }
        }
    }
    
    // MARK: - Detection Control
    func startDetection() {
        guard isEnabled, permissionGranted else { return }
        guard captureSession == nil else { return } // Already running
        
        setupCamera()
    }
    
    func stopDetection() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        
        Task { @MainActor in
            self.cameraActive = false
            self.phoneDetected = false
            self.confidenceLevel = 0.0
        }
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480 // Lower resolution for efficiency
        
        // Get default video device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("[PhoneDetector] No camera available")
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                print("[PhoneDetector] Cannot add video input")
                return
            }
            
            // Setup video output
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: videoQueue)
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                print("[PhoneDetector] Cannot add video output")
                return
            }
            
            self.captureSession = session
            self.videoOutput = output
            
            // Start capture on background thread
            videoQueue.async { [weak self] in
                session.startRunning()
                Task { @MainActor in
                    self?.cameraActive = true
                    print("[PhoneDetector] Camera started successfully")
                }
            }
            
        } catch {
            print("[PhoneDetector] Error setting up camera: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    func resetDetection() {
        Task { @MainActor in
            self.phoneDetected = false
            self.confidenceLevel = 0.0
            self.lastDetectionTime = nil
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension PhoneDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle processing to save CPU/battery
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= detectionInterval else { return }
        lastProcessedTime = now
        
        // Get pixel buffer from sample
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process frame for phone detection
        analyzeFrame(pixelBuffer)
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame dropped - this is normal under load
    }
    
    // MARK: - Frame Analysis
    private nonisolated func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let request = self.visionRequest else {
            print("[PhoneDetector] Vision request not initialized")
            return
        }
        
        // Create image request handler
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // Perform detection on vision queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[PhoneDetector] Vision request failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Vision Result Handlers
    private func handleVisionResults(request: VNRequest, error: Error?) {
        if let error = error {
            print("[PhoneDetector] Vision error: \(error.localizedDescription)")
            return
        }
        
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return
        }
        
        // Look for "cell phone" in the detected objects
        // COCO dataset class 67 is "cell phone"
        var phoneFound = false
        var maxConfidence: Float = 0.0
        
        for observation in results {
            // Check all labels for phone-related identifiers
            for label in observation.labels {
                let identifier = label.identifier.lowercased()
                
                // Match phone-related classes
                if identifier.contains("phone") || 
                   identifier.contains("cell") ||
                   identifier.contains("mobile") ||
                   identifier == "67" { // COCO class ID for cell phone
                    
                    let confidence = label.confidence
                    if confidence >= self.confidenceThreshold {
                        phoneFound = true
                        maxConfidence = max(maxConfidence, confidence)
                        print("[PhoneDetector] Phone detected! Confidence: \(confidence)")
                    }
                }
            }
        }
        
        // Update state on main actor
        Task { @MainActor in
            if phoneFound {
                self.phoneDetected = true
                self.confidenceLevel = maxConfidence
                self.lastDetectionTime = Date()
                
                // Auto-reset after cooldown to avoid continuous triggering
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(self.cooldownPeriod * 1_000_000_000))
                    await self.resetDetection()
                }
            }
        }
    }
    
    private func handleBuiltInVisionResults(request: VNRequest, error: Error?) {
        // Fallback handler when using built-in Vision (without proper COCO model)
        // This won't actually detect phones, but provides graceful fallback
        
        #if DEBUG
        // In debug mode, occasionally trigger for testing
        if Int.random(in: 0...100) < 2 { // 2% chance for testing
            Task { @MainActor in
                self.phoneDetected = true
                self.confidenceLevel = 0.65
                self.lastDetectionTime = Date()
                print("[PhoneDetector] Debug: Simulated phone detection")
                
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(self.cooldownPeriod * 1_000_000_000))
                    await self.resetDetection()
                }
            }
        }
        #endif
    }
}

// MARK: - Phone Detection Settings View
struct PhoneDetectionSettingsView: View {
    @ObservedObject var detector: PhoneDetector
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(detector.cameraActive ? .green : .gray)
                Text("Phone Detection")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: $detector.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!detector.permissionGranted)
            }
            
            if !detector.permissionGranted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("Camera permission required")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        detector.openSystemPreferences()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            if detector.isEnabled && detector.cameraActive {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Camera active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if detector.phoneDetected {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.red)
                    Text("Phone detected (\(Int(detector.confidenceLevel * 100))%)")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            Text("Uses camera to detect phone usage during focus sessions. Processing happens on-device.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

