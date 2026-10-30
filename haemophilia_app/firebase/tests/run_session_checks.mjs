import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const app = fileURLToPath(new URL('../../', import.meta.url));
const run = (binary, args, options = {}) => {
  const result = spawnSync(binary, args, { cwd: app, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
};
run(process.execPath, ['--test', 'firebase/tests/firestore.test.mjs']);
if (!process.env.HEMO_PYTHON || !process.env.HEMO_FUNCTION_DEPS) throw new Error('Set the test Python runtime and installed Firebase dependency directory.');
run(process.env.HEMO_PYTHON, ['-m', 'unittest', 'test_workflow', 'test_server_emulator', '-v'], {
  cwd: resolve(app, 'firebase/functions'),
  env: { ...process.env, GOOGLE_CLOUD_PROJECT: 'demo-hemo-workflow',
    PYTHONPATH: process.env.HEMO_FUNCTION_DEPS,
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8089' },
});
