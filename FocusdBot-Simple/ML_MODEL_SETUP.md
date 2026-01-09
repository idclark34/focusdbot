# ML Model Setup for Phone Detection

## Quick Start: Download Pre-trained Model

### Option 1: YOLOv3-Tiny (Recommended - Fast & Accurate)

1. **Download from Apple's Core ML Models:**
   - Visit: https://developer.apple.com/machine-learning/models/
   - Or use this direct link: https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3Tiny.mlmodel

2. **Or download YOLOv8n (Newer, Better):**
   ```bash
   # Install ultralytics
   pip3 install ultralytics
   
   # Export YOLOv8n to CoreML
   yolo export model=yolov8n.pt format=coreml
   ```
   This creates `yolov8n.mlpackage`

3. **Place the model:**
   ```bash
   # Copy to project
   cp YOLOv3Tiny.mlmodel FocusdBot-Simple/Sources/FocusdBot/
   # OR
   cp -r yolov8n.mlpackage FocusdBot-Simple/Sources/FocusdBot/
   ```

### Option 2: Use Built-in Vision Framework (No Download Required!)

The code includes a fallback that uses Apple's built-in object detection, which already knows about phones!

## COCO Dataset Classes

These models detect 80 object classes, including:
- Class 67: "cell phone"
- Class 0: "person" 
- Class 62: "laptop"
- Class 63: "mouse"
- Class 64: "remote"
- Class 65: "keyboard"

## Model Performance Comparison

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| YOLOv8n | 6 MB | Fast | High | Recommended |
| YOLOv3-Tiny | 35 MB | Medium | Good | Balanced |
| MobileNetV2 | 17 MB | Fast | Medium | Battery life |

## If You Skip This Step

The code will work with simulated detection in DEBUG mode for testing the UI.
In release mode, it will attempt to use Vision's built-in detection.

## Verify Model Works

After adding the model, build and run:
```bash
cd FocusdBot-Simple
swift build
swift run FocusdBot
```

Check the console for: `[PhoneDetector] Model loaded successfully`

