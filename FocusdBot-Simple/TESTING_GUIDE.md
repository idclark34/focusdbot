# Phone Detection Testing Guide

## ✅ Phase 2 Complete!

The Vision framework integration is now complete. The system will:
1. Try to load a custom YOLO/COCO model if available
2. Fall back to built-in Vision detection
3. In DEBUG mode, provide simulated detections for UI testing

## How to Test

### Option 1: With ML Model (Full Functionality)

1. **Download a COCO-trained model:**
   ```bash
   # Quick option: Download YOLOv3-Tiny
   curl -L -o YOLOv3Tiny.mlmodel \
     https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3Tiny.mlmodel
   
   # Or use YOLOv8 (recommended):
   pip3 install ultralytics
   yolo export model=yolov8n.pt format=coreml
   ```

2. **Add model to project:**
   ```bash
   # Copy to Sources directory
   cp YOLOv3Tiny.mlmodel FocusdBot-Simple/Sources/FocusdBot/
   
   # Or for YOLOv8
   cp -r yolov8n.mlpackage FocusdBot-Simple/Sources/FocusdBot/
   ```

3. **Compile the model (if needed):**
   ```bash
   xcrun coremlcompiler compile YOLOv3Tiny.mlmodel .
   # This creates YOLOv3Tiny.mlmodelc
   ```

4. **Update Package.swift to include model:**
   Add `resources: [.process("YOLOv3Tiny.mlmodel")]` or similar to the target.

5. **Build and run:**
   ```bash
   cd FocusdBot-Simple
   swift build
   swift run FocusdBot
   ```

6. **Test detection:**
   - Enable "Phone Detection" in the menu
   - Grant camera permission when prompted
   - Start a focus session
   - Hold your phone in front of the camera
   - Bot should mark you as "distracted" when phone detected

### Option 2: Without ML Model (Fallback Mode)

The app works without a custom model, but with limited detection:

```bash
cd FocusdBot-Simple
swift build -c debug  # Build in debug mode
swift run FocusdBot
```

In DEBUG mode:
- 2% random chance of simulated detection for UI testing
- Camera still activates (you'll see the red dot)
- Good for testing UI/UX without actual ML inference

### Option 3: Force Debug Simulation

For rapid UI testing without camera:

1. Edit `PhoneDetector.swift` line ~310
2. Change simulation rate:
   ```swift
   if Int.random(in: 0...100) < 20 { // 20% chance
   ```
3. Rebuild and test

## What to Look For

### Console Output

When working correctly, you should see:
```
[PhoneDetector] Custom ML model loaded successfully
[PhoneDetector] Camera started successfully
[PhoneDetector] Phone detected! Confidence: 0.87
[PhoneDetector] Phone detected - marking as distracted
```

Or in fallback mode:
```
[PhoneDetector] Using built-in Vision detection (limited functionality)
[PhoneDetector] Camera started successfully
```

### UI Indicators

1. **Menu bar:**
   - 🟢 Green camera icon = Camera active
   - 🔴 Red dot indicator = "Camera active"
   - Phone detection toggle works

2. **During focus session:**
   - Camera activates automatically
   - Red circle appears (macOS camera indicator)
   - When phone detected: Bot shows "Distracted!" state
   - After 2 seconds: Auto-resets (cooldown period)

3. **Settings:**
   - Can enable/disable phone detection
   - Shows permission status
   - Can open System Preferences for camera access

## Tuning Detection

### Adjust Confidence Threshold

In `PhoneDetector.swift` line ~36:
```swift
private let confidenceThreshold: Float = 0.6 // Lower = more sensitive
```

- **0.5-0.6**: More sensitive (may have false positives)
- **0.6-0.7**: Balanced (recommended)
- **0.7-0.8**: Very strict (may miss some detections)

### Adjust Detection Frequency

Line ~34:
```swift
private let detectionInterval: TimeInterval = 0.5 // Check every 0.5s
```

- **0.25**: Very responsive (higher CPU)
- **0.5**: Balanced (recommended)
- **1.0**: Battery-saving mode

### Adjust Cooldown Period

Line ~37:
```swift
private let cooldownPeriod: TimeInterval = 2.0 // Reset after 2 seconds
```

- **1.0**: Quick reset (may trigger frequently)
- **2.0**: Balanced (recommended)
- **5.0**: Longer grace period

## Troubleshooting

### Camera Not Working

1. **Check permissions:**
   ```bash
   # System Preferences > Privacy & Security > Camera
   # Make sure FocusdBot is allowed
   ```

2. **Check console:**
   ```bash
   # Look for permission denied messages
   log stream --predicate 'subsystem == "com.apple.TCC"'
   ```

3. **Reset permissions:**
   ```bash
   tccutil reset Camera
   # Then re-launch app
   ```

### No Detection Happening

1. **Verify model loaded:**
   - Check console for "Custom ML model loaded successfully"
   - If not, model file might be missing or incompatible

2. **Check detection settings:**
   - Is phone detection enabled in menu?
   - Is a focus session active?
   - Is camera permission granted?

3. **Test with debug mode:**
   - Build with `-c debug`
   - Should see occasional simulated detections

### False Positives

1. **Increase confidence threshold** (0.7 or higher)
2. **Adjust lighting** (better lighting = better detection)
3. **Update cooldown period** (longer cooldown = fewer triggers)

## Performance Monitoring

### CPU Usage
```bash
# Monitor CPU while running
top -pid $(pgrep FocusdBot)
```

Expected: 3-7% CPU during active detection

### Memory Usage
```bash
# Check memory footprint
ps aux | grep FocusdBot
```

Expected: ~50-100 MB

### Battery Impact

Run for 1 hour and check:
```bash
# Check energy impact
pmset -g log | grep FocusdBot
```

Should be "Low" or "Very Low" impact

## Production Checklist

Before releasing:
- [ ] Real ML model included (not just debug simulation)
- [ ] Tested with actual phones of various colors/sizes
- [ ] Confidence threshold tuned (< 5% false positive rate)
- [ ] Battery impact verified (< 2% per hour)
- [ ] Privacy documentation updated
- [ ] Entitlements correctly configured
- [ ] Camera usage description clear and accurate
- [ ] Debug logging removed or gated

## Known Limitations

1. **Lighting dependent**: Works best in good lighting
2. **Phone orientation**: May not detect phones face-down
3. **Distance**: Works best within 1-3 feet of camera
4. **Similar objects**: May occasionally detect TV remotes or similar objects
5. **Dark phones**: May be harder to detect in low light

## Future Improvements

- Custom training for specific phone models
- Hand gesture detection (holding phone pose)
- Face orientation detection (looking down)
- Multiple detection methods combined
- Adaptive thresholds based on environment

