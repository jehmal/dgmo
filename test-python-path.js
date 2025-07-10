const { spawn } = require('child_process');
const path = require('path');

const pythonPath = path.join(__dirname, 'dgm/venv/bin/python');
const scriptPath = path.join(__dirname, 'opencode/packages/dgm-integration/python/bridge.py');

console.log('Python path:', pythonPath);
console.log('Script path:', scriptPath);

const proc = spawn(pythonPath, ['-c', 'import sys; print("Python:", sys.executable); print("Path:", sys.path)']);

proc.stdout.on('data', (data) => {
  console.log('stdout:', data.toString());
});

proc.stderr.on('data', (data) => {
  console.log('stderr:', data.toString());
});

proc.on('close', (code) => {
  console.log('Process exited with code:', code);
});
