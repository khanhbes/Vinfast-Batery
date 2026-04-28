#!/usr/bin/env python3
"""Run AI server with proper imports"""
import sys
import os

# Add the web directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import and run the main module
from ai_server.main import app
import uvicorn

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8001)
