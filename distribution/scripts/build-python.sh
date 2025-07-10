#!/bin/bash
# DGMO Python Bridge Packaging Script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="/mnt/c/Users/jehma/Desktop/AI/DGMSTT"
DGM_DIR="$PROJECT_ROOT/opencode/packages/dgm-integration"
BUILD_DIR="$PROJECT_ROOT/distribution/build/python"
VENV_DIR="$BUILD_DIR/venv"

# Clean and create build directory
echo -e "${YELLOW}Setting up Python build environment...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create a minimal Python bridge script
echo -e "${GREEN}Creating minimal Python bridge...${NC}"
cat > "$BUILD_DIR/dgm_bridge_minimal.py" << 'EOF'
#!/usr/bin/env python3
"""
DGMO Minimal Python Bridge
Provides essential DGM functionality for consumer distribution
"""

import sys
import json
import traceback
from typing import Dict, Any, List
import asyncio
import logging

# Configure logging
logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)

class MinimalDGMBridge:
    """Minimal DGM Bridge for consumer distribution"""
    
    def __init__(self):
        self.methods = {
            'health_check': self.health_check,
            'echo': self.echo,
            'generate_code_improvements': self.generate_code_improvements,
            'apply_generated_code': self.apply_generated_code,
            'analyze_performance': self.analyze_performance,
        }
        self.running = True
    
    def health_check(self) -> Dict[str, Any]:
        """Health check endpoint"""
        return {
            'status': 'healthy',
            'adapter': 'MinimalDGMBridge',
            'version': '1.0.0',
            'mode': 'consumer'
        }
    
    def echo(self, message: str = '') -> Dict[str, Any]:
        """Echo test endpoint"""
        return {'echo': message, 'timestamp': time.time()}
    
    def generate_code_improvements(self, **kwargs) -> Dict[str, Any]:
        """Generate code improvements based on patterns"""
        # In consumer mode, return pre-configured improvements
        return {
            'generated_improvements': [],
            'status': 'consumer_mode',
            'message': 'Evolution features available in developer mode'
        }
    
    def apply_generated_code(self, **kwargs) -> Dict[str, Any]:
        """Apply generated improvements"""
        return {
            'success': True,
            'applied': [],
            'message': 'Plugin system will handle improvements'
        }
    
    def analyze_performance(self, **kwargs) -> Dict[str, Any]:
        """Analyze performance data"""
        return {
            'patterns': [],
            'recommendations': [],
            'status': 'consumer_mode'
        }
    
    def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle JSON-RPC request"""
        try:
            method = request.get('method')
            params = request.get('params', {})
            id = request.get('id')
            
            if method not in self.methods:
                return {
                    'jsonrpc': '2.0',
                    'id': id,
                    'error': {
                        'code': -32601,
                        'message': 'Method not found'
                    }
                }
            
            result = self.methods[method](**params)
            
            return {
                'jsonrpc': '2.0',
                'id': id,
                'result': result
            }
        except Exception as e:
            logger.error(f"Error handling request: {e}")
            return {
                'jsonrpc': '2.0',
                'id': request.get('id'),
                'error': {
                    'code': -32603,
                    'message': 'Internal error',
                    'data': str(e)
                }
            }
    
    def run(self):
        """Run the bridge"""
        logger.info("MinimalDGMBridge starting...")
        
        while self.running:
            try:
                line = sys.stdin.readline()
                if not line:
                    break
                
                request = json.loads(line.strip())
                response = self.handle_request(request)
                
                print(json.dumps(response))
                sys.stdout.flush()
                
            except json.JSONDecodeError:
                logger.error("Invalid JSON received")
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Unexpected error: {e}")
        
        logger.info("MinimalDGMBridge stopped")

if __name__ == '__main__':
    import time
    bridge = MinimalDGMBridge()
    bridge.run()
EOF

# Create PyInstaller spec file
echo -e "${YELLOW}Creating PyInstaller spec file...${NC}"
cat > "$BUILD_DIR/dgm_bridge.spec" << 'EOF'
# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['dgm_bridge_minimal.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['json', 'logging', 'asyncio'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'numpy', 'pandas', 'scipy'],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='dgm-bridge',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
EOF

# Create virtual environment
echo -e "${YELLOW}Creating Python virtual environment...${NC}"
python3 -m venv "$BUILD_DIR/venv"
source "$BUILD_DIR/venv/bin/activate"

# Install PyInstaller in venv
echo -e "${YELLOW}Installing PyInstaller...${NC}"
pip install pyinstaller

# Build with PyInstaller
echo -e "${GREEN}Building Python bridge with PyInstaller...${NC}"
cd "$BUILD_DIR"
pyinstaller dgm_bridge.spec --clean --noconfirm

# Copy the executable
if [ -f "dist/dgm-bridge" ]; then
    cp "dist/dgm-bridge" "$BUILD_DIR/"
    SIZE=$(ls -lh "$BUILD_DIR/dgm-bridge" | awk '{print $5}')
    echo -e "${GREEN}✓ Python bridge built successfully!${NC}"
    echo -e "Size: ${SIZE}"
elif [ -f "dist/dgm-bridge.exe" ]; then
    cp "dist/dgm-bridge.exe" "$BUILD_DIR/"
    SIZE=$(ls -lh "$BUILD_DIR/dgm-bridge.exe" | awk '{print $5}')
    echo -e "${GREEN}✓ Python bridge built successfully!${NC}"
    echo -e "Size: ${SIZE}"
else
    echo -e "${RED}❌ Build failed - executable not found${NC}"
    exit 1
fi

echo -e "Location: $BUILD_DIR"