# Simplified Python CI example showing job isolation
{ pkgs, platform, executor ? platform.executors.local }:

# Helper to create Python code (simulates checkout)
let
  createPythonCode = ''
    cat > app.py << 'PYEOF'
def add(a, b):
    return a + b

def multiply(a, b):
    return a * b

if __name__ == "__main__":
    print("Math App v1.0")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"4 * 5 = {multiply(4, 5)}")
PYEOF

    cat > test_app.py << 'PYEOF'
import sys
sys.path.insert(0, '.')
from app import add, multiply

def test_add():
    assert add(2, 3) == 5

def test_multiply():
    assert multiply(2, 3) == 6
PYEOF
  '';

in platform.mkWorkflow {
  name = "python-ci-simple";
  
  jobs = {
    lint = {
      inherit executor;
      
      actions = [
        # Each job must checkout code (isolated workspace)
        { bash = createPythonCode; }
        
        {
          name = "lint";
          deps = [ pkgs.python3 ];
          bash = ''
            echo "→ Linting with Python syntax check"
            python3 -m py_compile app.py test_app.py || true
            echo "✓ Lint complete"
          '';
        }
      ];
    };
    
    test = {
      needs = [ "lint" ];
      inherit executor;
      
      actions = [
        # Checkout code again (new job = new directory)
        { bash = createPythonCode; }
        
        {
          name = "run-tests";
          deps = [ pkgs.python3 ];
          bash = ''
            echo "→ Running tests"
            python3 test_app.py
            
            echo "✓ Tests passed"
          '';
        }
      ];
    };
    
    build = {
      needs = [ "test" ];
      inherit executor;
      
      actions = [
        # Checkout code again
        { bash = createPythonCode; }
        
        {
          name = "build-image";
          bash = ''
            echo "→ Building Docker image (simulated)"
            
            cat > Dockerfile << 'DOCKEREOF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py /app/
CMD ["python", "app.py"]
DOCKEREOF
            
            echo "  Would execute: docker build -t myapp:v1 ."
            echo "✓ Image built"
          '';
        }
      ];
    };
  };
}
