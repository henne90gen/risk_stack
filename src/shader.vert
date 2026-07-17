#version 330 core

precision mediump float;

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUV;
// Per-instance model matrix, occupies attribute locations 2–5.
layout(location = 2) in mat4 aModel;
// Per-instance UV rect: (u0, v0, u1, v1), location 6.
layout(location = 6) in vec4 aUVRect;

out vec2 vUV;

uniform mat4 uView;
uniform mat4 uProjection;

void main() {
    gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0) * aModel * uView * uProjection;
    vUV = vec2(mix(aUVRect.x, aUVRect.z, aUV.x), mix(aUVRect.y, aUVRect.w, aUV.y));
}
