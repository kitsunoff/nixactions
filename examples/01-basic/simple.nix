# Simple workflow example - basic sequential job execution
{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "simple-workflow";
  
  jobs = {
    # Single job with a few actions
    hello = {
      inherit executor;
      
      actions = [
        platform.actions.checkout
        
        {
          name = "greet";
          bash = ''
            echo "Hello from NixActions!"
            echo "Current directory: $PWD"
            echo "Current date: $(date)"
          '';
        }
        
        {
          name = "system-info";
          deps = [ pkgs.coreutils ];
          bash = ''
            echo "System information:"
            uname -a
            echo "Available disk space:"
            df -h . | tail -1
          '';
        }
      ];
    };
  };
}
