// Web worker hosting one thread of the Zig module. It instantiates the same
// module as the main thread on the same shared memory, then hands control to
// `workerEntry`, which loops over the task queue and never returns.
// See src/wasm_threads.zig.

onmessage = async ({ data: { module, memory, stackTop } }) => {
  const decoder = new TextDecoder();
  // TextDecoder refuses views on shared memory, so copy first.
  const getString = (ptr, len) =>
    decoder.decode(new Uint8Array(memory.buffer, ptr, len).slice());

  // Only what work functions may call. Everything else (WebGL, storage) belongs
  // to the main thread and throws loudly instead of silently doing nothing.
  const available = {
    memory,
    logInfo: (ptr, len) => console.log(getString(ptr, len)),
    logWarn: (ptr, len) => console.warn(getString(ptr, len)),
    logErr: (ptr, len) => console.error(getString(ptr, len)),
    dateNow: () => Date.now(),
    performanceNow: () => performance.now(),
    getRandomValues(ptr, len) {
      const bytes = new Uint8Array(len);
      crypto.getRandomValues(bytes);
      new Uint8Array(memory.buffer, ptr, len).set(bytes);
    },
  };
  const env = new Proxy(available, {
    get: (target, name) =>
      name in target
        ? target[name]
        : () => {
            throw new Error(`env.${String(name)} is not available in a worker`);
          },
  });

  const instance = await WebAssembly.instantiate(module, { env });
  instance.exports.workerEntry(stackTop);
};
