# Docker executor example - runs jobs in Docker containers
{ pkgs, platform }:

platform.mkWorkflow {
  name = "docker-ci";
  
  env = {
    PROJECT_NAME = "hello-docker";
  };
  
  jobs = {
    # Job 1: Run in Python container
    test-python = {
      executor = platform.executors.oci {
        image = "python:3.11-slim";
      };
      
      actions = [
        {
          name = "check-environment";
          bash = ''
            echo "→ Running in Docker container"
            echo "  Container image: python:3.11-slim"
            echo "  Working directory: $PWD"
            echo "  Python version:"
            python --version
            echo ""
          '';
        }
        
        {
          name = "run-python-code";
          bash = ''
            echo "→ Running Python code in container"
            
            cat > hello.py << 'EOF'
import sys
import platform

print(f"Hello from Docker container!")
print(f"Python version: {sys.version}")
print(f"Platform: {platform.platform()}")
print(f"Architecture: {platform.machine()}")
EOF
            
            python hello.py
            echo ""
            echo "✓ Python code executed successfully"
          '';
        }
      ];
    };
    
    # Job 2: Run in Node.js container
    test-node = {
      executor = platform.executors.oci {
        image = "node:20-slim";
      };
      
      actions = [
        {
          name = "check-node";
          bash = ''
            echo "→ Running in Node.js container"
            echo "  Container image: node:20-slim"
            echo "  Node version:"
            node --version
            echo "  NPM version:"
            npm --version
            echo ""
          '';
        }
        
        {
          name = "run-javascript";
          bash = ''
            echo "→ Running JavaScript code in container"
            
            cat > hello.js << 'EOF'
console.log('Hello from Docker container!');
console.log('Node version:', process.version);
console.log('Platform:', process.platform);
console.log('Architecture:', process.arch);
EOF
            
            node hello.js
            echo ""
            echo "✓ JavaScript code executed successfully"
          '';
        }
      ];
    };
    
    # Job 3: Run in Ubuntu container (after previous jobs)
    test-ubuntu = {
      needs = [ "test-python" "test-node" ];
      
      executor = platform.executors.oci {
        image = "ubuntu:22.04";
      };
      
      actions = [
        {
          name = "system-info";
          bash = ''
            echo "→ Running in Ubuntu container"
            echo "  Container image: ubuntu:22.04"
            echo ""
            
            echo "System information:"
            uname -a
            echo ""
            
            echo "Distribution:"
            cat /etc/os-release | grep -E "^(NAME|VERSION)="
            echo ""
          '';
        }
        
        {
          name = "install-and-run";
          bash = ''
            echo "→ Installing tools in container"
            
            # Update and install curl
            apt-get update -qq
            apt-get install -y -qq curl > /dev/null
            
            echo "✓ curl installed"
            curl --version | head -1
            echo ""
            
            echo "→ Making HTTP request"
            curl -s https://api.github.com/zen
            echo ""
          '';
        }
      ];
    };
    
    # Job 4: Build Docker image (local executor)
    build-docker-image = {
      needs = [ "test-ubuntu" ];
      executor = platform.executors.local;
      
      actions = [
        {
          name = "create-dockerfile";
          bash = ''
            echo "→ Creating Dockerfile"
            
            cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask

COPY app.py /app/

EXPOSE 5000

CMD ["python", "app.py"]
EOF
            
            cat > app.py << 'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from NixActions Docker build!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
            
            echo "✓ Dockerfile created"
            cat Dockerfile
          '';
        }
        
        {
          name = "build-image";
          deps = [ pkgs.docker ];
          bash = ''
            echo ""
            echo "→ Building Docker image (simulated)"
            echo ""
            echo "Would execute:"
            echo "  docker build -t $PROJECT_NAME:latest ."
            echo ""
            echo "Build context:"
            ls -lah
            echo ""
            echo "✓ Docker image would be built successfully"
            echo "  Image: $PROJECT_NAME:latest"
            echo "  Size: ~150MB (estimated)"
          '';
        }
      ];
    };
    
    # Job 5: Summary
    summary = {
      needs = [ "build-docker-image" ];
      "if" = "always()";
      executor = platform.executors.local;
      
      actions = [{
        name = "summary";
        bash = ''
          echo ""
          echo "╔═══════════════════════════════════════════════════╗"
          echo "║ Docker Executor Demo Complete                     ║"
          echo "╚═══════════════════════════════════════════════════╝"
          echo ""
          echo "Containers used:"
          echo "  ✓ python:3.11-slim - Python tests"
          echo "  ✓ node:20-slim - Node.js tests"
          echo "  ✓ ubuntu:22.04 - System tests"
          echo ""
          echo "Each job ran in isolated Docker container!"
          echo ""
          echo "Note: This example simulates docker commands."
          echo "To actually run in Docker containers, ensure:"
          echo "  1. Docker daemon is running"
          echo "  2. Images are pulled or available locally"
          echo "  3. Docker socket is accessible"
        '';
      }];
    };
  };
}
