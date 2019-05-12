import gohai.glvideo.*;

GLCapture video;
PShader filterEffectShader;

// video capture dimensions
// DONT CHANGE THIS
int captureW = 640;
int captureH = 480;

// the width and height of the input image for object detection
// String broadcastHost = getRemoteBroadcastHost();
int inputW = captureW;
int inputH = captureH;

// output dimensions
// int outputW = 1920;
// int outputH = 1080;
int outputW = 640;
int outputH = 480;

//translation coordinates for image rotate
int translationX = 120;
int translationY = -80;

// drawing config
boolean DEBUG_INPUT_IMAGE = false;
boolean DEBUG_DETECTION_BOXES = true;
boolean USE_SHADER = false;

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

// keeps track of how long it's been since last failure to detect face
int lastFail = 0;
// flag used to enable / disable video output. if false, we draw the default mirror state
boolean shouldDrawVideo = false;

BroadcastThread broadcastThread;
ResultsReceivingThread receiverThread;

void settings() {
  int windowW = 480;
  int windowH = 720;
  size(windowW, windowH, P2D);
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
  broadcastThread.log("Available cameras:");
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
  // draw video into input image, scaling while maintaining the aspect ratio
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

  if (DEBUG_DETECTION_BOXES) {
    drawDetectionBoxesToImage(numDetections, boxes, labels);
  }

  if (classificationLabel != null && classificationLabel != "") {
    drawFilterWithClassificationConfidence(classificationLabel, classificationConfidence);
  } else {
    handleDetectionFailed();
    //drawFilterWithClassificationConfidence(classificationLabel, new Double(0.5));
  }
}

void drawDetectionBoxesToImage(int numDetections, float[][] boxes, String[] labels) {
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

    // broadcastThread.log("detected " + x1 + ", " + y1 + ", " + x2 + ", " + y2);
    resultsImage.rect(x1, y1, x2 - x1, y2 - y1);

    if (label != null) {
      broadcastThread.log("label: " + label);
      // broadcastThread.log("confidence", confidence);
      resultsImage.text(label, x1, y1);
    }
  }

  resultsImage.endDraw();
}

void drawFilterWithClassificationConfidence(String label, Double confidence) {
  broadcastThread.log("classified as " + label + " with confidence " + confidence);

  float thresholdParam = 1.0 - Math.max(0.0, map(confidence.floatValue(), 0.5, 1.0, 0.0, 1.0));
  broadcastThread.log("threshold param: " + thresholdParam);

  if (thresholdParam < 0.2) {
    drawDefaultState();
  } else {
    broadcastThread.log("drawing filters");
    int thresholdColorValue = int(map(thresholdParam, 0.0, 1.0, 2, 255));
    filter(BLUR, thresholdParam);
    filter(POSTERIZE, thresholdColorValue);
    //filter(THRESHOLD, thresholdParam);
  }
}

void draw() {
  background(0);
  noCursor();
  // If the camera is sending new data, capture that data
  if (video.available()) {
    video.read();
    broadcastThread.updateImage(captureAndScaleInputImage());
  }

  if (DEBUG_INPUT_IMAGE) {
    image(inputImage, 0, 0, inputW, inputH);
  }

  if (receiverThread.newResultsAvailable()) {
    handleVideoAnalysisResults();
  }

  if (shouldDrawVideo) {
    drawVideo();
  } else {
    drawDefaultState();
  }
}

int getFps() {
  String fpsString = System.getenv("FPS");

  if (fpsString != null) {
    return int(fpsString);
  } else {
    return defaultFps;
  }
}

void handleDetectionFailed() {
    if (millis() - lastFail >= 5000) {
        shouldDrawVideo = false;
        lastFail = millis();
    }
}

// expects receiver thread to have results
void handleVideoAnalysisResults() {
  float[][] boxes = receiverThread.getDetectionBoxes();
  broadcastThread.log("draw results: " + shouldDrawVideo);
  broadcastThread.log("last fail: " + lastFail);

  if (boxes.length == 0) {
    if (millis() - lastFail >= 5000) {
      shouldDrawVideo = false;
      lastFail = millis();
    }
    broadcastThread.disableClassificationBroadcast();
    return;
  } else {
    shouldDrawVideo = true;
  }

  float[] cropBox = boxes[0];

  if (cropBox[0] == 0 && cropBox[1] == 0) {
    broadcastThread.disableClassificationBroadcast();
  } else if (receiverThread.isClassifying()) {
    // skip, we'll use the next detection box when classifier API is available
    broadcastThread.log("classifier busy, discarded this face crop");
    // broadcastThread.disableClassificationBroadcast();
  } else {
    String requestId = UUID.randomUUID().toString();
    receiverThread.initClassificationRequest(requestId);
    broadcastThread.initClassificationRequest(requestId, cropBox);
  }
}

void drawVideo() {
  // Copy pixels into a PImage object and show on the screen
  int halfW = outputW / 2;
  int halfH = outputH / 2;
  // purely trial and error values, nothing to see here
  // these work for 1920x1080 full resolution
  //int translationX = 420;
  //int translationY = 420;

  translate(halfW, halfH);
  rotate(radians(90));
  imageMode(CENTER);
  scale(1, -1);
  image(video, translationX, translationY, outputW, outputH);

  updateResultsImage();

  // image(resultsImage, translationX, translationY, outputW, outputH);

  if (USE_SHADER) {
    if (confidence != null && confidence > 0) {
      int filterEffectParam = (int) (confidence * 200);
      broadcastThread.log("shader value: " + filterEffectParam);
      filterEffectShader.set("pixels", filterEffectParam, filterEffectParam);
    }

    // global shader API
    shader(filterEffectShader);
  }
}

// draws a blank black box, acts as a mirror
void drawDefaultState() {
  fill(0);
  rect(0, 0, outputW, outputH);
}

void quitSketch() {
  video.close();
  // noLoop();

  inputImage.clear();
  resultsImage.clear();

  try {
    receiverThread.join();
    broadcastThread.join();
  } catch (InterruptedException e) {
    broadcastThread.log("stopped receiver / broadcast threads");
    exit();
  } finally {
    exit();
  }
}

void keyPressed() {
  quitSketch();
}

void mousePressed() {
  quitSketch();
}
