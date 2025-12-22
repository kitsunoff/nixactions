{ pkgs, lib }:

{
  checkout = {
    name = "checkout";
    deps = [ pkgs.git ];
    bash = ''
      echo "→ Checking out code"
      echo "  Working directory: $PWD"
      
      # In real CI, this would be:
      # git clone $REPO_URL .
      # or git fetch/checkout specific commit
      
      echo "  (simulated - in production use: git clone)"
      ls -la 2>/dev/null || echo "  (empty directory)"
    '';
  };
  
  setupNode = { version ? "20" }: {
    name = "setup-node";
    deps = [ pkgs.nodejs ];
    bash = ''
      echo "→ Setting up Node.js ${version}"
      node --version
      npm --version
    '';
  };
  
  setupPython = { version ? "3.11" }: {
    name = "setup-python";
    deps = [ pkgs.python311 ];
    bash = ''
      echo "→ Setting up Python ${version}"
      python --version
      pip --version
    '';
  };
  
  setupRust = {
    name = "setup-rust";
    deps = [ pkgs.rustc pkgs.cargo ];
    bash = ''
      echo "→ Setting up Rust"
      rustc --version
      cargo --version
    '';
  };
}
