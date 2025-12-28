{ pkgs, platform, executor ? platform.executors.local }:

# Example: Using nixShell to dynamically add packages to job environment
#
# This demonstrates:
# 1. Adding packages on-the-fly without modifying executor
# 2. Using those packages in subsequent actions
# 3. Different packages in different jobs

platform.mkWorkflow {
  name = "nix-shell-example";
  
  jobs = {
    # Job 1: Use curl and jq for API testing
    api-test = {
      inherit executor;
      actions = [
        # Add curl and jq to the environment
        (platform.actions.nixShell [ "curl" "jq" ])
        
        # Use them in subsequent actions
        {
          name = "Fetch and parse GitHub API";
          bash = ''
            echo "→ Testing curl and jq availability"
            which curl
            which jq
            
            echo ""
            echo "→ Fetching GitHub API rate limit"
            curl -s https://api.github.com/rate_limit | jq '.rate'
          '';
        }
      ];
    };
    
    # Job 2: Use different tools for file processing
    file-processing = {
      inherit executor;
      actions = [
        # Add file processing tools
        (platform.actions.nixShell [ "ripgrep" "fd" "bat" ])
        
        {
          name = "Process files";
          bash = ''
            echo "→ Testing ripgrep, fd, and bat"
            which rg
            which fd
            which bat
            
            echo ""
            echo "→ Searching for 'nixShell' in project files"
            fd -e nix -x rg -l "nixShell" || echo "No matches found"
          '';
        }
      ];
    };
    
    # Job 3: Combine multiple package sets
    multi-tool = {
      inherit executor;
      needs = [ "api-test" "file-processing" ];
      actions = [
        # First set of tools
        (platform.actions.nixShell [ "git" "tree" ])
        
        {
          name = "Use git and tree";
          bash = ''
            echo "→ Git version"
            git --version
            
            echo ""
            echo "→ Directory structure"
            tree -L 2 . || echo "Listing directory..."
            ls -la
          '';
        }
        
        # Add more tools in the same job
        (platform.actions.nixShell [ "htop" "ncdu" ])
        
        {
          name = "System tools available";
          bash = ''
            echo "→ Checking system monitoring tools"
            which htop
            which ncdu
            echo "  ✓ All tools available"
          '';
        }
      ];
    };
  };
}
