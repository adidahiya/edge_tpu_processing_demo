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

int halfOutputW = outputW / 2;
int halfOutputH = outputH / 2;

// drawing config
boolean DEBUG_INPUT_IMAGE = false;
boolean DEBUG_DETECTION_BOXES = false;
boolean DRAW_BLURRED_FACES = false;
boolean USE_SHADER = true;

PGraphics inputImage;
PGraphics resultsImage;
PGraphics blurImageLayer;
PGraphics fadeLayer;

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

// for shader
float thresholdParam = 0.0;

void settings() {
  int windowW = 480;
  int windowH = 720;
  size(windowW, windowH, P2D);
}

void setup() {
  inputImage = createGraphics(inputW, inputH, P2D);
  resultsImage = createGraphics(outputW, outputH, P2D);
  blurImageLayer = createGraphics(outputW, outputH, P2D);
  fadeLayer = createGraphics(outputW, outputH, P2D);
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
    filterEffectShader = loadShader("halftone.glsl");
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

  resultsImage.beginDraw();
  // transparent
  resultsImage.clear();
  // resultsImage.background(0, 0.0);
  // resultsImage.background(video);

  // HACKHACK: we shouldn't need this?
  // resultsImage.image(video, paddingW, paddingH, resizeW, resizeH);

  imageMode(CORNER);
  resultsImage.image(video, 0, 0, captureW, captureH);

  if (DEBUG_DETECTION_BOXES) {
    drawDetectionBoxesToResultsImage(numDetections, boxes, labels);
    // drawTestBoxes();
  }

  if (classificationLabel != null && classificationLabel != "") {
    broadcastThread.log("classified as " + classificationLabel + " (" + classificationConfidence + ")");

    drawFilterWithClassificationConfidence(classificationLabel, classificationConfidence);

    if (DRAW_BLURRED_FACES) {
      blurImageLayer.beginDraw();
      blurImageLayer.clear();
      drawBlurredFaces(blurImageLayer, numDetections, boxes);
      blurImageLayer.endDraw();
    }
  } else {
    handleDetectionFailed();
    //drawFilterWithClassificationConfidence(classificationLabel, new Double(0.5));
  }

  resultsImage.endDraw();
}

