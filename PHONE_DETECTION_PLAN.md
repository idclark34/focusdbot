# Phone Detection via Camera - Feature Plan

## Overview
Add computer vision capability to detect when a user is using their phone during a focus session, using the Mac's camera.

## Technical Approach

### 1. macOS Camera Access
- **Framework**: `AVFoundation` (native macOS camera API)
- **Permissions**: Need camera permission in entitlements
- **Privacy**: Add `NSCameraUsageDescription` to Info.plist

### 2. Computer Vision Options

#### Option A: Core ML + Vision Framework (Recommended)
```swift
import Vision
import CoreML
```

**Pros:**
- Native Apple frameworks, optimized for Apple Silicon
- Privacy-first (on-device processing)
- Can use pre-trained models (object detection)
- Lower battery impact

**Models to consider:**
- YOLOv8 (object detection) - detect "cell phone" class
- MobileNet + SSD (lighter weight)
- Custom Core ML model trained on phone detection

#### Option B: OpenCV + TensorFlow
**Pros:**
- More flexible, cross-platform ready
- Large model ecosystem

**Cons:**
- Heavier dependencies
- More battery drain
- Harder to package in macOS app

### 3. Implementation Plan

#### Phase 1: Camera Setup (Week 1)
- [ ] Add camera permission to entitlements
- [ ] Create `PhoneDetector.swift` class
- [ ] Implement AVCaptureSession for video capture
- [ ] Add preview window (for testing/debugging)
- [ ] Add privacy indicator (red light when camera active)

#### Phase 2: Object Detection (Week 2)
- [ ] Integrate Vision framework
- [ ] Load Core ML model (e.g., YOLOv8)
- [ ] Process frames (1-2 FPS sufficient)
- [ ] Detect "cell phone" or "mobile phone" class
- [ ] Filter false positives (confidence threshold)

#### Phase 3: Integration with Bot (Week 3)
- [ ] Add "Phone Detection" toggle in settings
- [ ] Hook detection into distraction system
- [ ] Update UI to show "Phone detected" state
- [ ] Add to session analytics
- [ ] Test battery impact

#### Phase 4: Polish (Week 4)
- [ ] Add visual feedback when phone detected
- [ ] Allow user to dismiss false positives
- [ ] Add "sensitivity" slider
- [ ] Privacy documentation
- [ ] Performance optimization

## Code Structure

```
FocusdBot-Simple/Sources/FocusdBot/
├── BotPanelApp.swift           (existing)
├── Database.swift              (existing)
├── PhoneDetector.swift         (NEW - camera + ML)
├── PhoneDetectorModel.mlmodel  (NEW - Core ML model)
└── Models/
    └── YOLOv8-phone.mlmodel    (NEW - downloaded model)
```

## Privacy Considerations

1. **Camera indicator**: Always show when camera is active
2. **User control**: Easy on/off toggle
3. **No recording**: Only analyze frames, don't save
4. **No cloud**: All processing on-device
5. **Transparency**: Explain why camera is needed

## Permissions Needed

### entitlements.plist
```xml
<key>com.apple.security.device.camera</key>
<true/>
```

### Info.plist
```xml
<key>NSCameraUsageDescription</key>
<string>FocusdBot uses your camera to detect phone usage during focus sessions. No images are saved or transmitted.</string>
```

## Performance Targets

- **CPU usage**: < 5% average
- **Battery impact**: < 2% per hour
- **Detection latency**: < 500ms
- **False positive rate**: < 5%
- **Frame rate**: 1-2 FPS (sufficient for detection)

## Alternative Approaches (Future)

1. **Hand gesture detection**: Detect phone-holding pose
2. **Face orientation**: Detect when looking down at phone
3. **Audio detection**: Detect phone vibration/notification sounds
4. **Bluetooth proximity**: Detect when phone is nearby (less invasive)

## Quick Start Code Snippet

```swift
import AVFoundation
import Vision

class PhoneDetector: NSObject, ObservableObject {
    @Published var phoneDetected: Bool = false
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    func startDetection() {
        setupCamera()
        setupVision()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        // TODO: Configure camera
    }
    
    private func setupVision() {
        // TODO: Load Core ML model
        // TODO: Create Vision request
    }
    
    private func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        // TODO: Run object detection
        // TODO: Check for phone in frame
    }
}
```

## Resources

- [Apple Vision Framework Docs](https://developer.apple.com/documentation/vision)
- [Core ML Models](https://developer.apple.com/machine-learning/models/)
- [YOLOv8 Core ML](https://github.com/ultralytics/ultralytics)
- [Object Detection Tutorial](https://developer.apple.com/documentation/vision/detecting_objects_in_still_images)

## Testing Plan

1. **Unit tests**: Mock camera input
2. **Integration tests**: Test with real phone
3. **Battery tests**: Run for 8 hours, measure impact
4. **Privacy audit**: Verify no data leaves device
5. **User testing**: Beta test with 10+ users

## Success Metrics

- Detection accuracy > 90%
- No significant battery drain
- User satisfaction (survey)
- Feature adoption rate
- False positive rate < 5%

