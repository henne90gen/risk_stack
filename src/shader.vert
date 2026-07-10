#version 330 core

precision mediump float;

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUV;

out vec2 vUV;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;

void main() {
    gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0) * uModel * uView * uProjection;
    vUV = aUV;
}
