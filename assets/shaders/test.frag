#include <flutter/runtime_effect.glsl>

uniform float uTime;
uniform float uWidth;
uniform float uHeight;
uniform float audioData[512];  // Array for audio data

out vec4 fragColor;

vec3 palette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

float getAudioIntensity(vec2 uv) {
    float intensity = 0.0;
    int index = int(uv.x * 511.0);
    index = clamp(index, 0, 511);
    return audioData[index];
}

void main() {
    vec2 uResolution = vec2(uWidth, uHeight);
    vec2 uv = (FlutterFragCoord().xy * 2.0 - uResolution.xy) / min(uResolution.x, uResolution.y);
    vec2 uv0 = uv;
    
    // Get audio intensity for the current position
    float audioIntensity = getAudioIntensity(FlutterFragCoord().xy / uResolution.xy);
    
    vec3 finalColor = vec3(0.0);
    
    for (float i = 0.0; i < 4.0; i++) {
        uv = fract(uv * 1.5) - 0.5;
        float d = length(uv) * exp(-length(uv0));
        
        // Incorporate audio data into the visualization
        vec3 col = palette(length(uv0) + i * 0.4 + uTime * 0.4);
        d = sin(d * 8.0 + uTime + audioIntensity * 2.0) / 8.0;
        d = abs(d);
        d = pow(0.01 / d, 1.2);
        
        // Modulate the color intensity with audio data
        finalColor += col * d * (1.0 + audioIntensity);
    }
    
    // Apply audio-reactive brightness modulation
    float avgIntensity = (audioIntensity * 2.0);
    finalColor *= 0.5 + avgIntensity * 0.5;
    
    fragColor = vec4(finalColor, 1.0);
}