import gohai.glvideo.*;
GLCapture video;

PShader filterEffectShader;

// CONFIGURATION
// video capture dimensions
int captureW = 640;
int captureH = 480;

// the width and height of the input image for
// object detection
String broadcastHost = getRemoteBroadcastHost();
int inputW = broadcastHost == "" ? 300 : captureW;
int inputH = broadcastHost == "" ? 300 : captureH;

// output dimensions
int outputW = 480;
int outputH = 640;

// drawing config
boolean debugInputImage = false;
boolean drawResults = true;

PGraphics inputImage;
PGraphics resultsImage;

String label;
Double confidence;

float aspect = captureW * 1.0 / captureH;

int resizeW = inputW;
// resize but maintain aspect ratio
int resizeH = floor(inputW / aspect);
int paddingW = (inputW - resizeW) / 2;
// pad image to fit input size
int paddingH = (inputH - resizeH) / 2;

int defaultFps = 25;

BroadcastThread broadcastThread;
ResultsReceivingThread receiverThread;

boolean USE_SHADER = false;


void settings(){
  size(outputW, outputH, P2D);
}

void setup() {
  inputImage = createGraphics(inputW, inputH, P2D);
  resultsImage = createGraphics(outputW, outputH, P2D);
  frameRate(getFps());

  // start threads
  broadcastThread = new BroadcastThread();
  broadcastThread.start();
  println("Opening TCP connection");
  receiverThread = new ResultsReceivingThread(this);
  receiverThread.start();

  // setup graphics
  String[] devices = GLCapture.list();
  println("Available cameras:");
  printArray(devices);

  // use the first camera
  video = new GLCapture(this, devices[0], captureW, captureH, getFps());

  video.start();

  if (USE_SHADER) {
    filterEffectShader = loadShader("../shaders/pixelate.glsl");
    filterEffectShader.set("pixels", 600, 600);
  }
}

PImage captureAndScaleInputImage() {
  inputImage.beginDraw();
  inputImage.background(0);
  // draw video into input image, scaling while maintaining the
  // aspect ratio
  inputImage.image(video, paddingW, paddingH, resizeW, resizeH);
  inputImage.endDraw();
  return inputImage.copy();
}

float padAndScale(float value, float padding, float scale) {
  return (value - padding) * scale;
}

void updateResultsImage() {
  int numDetections = receiverThread.getNumDetections();
  float[][] boxes = receiverThread.getDetectionBoxes();
  String[] labels = receiverThread.getDetectionLabels();

  String classificationLabel = receiverThread.getClassificationLabel();
  Double classificationConfidence = receiverThread.getClassificationConfidence();

  drawDetectionResultsToImage(numDetections, boxes, labels);

  if (classificationLabel != null && classificationLabel != "") {
    drawClassificationToImage(classificationLabel, classificationConfidence);
  }
}

void drawDetectionResultsToImage(int numDetections, float[][] boxes, String[] labels) {
  resultsImage.beginDraw();
  resultsImage.clear();
  resultsImage.noFill();
  resultsImage.stroke(#ff0000);
  resultsImage.strokeWeight(2);
  resultsImage.textSize(18);

  for (int i = 0; i < numDetections; i++) {
    float[] box = boxes[i];
    String label = labels[i];

    float scaleWH = captureW * 1.0 / inputW;

    float x1 = padAndScale(box[0], paddingW, scaleWH);
    float y1 = padAndScale(box[1], paddingH, scaleWH);
    float x2 = padAndScale(box[2], paddingW, scaleWH);
    float y2 = padAndScale(box[3], paddingH, scaleWH);

    resultsImage.rect(x1, y1, x2 - x1, y2 - y1);

    if (label != null) {
      println("label: ", label);
      // println("confidence", confidence);
      resultsImage.text(label, x1, y1);
    }
  }

  resultsImage.endDraw();
}

void drawClassificationToImage(String label, Double confidence) {
  print("classified as " + label + " with confidence " + confidence);
}

void draw() {
  background(0);
  // If the camera is sending new data, capture that data
  if (video.available()) {
    video.read();
    broadcastThread.update(captureAndScaleInputImage());
  }

  if (debugInputImage) {
    image(inputImage, 0, 0, inputW, inputH);
  }

  if (drawResults) {
    // Copy pixels into a PImage object and show on the screen
    rotate(90);
    image(video, 0, 0, outputW, outputH);

    if (receiverThread.newResultsAvailable()) {
      updateResultsImage();
      float[][] boxes = receiverThread.getDetectionBoxes();
      if (boxes.length > 0) {
        broadcastThread.setCropToBroadcast(boxes[0]);
      } else {
        broadcastThread.disableCropToBroadcast();
      }
    }

    image(resultsImage, 0, 0, outputW, outputH);

    if (USE_SHADER) {
      if (confidence != null && confidence > 0) {
        //filter(THRESHOLD, 1.0 - confidence.floatValue());
        int filterEffectParam = (int) (confidence * 200);
        println("shader value: ", filterEffectParam);
        filterEffectShader.set("pixels", filterEffectParam, filterEffectParam);
      }

      // global shader API
      shader(filterEffectShader);
    }
  }
}

int getFps() {
  String fpsString = System.getenv("FPS");

  if (fpsString != null) {
    return int(fpsString);
  } else
    return defaultFps;
}
