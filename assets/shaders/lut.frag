#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLutSize;
uniform sampler2D uTexture;
uniform sampler2D uLut;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 orig = texture(uTexture, uv);

    float maxColor = uLutSize - 1.0;
    float r = clamp(orig.r * maxColor, 0.0, maxColor);
    float g = clamp(orig.g * maxColor, 0.0, maxColor);
    float b = clamp(orig.b * maxColor, 0.0, maxColor);

    float b0 = floor(b);
    float b1 = min(b0 + 1.0, maxColor);
    float fracB = b - b0;

    float u = (r + 0.5) / uLutSize;
    float lutHeight = uLutSize * uLutSize;
    float v0 = (b0 * uLutSize + g + 0.5) / lutHeight;
    float v1 = (b1 * uLutSize + g + 0.5) / lutHeight;

    vec3 col0 = texture(uLut, vec2(u, v0)).rgb;
    vec3 col1 = texture(uLut, vec2(u, v1)).rgb;

    vec3 graded = mix(col0, col1, fracB);
    fragColor = vec4(graded, orig.a);
}