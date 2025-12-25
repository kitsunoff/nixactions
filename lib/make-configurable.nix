{ lib }:

# Universal helper to make any value configurable via __functor
# Adds ability to use value both directly AND as a function with custom config
#
# This enables elegant API:
#   thing                       -> uses default config
#   thing { option = value; }  -> creates new thing with custom config
#
# Example (executor):
#   makeConfigurable {
#     defaultConfig = { copyRepo = true; };
#     make = { copyRepo }: mkExecutor {
#       inherit copyRepo;
#       name = "local";
#       setupWorkspace = ...;
#       executeJob = ...;
#     };
#   }
#
# Example (any other thing):
#   makeConfigurable {
#     defaultConfig = { timeout = 30; retries = 3; };
#     make = { timeout, retries }: {
#       inherit timeout retries;
#       run = ...;
#     };
#   }

{ 
  # Default configuration
  defaultConfig ? {},
  
  # Function that creates the thing from config
  # Takes config attrset, returns the constructed value
  make,
}:

let
  # Create thing with given config (merges with defaults)
  create = config: make (defaultConfig // config);
  
  # Default instance (with default config)
  default = create {};
in

# Return value that can be used both ways:
# 1. As direct value: thing
# 2. As function: thing { option = value; }
default // {
  __functor = self: config: create config;
}
