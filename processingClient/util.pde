

int getEnvValueOrDefault(String name, int defaultValue) {
  String value = System.getenv(name);
  
  if (value != null) {
    return int(value);
  } else
    return defaultValue;
}

String getEnvValueOrDefault(String name, String defaultValue) {
  String value = System.getenv(name);
  //println("Broadcast host:", portString);
  
  if (value != null) {
    return value;
  } else
    return defaultValue;
}

byte[] createImageBytePacket(BufferedImage bimg) {
  // Need these output streams to get image as bytes for UDP communication
  ByteArrayOutputStream baStream = new ByteArrayOutputStream();
  BufferedOutputStream bos = new BufferedOutputStream(baStream);

  // Turn the BufferedImage into a JPG and put it in the BufferedOutputStream
  // Requires try/catch
  try {
    ImageIO.write(bimg, "jpg", bos);
  } catch (IOException e) {
    e.printStackTrace();
  }

  // Get the byte array, which we will send out via UDP!
  byte[] packet = baStream.toByteArray();

  return packet;
}
