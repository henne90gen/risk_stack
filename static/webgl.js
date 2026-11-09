let gl;

let webglOptions = {
  alpha: true, //Boolean that indicates if the canvas contains an alpha buffer.
  antialias: true, //Boolean that indicates whether or not to perform anti-aliasing.
  depth: 32, //Boolean that indicates that the drawing buffer has a depth buffer of at least 16 bits.
  failIfMajorPerformanceCaveat: false, //Boolean that indicates if a context will be created if the system performance is low.
  powerPreference: "default", //A hint to the user agent indicating what configuration of GPU is suitable for the WebGL context. Possible values are:
  premultipliedAlpha: true, //Boolean that indicates that the page compositor will assume the drawing buffer contains colors with pre-multiplied alpha.
  preserveDrawingBuffer: true, //If the value is true the buffers will not be cleared and will preserve their values until cleared or overwritten by the author.
  stencil: true, //Boolean that indicates that the drawing buffer has a stencil buffer of at least 8 bits.
};

function initWebGL(canvas, getString) {
  // The renderer relies on WebGL 2 (instancing, vertexAttribIPointer, GLSL ES 3.00).
  if (typeof WebGL2RenderingContext === "undefined") {
    throw new Error("The browser does not support WebGL 2.");
  }
  gl = canvas.getContext("webgl2", webglOptions);
  if (!gl) {
    throw new Error("The browser supports WebGL 2, but initialization failed.");
  }

  // NOTE index 0 = unbound sentinel
  const glShaders = [null];
  const glPrograms = [null];
  const glVertexArrays = [null];
  const glBuffers = [null];
  const glTextures = [null];
  const glUniformLocations = [null];

  function createGLTexture(ctx, image, texture) {
    ctx.enable(ctx.TEXTURE_2D);
    ctx.bindTexture(ctx.TEXTURE_2D, texture);
    ctx.texImage2D(
      ctx.TEXTURE_2D,
      0,
      ctx.RGBA,
      ctx.RGBA,
      ctx.UNSIGNED_BYTE,
      image,
    );
    ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_MAG_FILTER, ctx.LINEAR);
    ctx.texParameteri(
      ctx.TEXTURE_2D,
      ctx.TEXTURE_MIN_FILTER,
      ctx.LINEAR_MIPMAP_LINEAR,
    );
    ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_WRAP_S, ctx.REPEAT);
    ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_WRAP_T, ctx.REPEAT);
    ctx.generateMipmap(ctx.TEXTURE_2D);
    ctx.bindTexture(ctx.TEXTURE_2D, null);
  }

  function loadImageTexture(gl, url) {
    var texture = gl.createTexture();
    texture.image = new Image();
    texture.image.crossOrigin = "";
    texture.image.onload = function () {
      createGLTexture(gl, texture.image, texture);
    };
    texture.image.src = url;
    return texture;
  }

  const glViewport = (x, y, width, height) => gl.viewport(x, y, width, height);
  const glClearColor = (r, g, b, a) => gl.clearColor(r, g, b, a);
  const glEnable = (x) => gl.enable(x);
  const glDepthFunc = (x) => gl.depthFunc(x);
  const glBlendFunc = (x, y) => gl.blendFunc(x, y);
  const glClear = (x) => gl.clear(x);
  const glGetAttribLocation = (programId, namePtr, nameLen) =>
    gl.getAttribLocation(glPrograms[programId], getString(namePtr, nameLen));
  const glGetUniformLocation = (programId, namePtr, nameLen) => {
    const location = gl.getUniformLocation(
      glPrograms[programId],
      getString(namePtr, nameLen),
    );
    if (location === null) return -1;
    glUniformLocations.push(location);
    return glUniformLocations.length - 1;
  };
  const uniformLocation = (locationId) =>
    locationId < 0 ? null : glUniformLocations[locationId];
  const glUniform1i = (locationId, x) =>
    gl.uniform1i(uniformLocation(locationId), x);
  const glUniform1f = (locationId, x) =>
    gl.uniform1f(uniformLocation(locationId), x);
  const glUniform2f = (locationId, x, y) =>
    gl.uniform2f(uniformLocation(locationId), x, y);
  const glUniform3f = (locationId, x, y, z) =>
    gl.uniform3f(uniformLocation(locationId), x, y, z);
  const glUniform4f = (locationId, x, y, z, w) =>
    gl.uniform4f(uniformLocation(locationId), x, y, z, w);
  const glUniformMatrix4fv = (locationId, dataLen, transpose, dataPtr) => {
    const floats = new Float32Array(wasmMemory.buffer, dataPtr, dataLen * 16);
    gl.uniformMatrix4fv(uniformLocation(locationId), transpose, floats.slice());
  };
  const glCreateBuffer = () => {
    glBuffers.push(gl.createBuffer());
    return glBuffers.length - 1;
  };
  const glGenBuffers = (num, dataPtr) => {
    const buffers = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) {
      const b = glCreateBuffer();
      buffers[n] = b;
    }
  };
  const glCreateProgram = () => {
    glPrograms.push(gl.createProgram());
    return glPrograms.length - 1;
  };
  const glAttachShader = (programId, shaderId) => {
    gl.attachShader(glPrograms[programId], glShaders[shaderId]);
  };
  const glLinkProgram = (programId) => gl.linkProgram(glPrograms[programId]);
  const glCreateShader = (type) => {
    glShaders.push(gl.createShader(type));
    return glShaders.length - 1;
  };
  const glShaderSource = (shaderId, sourcePtr, sourceLen) => {
    const source = getString(sourcePtr, sourceLen);
    gl.shaderSource(glShaders[shaderId], source);
  };
  const glCompileShader = (shaderId) => {
    gl.compileShader(glShaders[shaderId]);
  };
  const glDetachShader = (program, shader) => {
    gl.detachShader(glPrograms[program], glShaders[shader]);
  };
  const glDeleteProgram = (id) => {
    gl.deleteProgram(glPrograms[id]);
    glPrograms[id] = undefined;
  };
  const glDeleteBuffer = (id) => {
    gl.deleteBuffer(glBuffers[id]);
    glBuffers[id] = undefined;
  };
  const glDeleteBuffers = (num, dataPtr) => {
    const buffers = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) glDeleteBuffer(buffers[n]);
  };
  const glDeleteShader = (id) => {
    gl.deleteShader(glShaders[id]);
    glShaders[id] = undefined;
  };
  const glBindBuffer = (type, bufferId) =>
    gl.bindBuffer(type, glBuffers[bufferId]);
  const glBufferData = (type, byteCount, dataPtr, drawType) => {
    const floats = new Float32Array(wasmMemory.buffer, dataPtr, byteCount / 4);
    gl.bufferData(type, floats.slice(), drawType);
  };
  const glUseProgram = (programId) => gl.useProgram(glPrograms[programId]);
  const glEnableVertexAttribArray = (x) => gl.enableVertexAttribArray(x);
  const glVertexAttribPointer = (
    attribLocation,
    size,
    type,
    normalize,
    stride,
    offset,
  ) => {
    gl.vertexAttribPointer(
      attribLocation,
      size,
      type,
      normalize,
      stride,
      offset,
    );
  };
  const glVertexAttribIPointer = (
    attribLocation,
    size,
    type,
    stride,
    offset,
  ) => {
    gl.vertexAttribIPointer(
      attribLocation,
      size,
      type,
      stride,
      offset,
    );
  };
  const glDrawArrays = (type, offset, count) =>
    gl.drawArrays(type, offset, count);
  const glDrawArraysInstanced = (mode, first, count, instanceCount) => {
    gl.drawArraysInstanced(mode, first, count, instanceCount);
  };
  const glCreateTexture = () => {
    glTextures.push(gl.createTexture());
    return glTextures.length - 1;
  };
  const glGenTextures = (num, dataPtr) => {
    const textures = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) {
      const b = glCreateTexture();
      textures[n] = b;
    }
  };
  const glDeleteTexture = (id) => {
    gl.deleteTexture(glTextures[id]);
    glTextures[id] = undefined;
  };
  const glDeleteTextures = (num, dataPtr) => {
    const textures = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) glDeleteTexture(textures[n]);
  };
  const glBindTexture = (target, textureId) =>
    gl.bindTexture(target, glTextures[textureId]);
  const glTexImage2D = (
    target,
    level,
    internalFormat,
    width,
    height,
    border,
    format,
    type,
    dataPtr,
    dataLen,
  ) => {
    const data = new Uint8Array(wasmMemory.buffer, dataPtr, dataLen);
    gl.texImage2D(
      target,
      level,
      internalFormat,
      width,
      height,
      border,
      format,
      type,
      data.slice(),
    );
  };
  const glTexParameteri = (target, pname, param) =>
    gl.texParameteri(target, pname, param);
  const glActiveTexture = (target) => gl.activeTexture(target);
  const glCreateVertexArray = () => {
    glVertexArrays.push(gl.createVertexArray());
    return glVertexArrays.length - 1;
  };
  const glGenVertexArrays = (num, dataPtr) => {
    const vaos = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) {
      const b = glCreateVertexArray();
      vaos[n] = b;
    }
  };
  const glDeleteVertexArrays = (num, dataPtr) => {
    const vaos = new Uint32Array(wasmMemory.buffer, dataPtr, num);
    for (let n = 0; n < num; n++) {
      gl.deleteVertexArray(glVertexArrays[vaos[n]]);
      glVertexArrays[vaos[n]] = undefined;
    }
  };
  const glBindVertexArray = (id) => gl.bindVertexArray(glVertexArrays[id]);
  const glVertexAttribDivisor = (index, divisor) =>
    gl.vertexAttribDivisor(index, divisor);
  const glGenerateMipmap = (target) => gl.generateMipmap(target);
  const glPixelStorei = (type, alignment) => gl.pixelStorei(type, alignment);
  const glGetError = () => gl.getError();
  const writeInfoLog = (log, logPtr, logLen, outLenPtr) => {
    const encoded = new TextEncoder().encode(log ?? "").subarray(0, logLen);
    new Uint8Array(wasmMemory.buffer, logPtr, logLen).set(encoded);
    new DataView(wasmMemory.buffer).setUint32(outLenPtr, encoded.length, true);
  };
  const glGetProgramInfoLog = (programId, logPtr, logLen, outLenPtr) =>
    writeInfoLog(
      gl.getProgramInfoLog(glPrograms[programId]),
      logPtr,
      logLen,
      outLenPtr,
    );
  const glGetShaderInfoLog = (shaderId, logPtr, logLen, outLenPtr) =>
    writeInfoLog(
      gl.getShaderInfoLog(glShaders[shaderId]),
      logPtr,
      logLen,
      outLenPtr,
    );
  const glGetProgramiv = (programId, pname, paramsPtr) => {
    const params = new Int32Array(wasmMemory.buffer, paramsPtr, 1);
    params[0] = gl.getProgramParameter(glPrograms[programId], pname);
  };
  const glGetShaderiv = (shaderId, pname, paramsPtr) => {
    const params = new Int32Array(wasmMemory.buffer, paramsPtr, 1);
    params[0] = gl.getShaderParameter(glShaders[shaderId], pname);
  };

  return {
    glCreateProgram,
    glAttachShader,
    glLinkProgram,
    glDeleteProgram,
    glCreateShader,
    glShaderSource,
    glCompileShader,
    glDetachShader,
    glDeleteShader,
    glViewport,
    glClearColor,
    glEnable,
    glDepthFunc,
    glBlendFunc,
    glClear,
    glGetAttribLocation,
    glGetUniformLocation,
    glUniform1i,
    glUniform1f,
    glUniform2f,
    glUniform3f,
    glUniform4f,
    glUniformMatrix4fv,
    glCreateBuffer,
    glGenBuffers,
    glDeleteBuffer,
    glDeleteBuffers,
    glBindBuffer,
    glBufferData,
    glUseProgram,
    glEnableVertexAttribArray,
    glVertexAttribPointer,
    glVertexAttribIPointer,
    glDrawArrays,
    glDrawArraysInstanced,
    glCreateTexture,
    glGenTextures,
    glDeleteTextures,
    glDeleteTexture,
    glBindTexture,
    glTexImage2D,
    glTexParameteri,
    glGenerateMipmap,
    glActiveTexture,
    glCreateVertexArray,
    glGenVertexArrays,
    glDeleteVertexArrays,
    glBindVertexArray,
    glVertexAttribDivisor,
    glPixelStorei,
    glGetError,
    glGetProgramInfoLog,
    glGetShaderInfoLog,
    glGetProgramiv,
    glGetShaderiv,
  };
}
