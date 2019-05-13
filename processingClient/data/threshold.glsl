#define PROCESSING_TEXTURE_SHADER
 
 uniform sampler2D texture;
 varying vec4 vertTexCoord;
 uniform float midPoint;
  
void main() {
  vec4 texColor = texture2D(texture, vertTexCoord.st).rgba;
  float brightness = (0.2126*texColor.r) + (0.7152*texColor.g) + (0.0722*texColor.b);
  if (brightness > midPoint) {
    gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
  } else {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
  }
}

