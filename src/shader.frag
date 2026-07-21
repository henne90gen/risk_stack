#version 330 core

precision mediump float;

in vec2 vUV;
in vec4 vColor;
flat in int vRenderType;

uniform sampler2D uCardTexture;
uniform sampler2D uFontTexture;

out vec4 fragColor;

void main() {
    if (vRenderType == 0) {
        fragColor = texture(uCardTexture, vUV);
    } else if (vRenderType == 1) {
        vec4 mask = texture(uFontTexture, vUV);
        fragColor = vec4(vColor.rgb, mask.r);
    } else {
        fragColor = vec4(1.0);
    }
}
