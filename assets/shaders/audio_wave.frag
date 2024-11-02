#version 460

precision highp float;

uniform float iTime;
uniform vec2 iResolution;
uniform float audioData[512];

out vec4 fragColor;

const float PI = 3.14159265359;
const vec3 backgroundColor = vec3(0.0, 0.0, 0.1);

float getAudioValue(float position) {
    int index = int(position * 511.0);
    return audioData[index];
}

void main() {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec2 pos = (uv * 2.0) - 1.0;
    pos.x *= iResolution.x / iResolution.y;
    
    vec3 color = backgroundColor;
    
    // Create multiple wave layers
    for(float i = 0.0; i < 3.0; i++) {
        float fi = i + 1.0;
        
        // Sample audio data
        float audioVal = getAudioValue(abs(pos.x));
        
        // Create wave
        float wave = sin(pos.x * 5.0 * fi + iTime * 2.0) * 0.5;
        wave *= audioVal * 0.5;
        
        // Calculate distance from wave
        float dist = abs(pos.y - wave);
        float brightness = smoothstep(0.05 / fi, 0.0, dist);
        
        // Add color
        vec3 waveColor = vec3(
            0.5 + 0.5 * sin(fi * 0.5),
            0.5 + 0.5 * cos(fi * 0.5),
            0.5 + 0.5 * sin(fi * 1.0)
        );
        
        color += waveColor * brightness * audioVal;
    }
    
    // Add glow
    float glow = length(pos);
    color *= 1.0 - (glow * 0.25);
    
    fragColor = vec4(color, 1.0);
}