#version 330 core

precision mediump float;

in vec2 vUV;

uniform sampler2D uTexture;
uniform vec3 uColor;
uniform int uRenderType;

out vec4 fragColor;

void main() {
    if (uRenderType == 0) {
        fragColor = texture(uTexture, vUV);
    } else if (uRenderType == 1) {
        vec4 mask = texture(uTexture, vUV);
        fragColor = vec4(uColor, mask.r);
    } else {
        fragColor = vec4(1.0);
    }
}
