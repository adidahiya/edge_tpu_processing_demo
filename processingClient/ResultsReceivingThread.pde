import java.nio.charset.*;
import processing.net.*;

static final int MAX_DETECTED_OBJECTS = 20;

class ResultsReceivingThread extends Thread {
  // This is the port we are receiving detection results on
  int port = 9102;

  byte[] buffer = new byte[65536];
  Client client;

  boolean running = false;
  boolean available = false;

  // unlocked -> unlocking with approved face -> unlocked
  String lockState = "locked";

  float[][] detectionBoxes = new float[MAX_DETECTED_OBJECTS][4];
  String[] detectionLabels = new String[1];
  int numDetections = 0;

  String classificationLabel;
  Double classificationConfidence;

  ResultsReceivingThread(PApplet parent) {
    // create new tcp client
    client = new Client(parent, "127.0.0.1", port);
  }

  void start(){
    running = true;
    super.start();
  }

  void run() {
    while (running) {
      checkForNewAndUpdateResults();
    }
  }

  // call once to see if new result is available.
  // after it's called, it sets its value to false.
  boolean newResultsAvailable() {
    boolean currentAvailable = available;
    available = false;
    return currentAvailable;
  }

  byte[] receiveBuffer = new byte[65536];

  void parseResults(JSONObject resultsJson) {
    JSONArray detections = resultsJson.getJSONArray("detection");
    String classification = resultsJson.getString("classification");
    // Double confidence; // declare empty variable since confidence may be null or empty

    numDetections = 0;

    if (detections != null) {
      for (int i = 0; i < detections.size() && i < MAX_DETECTED_OBJECTS; i++) {
        JSONObject result = detections.getJSONObject(i);

        detectionLabels[i] = result.getString("label");

        JSONArray box = result.getJSONArray("box");

        detectionBoxes[i][0] = box.getFloat(0);
        detectionBoxes[i][1] = box.getFloat(1);
        detectionBoxes[i][2] = box.getFloat(2);
        detectionBoxes[i][3] = box.getFloat(3);

        numDetections++;
      }
    }

    if (classification != null && classification != "") {
      // if classification, should be confidence as well
      classificationConfidence = Double.parseDouble(resultsJson.getString("confidence"));
      classificationLabel = classification;

      println("got classification! face recognized as: " + classificationLabel);
      println("confidence: " + classificationConfidence);

    }
  }

  void checkForNewAndUpdateResults(){
    if (client.available() > 0) {
      String base64String = client.readString();

      try {
        JSONObject obj = parseJSONObject(base64String);

        parseResults(obj);

        available = true;
      } catch (RuntimeException e) {
        println("bad json: ", base64String);
        e.printStackTrace();
      }
    }
  }

  int getNumDetections() {
    available = false;
    return numDetections;
  }

  float[][] getDetectionBoxes() {
    return detectionBoxes;
  }

  String[] getDetectionLabels() {
    return detectionLabels;
  }

  Double getClassificationConfidence() {
    return classificationConfidence;
  }

  String getClassificationLabel() {
    return classificationLabel;
  }
}
