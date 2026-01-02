@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML
import AppKit
import SwiftUI
import UserNotifications

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
    
    // Debug info
    @Published var currentHeadPitch: Double? = nil
    @Published var faceDetected: Bool = false
    @Published var headDownDuration: TimeInterval = 0
    
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
    
    // MARK: - Face Disappearance Tracking
    // New approach: Detect when face disappears (user looks away at phone)
    nonisolated(unsafe) private var lastFaceSeenTime: Date?
    nonisolated(unsafe) private var faceDisappearStartTime: Date?
    private let faceDisappearThreshold: TimeInterval = 8.0 // Detect after 8 seconds without face
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkCameraPermission()
        setupVisionDetection()
        // Note: Notifications only work in proper .app bundles, not swift run
    }
    
    deinit {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
    }
    
    // MARK: - Vision Setup
    private func setupVisionDetection() {
        // Use face detection with landmarks to detect head orientation
        // This detects when user is looking down (phone usage posture)
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceDetection(request: request, error: error)
        }
        
        // Configure for better tracking
        request.revision = VNDetectFaceLandmarksRequestRevision3
        
        self.visionRequest = request
        print("[PhoneDetector] Face orientation detection initialized")
        print("[PhoneDetector] Will detect head-down posture (looking at phone)")
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
    
    // MARK: - Test Mode
    func triggerTestDetection() {
        Task { @MainActor in
            self.phoneDetected = true
            self.confidenceLevel = 0.90
            self.lastDetectionTime = Date()
            
            // Play sound
            NSSound.beep()
            
            // Show notification
            sendNotification()
            
            print("[PhoneDetector] TEST: Manual detection triggered")
            
            // Auto-reset after cooldown
            Task {
                try? await Task.sleep(nanoseconds: UInt64(self.cooldownPeriod * 1_000_000_000))
                await self.resetDetection()
            }
        }
    }
    
    private func sendNotification() {
        // Only works in proper .app bundles, not swift run
        // Fail silently if not available
        do {
            let content = UNMutableNotificationContent()
            content.title = "FocusdBot - Distraction Detected"
            content.body = "You're looking away from your screen!"
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            
            // Request permission first time
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error = error {
                            print("[PhoneDetector] Notification error: \(error)")
                        }
                    }
                }
            }
        } catch {
            // Silently fail - notifications not critical
            print("[PhoneDetector] Notifications not available (needs .app bundle)")
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
    
    // MARK: - Face Detection Handler
    private func handleFaceDetection(request: VNRequest, error: Error?) {
        if let error = error {
            print("[PhoneDetector] Face detection error: \(error.localizedDescription)")
            return
        }
        
        let now = Date()
        guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
            // NO FACE DETECTED - user may be looking away at phone
            Task { @MainActor in
                self.faceDetected = false
                self.currentHeadPitch = nil
            }
            
            // Start tracking face disappearance
            if faceDisappearStartTime == nil && lastFaceSeenTime != nil {
                // Face just disappeared
                faceDisappearStartTime = now
                print("[PhoneDetector] ⚠️ Face disappeared - starting timer")
            } else if let disappearStart = faceDisappearStartTime {
                // Face has been gone for a while
                let duration = now.timeIntervalSince(disappearStart)
                
                // Update UI with duration
                Task { @MainActor in
                    self.headDownDuration = duration
                }
                
                print("[PhoneDetector] Face gone for \(String(format: "%.1f", duration))s")
                
                if duration >= faceDisappearThreshold && !phoneDetected {
                    // Face has been gone long enough - trigger detection
                    Task { @MainActor in
                        self.phoneDetected = true
                        self.confidenceLevel = 0.9 // High confidence for sustained absence
                        self.lastDetectionTime = Date()
                        print("[PhoneDetector] 🚨 Phone usage detected! (face gone for \(String(format: "%.1f", duration))s)")
                        
                        // Play sound feedback
                        NSSound.beep()
                        
                        // Show notification
                        self.sendNotification()
                        
                        // Auto-reset after cooldown
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(self.cooldownPeriod * 1_000_000_000))
                            await self.resetDetection()
                        }
                    }
                }
            }
            return
        }
        
        // FACE DETECTED - user is looking at screen
        Task { @MainActor in
            self.faceDetected = true
        }
        
        // Update last seen time
        lastFaceSeenTime = now
        
        // Reset disappearance tracking
        if faceDisappearStartTime != nil {
            print("[PhoneDetector] ✅ Face back - resetting timer")
            faceDisappearStartTime = nil
        }
        
        // Reset duration display
        Task { @MainActor in
            self.headDownDuration = 0
        }
        
        // Show pitch for debugging (optional)
        if let face = results.first, let pitch = face.pitch?.doubleValue {
            let pitchDegrees = pitch * 180.0 / .pi
            Task { @MainActor in
                self.currentHeadPitch = pitchDegrees
            }
        }
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Camera active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Debug info
                    if detector.faceDetected {
                        HStack {
                            Text("✓ Face detected")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Spacer()
                            if let pitch = detector.currentHeadPitch {
                                Text("Head: \(String(format: "%.1f", pitch))°")
                                    .font(.caption2)
                                    .foregroundColor(pitch < -15 ? .orange : .secondary)
                                    .monospacedDigit()
                            }
                        }
                        
                        if detector.headDownDuration > 0 {
                            // Face is gone - tracking duration
                            HStack {
                                Text("⚠️ Face gone for:")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("\(String(format: "%.1f", detector.headDownDuration))s / 8.0s")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .monospacedDigit()
                            }
                            
                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 4)
                                    
                                    Rectangle()
                                        .fill(Color.orange)
                                        .frame(width: geometry.size.width * CGFloat(min(detector.headDownDuration / 8.0, 1.0)), height: 4)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                            .frame(height: 4)
                        }
                    } else {
                        Text("⚠️ Looking away")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if detector.phoneDetected {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.red)
                    Text("Looking away - distracted!")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            Text("Detects when you look away from screen (e.g., at phone). Triggers after 8 seconds.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Test button
            if detector.isEnabled && detector.cameraActive {
                Button("Test Detection") {
                    detector.triggerTestDetection()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Manually trigger detection to see/hear feedback")
            }
        }
        .padding(.vertical, 4)
    }
}

