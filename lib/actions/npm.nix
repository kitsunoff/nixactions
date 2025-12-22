{ pkgs, lib }:

{
  npmInstall = {
    name = "npm-install";
    deps = [ pkgs.nodejs ];
    bash = ''
      echo "→ Installing npm dependencies"
      npm install
    '';
  };
  
  npmTest = {
    name = "npm-test";
    deps = [ pkgs.nodejs ];
    bash = ''
      echo "→ Running npm tests"
      npm test
    '';
  };
  
  npmBuild = {
    name = "npm-build";
    deps = [ pkgs.nodejs ];
    bash = ''
      echo "→ Building with npm"
      npm run build
    '';
  };
  
  npmLint = {
    name = "npm-lint";
    deps = [ pkgs.nodejs ];
    bash = ''
      echo "→ Running npm lint"
      npm run lint
    '';
  };
}