void drawTestBoxes() {
  resultsImage.strokeWeight(2);

  int[][] boxes = {{0, 0, #00ff00}, {50, 50, #0000ff}, {100, 100, #00ffff}};

  for (int i = 0; i < 3; i++) {
    int[] box = boxes[i];
    resultsImage.stroke(box[2]);
    resultsImage.rect(box[0], box[1], 20, 20);
  }
}

void drawDetectionBoxesToResultsImage(int numDetections, float[][] boxes, String[] labels) {
  resultsImage.noFill();
  // red stroke
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
    int x = int(x1);
    int y = int(y1);
    int w = int(x2 - x1);
    int h = int(y2 - y1);

    broadcastThread.log("drawing box at " + x + ", " + y);
    resultsImage.rect(x - 1, y - 1, w + 2, h + 2);
  }
}

void drawBlurredFaces(PGraphics layer, int numFaces, float[][] faceBoxes) {
  PImage blurredFace;
  // override param, just take the first face
  numFaces = 1;

  for (int i = 0; i < numFaces; i++) {
    float[] box = faceBoxes[i];

    float scaleWH = captureW * 1.0 / inputW;

    float x1 = padAndScale(box[0], paddingW, scaleWH);
    float y1 = padAndScale(box[1], paddingH, scaleWH);
    float x2 = padAndScale(box[2], paddingW, scaleWH);
    float y2 = padAndScale(box[3], paddingH, scaleWH);
    int x = int(x1);
    int y = int(y1);
    int w = int(x2 - x1);
    int h = int(y2 - y1);

    blurredFace = inputImage.get(x, y, w, h);
    // HACKHACK
    blurredFace.resize(h, w);

    int blurAmount = 8;
    blurredFace.filter(BLUR, blurAmount);

    // draw to screen
    println("drawing blur box");
    layer.image(blurredFace, x1, y1);
    // resultsImage.rect(x, y, w, h);
  }
}

void drawFilterWithClassificationConfidence(String label, Double confidence) {
  thresholdParam = 1.0 - Math.max(0.0, map(confidence.floatValue(), 0.6, 1.0, 0.0, 1.0));
  broadcastThread.log("threshold param: " + thresholdParam);

  if (thresholdParam < 0.1) {
    // resetShader();
    drawDefaultState();
  } else {
    // broadcastThread.log("drawing filters");
    // int thresholdLumaValue = int(map(thresholdParam, 0.0, 1.0, 2, 255));
    // resultsImage.filter(THRESHOLD, thresholdParam);
  }
}

void draw() {
  background(0, 0.0);
  noCursor();

  float threshold = 0.25;

  if (USE_SHADER) {
    filterEffectShader.set("pixelsPerRow", Math.round(100.0 / thresholdParam));
    if (thresholdParam < threshold) {
      // resultsImage.resetShader();
      shouldDrawVideo = false;
    } else {
      broadcastThread.log("drawing with shader");
      resultsImage.shader(filterEffectShader);
    }
  }

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
    drawVideoAndResultsImage();
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
  int now = millis();

  if (now - lastFail >= 5000) {
    shouldDrawVideo = false;
    lastFail = now;
  }
}

// expects receiver thread to have results
void handleVideoAnalysisResults() {
  float[][] boxes = receiverThread.getDetectionBoxes();
  broadcastThread.log(shouldDrawVideo ? "drawing video" : "not drawing" + ", last fail at: " + lastFail);

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

// copy pixels into a PImage object and show on the screen
void drawVideoAndResultsImage() {
  // purely trial and error values, nothing to see here
  int translationX = 120;
  int translationY = -80;

  // these work for 1920x1080 full resolution
  //int translationX = 420;
  //int translationY = 420;

  // must do this first, working in the landscape coordinate system
  updateResultsImage();

  // now switch to portrait coordinate system by moving anchor and rotating around center
  translate(halfOutputW, halfOutputH);
  rotate(radians(90));
  imageMode(CENTER);
  scale(1, -1);

  // image(video, translationX, translationY, outputW, outputH);
  // resultsImage.resize(outputH, outputW);
  image(resultsImage, translationX, translationY, outputW, outputH);

  if (DRAW_BLURRED_FACES) {
    image(blurImageLayer, 0, 0, outputW, outputH);
  }

  //if (USE_SHADER) {
  //  if (confidence != null && confidence > 0) {
  //    int filterEffectParam = (int) (confidence * 200);
  //    broadcastThread.log("shader value: " + filterEffectParam);
  //    filterEffectShader.set("pixels", filterEffectParam, filterEffectParam);
  //  }

  //  // global shader API
  //  shader(filterEffectShader);
  //}
}

int fadeOutStarted = 0;
int FADE_TIMEOUT_FRAMES = 30;

// draws a blank black box, acts as a mirror
void drawDefaultState() {
  int framesSinceFadeOutStarted = frameCount - fadeOutStarted;

  if (framesSinceFadeOutStarted > FADE_TIMEOUT_FRAMES) {
    clear();
    fadeOutStarted = 0;
    return;
  }

  fadeLayer.beginDraw();
  fadeLayer.clear();
  float alpha = 1 - (framesSinceFadeOutStarted / float(FADE_TIMEOUT_FRAMES));
  // fadeLayer.fill(0.0, alpha);
  broadcastThread.log("fade layer at opacity " + alpha);
  fadeLayer.fill(0.0, 0.25);

  if (fadeOutStarted == 0) {
    fadeOutStarted = frameCount;
  }

  fadeLayer.noStroke();
  fadeLayer.rect(0, 0, outputW, outputH);
  image(fadeLayer, 0, 0);
  fadeLayer.endDraw();
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
