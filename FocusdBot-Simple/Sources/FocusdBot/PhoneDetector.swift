@preconcurrency import AVFoundation
import Vision
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
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkCameraPermission()
    }
    
    deinit {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
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
        // TODO: In Phase 2, we'll add Vision framework object detection here
        // For now, this is a placeholder that simulates detection for testing
        
        #if DEBUG
        // Simulate random detection for testing UI (remove in production)
        let simulateDetection = false // Set to true to test UI
        if simulateDetection {
            let randomDetection = Int.random(in: 0...100) < 5 // 5% chance
            if randomDetection {
                Task { @MainActor in
                    self.phoneDetected = true
                    self.confidenceLevel = Float.random(in: 0.6...0.95)
                    self.lastDetectionTime = Date()
                    
                    // Auto-reset after cooldown
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(self.cooldownPeriod * 1_000_000_000))
                        await self.resetDetection()
                    }
                }
            }
        }
        #endif
        
        // Placeholder for ML model integration
        // We'll add Vision framework code here in Phase 2:
        /*
        let request = VNCoreMLRequest(model: phoneDetectionModel) { [weak self] request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            
            // Check for phone detection
            for observation in results {
                if observation.labels.contains(where: { $0.identifier.contains("phone") || $0.identifier.contains("cell") }) {
                    let confidence = observation.confidence
                    if confidence >= self?.confidenceThreshold ?? 0.6 {
                        Task { @MainActor in
                            self?.phoneDetected = true
                            self?.confidenceLevel = confidence
                            self?.lastDetectionTime = Date()
                        }
                    }
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        */
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

