# Simplified Python CI example showing job isolation
{ pkgs, platform }:

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

    cat > requirements.txt << 'PYEOF'
pytest==7.4.0
PYEOF
  '';

in platform.mkWorkflow {
  name = "python-ci-simple";
  
  jobs = {
    lint = {
      executor = platform.executors.local;
      
      actions = [
        # Each job must checkout code (isolated workspace)
        { bash = createPythonCode; }
        
        {
          name = "lint";
          deps = [ pkgs.python311 pkgs.python311Packages.flake8 ];
          bash = ''
            echo "→ Linting with flake8"
            flake8 app.py test_app.py --max-line-length=100 || true
            echo "✓ Lint complete"
          '';
        }
      ];
    };
    
    test = {
      needs = [ "lint" ];
      executor = platform.executors.local;
      
      actions = [
        # Checkout code again (new job = new directory)
        { bash = createPythonCode; }
        
        {
          name = "install-and-test";
          deps = [ pkgs.python311 pkgs.python311Packages.pip ];
          bash = ''
            echo "→ Installing dependencies"
            python -m venv venv
            source venv/bin/activate
            pip install --quiet -r requirements.txt
            
            echo "→ Running tests"
            pytest test_app.py -v
            
            echo "✓ Tests passed"
          '';
        }
      ];
    };
    
    build = {
      needs = [ "test" ];
      executor = platform.executors.local;
      
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
